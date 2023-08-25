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
// Protocol handler for the Internet Control Message Protocol (ICMP)
//
// ICMP provides various auxiliary services to support IPv4 networks,
// ranging from "ping" (ICMP Echo/Reply) to error reporting (e.g.,
// "Destination host unreachable").

#pragma once

#include <satcat5/net_core.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>

namespace satcat5 {
    namespace ip {
        // Define combined ICMP message codes (type + subtype).
        constexpr u16 ICMP_ECHO_REPLY           = 0x0000;
        constexpr u16 ICMP_UNREACHABLE_NET      = 0x0300;
        constexpr u16 ICMP_UNREACHABLE_HOST     = 0x0301;
        constexpr u16 ICMP_UNREACHABLE_PROTO    = 0x0302;
        constexpr u16 ICMP_UNREACHABLE_PORT     = 0x0303;
        constexpr u16 ICMP_FRAG_REQUIRED        = 0x0304;
        constexpr u16 ICMP_SRC_ROUTE_FAILED     = 0x0305;
        constexpr u16 ICMP_DST_NET_UNKNOWN      = 0x0306;
        constexpr u16 ICMP_DST_HOST_UNKNOWN     = 0x0307;
        constexpr u16 ICMP_SRC_HOST_ISOLATED    = 0x0308;
        constexpr u16 ICMP_NET_PROHIBITED       = 0x0309;
        constexpr u16 ICMP_HOST_PROHIBITED      = 0x030A;
        constexpr u16 ICMP_TOS_NET              = 0x030B;
        constexpr u16 ICMP_TOS_HOST             = 0x030C;
        constexpr u16 ICMP_COMM_PROHIBITED      = 0x030D;
        constexpr u16 ICMP_HOST_PRECEDENCE      = 0x030E;
        constexpr u16 ICMP_PRECEDENCE_CUTOFF    = 0x030F;
        constexpr u16 ICMP_REDIRECT_NET         = 0x0500;
        constexpr u16 ICMP_REDIRECT_HOST        = 0x0501;
        constexpr u16 ICMP_REDIRECT_NET_TOS     = 0x0502;
        constexpr u16 ICMP_REDIRECT_HOST_TOS    = 0x0503;
        constexpr u16 ICMP_ECHO_REQUEST         = 0x0800;
        constexpr u16 ICMP_TTL_EXPIRED          = 0x0B00;
        constexpr u16 ICMP_FRAG_TIMEOUT         = 0x0B01;
        constexpr u16 ICMP_IP_HDR_POINTER       = 0x0C00;
        constexpr u16 ICMP_IP_HDR_OPTION        = 0x0C01;
        constexpr u16 ICMP_IP_HDR_LENGTH        = 0x0C02;
        constexpr u16 ICMP_TIME_REQUEST         = 0x0D00;
        constexpr u16 ICMP_TIME_REPLY           = 0x0E00;

        // ICMP type-codes only (ignoring subtype)
        constexpr u16 ICMP_TYPE_MASK            = 0xFF00;
        constexpr u16 ICMP_TYPE_UNREACHABLE     = 0x0300;   // 0x0300 - 03FF
        constexpr u16 ICMP_TYPE_REDIRECT        = 0x0500;   // 0x0500 - 05FF
        constexpr u16 ICMP_TYPE_TIME_EXCEED     = 0x0B00;   // 0x0B00 - 0BFF
        constexpr u16 ICMP_TYPE_BAD_IP_HDR      = 0x0C00;   // 0x0C00 - 0CFF

        // Bytes required for ICMP error messages.
        constexpr unsigned ICMP_ECHO_BYTES   = 8;

        // Callback object for handling "ping" reponses.
        class PingListener {
        public:
            // Child class MUST override this method.
            virtual void ping_event(
                const satcat5::ip::Addr& from, u32 elapsed_usec) = 0;

        private:
            // Linked list to the next listener object.
            friend satcat5::util::ListCore;
            satcat5::ip::PingListener* m_next;
        };

        // Protocol handler for ICMP messages.
        class ProtoIcmp final : public satcat5::net::Protocol
        {
        public:
            ProtoIcmp(satcat5::ip::Dispatch* iface);
            ~ProtoIcmp() SATCAT5_OPTIONAL_DTOR;

            // Send various error-messages:
            //  "Destination unreachable" (Type 3.x, arg = unused)
            //  "Redirect" (Type 5.x, arg = new address)
            // Note: Readable "src" should contain the first 8 bytes after
            //       the IP header of the frame that triggered this error.
            // Returns true if frame sent successfully, false otherwise.
            bool send_error(
                u16 type, satcat5::io::Readable* src, uint32_t arg = 0);

            // Initiate a ping (Echo request = Type 8.0)
            // Returns true if frame sent successfully, false otherwise.
            bool send_ping(satcat5::ip::Address& dst);

            // Initiate a timestamp request.
            // Returns true if frame sent successfully, false otherwise.
            bool send_timereq(satcat5::ip::Address& dst);

            // Add/remove callback handlers for Ping responses.
            inline void add(satcat5::ip::PingListener* cb)
                {m_listeners.add(cb);}
            inline void remove(satcat5::ip::PingListener* cb)
                {m_listeners.remove(cb);}

        protected:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            bool write_icmp(
                satcat5::io::Writeable* wr,
                unsigned wcount, u16* data);

            satcat5::ip::Dispatch* const m_iface;
            satcat5::util::List<satcat5::ip::PingListener> m_listeners;
        };
    }
}
