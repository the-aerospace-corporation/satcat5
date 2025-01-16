//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ccsds_aos.h>
#include <satcat5/ccsds_spp.h>
#include <satcat5/utils.h>

using satcat5::ccsds_aos::Channel;
using satcat5::ccsds_aos::Dispatch;
using satcat5::ccsds_aos::Header;
using satcat5::ccsds_spp::APID_IDLE;
using satcat5::io::ArrayRead;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::net::Type;
using satcat5::util::min_unsigned;

// Define fields for Dispatch::m_state:
static constexpr u8 STATE_PRESYNC   = 0x80;     // Pre-packetized input?
static constexpr u8 STATE_DATA      = 0x40;     // Header OK, ready for data?
static constexpr u8 STATE_SYNC      = 0x07;     // Count matched sync-bytes

// Define fields for the M_PDU and B_PDU headers.
static constexpr u16 MPDU_MASK      = 0x07FF;   // First header location
static constexpr u16 MPDU_NONE      = MPDU_MASK;
static constexpr u16 BPDU_MASK      = 0xCFFF;   // Bitstream length
static constexpr u16 BPDU_FULL      = BPDU_MASK;
static constexpr u16 BPDU_NULL      = BPDU_MASK - 1;

// Min and max size for inserting SPP idle packets.
static constexpr unsigned MIN_FILLER = 7;
static constexpr unsigned MAX_FILLER = 256;

void Header::write_to(Writeable* wr) const {
    u8  ext = u8(count >> 24) & FRCT_VAL_MASK;
    u8  sig = signal & (REPLAY_MASK | FRCT_EXT_MASK);
    u32 cbo = (count << 8) | u32(sig);          // Combine count + signal
    if (signal & FRCT_EXT_MASK) cbo |= ext;     // Extended frame-count?
    wr->write_u16(id);
    wr->write_u32(cbo);
}

bool Header::read_from(Readable* rd) {
    if (rd->get_read_ready() < 6) return false;
    id      = rd->read_u16();                   // ID field is straightforward
    count   = rd->read_u24();                   // Basic frame-count (24 bit)
    signal  = rd->read_u8();                    // Signaling field
    if (signal & FRCT_EXT_MASK)                 // Extended frame-count?
        count += 16777216 * (signal & FRCT_VAL_MASK);
    return true;
}

Header& Header::operator++() {
    u32 rollover = (signal & FRCT_EXT_MASK) ? (1u << 28) : (1u << 24);
    count = (count + 1) & (rollover - 1);
    return *this;
}

Channel::Channel(
    Dispatch* iface, Readable* src, Writeable* dst,
    u8 svid, u8 vcid, bool pkt)
    : Protocol(satcat5::net::TYPE_NONE)
    , m_iface(iface)
    , m_src(src)
    , m_dst(dst)
    , m_rx_spp(m_rx_tmp, sizeof(m_rx_tmp))
    , m_rx_next(svid, vcid)
    , m_tx_next(svid, vcid)
    , m_rx_state(pkt ? State::RESYNC : State::RAW)
    , m_rx_rem(0)
    , m_tx_busy(0)
    , m_tx_irem(0)
    , m_tx_iseq(0)
    , m_rx_tmp{}
{
    m_filter = Type(m_rx_next.id);
    m_iface->add(this);
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Channel::~Channel() {
    m_iface->remove(this);
    if (m_src) m_src->set_callback(0);
}
#endif

void Channel::desync() {
    if (m_rx_state != State::RESYNC) {
        m_rx_state = State::RESYNC;
        m_rx_spp.write_abort();
        m_rx_rem = 0;
        m_dst->write_abort();
    }
}

// Callback for each incoming AOS transfer frame.
void Channel::frame_rcvd(LimitedRead& src) {
    // Sanity check: Abort & discard if there's output is disabled.
    if (!m_dst) return;

    // Read the frame and PDU headers.
    auto frm_hdr = m_iface->rcvd_hdr();
    u16  pdu_hdr = src.read_u16();

    // Parse the transfer frame data field...
    if (m_rx_state == State::RAW) {
        // Byte-stream (B_PDU) = Section 4.1.4.3
        // TODO: Handle inputs that aren't byte-aligned?
        if ((pdu_hdr & BPDU_MASK) == BPDU_NULL) return;
        unsigned pdu_bits  = 1 + unsigned(pdu_hdr & BPDU_MASK);
        unsigned pdu_bytes = min_unsigned(src.get_read_ready(), pdu_bits/8);
        // Copy valid bytes to the output buffer.
        // (Nothing we can do if we've lost a packet.)
        LimitedRead(&src, pdu_bytes).copy_to(m_dst);
        m_dst->write_finalize();
    } else {
        // Packet mode (M_PDU) = Section 4.1.4.2
        unsigned first_spp = unsigned(pdu_hdr & MPDU_MASK);
        if (first_spp == MPDU_NONE) first_spp = src.get_read_ready();
        // Desync if we've missed data or fail a sanity check.
        unsigned expect_spp = min_unsigned(m_rx_rem, src.get_read_ready());
        bool bad_align = (m_rx_state == State::DATA) && (first_spp != expect_spp);
        bool bad_count = (m_rx_next.count != frm_hdr.count);
        if (bad_align || bad_count) desync();
        // If resync required, discard up to the next SPP header, if any.
        if (m_rx_state == State::RESYNC) {
            if (first_spp) src.read_consume(first_spp);
        }
        // Keep reading data until input is empty or output is full...
        while (m_dst->get_write_space() && src.get_read_ready()) {
            // Read next SPP packet header, if we haven't already.
            if (!read_header(&src)) break;
            // Read SPP data up to end of SPP or AOS, whichever comes first.
            unsigned maxrd = min_unsigned(src.get_read_ready(), m_rx_rem);
            if (m_rx_state == State::DATA) {
                // Copy data to output until end-of-frame.
                m_rx_rem -= LimitedRead(&src, maxrd).copy_to(m_dst);
                if (!m_rx_rem) m_dst->write_finalize();
            } else {
                // Skip over idle frames.
                src.read_consume(maxrd); m_rx_rem -= maxrd;
            }
        }
        // If the output buffer overflowed, desync.
        if (src.get_read_ready()) desync();
    }

    // Update expected header for next time.
    m_rx_next = frm_hdr;
    ++m_rx_next;
}

// Callback for queued outgoing data.
void Channel::data_rcvd(Readable* src) {
    // Both transfer frame formats use a two-byte header.
    const unsigned dmax = m_iface->dsize() - 2;
    // Keep sending transfer frame(s) until we exhaust the input...
    while (src->get_read_ready()) {
        // Can the output fit another transfer frame?
        Writeable* wr = m_iface->open_write(m_tx_next);
        if (!wr) break;         // Output is full, try again later.
        ++m_tx_next;            // Increment next sequence counter.
        // What is the format for this channel?
        if (m_rx_state == State::RAW) {
            // Byte-stream (B_PDU) = Section 4.1.4.3
            // Partial frames indicate the number of valid bits.
            unsigned nbytes = min_unsigned(src->get_read_ready(), dmax);
            wr->write_u16((nbytes < dmax) ? u16(8*nbytes-1) : BPDU_FULL);
            // Copy stream data, then zero-pad as needed.
            LimitedRead(src, nbytes).copy_to(wr);
            for (unsigned a = nbytes ; a < dmax ; ++a) wr->write_u8(0);
        } else {
            // Packet mode (M_PDU) = Section 4.1.4.2
            // Write the AOS header, indicating next SPP start position.
            if (m_tx_busy) {
                // Continue SPP packet from previous transfer frame.
                // Next header starts immediately after, if there's room.
                unsigned rem = min_unsigned(dmax, src->get_read_ready());
                wr->write_u16((rem < dmax) ? u16(rem) : MPDU_NONE);
            } else {
                // Start first SPP immediately or after trailing idle.
                wr->write_u16(m_tx_irem);
            }
            // Trailing bytes from a split minimum-length idle packet?
            // (We try to avoid this, but it is sometimes inevitable.)
            satcat5::io::LimitedWrite aos(wr, dmax);
            if (m_tx_irem) m_tx_irem = idle_filler(&aos, MIN_FILLER);
            // Copy SPPs until input is exhausted or PDU is filled.
            while (aos.get_write_space() && src->get_read_ready()) {
                src->copy_to(&aos);
                if (!src->get_read_ready()) src->read_finalize();
            }
            m_tx_busy = (src->get_read_ready() ? 1 : 0);
            // If there's any space left, add filler packet(s) as needed.
            // (If possible, align the pad with the transfer frame boundary.)
            while (aos.get_write_space())
                m_tx_irem = idle_filler(&aos, aos.get_write_space());
        }
        // End of AOS transfer frame.
        wr->write_finalize();
    }
}

void Channel::data_unlink(Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

u8 Channel::idle_filler(Writeable* dst, unsigned req) {
    // Try to align to match the trasfer-frame boundary, but
    // clamp as needed to the supported min/max SPP length.
    if (req < MIN_FILLER) req = MIN_FILLER;
    if (req > MAX_FILLER) req = MAX_FILLER;
    // Trim if the *next* filler frame would need to split.
    unsigned rem = dst->get_write_space();
    if (req < rem && rem < req + MIN_FILLER) req -= MIN_FILLER;
    // Generate SPP header for the next idle packet.
    satcat5::ccsds_spp::Header hdr;
    hdr.set(false, APID_IDLE, m_tx_iseq);
    // Write the idle packet to a temporary buffer.
    u8 tmp[MAX_FILLER] = {0};
    satcat5::io::ArrayWrite wr(tmp, req);
    wr.write_u32(hdr.value);            // 6-byte header + Zero-pad
    wr.write_u16(req - 7);              // Pad length - 1
    // Copy the temporary buffer to the output, with
    // offset for bytes written on a previous attempt.
    unsigned skip = m_tx_irem ? (req - m_tx_irem) : 0;
    unsigned copy = min_unsigned(req - skip, dst->get_write_space());
    dst->write_bytes(copy, tmp + skip);
    return u8(req - skip - copy);       // Split bytes in next frame?
}

bool Channel::read_header(Readable* src) {
    // Should we start reading a new SPP header?
    constexpr unsigned SPP_HDR_LEN = 6;
    if (m_rx_state != State::HEADER) {
        if (m_rx_rem) return true;      // Mid-packet (DATA or SKIP)
        m_rx_state = State::HEADER;     // Start of new SPP header
        m_rx_rem   = SPP_HDR_LEN;
    }
    // Sanity check: Pause until there's space in the output buffer.
    if (m_dst->get_write_space() < SPP_HDR_LEN) return false;
    // Copy bytes to the working buffer.
    m_rx_rem -= src->copy_to(&m_rx_spp);
    if (m_rx_rem) return false;         // Incomplete header?
    // Parse the complete SPP header.
    ArrayRead rd(m_rx_tmp, sizeof(m_rx_tmp));
    satcat5::ccsds_spp::Header spp {rd.read_u32()};
    m_rx_rem = 1 + unsigned(rd.read_u16());
    // Is this idle filler or real data?
    if (spp.apid() == APID_IDLE) {
        m_rx_state = State::SKIP;       // Skip idle frames.
    } else {
        m_rx_state = State::DATA;       // Copy header + data.
        m_dst->write_bytes(sizeof(m_rx_tmp), m_rx_tmp);
    }
    m_rx_spp.write_finalize();          // Reset working buffer
    return true;                        // Ready to read SPP contents
}

Dispatch::Dispatch(Readable* src, Writeable* dst, u8* buff, unsigned dsize, bool insert)
    : m_dsize(dsize)
    , m_insert(insert)
    , m_sync_state(0)
    , m_src(src)
    , m_dst(dst)
    , m_work(buff, tsize())
    , m_crc_rx(&m_work, 0xFFFF)
    , m_crc_tx(dst, 0xFFFF)
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch() {
    if (m_src) m_src->set_callback(0);
}
#endif

// Stub required for the Dispatch API (reply mode is not supported).
Writeable* Dispatch::open_reply(const Type& type, unsigned len) {return 0;} // GCOVR_EXCL_LINE

Writeable* Dispatch::open_write(const Header& hdr) {
    // Sanity-check that a valid output exists.
    if (!m_dst) return 0;

    // Sanity-check available buffer before we start.
    unsigned required = tsize() + (m_insert ? 4 : 0);
    if (m_crc_tx.get_write_space() < required) return 0;

    // If sync headers are enabled, they bypass the CRC system.
    if (m_insert) m_dst->write_u32(TM_SYNC_WORD);

    // Write AOS frame header. User must write data and finalize.
    m_crc_tx.write_obj(hdr);
    return &m_crc_tx;
}

void Dispatch::data_rcvd(Readable* src) {
    while (src->get_read_ready()) {
        // If applicable, find and read the sync word.  Then copy data
        // from source through the CRC check up to next frame boundary.
        if (read_sync(src) && read_data(src)) {
            // If CRC matches, read header and deliver to indicated Channel.
            if (m_crc_rx.write_finalize()) {
                ArrayRead rd(m_work.buffer(), m_work.written_len());
                rd.read_obj(m_rcvd_hdr);
                if (m_rcvd_hdr.vcid() != VCID_IDLE)
                    deliver(Type(m_rcvd_hdr.id), &rd, dsize());
            }
            // Regardless, reset state for the next transfer frame.
            m_sync_state = 0;
            bool more_data = (m_insert && src->get_read_ready());
            if (!more_data) src->read_finalize();
        }
    }
}

void Dispatch::data_unlink(Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

bool Dispatch::read_sync(Readable* src) {
    // Skip this process if sync-word insertion is disabled.
    if (!m_insert) return true;
    // Read one byte at a time until we find a sync header.
    constexpr unsigned SYNC_LEN = sizeof(TM_SYNC_BYTES);
    while (m_sync_state < SYNC_LEN && src->get_read_ready()) {
        u8 next = src->read_u8();
        if (next == TM_SYNC_BYTES[0]) {
            m_sync_state = 1;   // Match first sync byte?
        } else if (next == TM_SYNC_BYTES[m_sync_state]) {
            ++m_sync_state;     // Match next sync byte?
        } else {
            m_sync_state = 0;   // No match = start over.
        }
    }
    return (m_sync_state >= SYNC_LEN);
}

bool Dispatch::read_data(Readable* src) {
    // Copy as much as we can through the CRC validator.
    // Return true if we've written a complete transfer frame.
    return src->copy_to(&m_crc_rx) && !m_work.get_write_space();
}
