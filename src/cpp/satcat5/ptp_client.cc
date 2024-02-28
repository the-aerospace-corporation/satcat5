//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ptp_client.h>
#include <satcat5/timer.h>

namespace log = satcat5::log;
using satcat5::io::LimitedRead;
using satcat5::ptp::Client;
using satcat5::ptp::ClientMode;
using satcat5::ptp::ClientState;
using satcat5::ptp::Callback;
using satcat5::ptp::DispatchTo;
using satcat5::ptp::Header;
using satcat5::ptp::PortId;
using satcat5::ptp::SyncUnicastL2;
using satcat5::ptp::SyncUnicastL3;
using satcat5::ptp::Time;
using satcat5::ptp::TIME_ZERO;

// For now the various identity fields are build-time constants.
#ifndef SATCAT5_PTP_DOMAIN
#define SATCAT5_PTP_DOMAIN 0
#endif

#ifndef SATCAT5_PTP_SDO_ID
#define SATCAT5_PTP_SDO_ID 0
#endif

#ifndef SATCAT5_PTP_PORT
#define SATCAT5_PTP_PORT 1
#endif

// Default rate is 2^3 = 8x per second
#ifndef SATCAT5_PTP_RATE
#define SATCAT5_PTP_RATE 3
#endif

// Assume offset from TAI to UTC is constant (see also: Section 7.2.4)
// This is equal to the number of leap seconds since the PTP epoch.
// The value provided below is valid from 2017 to 2035.
#ifndef SATCAT5_UTC_OFFSET
#define SATCAT5_UTC_OFFSET 37
#endif

// Set logging verbosity level (0/1/2).
static constexpr unsigned DEBUG_VERBOSE = 0;

// Most PTP messages are fixed-length (Section 13.*)
// (Stated lengths do not include TLVs.)
static constexpr u16 MSGLEN_ANNOUNCE    = 64;
static constexpr u16 MSGLEN_SYNC        = 44;
static constexpr u16 MSGLEN_DELAY_REQ   = 44;
static constexpr u16 MSGLEN_FOLLOW_UP   = 44;
static constexpr u16 MSGLEN_DELAY_RESP  = 54;
static constexpr u16 MSGLEN_PDELAY_REQ  = 54;
static constexpr u16 MSGLEN_PDELAY_RESP = 54;
static constexpr u16 MSGLEN_PDELAY_RFU  = 54;
static constexpr u16 MSGLEN_SIGNALING   = 44;

// Convert mode to preferred broadcast type.
constexpr inline DispatchTo broadcast_to(const ClientMode& mode)
{
    return (mode == ClientMode::MASTER_L2)
        ? DispatchTo::BROADCAST_L2
        : DispatchTo::BROADCAST_L3;
}

const char* satcat5::ptp::to_string(satcat5::ptp::ClientMode mode)
{
    switch (mode) {
    case ClientMode::DISABLED:      return "Disabled";
    case ClientMode::MASTER_L2:     return "MasterL2";
    case ClientMode::MASTER_L3:     return "MasterL3";
    default:                        return "SlaveOnly";
    }
}

const char* satcat5::ptp::to_string(satcat5::ptp::ClientState state)
{
    switch (state) {
    case ClientState::DISABLED:     return "Disabled";
    case ClientState::LISTENING:    return "Listening";
    case ClientState::MASTER:       return "Master";
    case ClientState::PASSIVE:      return "Passive";
    default:                        return "Slave";
    }
}

Client::Client(
        satcat5::ptp::Interface* ptp_iface,
        satcat5::ip::Dispatch* ip_dispatch,
        ClientMode mode)
    : m_iface(ptp_iface, ip_dispatch)
    , m_mode(ClientMode::DISABLED)
    , m_state(ClientState::DISABLED)
    , m_cache()
    , m_clock_local(satcat5::ptp::DEFAULT_CLOCK)
    , m_clock_remote(satcat5::ptp::DEFAULT_CLOCK)
    , m_current_source({})
    , m_announce_count(0)
    , m_announce_every(0)
    , m_sync_rate(SATCAT5_PTP_RATE)
    , m_pdelay_rate(SATCAT5_PTP_RATE)
    , m_announce_id(0)
    , m_sync_id(0)
    , m_pdelay_id(0)
{
    // Clock-ID from MAC address using the IEEE 1588-2008 method.
    // (Deprecated in IEEE 1588-2019 unless MAC/OUI is globally-unique.)
    m_clock_local.grandmasterIdentity = 256ULL * m_iface.macaddr().to_u64();

    // Link to the upstream interface.
    m_iface.ptp_callback(this);

    // Set mode and initial state.
    set_mode(mode);
}

#if SATCAT5_ALLOW_DELETION
Client::~Client()
{
    m_iface.ptp_callback(0);
}
#endif

void Client::set_mode(satcat5::ptp::ClientMode mode)
{
    // Set initial state for the new mode.
    m_mode = mode;
    switch (mode) {
    case ClientMode::MASTER_L2:     m_state = ClientState::MASTER; break;
    case ClientMode::MASTER_L3:     m_state = ClientState::MASTER; break;
    case ClientMode::SLAVE_ONLY:    m_state = ClientState::LISTENING; break;
    case ClientMode::PASSIVE:       m_state = ClientState::PASSIVE; break;
    default:                        m_state = ClientState::DISABLED; break;
    }

    // Configure or stop the timer based on the new state.
    timer_reset();
}

void Client::set_sync_rate(u8 rate)
{
    // Store the new rate setting.
    m_sync_rate = rate;

    // Reconfigure master-state timers?
    if (m_state == ClientState::MASTER) timer_reset();
}

void Client::set_pdelay_rate(u8 rate)
{
    // Store the new rate setting.
    m_pdelay_rate = rate;

    // Reconfigure passive-state timers?
    if (m_state == ClientState::PASSIVE) timer_reset();
}

bool Client::send_sync_unicast(
    const satcat5::eth::MacAddr& mac, const satcat5::ip::Addr& ip)
{
    // Sanity check: Only master should send Sync messages.
    if (m_state != ClientState::MASTER) return false;

    // Set the new address and immediately issue a SYNC message.
    // (Safe to overwrite stored address; it's not used by the master.)
    m_iface.store_addr(mac, ip);
    return send_sync(DispatchTo::STORED);
}

void Client::ptp_rcvd(LimitedRead& rd)
{
    // Sanity check: Immediately discard all messages if disabled.
    if (m_state == ClientState::DISABLED) return;

    // Read the basic PTP message header.
    Header hdr; bool ok = hdr.read_from(&rd);
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "PtpClient: ptp_rcvd").write(hdr.type);

    // Sanity-check on received message length.
    unsigned rcvd_len = hdr.HEADER_LEN + rd.get_read_ready();
    if (!ok || rcvd_len < hdr.length) {
        log::Log(log::WARNING, "PtpClient: Malformed header")
            .write10((u32)rcvd_len).write10((u32)hdr.length);
        return;     // Abort further processing...
    }

    // Take further action depending on message type...
    switch (hdr.type & 0x0F) {
    case Header::TYPE_SYNC:         rcvd_sync(hdr, rd); break;
    case Header::TYPE_DELAY_REQ:    rcvd_delay_req(hdr, rd); break;
    case Header::TYPE_PDELAY_REQ:   rcvd_pdelay_req(hdr, rd); break;
    case Header::TYPE_FOLLOW_UP:    rcvd_follow_up(hdr, rd); break;
    case Header::TYPE_PDELAY_RFU:   rcvd_pdelay_follow_up(hdr, rd); break;
    case Header::TYPE_DELAY_RESP:   rcvd_delay_resp(hdr, rd); break;
    case Header::TYPE_PDELAY_RESP:  rcvd_pdelay_resp(hdr, rd); break;
    case Header::TYPE_ANNOUNCE:     rcvd_announce(hdr, rd); break;
    default:                        rcvd_unexpected(hdr); break;
    }
}

void Client::timer_event()
{
    if (m_state == ClientState::MASTER) {
        // Send ANNOUNCE and SYNC at regular intervals.
        send_announce_maybe();
        send_sync(broadcast_to(m_mode));
    } else if (m_state == ClientState::SLAVE) {
        // Timeout waiting for SYNC from master.
        m_state = ClientState::LISTENING;
        timer_reset();
    } else if (m_state == ClientState::PASSIVE) {
        send_pdelay_req();
    }
}

void Client::timer_reset()
{
    if (m_state == ClientState::MASTER) {
        // On entry or rate change, master mode sets a timer:
        //  * SYNC (variable 2^rate / sec) = Every timer event
        //  * ANNOUNCE (fixed 1 / sec) = Every Nth timer event
        m_announce_every = (1u << m_sync_rate);
        m_announce_count = 0;
        timer_every(1000 >> m_sync_rate);
    } else if (m_state == ClientState::PASSIVE) {
        // On entry or rate change, passive mode sets a timer:
        // * PDELAY_REQ (variable 0.9 x 2^rate / sec) (Section 9.5.13.2)
        timer_every(900 >> m_pdelay_rate);
    } else if (m_state == ClientState::SLAVE) {
        // Watchdog timer for loss of communication.
        timer_once(5000);
    } else {
        // Timer is not used in current state.
        timer_stop();
    }
}

void Client::rcvd_announce(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Announcement");

    // Message contents defined in Section 13.5.1.
    // TODO: Read any fields of interest.

    // See Section 9.5.3, including flowchart in Figure 36.
    if (m_state == ClientState::LISTENING) {
        // For now, listening state just accepts the first ANNOUNCE message.
        // TODO: Listen a while and select the best option or self-promote.
        log::Log(log::INFO, "PtpClient: Selected master.");
        m_iface.store_reply_addr();
        m_current_source = hdr.src_port;
        m_state = ClientState::SLAVE;
    } else if (m_state == ClientState::MASTER) {
        // TODO: Self-demote if a better master clock comes along.
    }
}

void Client::rcvd_sync(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Sync");

    // See Section 9.5.4, including flowchart in Figure 37.
    if (m_state == ClientState::SLAVE && hdr.src_port == m_current_source) {
        // Reset the watchdog timer.
        timer_reset();

        // Message contents defined in Section 13.6.1.
        Time origin; bool ok = origin.read_from(&rd);
        Time rxtime = m_iface.ptp_rx_timestamp();
        if (!ok) return;

        // SYNC message from current parent begins a new handshake.
        auto meas = m_cache.push(hdr);
        meas->t2 = rxtime - Time(s64(hdr.correction));

        // Are we expecting a FOLLOW_UP message?
        if (!(hdr.flags & Header::FLAG_TWO_STEP)) {
            meas->t1 = origin;
            if (send_delay_req(hdr))
                meas->t3 = m_iface.ptp_tx_timestamp();
        }
    }
}

void Client::rcvd_follow_up(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Follow-up");

    // See Section 9.5.5, including flowchart in Figure 38.
    if (m_state == ClientState::SLAVE && hdr.src_port == m_current_source) {
        // Message contents defined in Section 13.7.1.
        Time origin; bool ok = origin.read_from(&rd);
        if (!ok) return;

        // Find the corresponding SYNC message.
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (meas) {
            meas->t1 = origin + Time(s64(hdr.correction));
            if (send_delay_req(hdr))
                meas->t3 = m_iface.ptp_tx_timestamp();
        }
    }
}

void Client::rcvd_delay_req(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Delay request");

    // See Section 9.5.6, including flowchart in Figure 39.
    if (m_state == ClientState::MASTER) {
        send_delay_resp(hdr);
    }
}

void Client::rcvd_pdelay_req(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay request");

    if (m_state == ClientState::PASSIVE) {
        send_pdelay_resp(hdr);
    }
}

void Client::rcvd_delay_resp(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Delay response");

    // See Section 9.5.7, including flowchart in Figure 40.
    if (m_state == ClientState::SLAVE && hdr.src_port == m_current_source) {
        // Message contents defined in Section 13.8.1.
        Time rxtime; bool ok = rxtime.read_from(&rd);
        if (!ok) return;

        // Find the corresponding SYNC message...
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (meas) {
            meas->t4 = rxtime - Time(s64(hdr.correction));
            // Optional diagnostics showing all collected timestamps.
            if (DEBUG_VERBOSE > 0)
                log::Log(log::DEBUG, "PtpClient: Measurement ready").write_obj(*meas);
            // If we have every timestamp, notify all callback object(s).
            if (meas->done()) notify_callbacks(*meas);
        }
    }
}

void Client::rcvd_pdelay_resp(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay response");

    if (m_state == ClientState::PASSIVE) {
        // Message contents defined in Section 13.9.1.
        Time rxtime = m_iface.ptp_rx_timestamp();

        // Find the corresponding PDELAY_REQ message.
        // If this completes the peer-to-peer delay request, notify the callback object.
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (meas) {
            meas->t4 = rxtime;
            if (!(hdr.flags & Header::FLAG_TWO_STEP)) {
                s64 delta = s64(hdr.correction - meas->ref.correction);
                meas->t3 = meas->t2 + Time(delta);
                if (meas->done()) notify_callbacks(*meas);
            }
        }
    }
}

void Client::rcvd_pdelay_follow_up(const Header& hdr, LimitedRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay response follow up");

    // Message contents defined in Section 13.11.1.
    Time origin; bool ok = origin.read_from(&rd);
    if (!ok) return;

    // Find the corresponding PDELAY_REQ message.
    auto meas = m_cache.find(hdr, hdr.src_port);
    if (meas) {
        s64 delta = s64(hdr.correction - meas->ref.correction);
        meas->t3 = meas->t2 + Time(delta);
        if (meas->done()) notify_callbacks(*meas);
    }
}

void Client::rcvd_unexpected(const Header& hdr)
{
    // Log all unexpected message types, but take no further action.
    log::Log(log::INFO, "PtpClient: Unexpected message").write(hdr.type);
}

Header Client::make_header(u8 type, u16 seq_id)
{
    // Most fields are simple constants.
    Header hdr;
    hdr.type            = type;
    hdr.version         = 2;        // PTPv2
    hdr.domain          = SATCAT5_PTP_DOMAIN;
    hdr.sdo_id          = SATCAT5_PTP_SDO_ID;
    hdr.flags           = 0;        // Section 13.3.2.8
    hdr.correction      = 0;        // Always initialized to zero
    hdr.subtype         = 0;        // Reserved
    hdr.src_port        = {m_clock_local.grandmasterIdentity, SATCAT5_PTP_PORT};
    hdr.seq_id          = seq_id;   // Section 7.3.7
    hdr.control         = 0;        // Obsolete (Section 13.3.2.13)

    // The two flags we care about are:
    //  * FLAG_PTP_TIMESCALE (required on all announce messages)
    //  * FLAG_UNICAST (inferred by type)
    //  * FLAG_TWO_STEP (set by caller if required)
    if (type == Header::TYPE_ANNOUNCE)
        hdr.flags |= Header::FLAG_PTP_TIMESCALE;
    if (type == Header::TYPE_DELAY_REQ || type == Header::TYPE_DELAY_RESP)
        hdr.flags |= Header::FLAG_UNICAST;

    // Set messageLength based on type (Section 13.*)
    switch (type & 0x0F) {
    case Header::TYPE_SYNC:         hdr.length = MSGLEN_SYNC; break;
    case Header::TYPE_DELAY_REQ:    hdr.length = MSGLEN_DELAY_REQ; break;
    case Header::TYPE_PDELAY_REQ:   hdr.length = MSGLEN_PDELAY_REQ; break;
    case Header::TYPE_PDELAY_RESP:  hdr.length = MSGLEN_PDELAY_RESP; break;
    case Header::TYPE_FOLLOW_UP:    hdr.length = MSGLEN_FOLLOW_UP; break;
    case Header::TYPE_DELAY_RESP:   hdr.length = MSGLEN_DELAY_RESP; break;
    case Header::TYPE_PDELAY_RFU:   hdr.length = MSGLEN_PDELAY_RFU; break;
    case Header::TYPE_ANNOUNCE:     hdr.length = MSGLEN_ANNOUNCE; break;
    default:                        hdr.length = 0; break; // Reserved / GCOVR_EXCL_LINE
    }

    // Set logMessageInterval based on type (Section 13.3.2.14)
    switch (type & 0x0F) {
    case Header::TYPE_ANNOUNCE:     hdr.log_interval = 0; break;  // 1 per sec
    case Header::TYPE_SYNC:         hdr.log_interval = (s8)(-m_sync_rate); break;
    case Header::TYPE_FOLLOW_UP:    hdr.log_interval = (s8)(-m_sync_rate); break;
    case Header::TYPE_DELAY_RESP:   hdr.log_interval = 0; break;
    default:                        hdr.log_interval = 0x7F; break;
    }

    return hdr;
}

void Client::send_announce_maybe()
{
    // Announcement message every N timer events.
    // Note: MailMap may block if multiple packets are sent too quickly.
    //  Simplest workaround is a short fixed delay, otherwise harmless.
    if (m_announce_count) {
        --m_announce_count;
    } else if (send_announce()) {
        m_announce_count = m_announce_every - 1;
        m_iface.timer()->busywait_usec(10);
    }
}

bool Client::send_announce()
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_announce");
    // ANNOUNCE messages are always broadcast.
    // Message contents defined in Section 13.5.
    // Note: Dummy timestamp is acceptable (Section 13.5.2.1)
    Header hdr = make_header(Header::TYPE_ANNOUNCE, ++m_announce_id);
    auto wr = m_iface.ptp_send(broadcast_to(m_mode), hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(TIME_ZERO);
    wr->write_u16(SATCAT5_UTC_OFFSET);
    wr->write_u8(0);    // Reserved
    wr->write_obj(m_clock_local);
    return wr->write_finalize();
}

bool Client::send_sync(DispatchTo addr)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_sync");
    // Can we provide a one-step timestamp?
    Header hdr = make_header(Header::TYPE_SYNC, ++m_sync_id);
    Time t1 = m_iface.ptp_tx_start();
    // T1 != 0: One-step mode, correctionField per Section 9.5.10.
    // T1 == 0: Two-step mode, correctionField and originTimestamp are zero.
    hdr.correction = t1.correction();
    if (t1 == TIME_ZERO) hdr.flags |= Header::FLAG_TWO_STEP;
    // SYNC messages are broadcast by default, unicast on-demand,
    // Message contents defined in Section 13.6.
    auto wr = m_iface.ptp_send(addr, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(t1);
    if (hdr.flags & Header::FLAG_TWO_STEP) {
        return wr->write_finalize() && send_follow_up(addr);
    } else {
        return wr->write_finalize();
    }
}

bool Client::send_follow_up(satcat5::ptp::DispatchTo addr)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_follow_up");
    // Get the timestamp from the SYNC message we just sent.
    Time t1 = m_iface.ptp_tx_timestamp();
    if (t1 == TIME_ZERO) log::Log(log::ERROR, "PtpClient: Bad hardware timestamp.");
    // FOLLOW_UP messages are sent to the same recipient(s) as the SYNC.
    // Message contents defined in Section 13.7.
    // Two-step correctionField per Section 9.5.10.
    Header hdr = make_header(Header::TYPE_FOLLOW_UP, m_sync_id);
    hdr.correction = t1.correction();
    auto wr = m_iface.ptp_send(addr, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(t1);
    return wr->write_finalize();
}

bool Client::send_delay_req(const Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_delay_req");
    // Transmit timestamp is noncritical informational; use Rx timestamp
    // from the preceding SYNC message as a placeholder. (Section 11.3.2 c)
    // Do NOT call ptp_tx_start() here, since incrementing correctionField
    // double-books the elapsed time compared to ptp_tx_timestamp().
    Time t3 = m_iface.ptp_rx_timestamp();
    // DELAY_REQ messages are sent in response to a SYNC message.
    // Message contents defined in Section 13.6.
    // Set correctionField to zero per Section 11.3.2 c.
    Header hdr = make_header(Header::TYPE_DELAY_REQ, ref.seq_id);
    hdr.correction = 0;
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(t3);
    return wr->write_finalize();
}

bool Client::send_delay_resp(const Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_delay_resp");
    // Get the timestamp from the DELAY_REQ message we just received.
    // (Also echo correctionField from the received packet.)
    Time t4 = m_iface.ptp_rx_timestamp();
    if (t4 == TIME_ZERO) log::Log(log::ERROR, "PtpClient: Bad hardware timestamp.");
    // DELAY_RESP messages are always replies to the client.
    // Message contents defined in Section 13.8.
    // Calculate correctionField per Section 11.3.2 d.
    Header hdr = make_header(Header::TYPE_DELAY_RESP, ref.seq_id);
    hdr.correction = ref.correction - t4.correction();
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(t4);
    wr->write_obj(ref.src_port);
    return wr->write_finalize();
}

bool Client::send_pdelay_req()
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_req");

    // Can we provide a one-step timestamp?
    Time originTimestamp = m_iface.ptp_tx_start();
    // Message contents defined in Section 13.9.
    Header hdr = make_header(Header::TYPE_PDELAY_REQ, ++m_pdelay_id);
    hdr.correction = originTimestamp.correction();
    if (originTimestamp == TIME_ZERO) hdr.flags |= Header::FLAG_TWO_STEP;
    auto wr = m_iface.ptp_send(DispatchTo::STORED, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(originTimestamp);
    wr->write_u64(0); // Reserved
    wr->write_u16(0); // Reserved

    auto meas = m_cache.push(hdr);
    Time t1 = m_iface.ptp_tx_timestamp();
    if (meas) {
        meas->t1 = t1;
        // Assumption: t2 approximately equal to t1
        meas->t2 = t1;
    }

    return wr->write_finalize();
}

bool Client::send_pdelay_resp(const satcat5::ptp::Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_resp");

    // Get the timestamp from the DELAY_REQ message we just received.
    // (Also echo correctionField from the received packet.)
    Time t2 = m_iface.ptp_rx_timestamp();
    // PDELAY_RESP messages are always replies to the client.
    // Message contents defined in Section 13.8.
    Time t3 = m_iface.ptp_tx_start();

    Header hdr = make_header(Header::TYPE_PDELAY_RESP, ref.seq_id);
    hdr.domain = ref.domain;
    hdr.sdo_id = ref.sdo_id;
    hdr.src_port = ref.src_port;
    if (t3 == TIME_ZERO) {
        // In two-step mode, set correction to 0
        hdr.correction = 0;
    } else {
        // See Section 11.4.2 b
        hdr.correction = ref.correction + (t3 - t2).delta_subns();
    }
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(TIME_ZERO);
    wr->write_obj(ref.src_port);

    if (hdr.flags & Header::FLAG_TWO_STEP || t3 == TIME_ZERO) {
        return wr->write_finalize() && send_pdelay_follow_up(ref);
    } else {
        return wr->write_finalize();
    }
}

bool Client::send_pdelay_follow_up(const satcat5::ptp::Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_follow_up");

    Time t2 = m_iface.ptp_rx_timestamp();
    Time t3 = m_iface.ptp_tx_timestamp();

    // Message contents defined in Section 13.11.
    Header hdr = make_header(Header::TYPE_PDELAY_RFU, ref.seq_id);
    hdr.domain = ref.domain;
    hdr.sdo_id = ref.sdo_id;
    hdr.src_port = ref.src_port;

    // See Section 11.4.2 c
    hdr.correction = ref.correction + (t3 - t2).delta_subns();
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);
    wr->write_obj(TIME_ZERO);
    wr->write_obj(ref.src_port);
    return wr->write_finalize();
}

SyncUnicastL2::SyncUnicastL2(Client* client)
    : m_client(client)
    , m_dstmac(satcat5::eth::MACADDR_NONE)
{
    // Nothing else to initialize.
}

void SyncUnicastL2::timer_event()
{
    if (m_dstmac != satcat5::eth::MACADDR_NONE) {
        m_client->send_sync_unicast(m_dstmac);
    }
}

SyncUnicastL3::SyncUnicastL3(Client* client)
    : m_client(client)
    , m_addr(client->get_iface(), satcat5::ip::PROTO_UDP)
{
    // Nothing else to initialize.
}

void SyncUnicastL3::timer_event()
{
    if (m_addr.ready()) {
        m_client->send_sync_unicast(m_addr.dstmac(), m_addr.dstaddr());
    }
}
