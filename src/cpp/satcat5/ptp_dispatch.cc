//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dispatch.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_dispatch.h>
#include <satcat5/ptp_interface.h>

using satcat5::eth::MacAddr;
using satcat5::eth::MacType;
using satcat5::ptp::Dispatch;
using satcat5::ptp::DispatchTo;
using satcat5::ptp::PortId;
using satcat5::ptp::Interface;

Dispatch::Dispatch(
        satcat5::ptp::Interface* iface,
        satcat5::ip::Dispatch* ip)
    : m_iface(iface)
    , m_ip(ip)
    , m_callback(0)
    , m_reply_mac(satcat5::eth::MACADDR_NONE)
    , m_stored_mac(satcat5::eth::MACADDR_NONE)
    , m_reply_ip(satcat5::ip::ADDR_NONE)
    , m_stored_ip(satcat5::ip::ADDR_NONE)
{
    m_iface->ptp_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch()
{
    m_iface->ptp_callback(0);
}
#endif

satcat5::io::Writeable* Dispatch::ptp_send(DispatchTo addr, unsigned num_bytes, u8 ptp_msg_type)
{
    // Calculate worst-case packet including Eth + IP headers.
    unsigned max_bytes = num_bytes + 34;

    // Get the Writable object use to write the message
    satcat5::io::Writeable* iface = m_iface->ptp_tx_write();
    if (!iface || iface->get_write_space() < max_bytes) return 0;

    // Create and write the ethernet header
    satcat5::eth::Header eth_header;
    eth_header.dst = get_dst_mac(addr);
    eth_header.src = m_ip->macaddr();
    eth_header.type = get_eth_type(addr);
    eth_header.write_to(iface);

    // Write IPv4 and UDP headers if this is a L3 PTP message
    if (eth_header.type == satcat5::eth::ETYPE_IPV4) {
        satcat5::ip::Addr dst_ip = get_dst_ip(addr);

        // Write IPv4 Header
        unsigned udp_bytes = num_bytes + 8;
        satcat5::ip::Header ip_header =
            m_ip->next_header(satcat5::ip::PROTO_UDP, dst_ip, udp_bytes);
        ip_header.write_to(iface);

        // Write UDP Header
        // Src and dst ports should match when sending messages.
        // UDP length field includes both header + contents.
        satcat5::udp::Port dst_port = get_dst_port(ptp_msg_type);
        satcat5::udp::Header udp_header = {dst_port, dst_port, (u16)udp_bytes};
        udp_header.write_to(iface);
    }

    // Return the Writeable so the caller can write the PTP body
    return iface;
}

void Dispatch::store_reply_addr()
{
    m_stored_mac = m_reply_mac;
    m_stored_ip  = m_reply_ip;
}

void Dispatch::store_addr(const MacAddr& mac, const satcat5::ip::Addr& ip)
{
    m_stored_mac = mac;
    m_stored_ip  = ip;
}

void Dispatch::poll_demand()
{
    satcat5::io::Readable* readable = m_iface->ptp_rx_read();

    // Read the Ethernet frame header and note L2 reply address.
    satcat5::eth::Header eth_header;
    eth_header.read_from(readable);
    m_reply_mac = eth_header.src;

    // If mac_type is IPv4, then store the L3 reply address.
    if (eth_header.type == satcat5::eth::ETYPE_IPV4) {
        // Read IPv4 header and note reply address.
        satcat5::ip::Header ip_header = { 0 };
        ip_header.read_from(readable);
        m_reply_ip = ip_header.src();
        // Read and discard the UDP header. We've already confirmed
        // the port numbers in ptp::Interface::ptp_dispatch().
        satcat5::udp::Header udp_header = satcat5::udp::HEADER_EMPTY;
        udp_header.read_from(readable);
    } else {
        m_reply_ip = satcat5::ip::ADDR_NONE;
    }

    // Notify callback with remaining contents, which are the PTP message.
    if (m_callback) {
        satcat5::io::LimitedRead limited_read(readable);
        m_callback->ptp_rcvd(limited_read);
    }

    readable->read_finalize();
}

satcat5::eth::MacAddr Dispatch::get_dst_mac(DispatchTo addr) const
{
    switch (addr) {
        case DispatchTo::REPLY:         return m_reply_mac;
        case DispatchTo::STORED:        return m_stored_mac;
        default:                        return satcat5::eth::MACADDR_BROADCAST;
    }
}

// A valid IPv4 address indicates an L3 packet; otherwise choose L2.
static constexpr MacType infer_etype(const satcat5::ip::Addr& addr) {
    return (addr == satcat5::ip::ADDR_NONE)
        ? satcat5::eth::ETYPE_PTP : satcat5::eth::ETYPE_IPV4;
}

satcat5::eth::MacType Dispatch::get_eth_type(DispatchTo addr) const
{
    switch (addr) {
        case DispatchTo::BROADCAST_L2:  return satcat5::eth::ETYPE_PTP;
        case DispatchTo::BROADCAST_L3:  return satcat5::eth::ETYPE_IPV4;
        case DispatchTo::REPLY:         return infer_etype(m_reply_ip);
        case DispatchTo::STORED:        // Fallthrough
        default:                        return infer_etype(m_stored_ip);
    }
}

satcat5::udp::Port Dispatch::get_dst_port(u8 ptp_msg_type) const
{
    if (ptp_msg_type == satcat5::ptp::Header::TYPE_SYNC ||
        ptp_msg_type == satcat5::ptp::Header::TYPE_DELAY_REQ ||
        ptp_msg_type == satcat5::ptp::Header::TYPE_PDELAY_REQ ||
        ptp_msg_type == satcat5::ptp::Header::TYPE_PDELAY_RESP) {
        return satcat5::udp::PORT_PTP_EVENT;
    } else {
        return satcat5::udp::PORT_PTP_GENERAL;
    }
}

satcat5::ip::Addr Dispatch::get_dst_ip(DispatchTo addr) const
{
    switch (addr) {
        case DispatchTo::REPLY:         return m_reply_ip;
        case DispatchTo::STORED:        return m_stored_ip;
        default:                        return satcat5::ip::ADDR_BROADCAST;
    }
}
