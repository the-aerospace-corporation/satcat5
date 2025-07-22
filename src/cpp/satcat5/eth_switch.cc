//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_plugin.h>
#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_log.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::eth::Header;
using satcat5::eth::PluginPacket;
using satcat5::eth::PluginCore;
using satcat5::eth::PluginPort;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchLogMessage;
using satcat5::eth::SwitchPort;
using satcat5::io::MultiPacket;
using satcat5::io::Writeable;
using satcat5::log::CRITICAL;
using satcat5::log::DEBUG;
using satcat5::log::Log;

typedef satcat5::util::optional<unsigned> opt_uint;

// Identify the various watch-points where the debug port can be attached.
// Any enabled point(s) will carbon-copy the packet contents to m_debug.
// Setting multiple points will result in near-duplicate packets, but may
// be useful in diagnosing problems with SwitchCore, SwitchPort, switch
// plugins, the router2::Dispatch block, or user-defined child classes.
// Note: DEBUG_EGRESS is logged separately for each egress port.
static constexpr unsigned
    DEBUG_INGRESS   = (1u << 0),    // Immediately on ingress
    DEBUG_PLUGIN    = (1u << 1),    // Before plugin processing
    DEBUG_PLUGOUT   = (1u << 2),    // After plugin processing
    DEBUG_DELIVERY  = (1u << 3),    // During delivery
    DEBUG_EGRESS    = (1u << 4);    // During egress (each port)

// Set the default watch-point(s) for the debug port.
// e.g., (DEBUG_INGRESS | DEBUG_PLUGOUT | DEBUG_EGRESS)
#ifndef SATCAT5_SWITCH_DEBUG
#define SATCAT5_SWITCH_DEBUG (DEBUG_PLUGOUT)
#endif

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

SwitchCore::SwitchCore(u8* buff, unsigned nbytes)
    : MultiBuffer(buff, nbytes)
    , m_debug(nullptr)
    , m_pktlogs()
    , m_free_pmask(PMASK_ALL)
    , m_prom_mask(0)
    , m_stats_filter(0)
    , m_stats_count(0)
{
    // Nothing else to initialize.
}

void SwitchCore::plugin_add(PluginCore* plugin)
    { m_plugins.add(plugin); }
void SwitchCore::plugin_remove(PluginCore* plugin)
    { m_plugins.remove(plugin); }

SATCAT5_PMASK_TYPE SwitchCore::next_port_mask() {
    // The "free_pmask" sets a bit for each free index.
    // Starting from the LSB, find and clear the first '1' bit.
    // If there's no more space, then this function returns zero.
    SATCAT5_PMASK_TYPE lsb = (m_free_pmask & -m_free_pmask);
    satcat5::util::clr_mask(m_free_pmask, lsb);
    return lsb;
}

void SwitchCore::port_add(satcat5::eth::SwitchPort* port) {
    // Clear the "free" bit for each associated port.
    satcat5::util::clr_mask(m_free_pmask, port->port_mask());
    // Add the object to the list of registered ports.
    m_ports.push_back(port);
}

void SwitchCore::port_remove(satcat5::eth::SwitchPort* port) {
    // Restore the "free" bit for each associated port.
    port_remove(port->port_mask());
    // Remove the object from the list of registered ports.
    m_ports.remove(port);
}

void SwitchCore::port_remove(const SATCAT5_PMASK_TYPE& mask) {
    // Restore the "free" bit for each associated port.
    satcat5::util::set_mask(m_free_pmask, mask);
}

void SwitchCore::set_promiscuous(unsigned port_idx, bool enable) {
    SATCAT5_PMASK_TYPE mask = idx2mask(port_idx);
    satcat5::util::set_mask_if(m_prom_mask, mask, enable);
}

void SwitchCore::set_traffic_filter(u16 etype) {
    m_stats_filter = etype;
    m_stats_count = 0;
}

u32 SwitchCore::get_traffic_count() {
    u32 temp = m_stats_count;
    m_stats_count = 0;
    return temp;
}

unsigned SwitchCore::deliver(satcat5::io::MultiPacket* packet) {
    // Attempt to read the Ethernet and IPv4 headers.
    PluginPacket meta{};
    if (!meta.read_from(packet)) {
        debug_log(packet, SwitchLogMessage::DROP_BADFRM);
        return 0;
    }

    // Update statistics before additional rule checks.
    process_stats(meta);

    // Query applicable plugins (PluginPort and/or PluginCore).
    // TODO: Handling for pause frames and spanning-tree protocol?
    auto plg_result = process_plugins(meta);
    if (plg_result) return plg_result.value();

    // Promiscuous ports get a copy of every packet, but
    // switches never allow loopback to the original source(s).
    satcat5::util::set_mask(meta.dst_mask, m_prom_mask);
    satcat5::util::clr_mask(meta.dst_mask, meta.src_mask());

    // Attempt to deliver the packet to each matching port object.
    return deliver_switch(meta);
}

void SwitchCore::debug_if(const PluginPacket& pkt, unsigned mask) const {
    unsigned enable = (SATCAT5_SWITCH_DEBUG) & mask;
    if (m_debug && enable) {
        MultiPacket::Reader rd(pkt.pkt);    // Read from start of packet.
        if (pkt.is_adjusted()) {
            rd.read_consume(pkt.hlen);      // Skip original header.
            pkt.write_to(m_debug);          // Write modified header.
        }
        rd.copy_and_finalize(m_debug);      // Copy remaining data.
    }
}

void SwitchCore::debug_log(const MultiPacket* pkt, u8 reason, SATCAT5_PMASK_TYPE dst) const {
    Header hdr = satcat5::eth::HEADER_NULL;
    u8 src_port = 255;
    if (m_pktlogs.head()) {
        // If possible, read frame header and metadata.
        // See also: SwitchPort::write_finalize().
        if (pkt) {
            auto rd = pkt->peek();
            hdr.read_from(&rd);
            src_port = u8(pkt->m_user[0]);
        }

        // Construct a KEEP or DROP message.
        satcat5::eth::SwitchLogMessage msg;
        if (reason == SwitchLogMessage::REASON_KEEP) {
            msg.init_keep(hdr, src_port, dst);
        } else {
            msg.init_drop(hdr, src_port, reason);
        }

        // Deliver the message to each logging object.
        satcat5::eth::SwitchLogHandler* item = m_pktlogs.head();
        while (item) {
            item->log_packet(msg);
            item = m_pktlogs.next(item);
        }
    }
}

void SwitchCore::process_stats(const PluginPacket& meta) {
    // Optional carbon-copy to debug port.
    debug_if(meta, DEBUG_INGRESS);

    // The main packet counter may be filtered by EtherType.
    if ((!m_stats_filter) || (m_stats_filter == meta.hdr.type.value)) {
        ++m_stats_count;
    }
    // TODO: Additional statistics and diagnostics?
}

opt_uint SwitchCore::process_plugins(PluginPacket& meta) {
    // Optional carbon-copy to debug port.
    debug_if(meta, DEBUG_PLUGIN);

    // Identify the source port and query each port plugin.
    // Stop early if any plugin drops or diverts the packet.
    SwitchPort* src = get_port(meta.src_port());
    if (src) src->plugin_ingress(meta);
    auto result = pkt_has_dropped(meta);
    if (result) return result;

    // Query each switch plugin. This may affect packet data and metadata.
    // Stop early if any plugin drops or diverts the packet.
    PluginCore* plg = m_plugins.head();
    while (plg) {
        plg->query(meta);
        result = pkt_has_dropped(meta);
        if (result) return result;
        plg = m_plugins.next(plg);
    }

    // In-place buffer overwrite of the modified packet headers?
    // This method can't tolerate length changes; sound alarm if needed.
    if (meta.is_adjusted()) {
        MultiPacket::Overwriter wr(meta.pkt);
        meta.write_to(&wr);
        if (wr.write_count() != meta.hlen) {
            Log(CRITICAL, "Plugin changed header length.");
            debug_log(meta.pkt, SwitchLogMessage::DROP_UNKNOWN);
            return opt_uint(0); // Discard this packet
        }
    }

    // Optional carbon-copy to debug port.
    debug_if(meta, DEBUG_PLUGOUT);

    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 1) {
        auto peek = meta.pkt->peek();
        Log(DEBUG, "SwitchCore::deliver")
            .write("\r\n  Mask").write(meta.dst_mask)
            .write("\r\n  Data").write(&peek);
    }
    return opt_uint();
}

opt_uint SwitchCore::pkt_has_dropped(PluginPacket& meta) {
    if (meta.dst_mask == 0) {
        u8 reason = meta.reason()
            ? meta.reason() : SwitchLogMessage::DROP_UNKNOWN;
        debug_log(meta.pkt, reason);
        return opt_uint(0);     // Dropped
    } else if (meta.is_diverted()) {
        debug_log(meta.pkt, SwitchLogMessage::REASON_KEEP);
        return opt_uint(1);     // Diverted
    } else {
        return opt_uint();      // Success
    }
}

unsigned SwitchCore::deliver_switch(const PluginPacket& meta) {
    // Attempt to deliver the packet to each destination port.
    unsigned count = 0;
    SwitchPort* port = m_ports.head();
    while (port) {
        if (port->accept(meta.dst_mask, meta.pkt)) ++count;
        port = m_ports.next(port);
    }

    // Optional carbon-copy to debug port.
    debug_if(meta, DEBUG_DELIVERY);
    debug_log(meta.pkt, SwitchLogMessage::REASON_KEEP, meta.dst_mask);

    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 0)
        Log(DEBUG, "SwitchCore: Rcvd").write(meta.dst_mask).write10((u32)count);
    return count;
}

SwitchPort::SwitchPort(SwitchCore* sw, Writeable* dst)
    : MultiWriter(sw)
    , m_switch(sw)
    , m_port_mask(sw->next_port_mask())
    , m_port_index(satcat5::util::log2_floor(m_port_mask))
    , m_vlan_cfg(satcat5::eth::VCFG_DEFAULT)
    , m_egress(sw)
    , m_eg_dst(dst)
    , m_eg_hdr(false)
    , m_next(0)
{
    // Sanity check: Is the SwitchCore out of unique port masks?
    if (m_port_mask) m_switch->port_add(this);
    else Log(CRITICAL, "SwitchPort overflow");
    // Are we the callback for processing egress data?
    if (m_eg_dst) m_egress.set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
SwitchPort::~SwitchPort() {
    m_switch->port_remove(this);
}
#endif

bool SwitchPort::accept(SATCAT5_PMASK_TYPE dst_mask, MultiPacket* packet) {
    return (m_port_mask & dst_mask) && m_egress.accept(packet);
}

void SwitchPort::plugin_add(PluginPort* plugin)
    { m_plugins.add(plugin); }
void SwitchPort::plugin_remove(PluginPort* plugin)
    { m_plugins.remove(plugin); }

void SwitchPort::plugin_ingress(satcat5::eth::PluginPacket& meta) {
    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "SwitchPort::plugin_ingress");

    // Query each port plugin. This may affect packet data and metadata.
    // Stop early if any plugin signals that it has diverted the packet.
    PluginPort* plg = m_plugins.head();
    while (plg) {
        plg->ingress(meta);
        if (meta.dst_mask == 0) return;
        if (meta.is_diverted()) return;
        plg = m_plugins.next(plg);
    }
}

void SwitchPort::plugin_egress(satcat5::eth::PluginPacket& meta) {
    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "SwitchPort::plugin_egress");

    // Query each port plugin. This may affect packet data and metadata.
    // Stop early if any plugin signals that it has diverted the packet.
    PluginPort* plg = m_plugins.head();
    while (plg) {
        plg->egress(meta);
        if (m_switch->pkt_has_dropped(meta)) return;
        plg = m_plugins.next(plg);
    }
}

void SwitchPort::write_abort() {
    // Log the CRC/PHY error, then flush buffer contents.
    if (m_write_pkt) m_switch->debug_log(m_write_pkt, SwitchLogMessage::DROP_BADFCS);
    MultiWriter::write_abort();
}

bool SwitchPort::write_finalize() {
    // Use the "m_user" field to store some packet metadata.
    // Note: Using "m_port_index" only works for single-port objects.
    //  Children with multiple ports MUST override write_finalize().
    if (m_write_pkt) {
        static_assert(SATCAT5_MBUFF_USER >= 2,
            "SATCAT5_MBUFF_USER must be at least 2.");
        m_write_pkt->m_user[0] = u32(m_port_index);
        m_write_pkt->m_user[1] = u32(m_vlan_cfg.value);
    }

    // Attempt delivery of the packet.
    if (!m_egress.get_port_enable()) {
        // Dropped (port disabled)
        m_switch->debug_log(m_write_pkt, SwitchLogMessage::DROP_DISABLED);
    } else if (MultiWriter::write_finalize()) {
        // Delivered to switch
        return true;
    } else {
        // Dropped (overflow)
        m_switch->debug_log(nullptr, SwitchLogMessage::DROP_OVERFLOW);
    }

    // Cleanup after any delivery failure.
    MultiWriter::write_abort();
    return false;
}

// This method is called whenever this port has pending output data.
// We need to read the original contents, modify the VLAN tag, then
// copy the modified data to the designated Writeable sink.  If the
// sink cannot accept the entire packet at once, resume work when
// data_rcvd() is called again during the next polling interval.
void SwitchPort::data_rcvd(satcat5::io::Readable* src) {
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "SwitchPort::data_rcvd");

    // Start of frame only: Read and modify the packet header.
    if (!m_eg_hdr) {
        // Proceed only if we can read/modify/write the entire frame header.
        // (This includes Ethernet header, and may include VTAG/IP/ARP.)
        PluginPacket pkt{};
        if (m_eg_dst->get_write_space() < SATCAT5_MBUFF_CHUNK) return;
        if (pkt.read_from(m_egress.get_packet())) {
            // Header OK, proceed with egress processing...
            plugin_egress(pkt);
            if (pkt.dst_mask == 0) {
                m_egress.read_finalize();   // Packet dropped?
                return;
            } else if (pkt.is_adjusted()) {
                m_egress.read_consume(pkt.hlen);
                pkt.write_to(m_eg_dst);     // Write new header?
            }
            m_eg_hdr = true;                // Copy remaining data.
            // Optional carbon-copy to debug port.
            m_switch->debug_if(pkt, DEBUG_EGRESS);
        } else {
            // Error reading packet, discard.
            m_egress.read_finalize();
            return;
        }
    }

    // Everything after the frame header is a one-for-one copy.
    // Once finished, call finalize and get ready for the next frame.
    m_egress.copy_to(m_eg_dst);
    if (!m_egress.get_read_ready()) {
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "VlanAdapter::data_rcvd::fin");
        m_egress.read_finalize();
        m_eg_dst->write_finalize();
        m_eg_hdr = false;
    }
}

