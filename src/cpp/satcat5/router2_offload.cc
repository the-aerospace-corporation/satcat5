//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/log.h>
#include <satcat5/router2_offload.h>
#include <satcat5/timeref.h>
#include <satcat5/utils.h>

using satcat5::io::MultiPacket;
using satcat5::log::CRITICAL;
using satcat5::log::Log;
using satcat5::router2::Offload;

static const char* LBL = "ROUTER_OFFLOAD";
static const unsigned REGADDR_LOG = 489;    // Same as m_ctrl->pkt_log
static const unsigned REGADDR_IRQ = 510;    // Same as m_ctrl->rx_irq

Offload::Offload(
    satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr,
    satcat5::router2::Dispatch* router, unsigned hw_ports)
    : Interrupt(cfg, devaddr, REGADDR_IRQ)
    , MultiWriter(router)
    , m_ctrl((ctrl_reg*)cfg->get_device_mmap(devaddr))
    , m_router(router)
    , m_pktlog(cfg->get_register(devaddr, REGADDR_LOG))
    , m_port_index(router->port_count())
    , m_zero_pad(true)
    , m_port_mask(0)
    , m_policy(satcat5::router2::RULE_ALL)
{
    // Sanity check on the control register map.
    static_assert(sizeof(ctrl_reg) == 4096);

    // Load policy, MAC address, and IP address.
    reconfigure();

    // Register each associated hardware port, and fail loudly if assigned
    // bits are not consecutive. (Dynamic mapping is prohibitively complex.)
    for (unsigned a = 0 ; a < hw_ports ; ++a) {
        SATCAT5_PMASK_TYPE new_mask = m_router->next_port_mask();
        m_port_mask |= new_mask;
        if (new_mask != satcat5::eth::idx2mask(m_port_index+a))
            Log(CRITICAL, LBL).write("Port registration error.");   // GCOVR_EXCL_LINE
    }

    // Register ourselves as the callback for outgoing data.
    m_router->set_offload(this);
}

#if SATCAT5_ALLOW_DELETION
Offload::~Offload() {
    m_router->set_offload(0);
}
#endif

void Offload::rule_allow(u32 mask) {
    satcat5::util::clr_mask(m_policy, mask);
    reconfigure();  // Load the new settings.
}

void Offload::rule_block(u32 mask) {
    satcat5::util::set_mask(m_policy, mask);
    reconfigure();  // Load the new settings.
}

void Offload::deliver(const satcat5::eth::PluginPacket& meta) {
    // Sanity check: This interface can't support jumbo frames.
    unsigned len = meta.pkt->m_length;
    if (len > sizeof(m_ctrl->txrx_buff)) return;

    // Translate the software port-mask to a hardware port-mask.
    u32 hw_mask((meta.dst_mask & m_port_mask) >> m_port_index);
    if (!hw_mask) return;               // No matching ports?

    // If the busy flag is set, wait a moment and check one more time.
    // (Worst-case delay is ~4 microseconds for a buffer-to-buffer copy.)
    if (m_ctrl->tx_ctrl) {
        SATCAT5_CLOCK->busywait_usec(10);
        if (m_ctrl->tx_ctrl) return;    // Still busy? Drop packet.
    }

    // Copy packet to the transmit buffer.
    MultiPacket::Reader rd(meta.pkt);
    rd.read_bytes(len, m_ctrl->txrx_buff);
    rd.read_finalize();

    // Zero-padding to the minimum Ethernet frame size?
    static const unsigned MIN_ZPAD = 60;
    if (m_zero_pad && len < MIN_ZPAD) {
        unsigned diff = MIN_ZPAD - len;
        memset(m_ctrl->txrx_buff + len, 0, diff);
        len += diff;
    }

    // Start transmission.
    m_ctrl->tx_mask = u32(hw_mask);
    m_ctrl->tx_ctrl = u32(len);
}

void Offload::irq_event() {
    // Read metadata for the incoming packet, if any.
    u32 status = m_ctrl->rx_ctrl;
    u32 source = (status >> 16) & 0xFF;
    u32 length = (status & 0xFFFF);
    if (!length) return;    // False alarm?

    // Read the VLAN configuration for this source port.
    auto vlan_cfg = satcat5::eth::VCFG_DEFAULT; // TODO: Implement me!
    // (Revisit this once we've added necessary registers to the VHDL.)

    // Copy data from the hardware buffer to the router's input queue.
    bool ok = (length <= sizeof(m_ctrl->txrx_buff));
    if (ok) MultiWriter::write_bytes(length, m_ctrl->txrx_buff);

    // Store required packet metadata before finalizing.
    // This MUST match the format used in SwitchPort::write_finalize().
    if (m_write_pkt) {
        static_assert(SATCAT5_MBUFF_USER >= 2,
            "SATCAT5_MBUFF_USER must be at least 2.");
        m_write_pkt->m_user[0] = u32(port_index(source));
        m_write_pkt->m_user[1] = u32(vlan_cfg.value);
    }
    if (ok) MultiWriter::write_finalize();

    // Flush contents of the hardware buffer.
    m_ctrl->rx_ctrl = 0;
}

u32 Offload::reconfigure() {
    // Load the gateway-configuration register (3x write + read).
    u32 ipaddr = m_router->ipaddr().value;
    u64 mac64 = m_router->macaddr().to_u64();
    m_ctrl->gateway = u32(mac64 >> 32) | m_policy;
    m_ctrl->gateway = u32(mac64 >> 0);
    m_ctrl->gateway = ipaddr;
    return m_ctrl->gateway;
}
