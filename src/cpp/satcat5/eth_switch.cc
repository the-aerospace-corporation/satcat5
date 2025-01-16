//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_switch.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::eth::Header;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchPlugin;
using satcat5::eth::SwitchPort;
using satcat5::io::MultiPacket;
using satcat5::log::CRITICAL;
using satcat5::log::DEBUG;
using satcat5::log::Log;

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Enable runtime prevention of uninitialized memory?
#ifndef SATCAT5_PARANOIA
#define SATCAT5_PARANOIA 0
#endif

SwitchCore::SwitchCore(u8* buff, unsigned nbytes)
    : MultiBuffer(buff, nbytes)
    , m_free_pmask(PMASK_ALL)
    , m_prom_mask(0)
    , m_stats_filter(0)
    , m_stats_count(0)
{
    // Nothing else to initialize.
}

SATCAT5_PMASK_TYPE SwitchCore::next_port_mask()
{
    // The "free_pmask" sets a bit for each free index.
    // Starting from the LSB, find and clear the first '1' bit.
    // If there's no more space, then this function returns zero.
    SATCAT5_PMASK_TYPE lsb = (m_free_pmask & -m_free_pmask);
    satcat5::util::clr_mask(m_free_pmask, lsb);
    return lsb;
}

void SwitchCore::port_add(satcat5::eth::SwitchPort* port)
{
    // Clear the "free" bit for each associated port.
    satcat5::util::clr_mask(m_free_pmask, port->port_mask());
    // Add the object to the list of registered ports.
    m_ports.push_back(port);
}

void SwitchCore::port_remove(satcat5::eth::SwitchPort* port)
{
    // Restore the "free" bit for each associated port.
    port_remove(port->port_mask());
    // Remove the object from the list of registered ports.
    m_ports.remove(port);
}

void SwitchCore::port_remove(const SATCAT5_PMASK_TYPE& mask)
{
    // Restore the "free" bit for each associated port.
    satcat5::util::set_mask(m_free_pmask, mask);
}

void SwitchCore::set_promiscuous(unsigned port_idx, bool enable)
{
    SATCAT5_PMASK_TYPE mask = idx2mask(port_idx);
    satcat5::util::set_mask_if(m_prom_mask, mask, enable);
}

void SwitchCore::set_traffic_filter(u16 etype)
{
    m_stats_filter = etype;
    m_stats_count = 0;
}

u32 SwitchCore::get_traffic_count()
{
    u32 temp = m_stats_count;
    m_stats_count = 0;
    return temp;
}

unsigned SwitchCore::deliver(satcat5::io::MultiPacket* packet)
{
    // Attempt to read the Ethernet and IPv4 headers.
    SwitchPlugin::PacketMeta meta{};
    if (!meta.read_from(packet)) return 0;

    // Update statistics, query any plugins.
    // TODO: Handling for pause frames and spanning-tree protocol?
    process_stats(meta);
    if (process_plugins(meta)) return 1;

    // Promiscuous ports get a copy of every packet, but
    // switches never allow loopback to the original source(s).
    satcat5::util::set_mask(meta.dst_mask, m_prom_mask);
    satcat5::util::clr_mask(meta.dst_mask, meta.src_mask());

    // Attempt to deliver the packet to each matching port object.
    return deliver_switch(meta);
}

void SwitchCore::process_stats(const SwitchPlugin::PacketMeta& meta)
{
    // The main packet counter may be filtered by EtherType.
    if ((!m_stats_filter) || (m_stats_filter == meta.hdr.type.value)) {
        ++m_stats_count;
    }
    // TODO: Additional statistics and diagnostics?
}

bool SwitchCore::process_plugins(SwitchPlugin::PacketMeta& meta)
{
    // Query each plugin to set or limit destination port(s).
    // Stop early if any plugin signals that it has diverted the packet.
    SwitchPlugin* plg = m_plugins.head();
    while (plg) {
        if (!plg->query(meta)) return true;
        plg = m_plugins.next(plg);
    }

    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 1) {
        auto peek = meta.pkt->peek();
        Log(DEBUG, "SwitchCore::deliver")
            .write("\n\tMask").write(meta.dst_mask)
            .write("\n\tData").write(&peek);
    }
    return false;
}

unsigned SwitchCore::deliver_switch(const SwitchPlugin::PacketMeta& meta)
{
    // Abort now if there are no valid destination ports.
    // Otherwise, attempt to deliver the packet to each destination port.
    if (!meta.dst_mask) return 0;
    unsigned count = 0;
    SwitchPort* port = m_ports.head();
    while (port) {
        if (port->accept(meta.dst_mask, meta.pkt)) ++count;
        port = m_ports.next(port);
    }

    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 0)
        Log(DEBUG, "SwitchCore: Rcvd").write(meta.dst_mask).write10((u32)count);
    return count;
}

bool SwitchPlugin::PacketMeta::read_from(MultiPacket* packet)
{
    // Set basic parameters.
    pkt         = packet;
    dst_mask    = PMASK_ALL;

    // Attempt to read the frame headers using the peek function.
    // Peek size is limited to ~56 bytes, but that's enough for Eth + IPv4.
    auto rd = packet->peek();
    if (!hdr.read_from(&rd)) return false;
    if (hdr.type == ETYPE_IPV4) {
        if (!ip.read_core(&rd)) return false;
    } else if (SATCAT5_PARANOIA) {
        memset(&ip, 0, sizeof(ip));
    }

    return true;
}

SwitchPlugin::SwitchPlugin(SwitchCore* sw)
    : m_switch(sw), m_next(0)
{
    if (m_switch) m_switch->plugin_add(this);
}

#if SATCAT5_ALLOW_DELETION
SwitchPlugin::~SwitchPlugin()
{
    if (m_switch) m_switch->plugin_remove(this);
}
#endif

SwitchPort::SwitchPort(satcat5::eth::SwitchCore* sw)
    : MultiWriter(sw)
    , m_switch(sw)
    , m_port_mask(sw->next_port_mask())
    , m_port_index(satcat5::util::log2_floor(m_port_mask))
    , m_vlan_cfg(satcat5::eth::VCFG_DEFAULT)
    , m_egress(sw)
    , m_next(0)
{
    // Sanity check: Is the SwitchCore out of unique port masks?
    if (m_port_mask) m_switch->port_add(this);
    else Log(CRITICAL, "SwitchPort overflow");
}

#if SATCAT5_ALLOW_DELETION
SwitchPort::~SwitchPort()
{
    m_switch->port_remove(this);
}
#endif

bool SwitchPort::accept(SATCAT5_PMASK_TYPE dst_mask, MultiPacket* packet)
{
    return (m_port_mask & dst_mask) && m_egress.accept(packet);
}

bool SwitchPort::write_finalize()
{
    // Use the "m_user" field to store some packet metadata.
    // Note: Using "m_port_index" only works for single-port objects.
    //  Children with multiple ports must override this method.
    if (m_write_pkt) {
        static_assert(SATCAT5_MBUFF_USER >= 2,
            "SATCAT5_MBUFF_USER must be at least 2.");
        m_write_pkt->m_user[0] = u32(m_port_index);
        m_write_pkt->m_user[1] = u32(m_vlan_cfg.value);
    }
    return MultiWriter::write_finalize();
}
