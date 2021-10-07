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
// ConfigBus core definitions
//
// Define a memory-mapped "ConfigBus" interface, based on a base address.
// All registers in this interface correspond to volatile pointers.
//

#include <satcat5/cfgbus_stats.h>

namespace cfg = satcat5::cfg;

cfg::NetworkStats::NetworkStats(
        cfg::ConfigBusMmap* cfg, unsigned devaddr)
    : m_traffic((cfg::TrafficStats*)cfg->get_device_mmap(devaddr))
{
    // Nothing else to initialize.
}

void cfg::NetworkStats::refresh_now()
{
    // Writing to any portion of the register map reloads all counters.
    m_traffic->status = 0;
}

volatile cfg::TrafficStats* cfg::NetworkStats::get_port(unsigned idx)
{
    // ConfigBus address space = 4 kiB = 128 ports max.
    if (idx < 128)
        return m_traffic + idx;
    else
        return 0;
}
