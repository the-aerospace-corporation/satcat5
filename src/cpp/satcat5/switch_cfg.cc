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

namespace cfg   = satcat5::cfg;
namespace log   = satcat5::log;
namespace swcfg = satcat5::eth;

// Define ConfigBus register map (see also: mac_core.vhd)
static const unsigned REG_PORTCOUNT = 0;    // Number of ports (read-only)
static const unsigned REG_DATAPATH  = 1;    // Datapath width, in bits (read-only)
static const unsigned REG_CORECLOCK = 2;    // Core clock frequency, in Hz (read-only)
static const unsigned REG_MACCOUNT  = 3;    // MAC-address table size (read-only)
static const unsigned REG_PROMISC   = 4;    // Promisicuous port mask (read-write)
static const unsigned REG_PRIORITY  = 5;    // Packet prioritization (read-write, optional)
static const unsigned REG_PKTCOUNT  = 6;    // Packet-counting w/ filter (read-write)
static const unsigned REG_FRAMESIZE = 7;    // Frame size limits

swcfg::SwitchConfig::SwitchConfig(cfg::ConfigBus* cfg, unsigned devaddr)
    : m_reg(cfg->get_register(devaddr, 0))
    , m_pri_wridx(0)
    , m_filter(0)
{
    priority_reset();
}

void swcfg::SwitchConfig::log_info(const char* label)
{
    log::Log msg(log::INFO, label);
    msg.write("\r\n\tPorts").write(m_reg[REG_PORTCOUNT]);
    msg.write("\r\n\tDatapath").write(m_reg[REG_DATAPATH]);
    msg.write("\r\n\tCoreClk").write(m_reg[REG_CORECLOCK]);
    msg.write("\r\n\tMAC-count").write(m_reg[REG_MACCOUNT]);
    msg.write("\r\n\tPRI-count").write(m_reg[REG_PRIORITY]);
}

void swcfg::SwitchConfig::priority_reset()
{
    // Read table size, then zeroize.
    u32 tsize = m_reg[REG_PRIORITY];
    for (u32 a = 0 ; a < tsize ; ++a) {
        m_reg[REG_PRIORITY] = (a << 24);
    }

    // Next write is to table index zero.
    m_pri_wridx = 0;
}

bool swcfg::SwitchConfig::priority_set(u16 etype, unsigned plen)
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

void swcfg::SwitchConfig::set_promiscuous(unsigned port_idx, bool enable)
{
    u32 temp = m_reg[REG_PROMISC];
    u32 mask = (1u << port_idx);
    satcat5::util::set_mask_if(temp, mask, enable);
    m_reg[REG_PROMISC] = temp;
}

u32 swcfg::SwitchConfig::get_promiscuous_mask()
{
    return m_reg[REG_PROMISC];
}

void swcfg::SwitchConfig::set_traffic_filter(u16 etype)
{
    m_filter = etype;
    get_traffic_count();
}

u32 swcfg::SwitchConfig::get_traffic_count()
{
    // Write any value to refresh the counter register.
    // (This also sets filter configuratin for the *next* interval.)
    m_reg[REG_PKTCOUNT] = m_filter;
    // Short delay before reading the register value.
    for (volatile unsigned a = 0 ; a < 16 ; ++a) {}
    return m_reg[REG_PKTCOUNT];
}

u16 swcfg::SwitchConfig::get_frame_min()
{
    u32 regval = m_reg[REG_FRAMESIZE];
    return (u16)((regval >> 0) & 0xFFFF);
}

u16 swcfg::SwitchConfig::get_frame_max()
{
    u32 regval = m_reg[REG_FRAMESIZE];
    return (u16)((regval >> 16) & 0xFFFF);
}
