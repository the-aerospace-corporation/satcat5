//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ntp_client.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/utils.h>

using satcat5::log::DEBUG;
using satcat5::log::Log;
using satcat5::ntp::Client;
using satcat5::ntp::Header;
using satcat5::ptp::Time;
using satcat5::udp::PORT_NTP_SERVER;

// Set debugging verbosity (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Type filter for UDP sockets is the server port number.
satcat5::net::Type TYPE_NTP(PORT_NTP_SERVER.value);

// Assume the offset from TAI to UTC is constant.
// The value provided below is valid from 2017 to 2035.
#ifndef SATCAT5_UTC_OFFSET
#define SATCAT5_UTC_OFFSET 37
#endif

// The effective NTP epoch is 1900-01-01T00:00:00UTC + L, where L is the
// current TAI-UTC offset (i.e., SATCAT5_UTC_OFFSET).  Convert this to the
// PTP epoch, which is 1970-01-01T00:00:00TAI.
// See also: https://www.ntp.org/reflib/leap/
// See also: https://stackoverflow.com/questions/29112071/
constexpr u64 NTP_OFFSET_SEC = 2208988800ull - SATCAT5_UTC_OFFSET;

Client::Client(
    satcat5::ptp::TrackingClock* refclk,
    satcat5::udp::Dispatch* iface)
    : Protocol(TYPE_NTP)
    , m_refclk(refclk)
    , m_iface(iface)
    , m_reftime(0)
    , m_leap(Header::LEAP_UNK)
    , m_stratum(0)
    , m_rate(0)
{
    m_iface.udp()->add(this);
}

#if SATCAT5_ALLOW_DELETION
Client::~Client() {
    m_iface.udp()->remove(this);
}
#endif

void Client::client_connect(const satcat5::ip::Addr& server, s8 poll_rate) {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "NtpClient: client_connect").write(server);
    m_iface.connect(server, PORT_NTP_SERVER, PORT_NTP_SERVER);
    client_set_rate(poll_rate);
}

void Client::client_close() {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "NtpClient: client_close").write(m_iface.dstaddr());
    m_iface.close();
}

void Client::client_set_rate(s8 poll_rate) {
    m_rate = poll_rate;
    timer_every(1000 << poll_rate);
}

void Client::frame_rcvd(satcat5::io::LimitedRead& src) {
    // Note the receive timestamp as soon as possible.
    u64 rxtime = ntp_now();
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "NtpClient: frame_rcvd").write(rxtime);

    // Read and sanity-check the incoming NTP message.
    // (Our NTPv4 client/server is backwards-compatible with NTPv3.)
    Header msg;
    if (!msg.read_from(&src)) return;
    if (msg.vn() < Header::VERSION_3) return;
    if (msg.vn() > Header::VERSION_4) return;

    // How should we respond? (RFC-5905 Section 9.2)
    if (msg.mode() == Header::MODE_SERVER) {
        // Ignore anything that doesn't come from the expected server.
        // TODO: Support broadcast mode for auto-association?
        if (m_iface.udp()->reply_ip() == m_iface.dstaddr())
            rcvd_reply(msg, rxtime);
    } else if (msg.mode() == Header::MODE_CLIENT) {
        // If server mode is active, respond to client queries.
        if (m_stratum) send_reply(msg, rxtime);
    }
}

void Client::timer_event() {
    // The only timer event is for starting each client-mode query.
    send_query();
}

void Client::rcvd_reply(const Header& msg, u64 rxtime) {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "NtpClient: rcvd_reply").write(msg.stratum);
    if (msg.stratum == 0) {
        // Check for kiss-of-death codes (Section 7.4).
        if (msg.refid == Header::KISS_DENY) client_close();
        if (msg.refid == Header::KISS_RSTR) client_close();
        if (msg.refid == Header::KISS_RATE) client_set_rate(m_rate + 1);
    } else {
        // Update protocol state.
        m_leap = msg.li();
        m_reftime = msg.xmt;
        m_stratum = msg.stratum + 1;
        // Deliver completed measurement to callback(s).
        satcat5::ptp::Measurement m;
        m.t1 = to_ptp(msg.org);
        m.t2 = to_ptp(msg.rec);
        m.t3 = to_ptp(msg.xmt);
        m.t4 = to_ptp(rxtime);
        notify_callbacks(m);
    }
}

bool Client::send_reply(const Header& query, u64 rxtime) {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "NtpClient: send_reply");
    auto wr = m_iface.udp()->open_reply(TYPE_NTP, Header::HEADER_LEN);
    bool ok = false;
    if (wr) {
        // Formulate and send the SNTP reply (Section 14).
        Header msg;
        msg.lvm         = m_leap | query.vn() | Header::MODE_SERVER;
        msg.stratum     = m_stratum;
        msg.poll        = query.poll;
        msg.precision   = Header::TIME_1USEC;
        msg.rootdelay   = 0;    // TODO: Fill this in?
        msg.rootdisp    = 0;    // TODO: Fill this in?
        msg.refid       = m_iface.udp()->ipaddr().value;
        msg.ref         = m_reftime;
        msg.org         = query.xmt;
        msg.rec         = rxtime;
        msg.xmt         = ntp_now();
        wr->write_obj(msg);
        ok = wr->write_finalize();
    } else if (DEBUG_VERBOSE > 1) {
        Log(DEBUG, "NtpClient: send_reply blocked");
    }
    return ok;
}

bool Client::send_query() {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "NtpClient: send_query");
    auto wr = m_iface.open_write(Header::HEADER_LEN);
    bool ok = false;
    if (wr) {
        // Formulate and send a query to the server.
        Header msg;
        msg.lvm         = m_leap | Header::VERSION_4 | Header::MODE_CLIENT;
        msg.stratum     = m_stratum;
        msg.poll        = m_rate;
        msg.precision   = Header::TIME_1MSEC;
        msg.rootdelay   = 0;
        msg.rootdisp    = 0;
        msg.refid       = m_iface.udp()->ipaddr().value;
        msg.ref         = m_reftime;
        msg.org         = 0;
        msg.rec         = 0;
        msg.xmt         = ntp_now();
        wr->write_obj(msg);
        ok = wr->write_finalize();
    } else if (DEBUG_VERBOSE > 1) {
        Log(DEBUG, "NtpClient: send_query blocked");
    }
    return ok;
}

u64 Client::ntp_now() const {
    return to_ntp(m_refclk->clock_now());
}

u64 Client::to_ntp(const satcat5::ptp::Time& t) const {
    // Convert the provided time to NTP format (seconds + fraction).
    // This conversion is lossy, but correctly handles rollover.
    u64 sec  = u64(t.round_secs()) + NTP_OFFSET_SEC;
    u64 frac = u64(t.round_nsec()) * 18446744073ull;    // 2^64 / 1e9
    return (sec << 32) + (frac >> 32);
}

Time Client::to_ptp(u64 t) const {
    // Convert NTP timestamp to seconds and nanoseconds.
    s64 secs = s64((t >> 32) - NTP_OFFSET_SEC);
    u64 nsec = ((t & 0xFFFFFFFFu) * 1000000000ull) >> 32;
    // Infer era number by comparing against current system time.
    // (NTP rollover every 2^32 seconds, or about 136 years.)
    const s64 ROLLOVER = (1ull << 32);
    s64 ref = m_refclk->clock_now().field_secs();
    s64 era = satcat5::util::div_round(ref - secs, ROLLOVER);
    // Convert to PTP timestamp.
    return Time(secs + era * ROLLOVER, nsec);
}
