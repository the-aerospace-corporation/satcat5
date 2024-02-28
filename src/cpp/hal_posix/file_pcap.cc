//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/file_pcap.h>
#include <satcat5/datetime.h>
#include <satcat5/log.h>

using satcat5::io::ReadPcap;
using satcat5::io::WritePcap;
using satcat5::log::Log;

// Set debugging verbosity level (0/1/2)
constexpr unsigned DEBUG_VERBOSE = 0;

// Magic-numbers for PCAP:
constexpr u32 BLK_PCAP_HDR1_BE  = 0xA1B2C3D4;
constexpr u32 BLK_PCAP_HDR2_BE  = 0xA1B23C4D;
constexpr u32 BLK_PCAP_HDR1_LE  = 0xD4C3B2A1;
constexpr u32 BLK_PCAP_HDR2_LE  = 0x4D3CB2A1;

// Magic-numbers for PCAPNG (Section 11.1):
constexpr u32 BLK_PCAPNG_IDB    = 1;
constexpr u32 BLK_PCAPNG_SPB    = 3;
constexpr u32 BLK_PCAPNG_EPB    = 6;
constexpr u32 BLK_PCAPNG_SHB    = 0x0A0D0D0Au;
constexpr u32 PCAPNG_MAGIC_BE   = 0x1A2B3C4D;

// Calculate zero-padding for word-aligned PCAPNG fields.
constexpr inline unsigned word_pad(unsigned len)
    { return (-len) % 4; }

ReadPcap::ReadPcap(const char* filename)
    : satcat5::io::ArrayRead(m_buff, 0)
    , m_file(0)
    , m_mode_be(false)
    , m_mode_ng(false)
    , m_mode_pc(false)
    , m_trim(0)
{
    if (filename) open(filename);
}

void ReadPcap::open(const char* filename)
{
    if (DEBUG_VERBOSE > 0)
        Log(satcat5::log::DEBUG, "ReadPcap::open");

    // Open the specified file.
    m_file.open(filename);

    // Reset parser state.
    m_mode_be = false;
    m_mode_ng = false;
    m_mode_pc = false;
    m_trim = 0;

    // Read first word to detect format...
    u32 magic = m_file.read_u32();
    if (magic == BLK_PCAPNG_SHB) {
        // PCAPNG format, read the rest of the SHB.
        m_mode_ng = true;
        pcapng_shb();   // Read header.
    } else if (magic == BLK_PCAP_HDR1_BE || magic == BLK_PCAP_HDR2_BE) {
        // PCAP format, big-endian.
        m_mode_be = true;
        pcap_hdr();     // Read header
    } else if (magic == BLK_PCAP_HDR1_LE || magic == BLK_PCAP_HDR2_LE) {
        // PCAP format, little-endian.
        m_mode_be = false;
        pcap_hdr();     // Read header
    } else {
        // Invalid file or unsupported format.
        m_file.close();
        Log(satcat5::log::ERROR, "ReadPcap: Invalid file");
    }

    // If this is a valid file, attempt to read the first data packet.
    if (m_mode_ng || m_mode_pc) read_finalize();
}

void ReadPcap::read_finalize()
{
    // Done with current frame, clear the working buffer.
    read_reset(0);

    // Get ready to start reading the next frame.
    // Keep reading PCAP records or PCAPNG blocks, one at a time, until
    // we find a valid data packet or reach the end of the input file.
    if (m_mode_pc) {
        while (m_file.get_read_ready() && !pcap_dat()) {}
    } else if (m_mode_ng) {
        while (m_file.get_read_ready() && !pcapng_blk()) {}
    }
}

void ReadPcap::pcap_hdr()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcap_hdr");

    // Read the file header (Section 4).
    // (Note we've already read the "magic number".)
    u16 major = file_rd16();
    u16 minor = file_rd16();
    m_file.read_consume(12);
    u32 type = file_rd32();

    // Only version 2.4 is supported.
    // If FCS mode is enabled ("f" bit is set), note the FCS length.
    if (major == 2 && minor == 4) {
        m_mode_pc = true;
        if (type & 0x10000000) m_trim = (type >> 29);
    }
}

bool ReadPcap::pcap_dat()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcap_dat");

    // Read the "packet record" header (Section 5).
    m_file.read_consume(8);     // Skip timestamp
    u32 clen = file_rd32();     // Captured packet length
    u32 olen = file_rd32();     // Original packet length

    // Take further action?
    if (clen <= m_trim || olen <= m_trim) {
        // Abort on end-of-file or invalid length.
        m_file.close();
    } else if (olen <= clen && clen <= sizeof(m_buff)) {
        // Copy normal packets to the working buffer.
        m_file.read_bytes(clen, m_buff);
        read_reset(olen - m_trim);
    } else {
        // Skip if truncated or larger than our working buffer.
        m_file.read_consume(clen);
    }

    // Did we read some data successfully?
    return get_read_ready() > 0;
}

bool ReadPcap::pcapng_blk()
{
    // Read the block type and parse accordingly...
    switch (file_rd32()) {
    case BLK_PCAPNG_IDB:    pcapng_idb(); break;
    case BLK_PCAPNG_SPB:    pcapng_spb(); break;
    case BLK_PCAPNG_EPB:    pcapng_epb(); break;
    case BLK_PCAPNG_SHB:    pcapng_shb(); break;
    default:                pcapng_skip(); break;
    }

    // Did we read some data successfully?
    return get_read_ready() > 0;
}

void ReadPcap::pcapng_shb()
{
    if (DEBUG_VERBOSE > 0)
        Log(satcat5::log::DEBUG, "ReadPcap::pcapng_shb");

    // Section Header Block (SHB), Section 4.1.
    // Read the "block total length" and the "byte-order magic".
    u32 len = m_file.read_u32();
    u32 bom = m_file.read_u32();

    // Detect byte-order and reinterpret length accordingly.
    m_mode_be = (bom == PCAPNG_MAGIC_BE);
    if (!m_mode_be) len = __builtin_bswap32(len);

    // Discard the rest of this block.
    if (len > 12) m_file.read_consume(len - 12);
}

void ReadPcap::pcapng_idb()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcapng_idb");

    // Interface Description Block (IDB), Section 4.2.
    // Read block length and discard up to the Options field.
    u32 blen = file_rd32();
    m_file.read_consume(8);
    // TODO: Filter by LinkType?

    // Read the concatenated options (Section 3.5).
    u32 rdpos = 16;
    while (rdpos + 8 < blen) {
        // Read type and length.
        u16 opt_typ = file_rd16();
        u16 opt_len = file_rd16();
        rdpos += 4;
        // End of options? (opt_endofopt = 0)
        if (opt_typ == 0) break;
        // Parse selected options and ignore all others.
        if (opt_typ == 13 && opt_len == 1) {
            m_trim = m_file.read_u8();  // "if_fcslen"
            m_file.read_consume(3);
            rdpos += 4;
        } else {
            unsigned pad_len = opt_len + word_pad(opt_len);
            m_file.read_consume(pad_len);
            rdpos += pad_len;
        }
    }

    // Discard up to the start of the next block.
    m_file.read_consume(blen - rdpos);
}

void ReadPcap::pcapng_spb()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcapng_spb");

    // Simple Packet Block (SPB), Section 4.4.
    u32 blen = file_rd32();     // Block total length
    u32 olen = file_rd32();     // Original packet length
    u32 plen = blen - 16;       // Size of packet data field

    // Take further action?
    if (blen < 16 || plen <= m_trim || olen <= m_trim) {
        // Abort on end-of-file or invalid length.
        m_file.close();
    } else if (olen <= plen && olen <= sizeof(m_buff)) {
        // Copy normal packets to the working buffer.
        m_file.read_bytes(olen, m_buff);
        read_reset(olen - m_trim);
        // Discard zero-pad and end-of-block footer.
        m_file.read_consume(4 + plen - olen);
    } else {
        // Skip if truncated or larger than our working buffer.
        m_file.read_consume(4 + plen);
    }
}

void ReadPcap::pcapng_epb()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcapng_epb");

    // Enhanced Packet Block (SPB), Section 4.3.
    // TODO: Support multi-interface captures and filter by interface ID?
    u32 blen = file_rd32();     // Block total length
    m_file.read_consume(12);    // Discard interface ID and timestamp.
    u32 clen = file_rd32();     // Captured packet length
    u32 olen = file_rd32();     // Original packet length

    // Take further action?
    if (clen <= m_trim || olen <= m_trim) {
        // Abort on end-of-file or invalid length.
        m_file.close();
    } else if (olen <= clen && olen <= sizeof(m_buff)) {
        // Copy normal packets to the working buffer.
        m_file.read_bytes(olen, m_buff);
        read_reset(olen - m_trim);
        // Discard zero-pad, options, and end-of-block footer.
        m_file.read_consume(blen - olen - 28);
    } else {
        // Skip if truncated or larger than our working buffer.
        m_file.read_consume(blen - 28);
    }
}

void ReadPcap::pcapng_skip()
{
    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "ReadPcap::pcapng_skip");

    // Skip unknown blocks using core header, Section 3.1.
    u32 blen = file_rd32();     // Block total length
    if (blen > 8) m_file.read_consume(blen - 8);
}

WritePcap::WritePcap(satcat5::datetime::Clock* clock, const char* filename, bool pcapng)
    : satcat5::io::ArrayWrite(m_buff, sizeof(m_buff))
    , m_clock(clock)
    , m_file(0)
    , m_mode_ng(pcapng)
    , m_mode_ovr(false)
{
    if (filename) open(filename);
}

void WritePcap::open(const char* filename)
{
    if (DEBUG_VERBOSE > 0)
        Log(satcat5::log::DEBUG, "WritePcap::open");

    // Open the designated file.
    m_file.open(filename);

    // Write the PCAP or PCAPNG header...
    if (m_mode_ng) {
        // Write PCAPNG-SHB block (Section 4.1).
        m_file.write_u32(BLK_PCAPNG_SHB);           // Block type
        m_file.write_u32(32);                       // Block total length
        m_file.write_u32(PCAPNG_MAGIC_BE);          // Byte-Order Magic
        m_file.write_u32(0x00010000);               // Version 1.0
        m_file.write_u64(-1ull);                    // Section length disabled
        m_file.write_u32(0);                        // Options (none)
        m_file.write_u32(32);                       // Block total length (again)
        // Write PCAPNG-IDB block (Section 4.2).
        m_file.write_u32(BLK_PCAPNG_IDB);           // Block type
        m_file.write_u32(24);                       // Block total length
        m_file.write_u32(0x00010000);               // LinkType = Ethernet
        m_file.write_u32(SATCAT5_PCAP_BUFFSIZE);    // SnapLen
        m_file.write_u32(0);                        // Options (none)
        m_file.write_u32(24);                       // Block total length (again)
    } else {
        // Write the legacy PCAP header (Section 4).
        m_file.write_u32(BLK_PCAP_HDR1_BE);         // Magic number
        m_file.write_u32(0x00020004);               // Version 2.4
        m_file.write_u32(0);                        // Reserved
        m_file.write_u32(0);                        // Reserved
        m_file.write_u32(SATCAT5_PCAP_BUFFSIZE);    // SnapLen
        m_file.write_u32(1);                        // LinkType = Ethernet
    }
}

bool WritePcap::write_finalize()
{
    // Timestamp is measured in microseconds since UNIX epoch.
    constexpr u64 GPS2UNIX = 315964800000000ull;
    u64 unix_usec = 0;
    if (m_clock) unix_usec = 1000 * m_clock->now() + GPS2UNIX;

    // Forward event to parent class and note frame length.
    // (If overflow flag is set, original packet size is unknown.)
    satcat5::io::ArrayWrite::write_finalize();
    u32 clen = written_len();                       // Captured length
    u32 olen = m_mode_ovr ? UINT32_MAX : clen;      // Original length
    m_mode_ovr = false;                             // Reset overflow flag

    if (DEBUG_VERBOSE > 1)
        Log(satcat5::log::DEBUG, "WritePcap::write").write10(clen);

    // Write the buffered packet contents...
    if (m_mode_ng) {
        // Calculate packet length including zero-pad.
        u32 plen = clen + word_pad(clen);
        // Write the PCAPNG-EPB block.
        m_file.write_u32(BLK_PCAPNG_EPB);           // Block type
        m_file.write_u32(36 + plen);                // Block total length
        m_file.write_u32(0);                        // Interface ID = 0
        m_file.write_u64(unix_usec);                // Timestamp
        m_file.write_u32(clen);                     // Captured packet length
        m_file.write_u32(olen);                     // Original packet length
        m_file.write_bytes(plen, m_buff);           // Packet data
        m_file.write_u32(0);                        // Options (none)
        m_file.write_u32(36 + plen);                // Block total length (again)
    } else {
        // Write the legacy PCAP packet record.
        m_file.write_u32(unix_usec / 1000000ull);   // Timestamp (sec)
        m_file.write_u32(unix_usec % 1000000ull);   // Timestamp (usec)
        m_file.write_u32(clen);                     // Captured packet length
        m_file.write_u32(olen);                     // Original packet length
        m_file.write_bytes(clen, m_buff);           // Packet data
    }
    return m_file.write_finalize();
}

void WritePcap::write_overflow()
{
    if (DEBUG_VERBOSE > 0)
        Log(satcat5::log::DEBUG, "WritePcap::write_overflow");
    m_mode_ovr = true;
}
