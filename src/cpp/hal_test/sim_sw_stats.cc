//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/sim_sw_stats.h>

using satcat5::cfg::IoStatus;
using satcat5::eth::SwitchLogStats;
using satcat5::test::SimSwitchStats;

SimSwitchStats::SimSwitchStats(satcat5::eth::SwitchCore* sw)
    : SwitchLogStats(m_accum, MAX_PORTS)
    , m_sw(sw)
    , m_accum{}     // Zero-initialize
    , m_regs{}      // Zero-initialize
{
    // Register for packet-event callbacks.
    m_sw->add_log(this);
}

SimSwitchStats::~SimSwitchStats() {
    m_sw->remove_log(this);
}

IoStatus SimSwitchStats::read(unsigned regaddr, u32& rdval) {
    // Read the buffered counter value.
    rdval = m_regs[regaddr % satcat5::cfg::REGS_PER_DEVICE];
    return IoStatus::OK;
}

IoStatus SimSwitchStats::write(unsigned regaddr, u32 wrval) {
    // A write to any register refreshes counters for every port.
    // Note: Software API doesn't provide length metadata, so report
    //  the packet-count as a placeholder for each total-bytes field.
    for (unsigned p = 0 ; p < MAX_PORTS ; ++p) {
        TrafficStats stats = get_port(p);
        m_regs[16*p + 0] = stats.bcast_frames;  // bcast_bytes (placeholder)
        m_regs[16*p + 1] = stats.bcast_frames;  // bcast_frames
        m_regs[16*p + 2] = stats.rcvd_frames;   // rcvd_bytes (placeholder)
        m_regs[16*p + 3] = stats.rcvd_frames;   // rcvd_frames
        m_regs[16*p + 4] = stats.sent_frames;   // sent_bytes (placeholder)
        m_regs[16*p + 5] = stats.sent_frames;   // sent_frames
        m_regs[16*p + 6] = stats.errct_total;   // errct_word (ignore types)
        m_regs[16*p + 8] = (1000 << 16);        // status_word (assume 1000 Mbps)
    }
    return IoStatus::OK;
}
