//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/utils.h>

namespace eth = satcat5::eth;
namespace log = satcat5::log;
namespace util = satcat5::util;
using satcat5::eth::SwitchConfig;
using satcat5::eth::VlanRate;

// Define ConfigBus register map (see also: switch_types.vhd)
constexpr unsigned REG_PORTCOUNT    = 0;    // Number of ports (read-only)
constexpr unsigned REG_DATAPATH     = 1;    // Datapath width, in bits (read-only)
constexpr unsigned REG_CORECLOCK    = 2;    // Core clock frequency, in Hz (read-only)
constexpr unsigned REG_MACCOUNT     = 3;    // MAC-address table size (read-only)
constexpr unsigned REG_PROMISC      = 4;    // Promisicuous port mask (read-write)
constexpr unsigned REG_PRIORITY     = 5;    // Packet prioritization (read-write, optional)
constexpr unsigned REG_PKTCOUNT     = 6;    // Packet-counting w/ filter (read-write)
constexpr unsigned REG_FRAMESIZE    = 7;    // Frame size limits (read-only)
constexpr unsigned REG_VLAN_PORT    = 8;    // VLAN port configuration (write-only)
constexpr unsigned REG_VLAN_VID     = 9;    // VLAN connections: set VID (read-write)
constexpr unsigned REG_VLAN_MASK    = 10;   // VLAN connections: set mask (read-write)
constexpr unsigned REG_MACTBL_LSB   = 11;   // MAC-table control (read-write)
constexpr unsigned REG_MACTBL_MSB   = 12;   // MAC-table control (read-write)
constexpr unsigned REG_MACTBL_CTRL  = 13;   // MAC-table control (read-write)
constexpr unsigned REG_MISS_BCAST   = 14;   // Miss-as-broadcast port mask (read-write)
constexpr unsigned REG_PTP_2STEP    = 15;   // PTP "twoStep" mode flag (read-write)
constexpr unsigned REG_VLAN_RATE    = 16;   // VLAN rate-control configuration (write-only)

// Additional ConfigBus registers for each port.
static constexpr unsigned REG_PORT(unsigned idx)       {return 512 + 16*idx;}
static constexpr unsigned REG_PTP_RX(unsigned idx)     {return REG_PORT(idx) + 8;}
static constexpr unsigned REG_PTP_TX(unsigned idx)     {return REG_PORT(idx) + 9;}

// Define opcodes for REG_MACTBL_CTRL:
constexpr u32 MACTBL_OPCODE_MASK                = 0xFF000000u;
constexpr u32 MACTBL_ARGVAL_MASK                = 0x00FFFFFFu;
constexpr u32 MACTBL_IDLE                       = 0;
constexpr u32 MACTBL_READ(unsigned tbl_idx)     {return (u32)(0x01000000 + tbl_idx);}
constexpr u32 MACTBL_WRITE(unsigned port_idx)   {return (u32)(0x02000000 + port_idx);}
constexpr u32 MACTBL_CLEAR()                    {return (u32)(0x03000000);}
constexpr u32 MACTBL_LEARN(unsigned enable)     {return (u32)(0x04000000 + enable);}

SwitchConfig::SwitchConfig(satcat5::cfg::ConfigBus* cfg, unsigned devaddr)
    : m_reg(cfg->get_register(devaddr, 0))
    , m_pri_wridx(0)
    , m_stats_filter(0)
{
    priority_reset();
}

void SwitchConfig::log_info(const char* label)
{
    log::Log msg(log::INFO, label);
    msg.write("\r\n\tPorts").write10(m_reg[REG_PORTCOUNT]);
    msg.write("\r\n\tDatapath").write10(m_reg[REG_DATAPATH]);
    msg.write("\r\n\tCoreClk").write10(m_reg[REG_CORECLOCK]);
    msg.write("\r\n\tMAC-count").write10(m_reg[REG_MACCOUNT]);
    msg.write("\r\n\tPRI-count").write10(m_reg[REG_PRIORITY]);
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

void SwitchConfig::set_miss_bcast(unsigned port_idx, bool enable)
{
    u32 temp = m_reg[REG_MISS_BCAST];
    u32 mask = (1u << port_idx);
    util::set_mask_if(temp, mask, enable);
    m_reg[REG_MISS_BCAST] = temp;
}

u32 SwitchConfig::get_miss_mask()
{
    return m_reg[REG_MISS_BCAST];
}

void SwitchConfig::set_promiscuous(unsigned port_idx, bool enable)
{
    u32 temp = m_reg[REG_PROMISC];
    u32 mask = (1u << port_idx);
    util::set_mask_if(temp, mask, enable);
    m_reg[REG_PROMISC] = temp;
}

u32 SwitchConfig::get_promiscuous_mask()
{
    return m_reg[REG_PROMISC];
}

void SwitchConfig::set_traffic_filter(u16 etype)
{
    m_stats_filter = etype;
    get_traffic_count();
}

u32 SwitchConfig::get_traffic_count()
{
    // Write any value to refresh the counter register.
    // (This also sets filter configuration for the *next* interval.)
    m_reg[REG_PKTCOUNT] = m_stats_filter;
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

s32 SwitchConfig::ptp_get_offset_rx(unsigned port_idx)
{
    return (s32)m_reg[REG_PTP_RX(port_idx)];
}

s32 SwitchConfig::ptp_get_offset_tx(unsigned port_idx)
{
    return (s32)m_reg[REG_PTP_TX(port_idx)];
}

u32 SwitchConfig::ptp_get_2step_mask()
{
    return m_reg[REG_PTP_2STEP];
}

void SwitchConfig::ptp_set_offset_rx(unsigned port_idx, s32 subns)
{
    m_reg[REG_PTP_RX(port_idx)] = (u32)subns;
}

void SwitchConfig::ptp_set_offset_tx(unsigned port_idx, s32 subns)
{
    m_reg[REG_PTP_TX(port_idx)] = (u32)subns;
}

void SwitchConfig::ptp_set_2step(unsigned port_idx, bool enable)
{
    u32 temp = m_reg[REG_PTP_2STEP];
    u32 mask = (1u << port_idx);
    util::set_mask_if(temp, mask, enable);
    m_reg[REG_PTP_2STEP] = temp;
}

void SwitchConfig::vlan_reset(bool lockdown)
{
    // Set default policy and port-mask.
    u32 policy = lockdown ? eth::VTAG_RESTRICT : eth::VTAG_ADMIT_ALL;
    u32 mask   = lockdown ? eth::VLAN_CONNECT_NONE : eth::VLAN_CONNECT_ALL;
    VlanRate rate = lockdown ? eth::VRATE_8KBPS : eth::VRATE_UNLIMITED;

    // Reset each port with default policy and VID = 1.
    u32 pcount = m_reg[REG_PORTCOUNT];
    for (unsigned port = 0 ; port < pcount ; ++port)
        m_reg[REG_VLAN_PORT] = vlan_portcfg(port, policy, eth::VTAG_DEFAULT);

    // Reset every VID so it connects the designated ports.
    // (Write base address, then repeated masks with auto-increment.)
    m_reg[REG_VLAN_VID] = (u32)eth::VID_MIN;
    for (u16 vid = eth::VID_MIN ; vid <= eth::VID_MAX ; ++vid)
        m_reg[REG_VLAN_MASK] = mask;

    // If rate limiter is enabled, reset policy for each VID.
    if (m_reg[REG_VLAN_RATE] > 0) {
        for (u16 vid = eth::VID_MIN ; vid <= eth::VID_MAX ; ++vid)
            vlan_set_rate(vid, rate);
    }
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

void SwitchConfig::vlan_set_rate(u16 vid, const VlanRate& cfg)
{
    // Three consecutive writes sets the new rate-limit.
    m_reg[REG_VLAN_RATE] = cfg.tok_rate;
    m_reg[REG_VLAN_RATE] = cfg.tok_max;
    m_reg[REG_VLAN_RATE] = cfg.tok_policy | vid;
}

void SwitchConfig::vlan_join(u16 vid, unsigned port)
{
    // Read original mask.
    m_reg[REG_VLAN_VID] = (u32)vid;
    u32 mask = m_reg[REG_VLAN_MASK];
    // Write modified mask.
    util::set_mask_u32(mask, 1u << port);
    m_reg[REG_VLAN_VID] = (u32)vid;
    m_reg[REG_VLAN_MASK] = mask;
}

void SwitchConfig::vlan_leave(u16 vid, unsigned port)
{
    // Read original mask.
    m_reg[REG_VLAN_VID] = (u32)vid;
    u32 mask = m_reg[REG_VLAN_MASK];
    // Write modified mask.
    util::clr_mask_u32(mask, 1u << port);
    m_reg[REG_VLAN_VID] = (u32)vid;
    m_reg[REG_VLAN_MASK] = mask;
}

bool SwitchConfig::mactbl_read(
    unsigned tbl_idx,
    unsigned& port_idx,
    eth::MacAddr& mac_addr)
{
    // Wait until other commands are finished.
    if (!mactbl_wait_idle()) return false;  // Timeout?

    // Issue command and wait for completion.
    m_reg[REG_MACTBL_CTRL] = MACTBL_READ(tbl_idx);
    if (!mactbl_wait_idle()) return false;  // Timeout?

    // Read and parse results.
    u32 mac_lsb = m_reg[REG_MACTBL_LSB];
    u32 mac_msb = m_reg[REG_MACTBL_MSB];
    u32 status  = m_reg[REG_MACTBL_CTRL];
    port_idx = (unsigned)(status & MACTBL_ARGVAL_MASK);
    util::write_be_u16(mac_addr.addr + 0, mac_msb);
    util::write_be_u32(mac_addr.addr + 2, mac_lsb);

    // A value of 00:00:... or FF:FF:... indicates an empty row.
    return (mac_addr != MACADDR_NONE)
        && (mac_addr != MACADDR_BROADCAST);
}

bool SwitchConfig::mactbl_write(
    unsigned port_idx,
    const satcat5::eth::MacAddr& mac_addr)
{
    // Wait until other commands are finished.
    if (!mactbl_wait_idle()) return false;  // Timeout?

    // Setup arguments and issue command.
    m_reg[REG_MACTBL_MSB] = util::extract_be_u16(mac_addr.addr + 0);
    m_reg[REG_MACTBL_LSB] = util::extract_be_u32(mac_addr.addr + 2);
    m_reg[REG_MACTBL_CTRL] = MACTBL_WRITE(port_idx);

    // Wait for completion.
    return mactbl_wait_idle();              // Success?
}

unsigned SwitchConfig::mactbl_size()
{
    // Read table size from hardware (typ. 32-128)
    return (unsigned)m_reg[REG_MACCOUNT];
}

bool SwitchConfig::mactbl_clear()
{
    // Wait until other commands are finished.
    if (!mactbl_wait_idle()) return false;  // Timeout?

    // Issue command and wait for completion.
    m_reg[REG_MACTBL_CTRL] = MACTBL_CLEAR();
    return mactbl_wait_idle();              // Success?
}

bool SwitchConfig::mactbl_learn(bool enable)
{
    // Wait until other commands are finished.
    if (!mactbl_wait_idle()) return false;  // Timeout?

    // Issue command and wait for completion.
    m_reg[REG_MACTBL_CTRL] = MACTBL_LEARN(enable ? 1 : 0);
    return mactbl_wait_idle();              // Success?
}

void SwitchConfig::mactbl_log(const char* label)
{
    unsigned port_idx;
    eth::MacAddr mac_addr;

    // Create a log message for each table entry.
    unsigned table_size = mactbl_size();
    for (unsigned tbl_idx = 0 ; tbl_idx < table_size ; ++tbl_idx) {
        log::Log msg(log::INFO, label);
        msg.write(": Row").write10((u32)tbl_idx);
        if (mactbl_read(tbl_idx, port_idx, mac_addr)) {
            msg.write(": Port").write10((u32)port_idx);
            msg.write(", MAC").write(mac_addr);
        } else {
            msg.write(": Empty");
        }
    }
}

bool SwitchConfig::mactbl_wait_idle()
{
    // Poll the control register up to N times.
    // TODO: Tie this to real-world timeout of a few microseconds.
    for (unsigned a = 0 ; a < 100 ; ++a) {
        u32 status = m_reg[REG_MACTBL_CTRL];
        if ((status & MACTBL_OPCODE_MASK) == MACTBL_IDLE)
            return true;    // Done / idle
    }
    return false;           // Timeout
}
