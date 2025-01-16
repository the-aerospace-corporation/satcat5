//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_tlv.h>
#include <satcat5/timeref.h>
#include <satcat5/utils.h>

namespace log = satcat5::log;
using satcat5::io::ArrayRead;
using satcat5::io::LimitedRead;
using satcat5::ptp::Client;
using satcat5::ptp::ClientMode;
using satcat5::ptp::ClientState;
using satcat5::ptp::Callback;
using satcat5::ptp::DispatchTo;
using satcat5::ptp::Header;
using satcat5::ptp::Measurement;
using satcat5::ptp::PortId;
using satcat5::ptp::SyncUnicastL2;
using satcat5::ptp::SyncUnicastL3;
using satcat5::ptp::Time;
using satcat5::ptp::TIME_ZERO;
using satcat5::ptp::TlvHandler;
using satcat5::ptp::TlvHeader;

// Local shortcut for div_round:
#define div_round satcat5::util::div_round<unsigned>

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

// Enable support for SPTP?
// https://engineering.fb.com/2024/02/07/production-engineering/simple-precision-time-protocol-sptp-meta/
// https://ieeexplore.ieee.org/document/10296989
#ifndef SATCAT5_SPTP_ENABLE
#define SATCAT5_SPTP_ENABLE 1
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
    case ClientMode::SLAVE_ONLY:    return "SlaveOnly";
    case ClientMode::SLAVE_SPTP:    return "SlaveSimple";
    default:                        return "Passive";
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
    , m_current_source(satcat5::ptp::PORT_NONE)
    , m_announce_count(0)
    , m_announce_every(0)
    , m_cache_wdog(0)
    , m_request_wdog(0)
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
    m_current_source = satcat5::ptp::PORT_NONE;
    switch (mode) {
    case ClientMode::MASTER_L2:     m_state = ClientState::MASTER; break;
    case ClientMode::MASTER_L3:     m_state = ClientState::MASTER; break;
    case ClientMode::SLAVE_ONLY:    m_state = ClientState::LISTENING; break;
    #if SATCAT5_SPTP_ENABLE
    case ClientMode::SLAVE_SPTP:    m_state = ClientState::LISTENING; break;
    #endif
    case ClientMode::PASSIVE:       m_state = ClientState::PASSIVE; break;
    default:                        m_state = ClientState::DISABLED; break;
    }

    // Configure or stop the timer based on the new state.
    timer_reset();
}

void Client::set_sync_rate(int rate)
{
    // Store the new rate setting and reconfigure timers.
    m_sync_rate = rate;
    timer_reset();
}

void Client::set_pdelay_rate(int rate)
{
    // Store the new rate setting and reconfigure timers.
    m_pdelay_rate = rate;
    timer_reset();
}

bool Client::send_sync_unicast(
    const satcat5::eth::MacAddr& mac, const satcat5::ip::Addr& ip, const satcat5::eth::VlanTag& vtag)
{
    // Sanity check: Only master should send Sync messages.
    if (m_state != ClientState::MASTER) return false;

    // Set the new address and immediately issue a SYNC message.
    // (Safe to overwrite stored address; it's not used by the master.)
    m_iface.store_addr(mac, ip, vtag);
    return send_sync(DispatchTo::STORED, ++m_sync_id);
}

void Client::ptp_rcvd(LimitedRead& rd)
{
    // Sanity check: Immediately discard all messages if disabled.
    if (m_state == ClientState::DISABLED) return;

    // Read the basic PTP message header.
    Header hdr; bool ok = hdr.read_from(&rd);
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "PtpClient: ptp_rcvd").write(hdr.type);

    // Sanity-check on received message length:
    //  * hdr.length includes the entire header + message + TLVs.
    //  * hdr.msglen() is message only, based on header's type field.
    unsigned rcvd_len = hdr.HEADER_LEN + rd.get_read_ready();
    if (!ok || rcvd_len < hdr.length
            || hdr.length < hdr.HEADER_LEN + hdr.msglen()
            || hdr.msglen() > Header::MAX_MSGLEN) {
        log::Log(log::WARNING, "PtpClient: Malformed header");
        return;                 // Abort further processing...
    } else if (hdr.msglen() == 0) {
        rcvd_unexpected(hdr);   // Unsupported message type.
        return;                 // Abort further processing...
    }

    // Copy the message contents to a working buffer.
    u8 msg_buff[Header::MAX_MSGLEN];
    rd.read_bytes(hdr.msglen(), msg_buff);
    ArrayRead msg(msg_buff, hdr.msglen());

    // Parse the chain of type/length/value (TLV) triplets...
    TlvHeader tlv;
    while (tlv.read_from(&rd)) {
        // Try matching against each registered TlvHandler.
        LimitedRead tmp(&rd, tlv.length);
        TlvHandler* next = m_tlv_list.head();
        while (next && !next->tlv_rcvd(hdr, tlv, tmp)) {
            next = m_tlv_list.next(next);
        }
        // Consume any leftover bytes to get ready for next TLV.
        tmp.read_finalize();
    }

    // Take further action depending on message type...
    switch (hdr.type & 0x0F) {
    case Header::TYPE_SYNC:         rcvd_sync(hdr, msg); break;
    case Header::TYPE_DELAY_REQ:    rcvd_delay_req(hdr, msg); break;
    case Header::TYPE_PDELAY_REQ:   rcvd_pdelay_req(hdr, msg); break;
    case Header::TYPE_FOLLOW_UP:    rcvd_follow_up(hdr, msg); break;
    case Header::TYPE_PDELAY_RFU:   rcvd_pdelay_follow_up(hdr, msg); break;
    case Header::TYPE_DELAY_RESP:   rcvd_delay_resp(hdr, msg); break;
    case Header::TYPE_PDELAY_RESP:  rcvd_pdelay_resp(hdr, msg); break;
    case Header::TYPE_ANNOUNCE:     rcvd_announce(hdr, msg); break;
    }
}

void Client::timer_event()
{
    if (m_state == ClientState::MASTER) {
        // Send ANNOUNCE and SYNC at regular intervals.
        if (m_sync_rate >= 0) {
            send_announce_maybe();
            send_sync(broadcast_to(m_mode), ++m_sync_id);
        } else {
            send_announce();
        }
    } else if (m_state == ClientState::SLAVE) {
        if (SATCAT5_SPTP_ENABLE && m_mode == ClientMode::SLAVE_SPTP) {
            // SPTP clients send unsolicited DELAY_REQ at regular intervals.
            send_delay_req_sptp();
        } else {
            // Timeout waiting for SYNC from master.
            client_timeout();
        }
    } else if (m_state == ClientState::PASSIVE) {
        // Send PDELAY_REQ at regular intervals.
        send_pdelay_req();
    }
}

void Client::timer_reset()
{
    if (m_state == ClientState::MASTER) {
        // Conventional masters send both SYNC and ANNOUNCE:
        //  * SYNC (variable 2^rate / sec) = Every timer event
        //  * ANNOUNCE (fixed 1 / sec) = Every Nth timer event
        if (m_sync_rate >= 0) {
            m_announce_every = (1u << m_sync_rate);
            m_announce_count = 0;
            timer_every(div_round(1000u, 1u << m_sync_rate));
        } else {
            m_announce_every = 0;
            m_announce_count = 0;
            timer_every(1000);
        }
    } else if (m_state == ClientState::PASSIVE && m_pdelay_rate >= 0) {
        // On entry or rate change, passive mode sets a timer:
        // * PDELAY_REQ (variable 0.9 x 2^rate / sec) (Section 9.5.13.2)
        timer_every(div_round(900u, 1u << m_pdelay_rate));
    } else if (m_state == ClientState::SLAVE) {
        bool sptp_mode = SATCAT5_SPTP_ENABLE && (m_mode == ClientMode::SLAVE_SPTP);
        if (sptp_mode && m_sync_rate >= 0) {
            // SPTP slaves send DELAY_REQ at regular intervals (2^rate / sec).
            m_announce_every = 0;
            m_announce_count = 0;
            timer_every(div_round(1000, 1u << m_sync_rate));
        } else {
            // Watchdog timer for loss of communication.
            timer_once(5000);
        }
    } else {
        // Timer is not used in current state.
        timer_stop();
    }
}

void Client::cache_miss()
{
    // Rare errors (< 10%) are harmless, but high-latency connections may
    // need to increase SATCAT5_PTP_CACHE_SIZE (see "ptp_measurement.h").
    // A running tally logs this error only if the rate is excessive:
    //  * -1 for each received SYNC or PDELAY_REQ message.
    //  * +N for each cache miss -> Upward trend if average rate > 1/N.
    m_cache_wdog += 10;
    if (DEBUG_VERBOSE > 0 || m_cache_wdog >= 50) {
        log::Log(log::WARNING, "PtpClient: Unmatched SeqID");
        m_cache_wdog = 0;
    }
}

unsigned Client::tlv_send(const Header& hdr, satcat5::io::Writeable* wr)
{
    // Callback to each registered TlvHandler, return total length.
    // If wr is null, this is a prediction; otherwise write TLV(s).
    unsigned total = 0;
    TlvHandler* next = m_tlv_list.head();
    while (next) {
        total += next->tlv_send(hdr, wr);
        next = m_tlv_list.next(next);
    }
    return total;
}

void Client::notify_if_complete(const Measurement* meas)
{
    if (meas->done()) {
        // Make a local copy of the measurement object.
        // (TlvHandlers may modify or invalidate the timestamps.)
        Measurement temp = *meas;
        // Callback to each registered TlvHandler.
        TlvHandler* next = m_tlv_list.head();
        while (next && temp.done()) {
            next->tlv_meas(temp);
            next = m_tlv_list.next(next);
        }
        // Once finished, notify registered PTP callbacks.
        if (temp.done()) notify_callbacks(temp);
    }
}

void Client::client_timeout()
{
    log::Log(log::WARNING, "PtpClient: Connection timeout.");
    if (m_state == ClientState::SLAVE) {
        // Revert to LISTENING state, so we can identify a new server.
        m_state = ClientState::LISTENING;
        timer_reset();
    }
}

void Client::rcvd_announce(const Header& hdr, ArrayRead& rd)
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
        m_request_wdog = 0;
        m_state = ClientState::SLAVE;
        timer_reset();
    } else if (m_state == ClientState::MASTER) {
        // TODO: Self-demote if a better master clock comes along.
    }
}

void Client::rcvd_sync(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Sync");
    bool mode_sptp = SATCAT5_SPTP_ENABLE && (m_mode == ClientMode::SLAVE_SPTP);

    // See Section 9.5.4, including flowchart in Figure 37.
    if (m_state == ClientState::SLAVE && hdr.src_port == m_current_source) {
        // Reset the watchdog timer, unless we are in SPTP mode.
        if (!mode_sptp) timer_reset();

        // Decrement the cache-miss watchdog (see "cache_miss").
        if (m_cache_wdog) --m_cache_wdog;

        // Message contents defined in Section 13.6.1.
        Time origin; bool ok = origin.read_from(&rd);
        Time rxtime = m_iface.ptp_rx_timestamp();
        if (!ok) return;

        // SPTP: Attempt search for matching DELAY_REQ (may return null).
        // Normal: SYNC message begins a new handshake (always succeeds).
        auto meas = mode_sptp ? m_cache.find(hdr) : m_cache.push(hdr);
        if (!meas) {cache_miss(); return;}
        meas->t2 = rxtime - Time(s64(hdr.correction));

        // Are we expecting a FOLLOW_UP message?
        auto rcvd_2step = hdr.flags & Header::FLAG_TWO_STEP;
        auto rcvd_sptp  = hdr.flags & Header::FLAG_SPTP;
        if (mode_sptp) {
            // SPTP mode: Always two-step, with T4 in the "origin" field.
            if (rcvd_2step && rcvd_sptp) {
                meas->t4 = origin;
                m_request_wdog = 0;
            }
        } else if (rcvd_2step) {
            // Two-step mode: No further action until FOLLOW_UP.
        } else {
            // One-step mode: Note origin timestamp and send reply.
            meas->t1 = origin;
            if (send_delay_req(hdr.seq_id))
                meas->t3 = m_iface.ptp_tx_timestamp();
        }
    }
}

void Client::rcvd_follow_up(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Follow-up");
    bool mode_sptp = SATCAT5_SPTP_ENABLE && (m_mode == ClientMode::SLAVE_SPTP);

    // See Section 9.5.5, including flowchart in Figure 38.
    if (m_state == ClientState::SLAVE && hdr.src_port == m_current_source) {
        // Message contents defined in Section 13.7.1.
        Time origin; bool ok = origin.read_from(&rd);
        if (!ok) return;

        // Find the corresponding SYNC message.
        // Normal mode sends a reply, SPTP mode completes handshake.
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (meas) {
            if (mode_sptp) {
                meas->t1 = origin;
                meas->t3 += Time(s64(hdr.correction));
                notify_if_complete(meas);
            } else if (send_delay_req(hdr.seq_id)) {
                meas->t1 = origin + Time(s64(hdr.correction));
                meas->t3 = m_iface.ptp_tx_timestamp();
            }
        } else {cache_miss();} // GCOVR_EXCL_LINE
    }
}

void Client::rcvd_delay_req(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Delay request");

    // See Section 9.5.6, including flowchart in Figure 39.
    // (Except SPTP requests, which reply with SYNC instead.)
    if (m_state == ClientState::MASTER) {
        auto rcvd_sptp = hdr.flags & Header::FLAG_SPTP;
        if (SATCAT5_SPTP_ENABLE && rcvd_sptp) {
            u16 sptp_flags = Header::FLAG_SPTP | Header::FLAG_TWO_STEP;
            send_sync(DispatchTo::REPLY, hdr.seq_id, sptp_flags, hdr.correction);
        } else {
            send_delay_resp(hdr);
        }
    }
}

void Client::rcvd_pdelay_req(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay request");

    if (m_state == ClientState::PASSIVE) {
        send_pdelay_resp(hdr);
    }
}

void Client::rcvd_delay_resp(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: Delay response");

    // See Section 9.5.7, including flowchart in Figure 40.
    // This message is not used in SPTP mode.
    if (m_state == ClientState::SLAVE
        && m_mode != ClientMode::SLAVE_SPTP
        && hdr.src_port == m_current_source) {
        // Message contents defined in Section 13.8.1.
        Time rxtime; bool ok = rxtime.read_from(&rd);
        if (!ok) return;

        // Decrement the cache-miss watchdog (see "cache_miss").
        if (m_cache_wdog) --m_cache_wdog;

        // Find the corresponding SYNC message...
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (meas) {
            meas->t4 = rxtime - Time(s64(hdr.correction));
            // Optional diagnostics showing all collected timestamps.
            if (DEBUG_VERBOSE > 0)
                log::Log(log::DEBUG, "PtpClient: Measurement ready").write_obj(*meas);
            // If we have every timestamp, notify all callback object(s).
            notify_if_complete(meas);
        } else {cache_miss();} // GCOVR_EXCL_LINE
    }
}

void Client::rcvd_pdelay_resp(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay response");

    if (m_state == ClientState::PASSIVE) {
        // Message contents defined in Section 13.9.1.
        Time t4 = m_iface.ptp_rx_timestamp();
        Time t2; bool ok = t2.read_from(&rd);
        auto rcvd_2step = hdr.flags & Header::FLAG_TWO_STEP;

        // Find the corresponding PDELAY_REQ message.
        // If this completes the peer-to-peer delay request, notify the callback object.
        auto meas = m_cache.find(hdr, hdr.src_port);
        if (ok && meas) {
            // Use T2 if provided, otherwise best-guess placeholder.
            // Note: T1 and T4 are the only precise timestamps in this mode.
            meas->t1 += Time(s64(hdr.correction - meas->ref.correction));
            meas->t2 = (t2 == TIME_ZERO) ? (meas->t1 + t4)/2 : t2;
            meas->t3 = meas->t2;
            meas->t4 = t4;
            if (!rcvd_2step) notify_if_complete(meas);
        } else {cache_miss();}
    }
}

void Client::rcvd_pdelay_follow_up(const Header& hdr, ArrayRead& rd)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "PtpClient: PDelay response follow up");

    // Message contents defined in Section 13.11.1.
    Time origin; bool ok = origin.read_from(&rd);
    if (!ok) return;

    // Find the corresponding PDELAY_REQ message.
    auto meas = m_cache.find(hdr, hdr.src_port);
    if (meas) {
        meas->t1 += Time(s64(hdr.correction));
        notify_if_complete(meas);
    } else {cache_miss();} // GCOVR_EXCL_LINE
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

    // The flags we care about are:
    //  * FLAG_PTP_TIMESCALE (required on all announce messages)
    //  * FLAG_UNICAST (inferred by type)
    //  * FLAG_TWO_STEP (set by caller if required)
    //  * FLAG_SPTP aka FLAG_PROFILE1 (set if SPTP mode is enabled)
    if (type == Header::TYPE_ANNOUNCE)
        hdr.flags |= Header::FLAG_PTP_TIMESCALE;
    if (type == Header::TYPE_DELAY_REQ || type == Header::TYPE_DELAY_RESP)
        hdr.flags |= Header::FLAG_UNICAST;
    if (SATCAT5_SPTP_ENABLE && m_mode == ClientMode::SLAVE_SPTP)
        hdr.flags |= Header::FLAG_SPTP;

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
        SATCAT5_CLOCK->busywait_usec(10);
    }
}

bool Client::send_announce()
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_announce");
    // ANNOUNCE messages are always broadcast.
    // Message contents defined in Section 13.5.
    // Note: Dummy timestamp is acceptable (Section 13.5.2.1)
    Header hdr = make_header(Header::TYPE_ANNOUNCE, ++m_announce_id);
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(broadcast_to(m_mode), hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(TIME_ZERO);           // originTimestamp
    wr->write_u16(SATCAT5_UTC_OFFSET);  // currentUtcOffset
    wr->write_u8(0);                    // Reserved
    wr->write_obj(m_clock_local);       // Grandmaster clock info
    tlv_send(hdr, wr);                  // Write TLV(s)
    return wr->write_finalize();
}

bool Client::send_sync(DispatchTo addr, u16 seq_id, u16 flags, u64 tref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_sync");

    // Before we do anything, note the receive timestamp for SPTP only.
    bool send_sptp = SATCAT5_SPTP_ENABLE && (flags & Header::FLAG_SPTP);
    Time t4 = send_sptp ? m_iface.ptp_rx_timestamp() : TIME_ZERO;

    // Always use two-step mode for SPTP or for upstream requests.
    // (If so, avoid calling "ptp_tx_start" to prevent double-booking.)
    // Otherwise, attempt one-step mode if supported by hardware.
    bool req_2step = send_sptp || (flags & Header::FLAG_TWO_STEP);
    Time t1 = req_2step ? TIME_ZERO : m_iface.ptp_tx_start();

    // One-step mode: correctionField per Section 9.5.10.
    // Two-step mode: correctionField and originTimestamp are zero.
    // SPTP mode: correctionField zero, originTimestamp is T4.
    Header hdr = make_header(Header::TYPE_SYNC, seq_id);
    Time origin_time;
    if (send_sptp) {
        hdr.flags |= Header::FLAG_TWO_STEP | Header::FLAG_SPTP;
        hdr.correction = 0;
        origin_time = t4;
    } else if (t1 == TIME_ZERO) {
        hdr.flags |= Header::FLAG_TWO_STEP;
        hdr.correction = 0;
        origin_time = TIME_ZERO;
    } else {
        hdr.correction = t1.correction();
        origin_time = t1;
    }

    // SYNC messages are broadcast by default, unicast on-demand,
    // Message contents defined in Section 13.6.
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(addr, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(origin_time);         // originTimestamp
    tlv_send(hdr, wr);                  // Write TLV(s)
    if (hdr.flags & Header::FLAG_TWO_STEP) {
        return wr->write_finalize() && send_follow_up(addr, seq_id, flags, tref);
    } else {
        return wr->write_finalize();
    }
}

bool Client::send_follow_up(satcat5::ptp::DispatchTo addr, u16 seq_id, u16 flags, u64 tref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_follow_up");

    // Get the timestamp from the SYNC message we just sent.
    Time t1 = m_iface.ptp_tx_timestamp();
    if (t1 == TIME_ZERO) log::Log(log::ERROR, "PtpClient: Bad hardware timestamp.");

    // FOLLOW_UP messages are sent to the same recipient(s) as the SYNC.
    // Message contents defined in Section 13.7.
    // Two-step correctionField per Section 9.5.10.
    Header hdr = make_header(Header::TYPE_FOLLOW_UP, seq_id);
    hdr.correction = t1.correction() + tref;
    hdr.flags |= flags;
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(addr, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(t1);                  // preciseOriginTimestamp
    tlv_send(hdr, wr);                  // Write TLV(s)
    return wr->write_finalize();
}

void Client::send_delay_req_sptp()
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_delay_req_sptp");

    // Error if we send N requests in a row with no response.
    unsigned timeout = 5 << m_sync_rate;
    if (++m_request_wdog >= timeout) {
        client_timeout(); return;
    }

    // Attempt to send a DELAY_REQ message with the SPTP flag.
    // If successful, note the outgoing timestamp.
    Header hdr = make_header(Header::TYPE_DELAY_REQ, ++m_sync_id);
    hdr.src_port = m_current_source;
    if (send_delay_req(hdr.seq_id, Header::FLAG_SPTP)) {
        auto meas = m_cache.push(hdr);
        meas->t3 = m_iface.ptp_tx_timestamp();
    }
}

bool Client::send_delay_req(u16 seq_id, u16 flags)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_delay_req");

    // The timestamp we send here can be approximate (Section 11.3.2 c).
    // Do NOT call ptp_tx_start() here, since incrementing correctionField
    // double-books the elapsed time compared to ptp_tx_timestamp().
    Time t3_approx = m_iface.ptp_time_now();

    // DELAY_REQ messages are usually sent in response to a SYNC message.
    // (Except for unsolicited messages sent by SPTP clients.)
    // Message contents defined in Section 13.6.
    // Set correctionField to zero per Section 11.3.2 c.
    Header hdr = make_header(Header::TYPE_DELAY_REQ, seq_id);
    hdr.correction = 0;
    hdr.flags |= flags;
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(t3_approx);           // originTimestamp
    tlv_send(hdr, wr);                  // Write TLV(s)
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
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(t4);                  // receiveTimestamp
    wr->write_obj(ref.src_port);        // requestingPortIdentity
    tlv_send(hdr, wr);                  // Write TLV(s)
    return wr->write_finalize();
}

bool Client::send_pdelay_req()
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_req");

    // Estimate the current time for the originTimestamp field.
    // To avoid double-counting, do not call "ptp_tx_start" or set
    //  outgoing correctionField.  Further discussion under "send_delay_req".
    Time t1_approx = m_iface.ptp_time_now();

    // Message contents defined in Section 13.9 and Section 11.4.2.
    Header hdr = make_header(Header::TYPE_PDELAY_REQ, ++m_pdelay_id);
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(DispatchTo::STORED, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(t1_approx);           // originTimestamp
    wr->write_obj(TIME_ZERO);           // reserved = 0
    tlv_send(hdr, wr);                  // Write TLV(s)
    bool ok = wr->write_finalize();

    // If successful, note the precise transmit timestamp.
    if (ok) {
        Time t1_actual = m_iface.ptp_tx_timestamp();
        auto meas = m_cache.push(hdr);
        meas->t1 = t1_actual;
    }

    return ok;
}

bool Client::send_pdelay_resp(const satcat5::ptp::Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_resp");

    // Get the timestamp from the DELAY_REQ message we just received.
    // (Also echo correctionField from the received packet.)
    Time t2 = m_iface.ptp_rx_timestamp();

    // If one-step mode is supported, predict outgoing timestamp.
    Time t3 = m_iface.ptp_tx_start();

    // PDELAY_RESP messages are always replies to the client.
    // Message contents defined in Section 13.8.
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

    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(TIME_ZERO);           // requestReceiptTimestamp
    wr->write_obj(ref.src_port);        // requestingPortIdentity
    tlv_send(hdr, wr);                  // Write TLV(s)

    if (hdr.flags & Header::FLAG_TWO_STEP || t3 == TIME_ZERO) {
        return wr->write_finalize() && send_pdelay_follow_up(ref);
    } else {
        return wr->write_finalize();
    }
}

bool Client::send_pdelay_follow_up(const satcat5::ptp::Header& ref)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "PtpClient: send_pdelay_follow_up");

    // Two-step mode uses most recent transmit and receive timestamps.
    Time t2 = m_iface.ptp_rx_timestamp();
    Time t3 = m_iface.ptp_tx_timestamp();

    // Message contents defined in Section 13.11.
    Header hdr = make_header(Header::TYPE_PDELAY_RFU, ref.seq_id);
    hdr.domain = ref.domain;
    hdr.sdo_id = ref.sdo_id;
    hdr.src_port = ref.src_port;

    // See Section 11.4.2 c
    hdr.correction = ref.correction + (t3 - t2).delta_subns();
    hdr.length += tlv_send(hdr, 0);     // Predict tag length
    auto wr = m_iface.ptp_send(DispatchTo::REPLY, hdr.length, hdr.type);
    if (!wr) return false;
    wr->write_obj(hdr);                 // Common message header
    wr->write_obj(TIME_ZERO);           // responseOriginTimestamp
    wr->write_obj(ref.src_port);        // requestingPortIdentity
    tlv_send(hdr, wr);                  // Write TLV(s)
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
