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
// Basic type definitions for Internet Protocol v4 packets (IPv4)

#pragma once

#include <satcat5/io_core.h>

namespace satcat5 {
    namespace ip {
        // IPv4 address is a 32-bit unsigned integer.
        struct Addr {
            u32 value;

            constexpr Addr() : value(0) {}
            constexpr Addr(u32 ip) : value(ip) {}
            constexpr Addr(u16 msb, u16 lsb)
                : value(65536ul * msb + lsb) {}
            constexpr Addr(u8 a, u8 b, u8 c, u8 d)
                : value(16777216ul * a + 65536ul * b + 256ul * c + d) {}

            inline bool operator==(const satcat5::ip::Addr& other) const
                {return value == other.value;}
            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u32(value);}
            inline bool read_from(satcat5::io::Readable* rd)
                {value = rd->read_u32(); return true;}

            bool is_multicast() const;
        };

        // UDP and TCP ports are both 16-bit unsigned integers.
        struct Port {
            u16 value;

            constexpr Port(u16 port) : value(port) {}

            inline bool operator==(const satcat5::ip::Port& other) const
                {return value == other.value;}
            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u16(value);}
            inline bool read_from(satcat5::io::Readable* rd)
                {value = rd->read_u16(); return true;}
        };

        // Minimum and maximum IP header length:
        constexpr unsigned HDR_MIN_WORDS        = 5;
        constexpr unsigned HDR_MIN_SHORTS       = 2 * HDR_MIN_WORDS;
        constexpr unsigned HDR_MIN_BYTES        = 4 * HDR_MIN_WORDS;
        constexpr unsigned HDR_MAX_WORDS        = 15;
        constexpr unsigned HDR_MAX_SHORTS       = 2 * HDR_MAX_WORDS;
        constexpr unsigned HDR_MAX_BYTES        = 4 * HDR_MAX_WORDS;

        // Commonly used IP-addresses and other constants:
        constexpr satcat5::ip::Addr ADDR_NONE   = 0;
        constexpr satcat5::ip::Port PORT_NONE   = 0;
        constexpr u8 PROTO_ICMP                 = 0x01;
        constexpr u8 PROTO_IGMP                 = 0x02;
        constexpr u8 PROTO_TCP                  = 0x06;
        constexpr u8 PROTO_UDP                  = 0x11;

        // Structure for holding an IPv4 Header.
        struct Header {
            u16 data[HDR_MAX_SHORTS];

            unsigned ihl() const {return (data[0] >> 8) & 0x0F;}
        };

        // Calculate the IP header checksum over a block of data.
        // (To verify: Returned value should be equal to zero.)
        u16 checksum(unsigned wcount, const u16* data);
    }
}
