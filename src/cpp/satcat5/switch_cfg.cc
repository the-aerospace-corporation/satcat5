//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/utils.h>

namespace cfg = satcat5::cfg;
namespace eth = satcat5::eth;
namespace log = satcat5::log;
using eth::SwitchConfig;

// Define ConfigBus register map (see also: switch_types.vhd)
static const unsigned REG_PORTCOUNT = 0;    // Number of ports (read-only)
static const unsigned REG_DATAPATH  = 1;    // Datapath width, in bits (read-only)
static const unsigned REG_CORECLOCK = 2;    // Core clock frequency, in Hz (read-only)
static const unsigned REG_MACCOUNT  = 3;    // MAC-address table size (read-only)
static const unsigned REG_PROMISC   = 4;    // Promisicuous port mask (read-write)
static const unsigned REG_PRIORITY  = 5;    // Packet prioritization (read-write, optional)
static const unsigned REG_PKTCOUNT  = 6;    // Packet-counting w/ filter (read-write)
static const unsigned REG_FRAMESIZE = 7;    // Frame size limits
static const unsigned REG_VLAN_PORT = 8;    // VLAN port configuration
static const unsigned REG_VLAN_VID  = 9;    // VLAN connections (VID)
static const unsigned REG_VLAN_MASK = 10;   // VLAN connections (port-mask)

SwitchConfig::SwitchConfig(cfg::ConfigBus* cfg, unsigned devaddr)
    : m_reg(cfg->get_register(devaddr, 0))
    , m_pri_wridx(0)
    , m_filter(0)
{
    priority_reset();
}

void SwitchConfig::log_info(const char* label)
{
    log::Log msg(log::INFO, label);
    msg.write("\r\n\tPorts").write(m_reg[REG_PORTCOUNT]);
    msg.write("\r\n\tDatapath").write(m_reg[REG_DATAPATH]);
    msg.write("\r\n\tCoreClk").write(m_reg[REG_CORECLOCK]);
    msg.write("\r\n\tMAC-count").write(m_reg[REG_MACCOUNT]);
    msg.write("\r\n\tPRI-count").write(m_reg[REG_PRIORITY]);
}

// Note: Method cannot be "const" because register reads may have side-effects.
u32 SwitchConfig::port_count()
{
    return m_reg[REG_PORTCOUNT];
}

void SwitchConfig::priority_reset()
{
    // Read table size, then zeroize.
    u32 tsize = m_reg[REG_PRIORITY];
    for (u32 a = 0 ; a < tsize ; ++a) {
        m_reg[REG_PRIORITY] = (a << 24);
    }

    // Next write is to table index zero.
    m_pri_wridx = 0;
}

bool SwitchConfig::priority_set(u16 etype, unsigned plen)
{
    // Sanity checks before we write:
    u32 tsize = m_reg[REG_PRIORITY];
    if (m_pri_wridx >= tsize) {
        log::Log(log::WARNING, "MAC priority-table overflow.");
        return false;
    } else if (etype < 1536 || plen > 16) {
        log::Log(log::WARNING, "Invalid MAC-priority entry.");
        return false;
    }

    // Write the next table entry.
    u32 wcl = (u32)(16 - plen);     // Wildcard length
    u32 cmd = (m_pri_wridx << 24) | (wcl << 16) | etype;
    m_reg[REG_PRIORITY] = cmd;

    // Success!
    ++m_pri_wridx;
    return true;
}

void SwitchConfig::set_promiscuous(unsigned port_idx, bool enable)
{
    u32 temp = m_reg[REG_PROMISC];
    u32 mask = (1u << port_idx);
    satcat5::util::set_mask_if(temp, mask, enable);
    m_reg[REG_PROMISC] = temp;
}

u32 SwitchConfig::get_promiscuous_mask()
{
    return m_reg[REG_PROMISC];
}

void SwitchConfig::set_traffic_filter(u16 etype)
{
    m_filter = etype;
    get_traffic_count();
}

u32 SwitchConfig::get_traffic_count()
{
    // Write any value to refresh the counter register.
    // (This also sets filter configuratin for the *next* interval.)
    m_reg[REG_PKTCOUNT] = m_filter;
    // Short delay before reading the register value.
    for (volatile unsigned a = 0 ; a < 16 ; ++a) {}
    return m_reg[REG_PKTCOUNT];
}

u16 SwitchConfig::get_frame_min()
{
    u32 regval = m_reg[REG_FRAMESIZE];
    return (u16)((regval >> 0) & 0xFFFF);
}

u16 SwitchConfig::get_frame_max()
{
    u32 regval = m_reg[REG_FRAMESIZE];
    return (u16)((regval >> 16) & 0xFFFF);
}

void SwitchConfig::vlan_reset(bool lockdown)
{
    // Set default policy and port-mask.
    u32 policy = lockdown ? eth::VTAG_RESTRICT : eth::VTAG_ADMIT_ALL;
    u32 mask   = lockdown ? eth::VLAN_CONNECT_NONE : eth::VLAN_CONNECT_ALL;
    
    // Reset each port with default policy and VID = 1.
    u32 pcount = m_reg[REG_PORTCOUNT];
    for (unsigned a = 0 ; a < pcount ; ++a)
        m_reg[REG_VLAN_PORT] = vlan_portcfg(a, policy, eth::VTAG_DEFAULT);

    // Reset every VID so it connects the designated ports.
    // (Write base address, then repeated masks with auto-increment.)
    m_reg[REG_VLAN_VID] = (u32)eth::VID_MIN;
    for (u16 a = eth::VID_MIN ; a <= eth::VID_MAX ; ++a)
        m_reg[REG_VLAN_MASK] = mask;
}

u32 SwitchConfig::vlan_get_mask(u16 vid)
{
    m_reg[REG_VLAN_VID] = (u32)vid;
    return m_reg[REG_VLAN_MASK];
}

void SwitchConfig::vlan_set_mask(u16 vid, u32 mask)
{
    m_reg[REG_VLAN_VID] = (u32)vid;
    m_reg[REG_VLAN_MASK] = mask;
}

void SwitchConfig::vlan_set_port(u32 cfg)
{
    m_reg[REG_VLAN_PORT] = cfg;
}

void SwitchConfig::vlan_join(u16 vid, unsigned port)
{
    // Read original mask.
    m_reg[REG_VLAN_VID] = (u32)vid;
    u32 mask = m_reg[REG_VLAN_MASK];
    // Write modified mask.
    satcat5::util::set_mask_u32(mask, 1u << port);
    m_reg[REG_VLAN_VID] = (u32)vid;
    m_reg[REG_VLAN_MASK] = mask;
}

void SwitchConfig::vlan_leave(u16 vid, unsigned port)
{
    // Read original mask.
    m_reg[REG_VLAN_VID] = (u32)vid;
    u32 mask = m_reg[REG_VLAN_MASK];
    // Write modified mask.
    satcat5::util::clr_mask_u32(mask, 1u << port);
    m_reg[REG_VLAN_VID] = (u32)vid;
    m_reg[REG_VLAN_MASK] = mask;
}
