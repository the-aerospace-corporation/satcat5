//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_plugin.h>
#include <satcat5/eth_switch.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::eth::PluginCore;
using satcat5::eth::PluginPacket;
using satcat5::eth::PluginPort;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchPort;
using satcat5::io::MultiPacket;
using satcat5::io::Readable;
using satcat5::io::Writeable;

bool PluginPacket::read_from(MultiPacket* packet) {
    // Set basic parameters.
    pkt         = packet;
    dst_mask    = PMASK_ALL;
    flags       = 0;
    hlen        = 0;

    // Create a new Reader object, so we can peek at frame-headers.
    // TODO: ARP parser only accepts Ethernet/IPv4 ARP.
    //  Are we likely to encounter anything else in the wild?
    MultiPacket::Reader rd(packet);
    if (!hdr.read_from(&rd)) return false;
    if (is_arp() && !arp.read_from(&rd))    return false;
    if (is_ip() && !ip.read_from(&rd))      return false;
    if (is_tcp() && !tcp.read_from(&rd))    return false;
    if (is_udp() && !udp.read_from(&rd))    return false;

    // Calculate header length from number of bytes consumed.
    hlen = u16(packet->m_length - rd.get_read_ready());
    return true;
}

void PluginPacket::write_to(Writeable* wr) const {
    hdr.write_to(wr);
    if (is_arp())   arp.write_to(wr);
    if (is_ip())    ip.write_to(wr);
    if (is_tcp())   tcp.write_to(wr);
    if (is_udp())   udp.write_to(wr);
}

PluginCore::PluginCore(SwitchCore* sw)
    : m_switch(sw), m_next(0)
{
    if (m_switch) m_switch->plugin_add(this);
}

#if SATCAT5_ALLOW_DELETION
PluginCore::~PluginCore() {
    if (m_switch) m_switch->plugin_remove(this);
}
#endif

PluginPort::PluginPort(SwitchPort* port)
    : m_port(port), m_next(0)
{
    if (m_port) m_port->plugin_add(this);
}

#if SATCAT5_ALLOW_DELETION
PluginPort::~PluginPort() {
    if (m_port) m_port->plugin_remove(this);
}
#endif

