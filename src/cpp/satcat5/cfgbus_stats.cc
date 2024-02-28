//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus core definitions
//
// Define a memory-mapped "ConfigBus" interface, based on a base address.
// All registers in this interface correspond to volatile pointers.
//

#include <satcat5/cfgbus_stats.h>

namespace cfg = satcat5::cfg;

cfg::NetworkStats::NetworkStats(
        cfg::ConfigBus* cfg, unsigned devaddr)
    : m_traffic(cfg->get_register(devaddr))
{
    // Nothing else to initialize.
}

void cfg::NetworkStats::refresh_now()
{
    // Writing to any portion of the register map reloads all counters.
    *m_traffic = 0;
}

cfg::TrafficStats cfg::NetworkStats::get_port(unsigned idx)
{
    cfg::TrafficStats stats = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    unsigned reg = 16 * idx;         // Fixed size, 16 registers per port
    if (reg < cfg::REGS_PER_DEVICE) {
        // Read ConfigBus registers.
        stats.bcast_bytes   = m_traffic[reg+0];
        stats.bcast_frames  = m_traffic[reg+1];
        stats.rcvd_bytes    = m_traffic[reg+2];
        stats.rcvd_frames   = m_traffic[reg+3];
        stats.sent_bytes    = m_traffic[reg+4];
        stats.sent_frames   = m_traffic[reg+5];
        u32 errct_word      = m_traffic[reg+6];
        u32 errct_ptp       = m_traffic[reg+7];
        stats.status        = m_traffic[reg+8];
        // Split individual byte fields from errct_word.
        // (This method works on both little-endian and big-endian hosts.)
        stats.errct_mac     = (u8)(errct_word >> 24);
        stats.errct_ovr_tx  = (u8)(errct_word >> 16);
        stats.errct_ovr_rx  = (u8)(errct_word >> 8);
        stats.errct_pkt     = (u8)(errct_word >> 0);
        stats.errct_ptp_rx  = (u8)(errct_ptp >> 8);
        stats.errct_ptp_tx  = (u8)(errct_ptp >> 0);

    }
    return stats;
}
