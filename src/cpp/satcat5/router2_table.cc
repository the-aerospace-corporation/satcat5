//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/router2_table.h>

using satcat5::cfg::ConfigBus;
using satcat5::ip::Route;
using satcat5::router2::Table;

// Register map defined in "router2_common.vhd"
static constexpr unsigned REG_CTRL  = 509;
static constexpr unsigned REG_DATA  = 508;

// Bit masks for the control register.
static constexpr u32 MASK_BUSY      = (1u << 31);
static constexpr u32 MASK_SIZE      = 0xFFFF;
static constexpr u32 OPCODE_WRITE   = (1u << 28);
static constexpr u32 OPCODE_DROUTE  = (2u << 28);
static constexpr u32 OPCODE_CLEAR   = (3u << 28);

Table::Table(ConfigBus* cfg, unsigned devaddr)
    : m_cfg(cfg->get_register(devaddr))
{
    m_cfg[REG_CTRL] = OPCODE_CLEAR;
}

unsigned Table::table_size() {
    return unsigned(m_cfg[REG_CTRL] & MASK_SIZE);
}

bool Table::route_wrdef(const Route& route) {
    // Attempt write to the software table, mirror if successful.
    return satcat5::ip::Table::route_wrdef(route)
        && route_load(OPCODE_DROUTE, route);
}

bool Table::route_write(unsigned idx, const Route& route) {
    // Attempt write to the software table, mirror if successful.
    return satcat5::ip::Table::route_write(idx, route)
        && route_load(OPCODE_WRITE + idx, route);

}

bool Table::route_load(u32 opcode, const Route& route) {
    // Extract parameters of interest...
    u64 dmac = route.dstmac.to_u64();
    u32 pfix = route.subnet.prefix();
    u32 port = route.port;

    // Wait until hardware is idle/ready.
    // (This should only take a few microseconds...)
    while (m_cfg[REG_CTRL] & MASK_BUSY) {}

    // Copy the new entry to the hardware table.
    m_cfg[REG_DATA] = u32((pfix << 24) | (port << 16) | (dmac >> 32));
    m_cfg[REG_DATA] = u32(dmac & 0xFFFFFFFFu);
    m_cfg[REG_DATA] = u32(route.subnet.addr.value);
    m_cfg[REG_CTRL] = opcode;
    return true;
}
