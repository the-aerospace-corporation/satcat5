//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/sim_sw_core.h>
#include <satcat5/log.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/utils.h>

using satcat5::cfg::IoStatus;
using satcat5::eth::SwitchConfig;
using satcat5::test::SimSwitchCore;

SimSwitchCore::SimSwitchCore()
    : m_eth_sw()
    , m_eth_tbl(&m_eth_sw)
    , m_eth_vlan(&m_eth_sw, false)
    , m_next_vid(0)
    , m_rate_ctr(0)
    , m_rate_1st(0)
    , m_rate_2nd(0)
    , m_mac_lsb(0)
    , m_mac_msb(0)
    , m_mac_ctrl(0)
    , m_traffic_count(0)
    , m_reg_echo{}
{
    memset(m_reg_echo, 0, sizeof(m_reg_echo));
}

// Report min and max frame size:
static constexpr u32
    FRMSIZE_MIN     = 18,
    FRMSIZE_MAX     = 1522,
    FRMSIZE_WORD    = FRMSIZE_MAX << 16 | FRMSIZE_MIN;

IoStatus SimSwitchCore::read(unsigned regaddr, u32& rdval) {
    regaddr %= satcat5::cfg::REGS_PER_DEVICE;
    switch (regaddr) {
    case SwitchConfig::REG_PORTCOUNT:
        rdval = u32(m_eth_sw.port_count()); break;
    case SwitchConfig::REG_DATAPATH:
        rdval = 24; break;      // 24-bit datapath is typical.
    case SwitchConfig::REG_CORECLOCK:
        rdval = 100e6; break;   // 100 MHz typical
    case SwitchConfig::REG_MACCOUNT:
        rdval = m_eth_tbl.mactbl_size(); break;
    case SwitchConfig::REG_PROMISC:
        rdval = u32(m_eth_sw.get_promiscuous_mask()); break;
    case SwitchConfig::REG_PRIORITY:
        rdval = 0; break;       // EtherType prioritization is not supported
    case SwitchConfig::REG_PKTCOUNT:
        rdval = m_traffic_count; break;
    case SwitchConfig::REG_FRAMESIZE:
        rdval = FRMSIZE_WORD; break;
    case SwitchConfig::REG_VLAN_MASK:
        rdval = u32(m_eth_vlan.vlan_get_mask(m_next_vid)); break;
    case SwitchConfig::REG_MACTBL_LSB:
        rdval = m_mac_lsb; break;
    case SwitchConfig::REG_MACTBL_MSB:
        rdval = m_mac_msb; break;
    case SwitchConfig::REG_MACTBL_CTRL:
        rdval = m_mac_ctrl; break;
    case SwitchConfig::REG_MISS_BCAST:
        rdval = m_eth_tbl.get_miss_mask(); break;
    case SwitchConfig::REG_VLAN_RATE:
        rdval = 32; break;      // 32-bit accumulators
    case SwitchConfig::REG_LOGGING:
        // TODO: Add support for logging?
        rdval = 0; break;
    default:
        // All other registers = Echo last written value.
        rdval = m_reg_echo[regaddr]; break;
    }
    return IoStatus::OK;
}

IoStatus SimSwitchCore::write(unsigned regaddr, u32 wrval) {
    regaddr %= satcat5::cfg::REGS_PER_DEVICE;
    switch (regaddr) {
    case SwitchConfig::REG_PROMISC:
        m_eth_sw.set_promiscuous_mask(wrval); break;
    case SwitchConfig::REG_PKTCOUNT:
        // Writing this register latches the current packet-counter value,
        // resets the working counter, and reconfigures the filter.
        m_traffic_count = m_eth_sw.get_traffic_count();
        m_eth_sw.set_traffic_filter(u16(wrval)); break;
    case SwitchConfig::REG_VLAN_PORT:
        m_eth_vlan.vlan_set_port(satcat5::eth::VtagPolicy(wrval)); break;
    case SwitchConfig::REG_VLAN_VID:
        m_next_vid = u16(wrval); break;
    case SwitchConfig::REG_VLAN_MASK:
        m_eth_vlan.vlan_set_mask(m_next_vid++, wrval); break;
    case SwitchConfig::REG_MACTBL_LSB:
        m_mac_lsb = wrval; break;
    case SwitchConfig::REG_MACTBL_MSB:
        m_mac_msb = wrval; break;
    case SwitchConfig::REG_MACTBL_CTRL:
        mac_table_ctrl(wrval); break;
    case SwitchConfig::REG_MISS_BCAST:
        m_eth_tbl.set_miss_mask(wrval); break;
    case SwitchConfig::REG_VLAN_RATE:
        vlan_rate_ctrl(wrval); break;
    default:
        // Note written value, but take no other action.
        m_reg_echo[regaddr] = wrval;
    }
    return IoStatus::OK;
}

void SimSwitchCore::mac_table_ctrl(u32 wrval) {
    // Execute the designated opcode (read/write/clear/learn):
    u8 opcode = u8(wrval >> 24);
    u32 arg = wrval & 0xFFFFFF, port_tmp = 0;
    satcat5::eth::MacAddr mac_tmp = satcat5::eth::MACADDR_NONE;
    if (opcode == 0x01) {           // Table read
        m_eth_tbl.mactbl_read(arg, port_tmp, mac_tmp);
        m_mac_msb = satcat5::util::extract_be_u16(mac_tmp.addr + 0);
        m_mac_lsb = satcat5::util::extract_be_u32(mac_tmp.addr + 2);
    } else if (opcode == 0x02) {    // Table write
        satcat5::util::write_be_u16(mac_tmp.addr + 0, m_mac_msb);
        satcat5::util::write_be_u32(mac_tmp.addr + 2, m_mac_lsb);
        m_eth_tbl.mactbl_write(arg, mac_tmp);
    } else if (opcode == 0x03) {    // Table clear
        m_eth_tbl.mactbl_clear();
    } else if (opcode == 0x04) {    // Enable learning?
        m_eth_tbl.mactbl_learn(arg > 0);
    } else {
        satcat5::log::Log(satcat5::log::ERROR, "SimSwitchCore: Invalid opcode.");
    }
    // Update the status register.
    m_mac_ctrl = port_tmp;
}

void SimSwitchCore::vlan_rate_ctrl(u32 wrval) {
    // This register is always written three times consecutively:
    if (m_rate_ctr == 0) {
        m_rate_1st = wrval;         // Token rate
    } else if (m_rate_ctr == 1) {
        m_rate_2nd = wrval;         // Token max
    } else {
        u16 vid = wrval & 0xFFF;    // VID + Policy flags
        satcat5::eth::VlanRate cfg {wrval, m_rate_1st, m_rate_2nd};
        m_eth_vlan.vlan_set_rate(vid, cfg);
    }
    m_rate_ctr = (m_rate_ctr + 1) % 3;
}