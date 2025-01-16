//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
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
using satcat5::coap::Reader;
using satcat5::io::ArrayWriteStatic;
using satcat5::io::Writeable;
namespace log = satcat5::log;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Define fields for the "m_flags" variable.
constexpr u8 FLAG_TKL   = 0x0F; // LSBs = token length
constexpr u8 FLAG_SEP   = 0x10; // Separated response?

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
    constexpr unsigned SEP_TIMEOUT_MSEC     = 2500;
    constexpr unsigned MAX_RETRANSMIT       = 6;
#else
    // Within safe limits from Section 4.8 and 4.8.2.
    constexpr unsigned ACK_TIMEOUT_MSEC     = 1000;
    constexpr unsigned MAX_LEISURE_MSEC     = 2000;
    constexpr unsigned PROBE_TIMEOUT_MSEC   = 3000;
    constexpr unsigned SEP_TIMEOUT_MSEC     = 5000;
    constexpr unsigned MAX_RETRANSMIT       = 5;
#endif

// Derived constants from above parameters:
constexpr unsigned MAX_TRANSMIT_SPAN
    = (ACK_TIMEOUT_MSEC * (1u << MAX_RETRANSMIT) * 3) / 2;

Connection::Connection(
    satcat5::coap::Endpoint* endpoint,
    satcat5::net::Address* addr)
    : Protocol(satcat5::net::TYPE_NONE)
    , m_coap(endpoint)
    , m_addr(addr)
    , m_state(State::IDLE)
    , m_tx_count(0)
    , m_meta_idx(0)
    , m_meta_count(0)
    , m_flags{}
    , m_msgid{}
    , m_token{}
{
    m_coap->add_connection(this);
}

#if SATCAT5_ALLOW_DELETION
Connection::~Connection() {
    m_coap->remove_connection(this);
    if (m_filter.as_u32()) {
        m_coap->iface()->remove(this);
    }
}
#endif

bool Connection::is_match_coap(const Reader& msg) const {
    // Idle state can never match anything.
    if (m_state == State::IDLE) return false;
    // Check message-ID match (mid) and token match (tok).
    bool mid = (msg.msg_id() == msg_id());
    bool tok = (msg.tkl() == tkl() && msg.token() == token());
    // Is this the start of a separated response?
    bool sep = (is_request() && msg.type() == TYPE_CON);
    // Request/response matching rules (Section 5.3.2):
    if (msg.code() == CODE_EMPTY) {
        // Empty messages omit the token, comparing message ID only.
        return mid;
    } else {
        // Separated messages may have same token, different ID.
        // All others should match both token and ID.
        return tok && (mid || sep);
    }
}

void Connection::close() {
    if (m_filter.as_u32()) m_coap->iface()->remove(this);
    m_filter = satcat5::net::TYPE_NONE;
    if (m_addr) m_addr->close();
    reset_hard();
}

// Event-handler for the child's connect(...) method.
bool Connection::connected() {
    if (m_addr->ready()) {
        // Ready to send data immediately.
        m_coap->coap_connected(this);
    } else {
        // Set a timeout to retry connection (e.g., ARP query).
        ++m_tx_count;
        m_state = State::CONNECT;
        timer_rand(ACK_TIMEOUT_MSEC);
    }
    return true;
}

bool Connection::ping(u16 msg_id) {
    // Are we in a state that can send a ping?
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Ping");
    return is_idle() && m_addr->ready() && send_empty(TYPE_CON, msg_id);
}

bool Connection::ready() const {
    // Are we in a state that can send a new request?
    bool ok = (m_state == State::CONNECT) || (m_state == State::IDLE);
    return ok && m_addr->ready();
}

Writeable* Connection::open_request() {
    // Are we in a state that can send a new request?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: open_request");
    if (!ready()) return 0;
    reset_soft();           // Return to idle state.
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

bool Connection::open_separate(const Reader& msg) {
    // Are we in a state that can send a separated response?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: open_separate");
    satcat5::coap::Writer wr(open_response());
    if (!wr.ready()) return false;
    // Write an empty ACK message to the main working buffer.
    // Note: Do not echo request token (Section 3).
    wr.write_header(TYPE_ACK, CODE_EMPTY, msg.msg_id());
    return wr.write_finalize();
}

Writeable* Connection::continue_separate() {
    // Are we in a state that can continue a separated response?
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: continue_separate");
    if (m_state != State::RESPONSE_SEP1) return 0;
    write_abort();          // Flush leftovers in buffer.
    return this;            // Ready to continue response.
}

bool Connection::error_response(Code code, const Reader& msg, const char* why) {
    // Are we in a state that can send a response? Are given inputs valid?
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Returning error");
    if (!is_await()) return false;
    if (!code.is_error()) return false;
    if (!(msg.type() == TYPE_CON || msg.type() == TYPE_NON)) return false;
    write_abort();          // Flush leftovers in buffer.

    // Create a reply message of type ACK/NON raising an error
    satcat5::coap::Writer wr(open_response());
    if (!wr.ready()) return false;
    u8 type = msg.type() == TYPE_CON ? TYPE_ACK : TYPE_NON;
    wr.write_header(type, code, msg.msg_id(), msg.token(), msg.tkl());
    if (why) {
        wr.write_option(OPTION_FORMAT, FORMAT_TEXT);
        wr.write_data()->write_str(why);
    }
    return wr.write_finalize();
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
    coap::Reader msg(&src);
    deliver(msg);
}

// Stateful message-handling.  Endpoint ensures messages are routed
// to the matching Connection object if applicable, so this method
// should not attempt to handle responses for other addresses.
bool Connection::deliver(Reader& msg) {
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: deliver")
        .write(msg.type()).write(msg.code().value).write(msg.msg_id());

    // Can we accept this message?
    bool accept = is_idle() || is_match_addr();
    if (msg.error() || !accept) return false;

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
        .write(msg.type()).write(msg.code().value).write(msg.msg_id()).write(match);

    if (msg.type() == TYPE_CON && msg.code() == CODE_EMPTY) {
        // CoAP ping request (Section 1.2, Section 4.3).
        if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Ping-rcvd");
        send_empty(TYPE_RST, msg.msg_id());     // Send ping response
    } else if (msg.type() == TYPE_RST && msg.code() == CODE_EMPTY) {
        // CoAP ping response (Section 1.2, Section 4.3).
        if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: Pong-rcvd");
        m_coap->coap_ping(msg);                 // Notification for user logic
    } else if (msg.type() == TYPE_RST) {
        // Reset message forcibly returns connection to the idle state.
        if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rst");
        bool notify = is_request();             // Is user awaiting a response?
        reset_hard();                           // Hard reset of state + history
        if (notify) m_coap->coap_error(this);   // Notification for user logic
    } else if (match && is_request()) {
        // Response to a query that we issued?
        if (msg.type() == TYPE_ACK && msg.code() == CODE_EMPTY) {
            // Separate response start: Wait silently for the full response.
            // (Timer changes from a retry loop to a transaction timeout.)
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep1");
            m_state = State::REQUEST_SEP;       // Pause the retry loop.
            timer_once(SEP_TIMEOUT_MSEC);       // Set new overall timeout.
        } else if (msg.type() == TYPE_CON) {
            // Completion of separated response.
            // Note: This may arrive first if the ACK is lost or delayed.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep2");
            m_flags[m_meta_idx] |= FLAG_SEP;    // Set separated flag.
            m_coap->reply(TYPE_ACK, msg);       // Send acknowledgement.
            reset_soft();                       // Return to idle state.
            m_coap->coap_response(this, msg);   // Deliver response to parent.
        } else {
            // Any other message: Query completed, return to idle state.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-ack");
            reset_soft();                       // Return to idle state.
            m_coap->coap_response(this, msg);   // Deliver response to parent.
        }
    } else if (match && is_response()) {
        if (msg.is_request()) {
            // Repeated request: Retransmit cached response if applicable.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rpt1");
            if (msg.type() == TYPE_CON) send_buffer();
        } else if (m_state == State::RESPONSE_SEP2) {
            // Separate response ACK: Exchange completed, return to idle.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-sep3");
            reset_soft();                       // Return to idle state.
        }
    } else if (msg.is_request()) {
        // Is this a fresh request? Check recent history.
        int recent = match_history(msg);
        if (recent >= 0) {
            // Stale requests are ignored, but may need to resend an ACK.
            // (i.e., We got the separated response but the ACK was lost.)
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-rpt2");
            u8 sep = m_flags[recent] & FLAG_SEP;
            if (msg.type() == TYPE_CON && sep) m_coap->reply(TYPE_ACK, msg);
        } else if (!is_await()) {
            // Service each new request, ignoring duplicates.
            if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: rcvd-req");
            // Enter "await" state, waiting for response or watchdog timeout.
            m_state = m_addr->reply_is_multicast()
                ? State::WAIT_RESPONSE_M : State::WAIT_RESPONSE_U;
            timer_once(MAX_LEISURE_MSEC);       // Timeout for user response
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

int Connection::match_history(const Reader& msg) const {
    // Is this a new ID, or does it appear in our recent history?
    // Return matching index, or -1 if none is found.
    for (u8 a = 0 ; a < m_meta_count ; ++a) {
        u8 sep = m_flags[a] & FLAG_SEP;
        u8 tkl = m_flags[a] & FLAG_TKL;
        bool match = (msg.tkl() == tkl)
                  && (msg.token() == m_token[a])
                  && (msg.msg_id() == m_msgid[a] || sep);
        if (match) return int(a);
    }
    return -1;
}

void Connection::push_history(const Reader& msg) {
    // Update the write index.
    if (m_meta_count < SATCAT5_COAP_HISTORY) {
        m_meta_idx = m_meta_count++;    // Index lags by one
    } else if (++m_meta_idx >= SATCAT5_COAP_HISTORY) {
        m_meta_idx = 0;                 // Increment with wraparound
    }

    // Note the new message identifiers.
    m_flags[m_meta_idx] = msg.tkl();
    m_msgid[m_meta_idx] = msg.msg_id();
    m_token[m_meta_idx] = msg.token();
}

void Connection::reset_hard() {
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CoAP: reset_hard");
    // Hard reset clears history.
    reset_soft();
    m_meta_idx = 0;
    m_meta_count = 0;
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
    if (!m_addr) return;

    if (m_state == State::CONNECT && m_addr->ready()) {
        // Connection is ready, return to idle state.
        reset_soft();
        m_coap->coap_connected(this);
    } else if (m_state == State::CONNECT && m_tx_count < MAX_RETRANSMIT) {
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
        // Ultimate timeout reached, revert to idle.
        // This is expected in certain states, otherwise notify user.
        bool ok = (m_state == State::RESPONSE_CACHE);
        reset_soft();
        if (!ok) m_coap->coap_error(this);
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
    // Call the parent's event-handler, and abort on overflow.
    // (This finalizes the transmit buffer, but doesn't send anything yet.)
    if (!ArrayWrite::write_finalize()) return false;

    // Parse the transmit buffer contents...
    satcat5::io::ArrayRead rdbuf(buffer(), written_len());
    Reader msg(&rdbuf);
    if (msg.error()) return false;  // Abort for invalid message?
    push_history(msg);              // Otherwise, note identifiers.
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "CoAP: write_finalize").write(msg_id());

    // For outgoing multicast messages, the only permissible type is a
    // nonconfirmable request (Section 8.1).  Block all other types.
    if (m_addr->is_multicast() && msg.type() != TYPE_NON) return false;

    // Set the new state, and set timer if applicable.
    m_tx_count = 0;
    if (msg.type() == TYPE_CON && m_state == State::RESPONSE_SEP1) {
        // Separated response, set retry timer.
        m_state = State::RESPONSE_SEP2;
        timer_rand(ACK_TIMEOUT_MSEC);
    } else if (msg.type() == TYPE_CON) {
        // Confirmable request, set retry timer.
        m_state = State::REQUEST_CON;
        timer_rand(ACK_TIMEOUT_MSEC);
    } else if (msg.type() == TYPE_NON) {
        // Nonconfirmable request, set rate-limit timer.
        // (i.e., No more outgoing requests until response or timeout.)
        m_state = State::REQUEST_NON;
        timer_rand(PROBE_TIMEOUT_MSEC);
    } else if (msg.type() == TYPE_ACK && m_state == State::WAIT_RESPONSE_M) {
        // Respond to multicast queries after a random delay (Section 8.2).
        m_state = State::RESPONSE_DEFER;
        timer_once(satcat5::util::prng.next(1, MAX_LEISURE_MSEC));
    } else if (msg.type() == TYPE_ACK && msg.code() == CODE_EMPTY) {
        // Separated response, set cache-expiration timeout.
        m_state = State::RESPONSE_SEP1;
        timer_once(MAX_TRANSMIT_SPAN);
    } else if (msg.type() == TYPE_ACK) {
        // Ack/Response, set cache-expiration timeout.
        m_state = State::RESPONSE_CACHE;
        timer_once(MAX_TRANSMIT_SPAN);
    } else if (msg.type() == TYPE_RST) {
        // Hard reset of state + history.
        reset_hard();
    }

    // Except for the deferred-response case, send immediately.
    return (m_state == State::RESPONSE_DEFER) || send_buffer();
}

ConnectionSpp::ConnectionSpp(
    satcat5::coap::Endpoint* endpoint,
    satcat5::ccsds_spp::Dispatch* iface)
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
    return connected();
}

bool ConnectionUdp::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport)
{
    // Sanity check: Don't break active connections.
    if (m_state != State::IDLE) return false;

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
    return connected();
}
