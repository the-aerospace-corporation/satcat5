//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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
// Type definitions for Ethernet frames and protocol handlers
//
// This file defines various data structures relating to Ethernet frames
// and their headers, including the MAC address and EtherType fields.
//
// Note: Due to byte-alignment and byte-ordering issues, direct use of
//       write_bytes and read_bytes on header data structures is not
//       recommended.  Please use the provided write and read methods.
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/types.h>

// Enable 802.1Q VLAN tagging?
#ifndef SATCAT5_VLAN_ENABLE
#define SATCAT5_VLAN_ENABLE 1
#endif

namespace satcat5 {
    namespace eth {
        // An Ethernet MAC address (with serializable interface).
        struct MacAddr {
            u8 addr[6];

            bool operator==(const satcat5::eth::MacAddr& other) const;
            bool operator<(const satcat5::eth::MacAddr& other) const;
            inline bool operator!=(const satcat5::eth::MacAddr& other) const
                {return !operator==(other);}

            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_bytes(6, addr);}
            inline bool read_from(satcat5::io::Readable* rd)
                {return rd->read_bytes(6, addr);}
        };

        // EtherType field (uint16) is used a protocol-ID [1536..65535].
        // Use as a "length" field [64..1500] is supported but not recommended.
        // See also: https://en.wikipedia.org/wiki/EtherType
        struct MacType {
            u16 value;

            inline bool operator==(const satcat5::eth::MacType& other) const
                {return value == other.value;}
            inline bool operator!=(const satcat5::eth::MacType& other) const
                {return value != other.value;}
            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u16(value);}
            inline bool read_from(satcat5::io::Readable* rd)
                {value = rd->read_u16(); return true;}
        };

        // Header contents for an 802.1Q Virtual-LAN tag.
        // See also: https://en.wikipedia.org/wiki/IEEE_802.1Q
        struct VlanTag {
            u16 value;

            inline u16 vid() const {return ((value >> 0)  & 0xFFF);}
            inline u16 dei() const {return ((value >> 12) & 0x1);}
            inline u16 pcp() const {return ((value >> 13) & 0x7);}

            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u16(value);}
            inline bool read_from(satcat5::io::Readable* rd)
                {value = rd->read_u16(); return true;}
        };

        // An Ethernet header (destination, source, and EtherType)
        // See also: https://en.wikipedia.org/wiki/Ethernet_frame
        struct Header {
            satcat5::eth::MacAddr dst;
            satcat5::eth::MacAddr src;
            satcat5::eth::MacType type;
            #if SATCAT5_VLAN_ENABLE
            satcat5::eth::VlanTag vtag;
            #endif

            // Write Ethernet header to the designated stream.
            void write_to(satcat5::io::Writeable* wr) const;

            // Read Ethernet header from the designated stream.
            // (Returns true on success, false otherwise.)
            bool read_from(satcat5::io::Readable* rd);
        };

        // Commonly used MAC addresses and EtherTypes.
        constexpr satcat5::eth::MacAddr MACADDR_NONE =
            {{0x00, 0x00, 0x00, 0x00, 0x00, 0x00}};
        constexpr satcat5::eth::MacAddr MACADDR_BROADCAST =
            {{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF}};

        constexpr satcat5::eth::MacType
            ETYPE_NONE          = {0x0000},
            ETYPE_IPV4          = {0x0800},
            ETYPE_ARP           = {0x0806},
            ETYPE_CFGBUS_CMD    = {0x5C01},
            ETYPE_CFGBUS_ACK    = {0x5C02},
            ETYPE_SLINGSHOT_LOG = {0x5C03},
            ETYPE_VTAG          = {0x8100},
            ETYPE_FLOWCTRL      = {0x8808},
            ETYPE_PTP           = {0x88F7};

        constexpr satcat5::eth::VlanTag
            VTAG_NONE           = {0x0000},     // Untagged frame
            VTAG_DEFAULT        = {0x0001},     // Default ports use VID = 1
            VTAG_PRIORITY1      = {0x2000},     // Set priority only (1-7)
            VTAG_PRIORITY2      = {0x4000},
            VTAG_PRIORITY3      = {0x6000},
            VTAG_PRIORITY4      = {0x8000},
            VTAG_PRIORITY5      = {0xA000},
            VTAG_PRIORITY6      = {0xC000},
            VTAG_PRIORITY7      = {0xE000};

        // Min/max range for VLAN identifier (VID)
        constexpr u16 VID_NONE  = 0;    // Default / placeholder
        constexpr u16 VID_MIN   = 1;    // Start of user VID range
        constexpr u16 VID_MAX   = 4094; // End of user VID range
        constexpr u16 VID_RSVD  = 4095; // Reserved
    }
}
