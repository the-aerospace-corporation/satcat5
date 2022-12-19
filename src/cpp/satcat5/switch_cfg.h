//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022 The Aerospace Corporation
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
#include <satcat5/ethernet.h>

namespace satcat5 {
    namespace eth {
        // Define VLAN policy modes for each switch port:
        //  ADMIT_ALL: Default, suitable for most network endpoints.
        //      Rx: Accept any frame, tagged or untagged.
        //      Tx: Never emit tagged frames.
        //  RESTRICTED: Suitable for locking devices to a single VID.
        //      Rx: Accept tagged frames with VID = 0, or untagged frames.
        //      Tx: Never emit tagged frames.
        //  PRIORITY: Suitable for VLAN-aware devices with a single VID.
        //      Rx: Accept tagged frames with VID = 0, or untagged frames.
        //      Tx: Always emit tagged frames with VID = 0.
        //  MANDATORY: Recommended for crosslinks to another VLAN-aware switch.
        //      Rx: Accept tagged frames only, with any VID.
        //      Tx: Always emit tagged frames with VID > 0.
        constexpr u32 VTAG_ADMIT_ALL    = 0x00000000u;
        constexpr u32 VTAG_RESTRICT     = 0x00010000u;
        constexpr u32 VTAG_PRIORITY     = 0x00110000u;
        constexpr u32 VTAG_MANDATORY    = 0x00220000u;

        // Common port-connection masks for use with "vlan_set_mask".
        constexpr u32 VLAN_CONNECT_ALL  = (u32)(-1);
        constexpr u32 VLAN_CONNECT_NONE = 0;

        // Set configuration word for a given port index:
        inline constexpr u32 vlan_portcfg(u32 port, u32 policy,
            satcat5::eth::VlanTag vtag = satcat5::eth::VTAG_DEFAULT)
        {
            return policy                       // VLAN_ADMIT_ALL, etc (see above)
                | ((port & 0xFF)    << 24)      // Port index (0-255)
                | (vtag.value);                 // VLAN identifier and/or priority
        }

        class SwitchConfig {
        public:
            SwitchConfig(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Log some basic info about this switch.
            void log_info(const char* label);

            // Number of ports on this switch.
            u32 port_count();

            // Designate specific EtherType range(s) as high-priority.
            // Each range is specified with a CIDR-style prefix-length:
            //  * 0x1234/16 = EtherType 0x1234 only
            //  * 0x1230/12 = EtherType 0x1230 through 0x123F
            void priority_reset();
            bool priority_set(u16 etype, unsigned plen = 16);

            // Enable or disable "miss-as-broadcast" flag on the specified port
            // index.  Frames with an unknown destination (i.e., destination
            // MAC not found in cache) are sent to every port with this flag.
            void set_miss_bcast(unsigned port_idx, bool enable);

            // Identify which ports are currently in "miss-as-broadcast" mode.
            u32 get_miss_mask();

            // Enable or disable "promiscuous" flag on the specified port index.
            // For as long as the flag is set, those port(s) will receive ALL
            // switch traffic regardless of the desitnation address.
            void set_promiscuous(unsigned port_idx, bool enable);

            // Identify which ports are currently promiscuous.
            u32 get_promiscuous_mask();

            // Set EtherType filter for traffic reporting. (0 = Any type)
            void set_traffic_filter(u16 etype = 0);
            inline u16 get_traffic_filter() const {return m_stats_filter;}

            // Report matching frames since last call to get_traffic_count().
            u32 get_traffic_count();

            // Get the minimum and maximum frame size, in bytes.
            u16 get_frame_min();
            u16 get_frame_max();

            // PTP configuration for each port.
            // Time units are in sub-nanoseconds (see ptp_time.h)
            s32  ptp_get_offset_rx(unsigned port_idx);
            s32  ptp_get_offset_tx(unsigned port_idx);
            u32  ptp_get_2step_mask();
            void ptp_set_offset_rx(unsigned port_idx, s32 subns);
            void ptp_set_offset_tx(unsigned port_idx, s32 subns);
            void ptp_set_2step(unsigned port_idx, bool enable);

            // VLAN configuration for each port and each VID.
            void vlan_reset(bool lockdown = false);     // Revert all settings to default
            u32 vlan_get_mask(u16 vid);                 // Get port-mask for designated VID
            void vlan_set_mask(u16 vid, u32 mask);      // Limit VID to designated ports
            void vlan_set_port(u32 cfg);                // Port settings (see vlan_portcfg)
            void vlan_join(u16 vid, unsigned port);     // Port should join VLAN
            void vlan_leave(u16 vid, unsigned port);    // Port should leave VLAN

            // Read or manipulate the contents of the MAC-address table.
            // All functions return true if successful, false otherwise.
            // Note: When writing, FPGA logic chooses the next available table
            //       index; this parameter is not under software control.
            bool mactbl_read(                           // Read Nth entry from table
                unsigned tbl_idx,                       // Table index to be read
                unsigned& port_idx,                     // Resulting port index
                satcat5::eth::MacAddr& mac_addr);       // Resulting MAC address
            bool mactbl_write(                          // Write new entry to table
                unsigned port_idx,                      // New port index
                const satcat5::eth::MacAddr& mac_addr); // New MAC address
            bool mactbl_clear();                        // Clear table contents
            bool mactbl_learn(bool enable);             // Enable automatic learning?
            void mactbl_log(const char* label);         // Log MAC-table contents

        protected:
            bool mactbl_wait_idle();                    // Wait for MAC-table access

            satcat5::cfg::Register m_reg;               // ConfigBus register space
            u32 m_pri_wridx;                            // Next index in priority table
            u16 m_stats_filter;                         // Filter stats by EtherType
        };
    }
}
