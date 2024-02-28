//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/net_socket.h>
#include <satcat5/utils.h>

using satcat5::net::Type;
using satcat5::net::SocketCore;

SocketCore::SocketCore(
        satcat5::net::Address* addr,
        u8* txbuff, unsigned txbytes, unsigned txpkt,
        u8* rxbuff, unsigned rxbytes, unsigned rxpkt)
    : satcat5::io::BufferedIO(
        txbuff, txbytes, txpkt,
        rxbuff, rxbytes, rxpkt)
    , satcat5::net::Protocol(satcat5::net::TYPE_NONE)
    , m_addr_ptr(addr)
{
    m_addr_ptr->iface()->add(this);
}

#if SATCAT5_ALLOW_DELETION
SocketCore::~SocketCore()
{
    m_addr_ptr->iface()->remove(this);
}
#endif

void SocketCore::close()
{
    m_addr_ptr->close();                    // Unbind Tx
    m_filter = satcat5::net::TYPE_NONE;     // Unbind Rx
}

bool SocketCore::ready_tx() const
{
    return m_addr_ptr->ready();
}

bool SocketCore::ready_rx() const
{
    return m_filter.bound();
}

void SocketCore::data_rcvd()
{
    // Data is ready in the transmit buffer.
    unsigned rem = m_tx.get_read_ready();
    satcat5::io::Writeable* wr = m_addr_ptr->open_write(rem);
    if (wr) {
        // Copy to the parent interface in blocks, then finalize.
        while (rem) {
            unsigned  plen = m_tx.get_peek_ready();
            const u8* peek = m_tx.peek(plen);
            wr->write_bytes(plen, peek);
            rem -= plen;
        }
        m_tx.read_finalize();
        wr->write_finalize();
    }
}

void SocketCore::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // Drop packet if there's not enough room in the Rx buffer.
    unsigned rem = src.get_read_ready();
    if (m_rx.get_write_space() < rem) return;

    // New data is ready, copy it to the receive buffer.
    // (Use ZCW method to reduce unnecessary overhead.)
    while (rem) {
        unsigned zlen = satcat5::util::min_unsigned(rem, m_rx.zcw_maxlen());
        u8* zptr = m_rx.zcw_start();
        src.read_bytes(zlen, zptr);
        m_rx.zcw_write(zlen);
        rem -= zlen;
    }
    m_rx.write_finalize();
}
