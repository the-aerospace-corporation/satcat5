//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>
#include <satcat5/ptp_interface.h>
#include <satcat5/udp_core.h>
#include <satcat5/utils.h>

using satcat5::ptp::Interface;
using satcat5::ptp::PacketType;
using satcat5::util::extract_be_u16;

// Note: This function is timing-critical, because it is often called
//  from inside interrupt service routines. Minimize excess delays.
bool Interface::ptp_dispatch(const u8* peek, unsigned length)
{
    // Sanity check: If no PTP callback, skip detailed inspection.
    m_ptp_rx_type = PacketType::NON_PTP;
    if (!m_ptp_callback) return false;

    // Avoid out-of-bounds read
    if (length < 14) return false;

    // Peek at the contents and determine if it is a PTP message.
    satcat5::eth::MacType ether_type =
        {extract_be_u16(peek + 12)};

    if (ether_type == satcat5::eth::ETYPE_PTP) {
        // PTP - L2 if etherType is 0x88F7
        m_ptp_rx_type = PacketType::PTP_L2;
    } else if (ether_type == satcat5::eth::ETYPE_IPV4) {
        // Might be PTP - L3 if ether_type is 0x0800
        // Get IPv4 protocol type, check if it's UDP.

        // Avoid out-of-bounds read
        if (length < 24) return false;

        u8 protocol = peek[23];
        if (protocol == satcat5::ip::PROTO_UDP) {
            // Get the IPv4 header length (in 32-bit words)
            unsigned header_length = peek[14] & 0x000f;

            // Read the UDP source and destination ports
            // (their position depends on the header length)
            unsigned src_port_index = 14 + header_length * 4;
            unsigned dst_port_index = 16 + header_length * 4;

            // Avoid out-of-bounds read
            if (length < dst_port_index + 2) return false;

            satcat5::ip::Port src_port = extract_be_u16(peek + src_port_index);
            satcat5::ip::Port dst_port = extract_be_u16(peek + dst_port_index);

            // If source or destination port is 319 or 320, message is PTP - L3
            if (src_port == satcat5::udp::PORT_PTP_EVENT ||
                src_port == satcat5::udp::PORT_PTP_GENERAL ||
                dst_port == satcat5::udp::PORT_PTP_EVENT ||
                dst_port == satcat5::udp::PORT_PTP_GENERAL) {
                m_ptp_rx_type = PacketType::PTP_L3;
            }
        }
    }

    // Indicate whether caller should call ptp_notify().
    return m_ptp_rx_type != PacketType::NON_PTP;
}
