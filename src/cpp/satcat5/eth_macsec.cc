//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/eth_header.h>
#include <satcat5/eth_macsec.h>

using satcat5::eth::ETYPE_MACSEC;
using satcat5::eth::MacAddr;
using satcat5::eth::MacSec;
using satcat5::eth::MacType;
using satcat5::io::ArrayWrite;
using satcat5::io::Readable;
using satcat5::io::Writeable;

// MACsec cyphertext frames add 6-byte header and 16-byte ICV,
// but they still need to fit in the standard Ethernet MTU.
static constexpr unsigned MAX_CT_FRAME = 1518;
static constexpr unsigned MAX_PT_FRAME = MAX_CT_FRAME - 22;

// TAG control information (TCI) defined in Section 9.5.
constexpr u8 FLAG_VER   = 0x80;     // Version number (always 0)
constexpr u8 FLAG_ES    = 0x40;     // End-station bit
constexpr u8 FLAG_SCI   = 0x20;     // SCI encoded in SecTAG
constexpr u8 FLAG_ENC   = 0x0C;     // SH bit + E bit?

// Maximum "short" length for the SL field (Section 9.7)
constexpr unsigned MAX_LEN_SL = 48;

// Length of specific fields
constexpr unsigned IV_LEN_BYTES = 12;
constexpr unsigned ICV_LEN_BYTES = 16;
constexpr unsigned SCI_LEN_BYTES = 8;

// Given TCI value, calculate expected header length.
// (Destination MAC + Source MAC + SecTag including EtherType)
inline constexpr unsigned header_len(u8 tci)
    { return (tci & FLAG_SCI) ? 28 : 20; }

// Determine if the provided TCI value is valid.
bool tci_error(u8 tci) {
    // Sanity check: MACsec version bit should be zero.
    if (tci & FLAG_VER) return true;
    // Sanity check: Never set both ES and SC flags.
    return ((tci & FLAG_SCI) && (tci & FLAG_ES));
}

MacSec::MacSec(unsigned key_len_bits, const u8* key, u8 tci, u64 sci)
    : m_gcm(key_len_bits, key, 0, 0)
    , m_sci(sci)                // Secure channel identifier
    , m_ssci(0)                 // Not used in regular mode
    , m_xpn(false)              // Disable extended packet number
    , m_error(tci_error(tci))   // TCI error?
    , m_tci(tci)                // Tag control info (TCI) + Association number (AN)
    , m_salt{}                  // Not used in regular mode
{
    // Nothing else to initialize.
}

MacSec::MacSec(unsigned key_len_bits, const u8* key, const u8* salt, u8 tci, u64 sci, u32 ssci)
    : m_gcm(key_len_bits, key, IV_LEN_BYTES*8, salt)
    , m_sci(sci)                // Secure channel identifier
    , m_ssci(ssci)              // Short secure channel ID
    , m_xpn(true)               // Enable extended packet number
    , m_error(tci_error(tci))   // Error during initialization?
    , m_tci(tci)                // Tag control info (TCI) + Association number (AN)
    , m_salt{}                  // Initial value (aka "salt") = 12 bytes
{
    memcpy(m_salt, salt, 12);
}

// performs GCM-AES encryption on the input ethernet frame's type+data
// and authentication on the macsec frame's header+encrypted data.
bool MacSec::encrypt_frame(Readable* src, Writeable* dst, u64 packet_number) {
    // Sanity check before we start...
    if (m_error) return false;
    if (src->get_read_ready() < 14) return false;
    if (src->get_read_ready() > MAX_PT_FRAME) return false;

    // Read the MAC addresses from the incoming Ethernet header.
    // (Note: MACsec goes outside VLAN headers, if present.)
    MacAddr dstmac, srcmac;
    dstmac.read_from(src);
    srcmac.read_from(src);

    // Note user data length and set the short-length header (Section 9.7)
    // (The plaintext user input includes the inner EtherType plus data.)
    unsigned in_len = src->get_read_ready();        // Payload/Input
    u8 sl = (in_len < MAX_LEN_SL) ? u8(in_len) : 0; // Short length?

    // Create the working buffer for the output frame contents.
    u8 buffer[MAX_CT_FRAME];
    ArrayWrite wr(buffer, MAX_CT_FRAME);

    // Write the outgoing Ethernet header: DstMac, SrcMac, Etype.
    // Note: Outer EtherType is also considered part of SecTag.
    wr.write_obj(dstmac);                           // Always copy DstMAC
    if (m_tci & FLAG_ES) {                          // Replace source-MAC?
        wr.write_u48(m_sci >> 16);                  // MSBs of channel-ID
    } else {
        wr.write_obj(srcmac);                       // Original source-MAC
    }
    wr.write_obj(ETYPE_MACSEC);                     // Outer EtherType

    // Write the SecTag (Section 9.3)
    wr.write_u8(m_tci);                             // Combined TCI + AN
    wr.write_u8(sl);                                // Short length
    wr.write_u32(packet_number);                    // LSBs of packet number
    if (m_tci & FLAG_SCI) wr.write_u64(m_sci);      // Include SCI field?

    // Copy the plaintext input into the working buffer.
    src->copy_and_finalize(&wr);

    // Encrypt-in-place and/or authenticate the working buffer contents.
    // (MACsec can be used for authentication without confidentiality.)
    u8 icv[ICV_LEN_BYTES];
    set_gcm_frame_iv(packet_number);                // Set IV for this frame
    u8* buf_pt = buffer + header_len(m_tci);        // Start of plaintext
    if (m_tci & FLAG_ENC) m_gcm.encrypt_decrypt(in_len, buf_pt, buf_pt);
    calculate_icv(wr.written_len(), buffer, icv);   // Calculate ICV

    // Copy the final result to the output.
    dst->write_bytes(wr.written_len(), buffer);
    dst->write_bytes(ICV_LEN_BYTES, icv);
    return dst->write_finalize();
}

bool MacSec::decrypt_frame(Readable* src, Writeable* dst, u64& packet_number) {
    // Sanity check before we start...
    if (m_error) return false;
    if (src->get_read_ready() > MAX_CT_FRAME) return false;

    // Copy the entire input frame to a working buffer.
    unsigned raw_len = src->get_read_ready();
    u8 buffer[MAX_CT_FRAME];
    src->read_bytes(raw_len, buffer);

    // Read the Ethernet header and SecTag.
    satcat5::io::ArrayRead rd(buffer, raw_len);
    MacAddr dstmac, srcmac;
    dstmac.read_from(&rd);
    srcmac.read_from(&rd);
    MacType etype;
    etype.read_from(&rd);

    // Anything that's not a MACsec frame is discarded.
    if (etype != ETYPE_MACSEC) return false;

    // Read the MACsec header (aka SecTag).
    // Note: SCI is used to multiplex streams with different keys,
    //  but we only support one loaded key at a time, so ignore it.
    u8 tci = rd.read_u8();                          // TAG control information
    u8 sl  = rd.read_u8();                          // Short length (if < 48)
    u32 pn = rd.read_u32();                         // Packet number LSBs
    if (tci & FLAG_SCI) rd.read_u64();              // Optional SCI field

    // Calculate effective cyphertext length.
    if (rd.get_read_ready() < ICV_LEN_BYTES) return false;
    unsigned len_usr = rd.get_read_ready() - ICV_LEN_BYTES;
    if (sl > 0 && sl < len_usr) len_usr = sl;       // Trim if zero-padded
    unsigned len_aad = header_len(tci) + len_usr;   // Authenticated length

    // Calculate useful offsets into the buffer.
    u8* buf_usr = buffer + header_len(tci);         // Start of user data
    u8* buf_icv = buffer + len_aad;                 // Start of received ICV

    // Detect extended packet-number rollover. (Section 10.6.2)
    u64 rcvd_pn = pn;                                   // PN from header
    if (m_xpn) {
        constexpr u64 LSB_MASK = 0x00000000FFFFFFFFull;
        constexpr u64 MSB_MASK = 0xFFFFFFFF00000000ull;
        u32 ref_lsb = u32(packet_number & LSB_MASK);    // Reference LSBs
        rcvd_pn |= (packet_number & MSB_MASK);          // Add previous MSBs
        if (pn <= ref_lsb) rcvd_pn += (1ull << 32);     // Rollover detected?
    }

    // Authenticate the working buffer, then optionally decrypt in-place.
    // (MACsec can be used for authentication without confidentiality.)
    u8 calc_icv[ICV_LEN_BYTES];
    set_gcm_frame_iv(packet_number);                // Set IV for this frame
    calculate_icv(len_aad, buffer, calc_icv);       // Calculated ICV
    if (tci & FLAG_ENC) m_gcm.encrypt_decrypt(len_usr, buf_usr, buf_usr);
    if (memcmp(calc_icv, buf_icv, ICV_LEN_BYTES)) return false;

    // Authentication OK! Store result and update packet-number.
    packet_number = rcvd_pn + 1;                    // Next allowed PN
    dst->write_obj(dstmac);                         // Copy raw DstMAC
    dst->write_obj(srcmac);                         // Copy raw SrcMAC
    dst->write_bytes(len_usr, buf_usr);             // Decrypted user data
    return dst->write_finalize();                   // Packet accepted?
}

void MacSec::calculate_icv(unsigned len_tot, const u8* frame, u8* icv) {
    // Encrypted mode: Eth header + SecTag is AAD, remainder is cyphertext.
    // Plaintext mode: Eth header + SecTag + Data are all AAD.
    unsigned len_aad = (m_tci & FLAG_ENC) ? header_len(m_tci) : len_tot;
    unsigned len_txt = len_tot - len_aad;
    m_gcm.compute_tag(len_aad, len_txt, frame, frame + len_aad, icv);
}

void MacSec::set_gcm_frame_iv(u64 packet_number) {
    u8 frame_iv[IV_LEN_BYTES];
    if (m_xpn) {
        memcpy(frame_iv, m_salt, IV_LEN_BYTES);
        frame_iv[11] ^= (packet_number)     & 0xFF;
        frame_iv[10] ^= (packet_number>>8)  & 0xFF;
        frame_iv[9]  ^= (packet_number>>16) & 0xFF;
        frame_iv[8]  ^= (packet_number>>24) & 0xFF;
        frame_iv[7]  ^= (packet_number>>32) & 0xFF;
        frame_iv[6]  ^= (packet_number>>40) & 0xFF;
        frame_iv[5]  ^= (packet_number>>48) & 0xFF;
        frame_iv[4]  ^= (packet_number>>56) & 0xFF;
        frame_iv[3]  ^= (m_ssci)     & 0xFF;
        frame_iv[2]  ^= (m_ssci>>8)  & 0xFF;
        frame_iv[1]  ^= (m_ssci>>16) & 0xFF;
        frame_iv[0]  ^= (m_ssci>>24) & 0xFF;
    } else {
        frame_iv[11] = (packet_number)     & 0xFF;
        frame_iv[10] = (packet_number>>8)  & 0xFF;
        frame_iv[9]  = (packet_number>>16) & 0xFF;
        frame_iv[8]  = (packet_number>>24) & 0xFF;
        frame_iv[7]  = (m_sci)     & 0xFF;
        frame_iv[6]  = (m_sci>>8)  & 0xFF;
        frame_iv[5]  = (m_sci>>16) & 0xFF;
        frame_iv[4]  = (m_sci>>24) & 0xFF;
        frame_iv[3]  = (m_sci>>32) & 0xFF;
        frame_iv[2]  = (m_sci>>40) & 0xFF;
        frame_iv[1]  = (m_sci>>48) & 0xFF;
        frame_iv[0]  = (m_sci>>56) & 0xFF;
    }
    m_gcm.set_iv(IV_LEN_BYTES*8, frame_iv);
}
