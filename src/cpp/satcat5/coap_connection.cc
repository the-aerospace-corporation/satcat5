//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_connection.h>
#include <satcat5/coap_endpoint.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <satcat5/log.h>
#include <satcat5/udp_dispatch.h>

using satcat5::coap::Connection;
using satcat5::coap::ConnectionSpp;
using satcat5::coap::ConnectionUdp;
using satcat5::coap::Endpoint;
using satcat5::coap::Reader;
using satcat5::coap::ReadHeader;
using satcat5::io::ArrayWriteStatic;
using satcat5::io::Writeable;
namespace log = satcat5::log;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Define fields for the "m_flags" variable.
constexpr u8 FLAG_TKL   = 0x0F; // LSBs = token length
constexpr u8 FLAG_SEP   = 0x10; // Separated response?
constexpr u8 FLAG_CON   = 0x20; // Confirmable request

// Set safe or aggressive transmission parameters?
//  * Fast (1) = Aggressively optimized for less-constrained networks.
//  * Safe (0) = Within limits from Section 4.8 and 4.8.2.
#ifndef SATCAT5_COAP_FAST
#define SATCAT5_COAP_FAST 1
#endif

#if SATCAT5_COAP_FAST
    // Aggressively optimized for less-constrained networks.
    // Note: Listed timeouts are for first attempt only.
    // Maximum timeout is ACK_TIMEOUT_MSEC * 2^(MAX_RETRANSMIT-1)
    constexpr unsigned ACK_TIMEOUT_MSEC     = 125;
    constexpr unsigned MAX_LEISURE_MSEC     = 500;
    constexpr unsigned PROBE_TIMEOUT_MSEC   = 1000;
    constexpr unsigned MAX_RETRANSMIT       = 6;
#else
    // Within safe limits from Section 4.8 and 4.8.2.
    constexpr unsigned ACK_TIMEOUT_MSEC     = 1000;
    constexpr unsigned MAX_LEISURE_MSEC     = 2000;
    constexpr unsigned PROBE_TIMEOUT_MSEC   = 3000;
    constexpr unsigned MAX_RETRANSMIT       = 5;
#endif

// Derived constants from above parameters:
constexpr unsigned MAX_TRANSMIT_SPAN
    = (ACK_TIMEOUT_MSEC * (1u << MAX_RETRANSMIT) * 3) / 2;
constexpr unsigned MAX_SEPARATE_SPAN
    = (MAX_TRANSMIT_SPAN * 3) / 2;

Connection::Connection(Endpoint* endpoint, satcat5::net::Address* addr)
    : Protocol(satcat5::net::TYPE_NONE)
    , m_coap(nullptr)
    , m_addr(addr)
    , m_state(State::IDLE)
    , m_proxy_token(0)
    , m_allow_reuse(1)
    , m_tx_count(0)
    , m_meta_idx(0)
    , m_meta_count(0)
    , m_flags{}
    , m_msgid{}
    , m_token{}
{
    init(endpoint);
}

#if SATCAT5_ALLOW_DELETION
Connection::~Connection() {
    if (m_coap) {
        m_coap->remove_connection(this);
        if (m_filter.as_u32()) {
            m_coap->iface()->remove(this);
        }
    }
}
#endif

void Connection::init(Endpoint* endpoint) {
    if (endpoint && !m_coap) {
        m_coap = endpoint;
        m_coap->add_connection(this);
    }
}

bool Connection::is_match_coap(const ReadHeader* msg) const {
    // Idle state can never match anything.
    if (m_state == State::IDLE) return false;
    // Check message-ID match (mid) and token match (tok).
    bool mid = (msg->msg_id() == msg_id());
    bool tok = (msg->tkl() == tkl() && msg->token() == token());
    // Is this the start of a separated response?
    bool sep = (is_request() && msg->type() == TYPE_CON);
    // Request/response matching rules (Section 5.3.2):
    if (msg->code() == CODE_EMPTY) {
        // Empty messages omit the token, comparing message ID only.
        return mid;
    } else {
        // Separated messages may have same token, different ID.
        // All others should match both token and ID.
        return tok && (mid || sep);
    }
}

void Connection::close() {
    if (m_coap && m_filter.as_u32()) m_coap->iface()->remove(this);
    m_filter = satcat5::net::TYPE_NONE;
    m_addr->close();
    reset_hard();
    m_allow_reuse = 1;
}

// Event-handler for the child's connect(...) method.
bool Connection::connected(bool allow_reuse) {
    // Set the flag to allow or prevent automatic reuse of idle connections.
    // (Manual connections may want to remain open until explicitly closed.)
    m_allow_reuse = allow_reuse ? 1 : 0;
    // If required, set a timeout to retry connection (e.g., ARP query).
    if (!m_addr->ready()) {
        ++m_tx_count;
        m_state = State::CONNECT_IDLE;
        timer_rand(ACK_TIMEOUT_MSEC);
    }
    return true;
}

bool Connection::ping(u16 msg_id) {
    // Are we in a state that can send a ping?
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Ping");
    return ready() && send_empty(TYPE_CON, msg_id);
}

bool Connection::ready() const {
    // Are we in a state that can send a new request?
    if (m_state == State::CONNECT_IDLE) return true;
    return (m_state == State::IDLE) && m_addr->ready();
}

Writeable* Connection::open_request() {
    // Are we in a state that can send a new request?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: open_request");
    if (!ready()) return 0; // Are we in idle or pseudo-idle state?
    write_abort();          // Flush leftovers in buffer.
    return this;            // Wait for user to call write_finalize().
}

Writeable* Connection::open_response() {
    // Are we in a state that can send a response?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: open_response");
    if (!is_await()) return 0;
    write_abort();          // Flush leftovers in buffer.
    return this;            // Wait for user to call write_finalize().
}

bool Connection::open_separate(const ReadHeader* msg) {
    // Are we in a state that can send a separated response?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: open_separate");
    if (msg->type() != TYPE_CON) return false;
    satcat5::coap::Writer wr(open_response());
    if (!wr.ready()) return false;
    // Write an empty ACK message to the main working buffer.
    // Note: Do not echo request token (Section 3).
    wr.write_header(TYPE_ACK, CODE_EMPTY, msg->msg_id());
    return wr.write_finalize();
}

Writeable* Connection::continue_separate() {
    // Are we in a state that can continue a separated response?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: continue_separate");
    if (m_state != State::RESPONSE_SEP1) return 0;
    write_abort();          // Flush leftovers in buffer.
    return this;            // Ready to continue response.
}

bool Connection::error_response(Code code, const char* why) {
    // Are we in a state that can send a response? Are given inputs valid?
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Returning error");
    if (!is_await()) return false;
    if (!code.is_error()) return false;
    write_abort();          // Flush leftovers in buffer.

    // Create a reply message of type ACK/NON raising an error
    satcat5::coap::Writer wr(open_response());
    if (!wr.ready()) return false;
    wr.write_header(response_type(), code, msg_id(), token(), tkl());
    if (why) {
        wr.write_option(OPTION_FORMAT, FORMAT_TEXT);
        wr.write_data()->write_str(why);
    }
    return wr.write_finalize();
}

u8 Connection::response_type() const {
    if (is_separate()) return TYPE_CON;
    u8 flag_con = m_flags[m_meta_idx] & FLAG_CON;
    return flag_con ? TYPE_ACK : TYPE_NON;
}

bool Connection::test_inject(unsigned len, const void* data) {
    // Test only. Not intended for use in production.
    Writeable* wr = m_addr->open_write(len);
    if (!wr) return false;  // Unable to send?
    wr->write_bytes(len, data);
    return wr->write_finalize();
}

void Connection::frame_rcvd(satcat5::io::LimitedRead& src) {
    // Process messages for this connection's unique port.
    // Shared ports are handled by Endpoint::frame_rcvd().
    // TODO: Find a way to allow user-defined option handling?
    satcat5::coap::ReadSimple msg(&src);
    deliver(&msg);
}

// Stateful message-handling.  Endpoint ensures messages are routed
// to the matching Connection object if applicable, so this method
// should not attempt to handle responses for other addresses.
bool Connection::deliver(Reader* msg) {
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: deliver")
        .write(msg->type()).write(msg->code().value).write(msg->msg_id());

    // Can we accept this message?
    bool accept = m_coap && (is_idle() || is_match_addr());
    if (msg->error() || !accept) return false;

    // If this is a new connection, accept it and reset history.
    // Make the connection now, while the network stack has the reply address,
    // in case user logic delays the callback to open_request/open_separate.
    if (is_idle() && !is_match_addr()) {
        reset_hard();
        m_addr->save_reply_address();
    }

    // Compare message-ID and token fields.
    bool match = is_match_coap(msg);
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Matched")
        .write(msg->type()).write(msg->code().value).write(msg->msg_id()).write(match);

    if (msg->type() == TYPE_CON && msg->code() == CODE_EMPTY) {
        // CoAP ping request (Section 1.2, Section 4.3).
        if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Ping-rcvd");
        send_empty(TYPE_RST, msg->msg_id());    // Send ping response
    } else if (msg->type() == TYPE_RST && msg->code() == CODE_EMPTY) {
        // CoAP ping response (Section 1.2, Section 4.3).
        if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Pong-rcvd");
        m_coap->coap_ping(msg);                 // Notification for user logic
    } else if (msg->type() == TYPE_RST) {
        // Reset message forcibly returns connection to the idle state.
        if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rst");
        if (is_request()) error_event();        // Notification for user logic?
        reset_hard();                           // Hard reset of state + history
    } else if (match && is_request()) {
        // Response to a query that we issued?
        if (msg->type() == TYPE_ACK && msg->code() == CODE_EMPTY) {
            // Separate response start: Wait silently for the full response.
            // (Timer changes from a retry loop to a transaction timeout.)
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep1");
            m_state = State::REQUEST_SEP;       // Pause the retry loop.
            timer_once(MAX_SEPARATE_SPAN);      // Set new overall timeout.
            m_coap->coap_separate(this, msg);   // Notification to parent.
        } else if (msg->type() == TYPE_CON) {
            // Completion of separated response.
            // Note: This may arrive first if the ACK is lost or delayed.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep2");
            m_flags[m_meta_idx] |= FLAG_SEP;    // Set separated flag.
            m_coap->reply(TYPE_ACK, msg);       // Send acknowledgement.
            reset_soft();                       // Return to idle state.
            m_coap->coap_response(this, msg);   // Deliver response to parent.
        } else {
            // Normal response. For unicast queries, return to idle state.
            // For multicast, keep listening for more responses until timeout.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-ack");
            if (!m_addr->is_multicast()) reset_soft();
            m_coap->coap_response(this, msg);   // Deliver response to parent.
        }
    } else if (match && is_response()) {
        if (msg->is_request()) {
            // Repeated request: Retransmit cached response if applicable.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rpt1");
            if (msg->type() == TYPE_CON) send_buffer();
        } else if (m_state == State::RESPONSE_SEP2) {
            // Separate response ACK: Exchange completed, return to idle.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep3");
            reset_soft();                       // Return to idle state.
        }
    } else if (msg->is_request()) {
        // Is this a fresh request? Check recent history.
        int recent = match_history(msg);
        if (match && is_await()) {
            // Received a duplicate request while waiting in the "await" state.
            // (see below). Issue a notification for unusual endpoints, such as
            // reverse-proxies that may switch over to separated-response mode.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-dupe");
            m_coap->coap_reqwait(this, msg);    // Notify user of the event
        } else if (recent >= 0) {
            // Stale requests are ignored, but may need to resend an ACK.
            // (i.e., We got the separated response but the ACK was lost.)
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rpt2");
            u8 sep = m_flags[recent] & FLAG_SEP;
            if (msg->type() == TYPE_CON && sep) m_coap->reply(TYPE_ACK, msg);
        } else {
            // Received a new request. Before we ask user Endpoint to respond,
            // enter "await" state to set a watchdog timeout for that response.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-req");
            m_state = m_addr->reply_is_multicast()
                ? State::WAIT_RESPONSE_M : State::WAIT_RESPONSE_U;
            timer_once(MAX_TRANSMIT_SPAN);      // Timeout for user response
            push_history(msg);                  // Note message-ID and token.
            // User logic must process the request and issue a response.
            // (This may occur inside the callback or after a short delay.)
            m_coap->coap_request(this, msg);    // Notify user of the request
        }
    } else {
        // Stale responses are simply discarded.
        if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-stale");
    }
    return true;
}

void Connection::error_event() {
    // Set ERROR state to block user callback from trying to transmit.
    // (This call should usually be followed by a hard or soft reset.)
    m_state = State::ERROR;
    m_coap->coap_error(this);
}

int Connection::match_history(const ReadHeader* msg) const {
    // Is this a new ID, or does it appear in our recent history?
    // Return matching index, or -1 if none is found.
    for (u8 a = 0 ; a < m_meta_count ; ++a) {
        u8 sep = m_flags[a] & FLAG_SEP;
        u8 tkl = m_flags[a] & FLAG_TKL;
        bool match = (msg->tkl() == tkl)
                  && (msg->token() == m_token[a])
                  && (msg->msg_id() == m_msgid[a] || sep);
        if (match) return int(a);
    }
    return -1;
}

void Connection::push_history(const ReadHeader* msg) {
    // Ignore duplicate request/response.
    if (is_match_coap(msg)) return;

    // Update the write index.
    if (m_meta_count < SATCAT5_COAP_HISTORY) {
        m_meta_idx = m_meta_count++;    // Index lags by one
    } else if (++m_meta_idx >= SATCAT5_COAP_HISTORY) {
        m_meta_idx = 0;                 // Increment with wraparound
    }

    // Note the new message identifiers.
    u8 flags = msg->tkl();
    if (msg->type() == TYPE_CON) flags |= FLAG_CON;
    m_flags[m_meta_idx] = flags;
    m_msgid[m_meta_idx] = msg->msg_id();
    m_token[m_meta_idx] = msg->token();
}

void Connection::reset_hard() {
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: reset_hard");
    // Hard reset clears history.
    reset_soft();
    m_meta_idx = 0;
    m_meta_count = 0;
    m_proxy_token = 0;
}

void Connection::reset_soft() {
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: reset_soft");
    // Soft reset reverts to idle.
    m_state = State::IDLE;
    m_tx_count = 0;
    timer_stop();
}

bool Connection::send_buffer() {
    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "CoAP: send_buffer").write(msg_id());

    // Increment the transmit counter.
    ++m_tx_count;

    // Attempt to send the buffer contents.
    Writeable* wr = m_addr->open_write(written_len());
    if (!wr) return false;  // Unable to send?
    wr->write_bytes(written_len(), buffer());
    return wr->write_finalize();
}

void Connection::timer_event() {
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "CoAP: timer_event").write(msg_id());
    if (!m_coap) return;

    if (is_connecting() && m_addr->ready()) {
        // Connection ready, transmit message if one is queued.
        if (m_state == State::CONNECT_BUSY) send_first();
        else reset_soft();
    } else if (is_connecting() && m_tx_count < MAX_RETRANSMIT) {
        // Retry ARP query and set a timer for the next attempt.
        m_addr->retry();
        timer_rand(ACK_TIMEOUT_MSEC << m_tx_count);
        ++m_tx_count;   // Increase timeout for next time.
    } else if (m_state == State::RESPONSE_DEFER) {
        // Send the deferred response, then back to idle.
        // (Multicast cache is optional per Section 8.2.1.)
        send_buffer();
        reset_soft();
    } else if (m_state == State::REQUEST_CON && m_tx_count < MAX_RETRANSMIT) {
        // Retry CoAP request and set a timer for the next attempt.
        send_buffer();
        timer_rand(ACK_TIMEOUT_MSEC << m_tx_count);
    } else if (m_state == State::RESPONSE_SEP2 && m_tx_count < MAX_RETRANSMIT) {
        // Retry CoAP separated response and set a timer for the next attempt.
        send_buffer();
        timer_rand(ACK_TIMEOUT_MSEC << m_tx_count);
    } else {
        // Ultimate timeout reached, report error if applicable.
        // (For some states, timeouts may be expected during normal operation.)
        if (m_state == State::REQUEST_NON) {
            m_coap->coap_timeout(this);
        } else if (m_state != State::RESPONSE_CACHE) {
            m_coap->coap_error(this);
        }
        reset_soft();
    }
}

bool Connection::send_empty(u8 typ, u16 id) {
    // Construct the outgoing message in a temporary buffer.
    // (This is easier than trying to predict the total length.)
    ArrayWriteStatic<64> msg;
    satcat5::coap::Writer hdr(&msg);
    hdr.write_header(typ, CODE_EMPTY, id);
    hdr.write_finalize();   // Empty message (no options or data)

    // Send the message using the previously-configured connection.
    Writeable* wr = m_addr->open_write(msg.written_len());
    if (wr) wr->write_bytes(msg.written_len(), msg.buffer());
    return wr && wr->write_finalize();
}

void Connection::timer_rand(u32 base_msec) {
    // Randomize timeouts by a factor of [1.0..1.5] per Section 4.8.1.
    // (This helps prevent ensemble-lockstep synchronization effects.)
    timer_once(base_msec + satcat5::util::prng.next(0, base_msec / 2));
}

bool Connection::write_finalize() {
    // Call the parent's event-handler, which aborts on overflow.
    // Otherwise, proceed with header parsing to set initial state.
    return ArrayWrite::write_finalize() && send_first();
}

bool Connection::send_first() {
    // Parse the CoAP header from the transmit buffer contents...
    satcat5::io::ArrayRead rdbuf(buffer(), written_len());
    satcat5::coap::ReadHeader msg(&rdbuf);
    if (msg.error()) return false;  // Abort for invalid message?
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "CoAP: write_finalize").write(msg_id());

    // Block all outgoing messages from the ERROR state.
    if (m_state == State::ERROR) return false;

    // For outgoing multicast requests and responses to multicast requests,
    // the only permissible message type is nonconfirmable (Section 8.1).
    if (m_addr->is_multicast() && msg.type() != TYPE_NON) return false;
    if (m_state == State::WAIT_RESPONSE_M && msg.type() != TYPE_NON) return false;

    // During the initial connection phase, reject unexpected messages.
    if (is_connecting() && !msg.is_request()) return false;

    // On reaching this point, the message is accepted for transmission,
    // either immediately or after a short delay. Note ID/token/etc.
    push_history(&msg);

    // Set the new state, and set timer if applicable.
    if (m_state == State::CONNECT_IDLE && !m_addr->ready()) {
        // Defer outgoing requests until we're connected.
        // (Polling/retry logic will call this method again once ready.)
        m_state = State::CONNECT_BUSY;
        return true;
    } else if (m_state == State::RESPONSE_SEP1 && msg.type() == TYPE_CON) {
        // Separated response, set retry timer.
        m_state = State::RESPONSE_SEP2;
        timer_rand(ACK_TIMEOUT_MSEC);
    } else if (m_state == State::WAIT_RESPONSE_M) {
        // Respond to multicast queries after a random delay (Section 8.2).
        m_state = State::RESPONSE_DEFER;
        timer_once(satcat5::util::prng.next(1, MAX_LEISURE_MSEC));
    } else if (msg.type() == TYPE_CON) {
        // Confirmable request, set retry timer.
        m_state = State::REQUEST_CON;
        timer_rand(ACK_TIMEOUT_MSEC);
    } else if (msg.type() == TYPE_NON) {
        // Nonconfirmable request, set rate-limit timer.
        // (i.e., No more outgoing requests until response or timeout.)
        m_state = State::REQUEST_NON;
        timer_rand(PROBE_TIMEOUT_MSEC);
    } else if (msg.type() == TYPE_ACK && msg.code() == CODE_EMPTY) {
        // Separated response, set cache-expiration timeout.
        m_state = State::RESPONSE_SEP1;
        timer_once(MAX_SEPARATE_SPAN);
    } else if (msg.type() == TYPE_ACK) {
        // Ack/Response, set cache-expiration timeout.
        m_state = State::RESPONSE_CACHE;
        timer_once(MAX_TRANSMIT_SPAN);
    } else if (msg.type() == TYPE_RST) {
        // Hard reset of state + history.
        reset_hard();
    }

    // Except for the deferred-response case, send immediately.
    m_tx_count = 0;
    return (m_state == State::RESPONSE_DEFER) || send_buffer();
}

ConnectionSpp::ConnectionSpp(Endpoint* endpoint, satcat5::ccsds_spp::Dispatch* iface)
    : Connection(endpoint, &m_spp), m_spp(iface)
{
    // Nothing else to initialize.
}

bool ConnectionSpp::connect(u16 apid) {
    // Sanity check: Don't break active connections.
    if (m_state != State::IDLE) return false;

    // Close and reopen with the new APID.
    // (Outgoing requests are always telecommands.)
    close();
    m_spp.connect(true, apid);

    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "CoAP: Connect").write(apid);
    return connected(true);
}

bool ConnectionUdp::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport,
    bool allow_reuse)
{
    // Sanity check: Don't break active connections.
    if (m_state != State::IDLE) return false;
    if (!m_coap) return false;

    // Close and reopen with the new connection.
    close();
    m_udp.connect(dstaddr, dstport, srcport);

    // If we have a unique port number, register for incoming messages.
    if (m_udp.srcport() != m_coap->srcport()) {
        m_filter = satcat5::net::Type(m_udp.srcport().value);
        m_coap->iface()->add(this);
    }

    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "CoAP: Connect").write(dstaddr);
    return connected(allow_reuse);
}

bool ConnectionUdp::is_match_addr(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport) const
{
    return m_udp.dstaddr() == dstaddr
        && m_udp.dstport() == dstport;
}

void ConnectionUdp::init(Endpoint* endpoint, satcat5::udp::Dispatch* iface) {
    Connection::init(endpoint);
    m_udp.init(iface);
}
