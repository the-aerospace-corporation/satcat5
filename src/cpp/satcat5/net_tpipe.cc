//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/net_tpipe.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

namespace eth = satcat5::eth;
namespace net = satcat5::net;
namespace udp = satcat5::udp;
using satcat5::util::clr_mask_u16;
using satcat5::util::min_unsigned;
using satcat5::util::set_mask_u16;

net::Tpipe::Tpipe(net::Address* dst)
    : BufferedIO(m_txbuff, MAX_WINDOW, 0, m_rxbuff, MAX_WINDOW, 0)
    , Protocol(net::TYPE_NONE)
    , m_iface(dst)
    , m_retry(0)
    , m_state(0)
    , m_retransmit(500)     // Default = 0.5 seconds
    , m_timeout(30000)      // Default = 30 seconds
    , m_txpos(0)
    , m_txref(0)
    , m_rxpos(0)
    , m_rxref(0)
    , m_txbuff{}
    , m_rxbuff{}
{
    // Register for incoming packet callbacks.
    m_iface->iface()->add(this);
}

#if SATCAT5_ALLOW_DELETION
net::Tpipe::~Tpipe() {
    m_iface->iface()->remove(this);
}
#endif

void net::Tpipe::close() {
    // If a connection is open, let counterpart know it's closing.
    set_mask_u16(m_state, STATE_CLOSING);
    if (m_state & STATE_READY) send_block();
    // Close the local connection and halt timer events.
    m_iface->close();
    timer_stop();
}

bool net::Tpipe::completed() const {
    // Have we acknowledged every byte in the transmit FIFO?
    return (m_state & STATE_READY) && !m_tx.get_read_ready();
}

void net::Tpipe::set_txonly() {
    m_timeout = 0;
    m_state |= STATE_READY;
    m_state |= STATE_TXONLY;
}

void net::Tpipe::data_rcvd(io::Readable* src) {
    // If we were previously idle, send the new data.
    // (Otherwise ignore until reply or timeout.)
    if (!(m_state & STATE_TXBUSY)) send_block();
}

void net::Tpipe::frame_rcvd(io::LimitedRead& src) {
    // Read the packet header.
    u16 flags = src.read_u16();
    u16 txpos = src.read_u16();
    u16 rxpos = src.read_u16();

    // Sanity check on the reported data length.
    unsigned rxlen = unsigned(flags & FLAG_LEN);
    if (src.get_read_ready() < rxlen) return;
    if (rxlen > MAX_WINDOW) return;

    // Opening a new connection?
    bool send_reply = false;
    if (flags & FLAG_START) {
        // Remote endpoint requesting a new connection.
        m_iface->save_reply_address();
        m_state = STATE_READY;
        send_reply = true;
        // If we're in the middle of a session, check if this is
        // a delayed duplicate of the original start-of-session
        // request before we reset the session state.
        bool dupe_request = (m_state & STATE_READY)
            && (m_txref == rxpos) && (m_rxref == txpos);
        if (!dupe_request) {
            m_rx.clear();
            m_txpos = rxpos;
            m_txref = rxpos;
            m_rxpos = txpos;
            m_rxref = txpos;
        }
    } else if (m_state & STATE_OPENREQ) {
        // Reply to our start-of-connection request.
        m_rx.clear();
        clr_mask_u16(m_state, STATE_OPENREQ);
        set_mask_u16(m_state, STATE_READY);
    } else {
        // Normal packet, accept if there's an open connection.
        if (!(m_state & STATE_READY)) return;
    }

    // Any packet from the remote host resets the watchdog.
    m_retry = 0;

    // Has the remote side acknowledged additional data?
    u16 rxdiff = rxpos - m_txpos;
    if (s16(rxdiff) > 0) {
        // Update the transmit state.
        m_tx.read_consume(rxdiff);
        m_txpos += rxdiff;
        clr_mask_u16(m_state, STATE_TXBUSY);
        // Reply with next block of data.
        send_reply = true;
    }

    // Is there any new data in this packet?
    unsigned skip = unsigned(m_rxpos - txpos);
    if (rxlen > skip) {
        // Skip ahead to the portion of interest.
        // (We may have already received some data.)
        unsigned rdlen = min_unsigned(rxlen - skip, m_rx.get_write_space());
        src.read_consume(skip);
        // Copy new data to the output FIFO.
        u8 tmp[MAX_WINDOW];
        src.read_bytes(rdlen, tmp);
        m_rx.write_bytes(rdlen, tmp);
        if (m_rx.write_finalize()) {
            // Update receive state and send acknowledgement.
            m_rxpos += rdlen;
            send_reply = true;
        }
    }

    // If there's been any progress, send an immediate reply.
    // Stale or duplicate messages must not send an acknolwedgement, to avoid
    // "sorcerer's apprentice syndrome" as seen in early versions of TFTP.
    if (flags & FLAG_STOP) {
        // Remote endpoint is closing the connection.
        m_tx.clear();
        m_iface->close();
        m_state = 0;
        timer_stop();
    } else if (send_reply) {
        // Send acknowledgement and/or additional data.
        send_block();
    }
}

void net::Tpipe::timer_event() {
    // Timeout waiting for acknowledgement?
    if ((m_retry < m_timeout) || (m_state & STATE_TXONLY)) {
        send_block();   // Retry / keep-alive.
    } else {
        close();        // Close connection.
    }
}

void net::Tpipe::send_block() {
    // How much data can we send in this block?
    unsigned txlen = min_unsigned(MAX_WINDOW, m_tx.get_peek_ready());

    // Is the network device ready to send?
    // (Packet is next data block plus 6-byte header.)
    auto wr = m_iface->open_write(txlen + 6);
    if (wr) {
        // Randomize next-packet timeout from 1.0 to 1.5x nominal,
        // to reduce the number of crossing-in-transit messages.
        unsigned timeout = m_retransmit + util::prng.next(0, m_retransmit/2);
        // Update protocol state.
        set_mask_u16(m_state, STATE_TXBUSY);
        m_retry += timeout;
        timer_once(timeout);
        // Set header flags based on current state.
        u16 flags = u16(txlen);
        if (m_state & STATE_OPENREQ) flags |= FLAG_START;
        if (m_state & STATE_CLOSING) flags |= FLAG_STOP;
        // Write packet header and contents.
        // Note: Do not consume data until transfer is acknowledged.
        wr->write_u16(flags);
        wr->write_u16(m_txpos);
        wr->write_u16(m_rxpos);
        if (txlen) wr->write_bytes(txlen, m_tx.peek(txlen));
        bool sent = wr->write_finalize();
        // If we're in Tx-only mode, consume data immediately.
        // Otherwise, it's consumed by acknowledgement logic in `frame_rcvd`.
        if (sent && (m_state & STATE_TXONLY)) {
            m_tx.read_consume(txlen);
            m_txpos += txlen;
        }
    } else {
        // Rapid polling until device is ready to send.
        // (This may be due to flow-control or due to ARP resolution.)
        constexpr u16 POLL_MSEC = 10;
        m_retry += POLL_MSEC;
        timer_once(POLL_MSEC);
    }
}

void net::Tpipe::send_start() {
    // Randomizing initial parameters helps prevent pathological cases
    // where we accidentally "resume" a previously-terminated session.
    m_state = STATE_OPENREQ;
    m_txpos = u16(util::prng.next());
    m_rxpos = u16(util::prng.next());
    // Attempt to send the first packet.
    // (If unable, this also starts polling for follow-up.)
    send_block();
}

eth::Tpipe::Tpipe(eth::Dispatch* iface)
    : eth::AddressContainer(iface)
    , net::Tpipe(&m_addr)
{
    // Nothing else to initialize.
}

void eth::Tpipe::bind(const eth::MacType& etype, const eth::VlanTag& vtag) {
    close();    // Close previous connection, if any.
    m_filter = net::Type(vtag.vid(), etype.value);
}

void eth::Tpipe::connect(
    const eth::MacAddr& addr,
    const eth::MacType& etype,
    const eth::VlanTag& vtag)
{
    close();        // Close previous connection, if any.
    m_addr.connect(addr, etype, vtag);
    m_filter = net::Type(vtag.vid(), etype.value);
    send_start();   // Send request to open new connection.
}

udp::Tpipe::Tpipe(udp::Dispatch* iface)
    : udp::AddressContainer(iface)
    , net::Tpipe(&m_addr)
{
    // Nothing else to initialize.
}

void udp::Tpipe::bind(const udp::Port& port) {
    close();        // Close previous connection, if any.
    m_filter = net::Type(port.value);
}

void udp::Tpipe::connect(
    const ip::Addr& dstaddr,
    const udp::Port& dstport,
    const eth::VlanTag& vtag)
{
    close();        // Close previous connection, if any.
    udp::Port srcport = m_addr.udp()->next_free_port();
    m_addr.connect(dstaddr, dstport, srcport, vtag);
    m_filter = net::Type(dstport.value, srcport.value);
    send_start();   // Send request to open new connection.
}
