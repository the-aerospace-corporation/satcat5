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
// Configuration for a managed SatCat5 switch
//
// SatCat5 switches can operate autonomously.  However, an optional
// management interface allows runtime changes to the configuration,
// such as prioritizing frames with certain EtherType(s) or marking
// specific ports as "promiscuous" so they can monitor global traffic.
//

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace eth {
        class SwitchConfig {
        public:
            SwitchConfig(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Log some basic info about this switch.
            void log_info(const char* label);

            // Designate specific EtherType range(s) as high-priority.
            // Each range is specified with a CIDR-style prefix-length:
            //  * 0x1234/16 = EtherType 0x1234 only
            //  * 0x1230/12 = EtherType 0x1230 through 0x123F
            void priority_reset();
            bool priority_set(u16 etype, unsigned plen = 16);

            // Enable or disable "promiscuous" flag on the specified port index.
            // For as long as the flag is set, those port(s) will receive ALL
            // switch traffic regardless of the desitnation address.
            void set_promiscuous(unsigned port_idx, bool enable);

            // Identify which ports are currently promiscuous.
            u32 get_promiscuous_mask();

            // Set EtherType filter for traffic reporting. (0 = Any type)
            void set_traffic_filter(u16 etype = 0);
            inline u16 get_traffic_filter() const {return m_filter;}

            // Report matching frames since last call to get_traffic_count().
            u32 get_traffic_count();

            // Get the minimum and maximum frame size, in bytes.
            u16 get_frame_min();
            u16 get_frame_max();

        protected:
            satcat5::cfg::Register m_reg;
            u32 m_pri_wridx;
            u16 m_filter;
        };
    }
}
