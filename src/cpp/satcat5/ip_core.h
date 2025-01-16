//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Basic type definitions for Internet Protocol v4 packets (IPv4)

#pragma once

#include <satcat5/io_core.h>

namespace satcat5 {
    namespace ip {
        // IPv4 address is a 32-bit unsigned integer.
        struct Addr {
            // Raw access to the underlying representation.
            u32 value;

            // Constructors.
            constexpr Addr()
                : value(0) {}
            constexpr Addr(u32 ip)  // NOLINT
                : value(ip) {}
            constexpr Addr(u16 msb, u16 lsb)
                : value(65536ul * msb + lsb) {}
            constexpr Addr(u8 a, u8 b, u8 c, u8 d)
                : value(16777216ul * a + 65536ul * b + 256ul * c + d) {}

            // Commonly used operators.
            constexpr bool operator==(const satcat5::ip::Addr& other) const
                {return value == other.value;}
            constexpr bool operator!=(const satcat5::ip::Addr& other) const
                {return value != other.value;}
            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u32(value);}
            inline bool read_from(satcat5::io::Readable* rd)
                {value = rd->read_u32(); return true;}
            constexpr satcat5::ip::Addr operator+(unsigned offset) const
                {return satcat5::ip::Addr(value + (u32)offset);}

            // Log formatting.
            void log_to(satcat5::log::LogBuffer& wr) const;

            // Tests for various reserved address ranges:
            bool is_broadcast() const;  // Limited broadcast (255.255.255.255)
            bool is_multicast() const;  // IP multicast (224.*.*.*)
            bool is_reserved() const;   // Reserved blocks (0.*.*.* or 127.*.*.*)
            bool is_unicast() const;    // Any normal single-destination address
            bool is_valid() const;      // Any nonzero address
        };

        // CIDR "prefix" is the number of leading ones in the subnet mask.
        constexpr u32 cidr_prefix(unsigned npre) {
            return (npre ? ~((0x80000000 >> (npre-1)) - 1) : 0);
        }

        // IPv4 subnet masks share functionality with a basic address,
        // but are constructed differently to match common conventions.
        struct Mask : public satcat5::ip::Addr {
            constexpr Mask()
                : Addr() {}
            constexpr Mask(unsigned npre)  // NOLINT
                : Addr(satcat5::ip::cidr_prefix(npre)) {}
            constexpr Mask(u8 a, u8 b, u8 c, u8 d)
                : Addr(a, b, c, d) {}
            constexpr Mask(const satcat5::ip::Addr& addr)  // NOLINT
                : Addr(addr.value) {}

            // Convert this subnet-mask to a CIDR prefix length.
            // (Undefined if this mask is not a valid CIDR subnet.)
            unsigned prefix() const;
        };

        // An IPv4 subnet consists of a base address and a subnet mask.
        struct Subnet {
            // Raw access to the underlying representation.
            satcat5::ip::Addr addr;
            satcat5::ip::Mask mask;

            // Does this subnet contain the given address?
            constexpr bool contains(const satcat5::ip::Addr& other) const
                {return (addr.value & mask.value) == (other.value & mask.value);}

            // Commonly used operators.
            constexpr bool operator==(const satcat5::ip::Addr& other) const
                {return (addr == other) && (mask == Mask(32));}
            constexpr bool operator==(const satcat5::ip::Subnet& other) const
                {return (addr == other.addr) && (mask == other.mask);}
            constexpr bool operator!=(const satcat5::ip::Subnet& other) const
                {return (addr != other.addr) || (mask != other.mask);}

            // Get the CIDR prefix length for this subnet.
            inline unsigned prefix() const
                {return mask.prefix();}

            // Log formatting.
            void log_to(satcat5::log::LogBuffer& wr) const;
        };

        // UDP and TCP ports are both 16-bit unsigned integers.
        struct Port {
            // Raw access to the underlying representation.
            u16 value;

            // Constructor.
            constexpr Port(u16 port) : value(port) {}   // NOLINT

            // Commonly used operators.
            constexpr bool operator==(const satcat5::ip::Port& other) const
                {return value == other.value;}
            constexpr bool operator!=(const satcat5::ip::Port& other) const
                {return value != other.value;}
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
        constexpr satcat5::ip::Mask MASK_NONE   = 0;    // The entire Internet
        constexpr satcat5::ip::Mask MASK_8      = 8;    // 192.*.*.*
        constexpr satcat5::ip::Mask MASK_16     = 16;   // 192.168.*.*
        constexpr satcat5::ip::Mask MASK_24     = 24;   // 192.168.0.*
        constexpr satcat5::ip::Mask MASK_32     = 32;   // 192.168.0.123
        constexpr satcat5::ip::Port PORT_NONE   = 0;
        constexpr satcat5::ip::Addr ADDR_BROADCAST
            = satcat5::ip::Addr(255, 255, 255, 255);
        constexpr satcat5::ip::Addr ADDR_LOOPBACK
            = satcat5::ip::Addr(127, 0, 0, 1);
        constexpr satcat5::ip::Subnet DEFAULT_ROUTE
            = {ADDR_NONE, MASK_NONE};
        constexpr satcat5::ip::Subnet UDP_MULTICAST
            = {Addr(224, 0, 0, 0), Mask(4)};

        constexpr u8 PROTO_ICMP                 = 0x01;
        constexpr u8 PROTO_IGMP                 = 0x02;
        constexpr u8 PROTO_TCP                  = 0x06;
        constexpr u8 PROTO_UDP                  = 0x11;

        // Structure for holding an IPv4 Header.
        // For creating new headers, see ip::Dispatch::next_header(...)
        struct Header {
            // Raw access to the underlying header contents.
            u16 data[HDR_MAX_SHORTS];

            // Accessors for specific sub-fields.
            // See also: https://en.wikipedia.org/wiki/Internet_Protocol_version_4#Header
            constexpr unsigned ver() const              // Header version (i.e., "4")
                {return (data[0] >> 12) & 0x0F;}
            constexpr unsigned ihl() const              // Header length (4-byte words)
                {return (data[0] >> 8) & 0x0F;}
            constexpr unsigned len_total() const        // Total bytes including header
                {return data[1];}
            constexpr u16 id() const                    // Identifier / sequence number
                {return data[2];}
            constexpr u16 frg() const                   // Fragment offset
                {return data[3] & 0xBFFF;}
            constexpr unsigned len_inner() const        // Inner bytes excluding header
                {return len_total() - 4*ihl();}
            constexpr u8 ttl() const                    // Time to Live (TTL)
                {return (u8)(data[4] >> 8);}
            constexpr u8 proto() const                  // Inner protocol (UDP/TCP/etc.)
                {return (u8)(data[4] & 0x00FF);}
            constexpr u16 chk() const                   // Checksum (incoming only)
                {return data[5];}
            constexpr satcat5::ip::Addr src() const     // Source address
                {return satcat5::ip::Addr(data[6], data[7]);}
            constexpr satcat5::ip::Addr dst() const     // Destination address
                {return satcat5::ip::Addr(data[8], data[9]);}

            // Write IPv4 header to the designated stream.
            void write_to(satcat5::io::Writeable* wr) const;

            // Read a partial IPv4 header from the designated stream.
            // First 20 bytes contains all fields except options (IHL > 5).
            // (Returns true for valid header ignoring checksum, false otherwise.)
            bool read_core(satcat5::io::Readable* rd);  // Core header (first 20 bytes)

            // Read an entire IPv4 header from the designated stream.
            // (Returns true for valid header+checksum, false otherwise.)
            bool read_from(satcat5::io::Readable* rd);  // Entire header (up to 64 bytes)
        };

        // Calculate the IP header checksum over a block of data.
        // (To verify: Returned value should be equal to zero.)
        u16 checksum(unsigned wcount, const u16* data, u16 prev = UINT16_MAX);
    }
}
