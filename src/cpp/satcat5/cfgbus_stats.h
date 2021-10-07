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
// Network statistics reporting over ConfigBus
//
// Define a memory-mapped interface to the "config_stats" block.
// It can be refreshed manually, or instructed to refresh automatically
// at a fixed interval (e.g., once per second).
//

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_timer.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace cfg {
        // Data structure for reading per-port traffic statistics.
        // TODO: Support big-endian host platforms.
        struct TrafficStats {
            u32 bcast_bytes;        // Broadcast bytes received from device
            u32 bcast_frames;       // Broadcast frames received from device
            u32 rcvd_bytes;         // Total bytes received from device
            u32 rcvd_frames;        // Total frames received from device
            u32 sent_bytes;         // Total bytes sent from switch to device
            u32 sent_frames;        // Total frames sent from switch to device
            u8  errct_mac;          // MAC/PHY errors
            u8  errct_ovr_tx;       // Tx-FIFO overflow (common)
            u8  errct_ovr_rx;       // Rx-FIFO overflow (rare)
            u8  errct_pkt;          // Packet errors (bad checksum, length, etc.)
            u32 status;             // Port status (Varies by port)
        };

        // Traffic statistics polling.
        class NetworkStats {
        public:
            // Construct a memory-map for the designated ConfigBus device.
            // TODO: Support for the generic ConfigBus interface.
            NetworkStats(satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr);

            // Immediately refresh statistics.
            void refresh_now();

            // Get a pointer to the register map for the Nth port.
            volatile satcat5::cfg::TrafficStats* get_port(unsigned idx);

        private:
            volatile satcat5::cfg::TrafficStats* const m_traffic;
        };
    }
}
