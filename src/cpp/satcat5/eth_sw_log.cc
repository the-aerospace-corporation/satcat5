//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_stats.h>
#include <satcat5/datetime.h>
#include <satcat5/eth_sw_log.h>
#include <satcat5/log.h>

using satcat5::eth::Header;
using satcat5::eth::SwitchLogFormatter;
using satcat5::eth::SwitchLogHardware;
using satcat5::eth::SwitchLogMessage;
using satcat5::eth::SwitchLogReader;
using satcat5::eth::SwitchLogStats;
using satcat5::eth::SwitchLogWriter;
using satcat5::io::Readable;

// Explicit re-declaration of class-local constants.
// (Workaround for linker errors in some versions of GCC.)
constexpr u8 SwitchLogMessage::REASON_KEEP;
constexpr u8 SwitchLogMessage::DROP_OVERFLOW;
constexpr u8 SwitchLogMessage::DROP_BADFCS;
constexpr u8 SwitchLogMessage::DROP_BADFRM;
constexpr u8 SwitchLogMessage::DROP_MCTRL;
constexpr u8 SwitchLogMessage::DROP_VLAN;
constexpr u8 SwitchLogMessage::DROP_VRATE;
constexpr u8 SwitchLogMessage::DROP_PTPERR;
constexpr u8 SwitchLogMessage::DROP_NO_ROUTE;
constexpr u8 SwitchLogMessage::DROP_DISABLED;
constexpr u8 SwitchLogMessage::DROP_UNKNOWN;

u8 SwitchLogMessage::reason() const {
    switch (type()) {
    case TYPE_KEEP: return REASON_KEEP;
    case TYPE_DROP: return u8(meta & 0xFF);
    default:        return DROP_UNKNOWN;
    }
}

const char* SwitchLogMessage::reason_str() const {
    switch (reason()) {
    case REASON_KEEP:       return "N/A";
    case DROP_OVERFLOW:     return "Overflow";
    case DROP_BADFCS:       return "Bad CRC";
    case DROP_BADFRM:       return "Bad header";
    case DROP_MCTRL:        return "Link-local";
    case DROP_VLAN:         return "VLAN policy";
    case DROP_VRATE:        return "Rate-limit";
    case DROP_PTPERR:       return "PTP error";
    case DROP_NO_ROUTE:     return "No route";
    case DROP_DISABLED:     return "Port off";
    default:                return "Unknown";
    }
}

u16 SwitchLogMessage::count_drop() const {
    if (type() == TYPE_KEEP) return 0;  // KEEP message
    if (type() == TYPE_DROP) return 1;  // DROP message
    return u16(meta >> 16);             // SKIP message
}

u16 SwitchLogMessage::count_keep() const {
    if (type() == TYPE_KEEP) return 1;  // KEEP message
    if (type() == TYPE_DROP) return 0;  // DROP message
    return u16(meta & 0xFFFF);          // SKIP message
}

void SwitchLogMessage::init_keep(const Header& _hdr, u8 _src, u32 _dst) {
    tstamp   = satcat5::datetime::clock.uptime_usec();
    type_src = TYPE_KEEP | (SRC_MASK & _src);
    hdr      = _hdr;
    meta     = _dst;
}

void SwitchLogMessage::init_drop(const Header& _hdr, u8 _src, u8 _why) {
    tstamp   = satcat5::datetime::clock.uptime_usec();
    type_src = TYPE_DROP | (SRC_MASK & _src);
    hdr      = _hdr;
    meta     = u32(_why);
}

void SwitchLogMessage::init_skip(u16 _drop, u16 _keep) {
    tstamp   = satcat5::datetime::clock.uptime_usec();
    type_src = TYPE_SKIP;
    hdr      = HEADER_NULL;
    meta     = (u32(_drop) << 16) | u32(_keep);
}

void SwitchLogMessage::log_to(satcat5::log::LogBuffer& wr) const {
    if (type() == TYPE_KEEP) {
        wr.wr_str("\r\n  Delivered to: 0x");
        wr.wr_h32(meta);
        hdr.log_to(wr);
    } else if (type() == TYPE_DROP) {
        wr.wr_str("\r\n  Dropped: ");
        wr.wr_str(reason_str());
        hdr.log_to(wr);
    } else if (type() == TYPE_SKIP) {
        wr.wr_str("\r\n  Summary: ");
        wr.wr_d32(count_keep());
        wr.wr_str(" delivered, ");
        wr.wr_d32(count_drop());
        wr.wr_str(" dropped.");
    }
}

void SwitchLogMessage::write_to(satcat5::io::Writeable* wr) const {
    wr->write_u24(tstamp);
    wr->write_u8(type_src);
    hdr.dst.write_to(wr);   // Write full header even if no VTAG.
    hdr.src.write_to(wr);
    hdr.type.write_to(wr);
    hdr.vtag.write_to(wr);
    wr->write_u32(meta);
}

bool SwitchLogMessage::read_from(Readable* rd) {
    if (rd->get_read_ready() < LEN_BYTES) return false;
    tstamp = rd->read_u24();
    type_src = rd->read_u8();
    hdr.dst.read_from(rd);  // Read full header even if no VTAG.
    hdr.src.read_from(rd);
    hdr.type.read_from(rd);
    hdr.vtag.read_from(rd);
    meta = rd->read_u32();
    return true;
}

SwitchLogHardware::SwitchLogHardware(
    SwitchLogHandler* dst, satcat5::cfg::Register src)
    : m_dst(dst)
    , m_src(src)
{
    // No interrupts, just poll at regular intervals.
    if (m_dst) timer_every(25);
}

void SwitchLogHardware::timer_event() {
    static constexpr u32 DATA_VALID = (1u << 31);
    static constexpr u32 DATA_FINAL = (1u << 30);

    // Poll the ConfigBus register...
    u32 reg = *m_src;
    while (reg & DATA_VALID) {
        // Each data word is copied to the working buffer.
        m_buff.write_u24(reg);
        if (reg & DATA_FINAL) {
            // Final word attempts to parse the message descriptor.
            m_buff.write_finalize();
            satcat5::io::ArrayRead rd(m_buff.buffer(), m_buff.written_len());
            SwitchLogMessage pkt;
            if (pkt.read_from(&rd)) m_dst->log_packet(pkt);
        }
        // Keep reading until FIFO is empty.
        reg = *m_src;
    }
}

void SwitchLogWriter::log_packet(const SwitchLogMessage& msg) {
    // Is there room in the output buffer?
    bool can_write = (m_dst->get_write_space() >= SwitchLogMessage::LEN_BYTES);

    // Have we already entered skip/summary mode?
    bool skip_mode = m_skip_drop || m_skip_keep;

    // Are we able to write an individual packet?
    if (can_write && !skip_mode) {
        // Forward the message descriptor as-is.
        msg.write_to(m_dst);
        m_dst->write_finalize();
    } else {
        // Increment applicable summary counter(s).
        m_skip_drop += msg.count_drop();
        m_skip_keep += msg.count_keep();
        // Write the summary now or later?
        if (can_write) timer_event();
        else timer_every(50);
    }
}

void SwitchLogWriter::timer_event() {
    // If the destination is full, try again later.
    if (m_dst->get_write_space() < SwitchLogMessage::LEN_BYTES) return;
    // Format the SKIP message.
    SwitchLogMessage msg;
    msg.init_skip(m_skip_drop, m_skip_keep);
    msg.write_to(m_dst);
    // Reset state once it's sent successfully.
    if (m_dst->write_finalize()) {
        m_skip_drop = 0;
        m_skip_keep = 0;
        timer_stop();
    }
}

static constexpr SwitchLogStats::TrafficStats STATS_ZERO = {};

SwitchLogStats::SwitchLogStats(TrafficStats* buff, unsigned size)
    : m_stats(buff)
    , m_size(size)
{
    for (unsigned a = 0 ; a < m_size ; ++a)
        m_stats[a] = STATS_ZERO;
}

SwitchLogStats::TrafficStats SwitchLogStats::get_port(unsigned idx) {
    if (idx >= m_size) return STATS_ZERO;
    TrafficStats tmp = m_stats[idx];
    m_stats[idx] = STATS_ZERO;
    return tmp;
}

void SwitchLogStats::log_packet(const SwitchLogMessage& msg) {
    // Sanity check for a valid source port.
    unsigned src = msg.srcport();
    if (src >= m_size) return;

    if (msg.reason() == SwitchLogMessage::REASON_KEEP) {
        // Increment packet counters for the source port.
        ++m_stats[src].rcvd_frames;
        if (msg.hdr.dst.is_broadcast())
            ++m_stats[src].bcast_frames;
        // Increment packet counters for the destination port(s).
        for (unsigned dst = 0 ; dst < m_size ; ++dst) {
            if ((msg.dstmask() >> dst) & 1)
                ++m_stats[dst].sent_frames;
        }
    } else {
        // Increment error counters for the source port only.
        ++m_stats[src].errct_total;
        if (msg.reason() == SwitchLogMessage::DROP_OVERFLOW)
            ++m_stats[src].errct_ovr;
        if (msg.reason() == SwitchLogMessage::DROP_BADFCS
         || msg.reason() == SwitchLogMessage::DROP_BADFRM)
            ++m_stats[src].errct_pkt;
    }
}

SwitchLogReader::SwitchLogReader(Readable* src)
    : m_src(src)
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
SwitchLogReader::~SwitchLogReader() {
    if (m_src) m_src->set_callback(nullptr);
}
#endif

void SwitchLogReader::data_rcvd(Readable* src) {
    SwitchLogMessage msg;
    if (msg.read_from(src)) {
        this->log_event(msg);   // Call child's event-handler.
        if (src->get_read_ready() == 0) src->read_finalize();
    }
}

void SwitchLogReader::data_unlink(Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

SwitchLogFormatter::SwitchLogFormatter(Readable* src, const char* lbl)
    : SwitchLogReader(src), m_label(lbl)
{
    // Nothing else to initialize.
}

void SwitchLogFormatter::log_event(const SwitchLogMessage& msg) {
    satcat5::log::Log(satcat5::log::DEBUG, m_label).write_obj(msg);
}
