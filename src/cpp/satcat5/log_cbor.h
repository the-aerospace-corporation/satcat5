//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
// CBOR-encoded network logging
//
// This file defines a log-to-network system, where each log message is
// encoded using CBOR (IETF-RFC-8949).  Variations using raw-Ethernet and
// UDP are provided.  Both default to broadcast mode, but can be changed
// to unicast by calling the connect(...) method.
//
// The encoding used here is compatible with the "Diagnostic Logging"
// message defined in the "Slingshot Payload Manual" (ATR-2022-01270).
//
// For the simpler encoding used in example designs, see "eth_chat.h".
// (Especially eth::LogToChat, which implements the same logging API.)
//
// The minimum priority level can be adjusted with set_min_priority to
// ignore messages with a lower priority.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/log.h>
#include <satcat5/types.h>
#include <satcat5/udp_core.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE

namespace satcat5 {
    namespace log {
        // Read CBOR-formatted network messages and copy to the local log.
        // (See wrappers below for raw-Ethernet or UDP transport layer.)
        class FromCbor : public satcat5::net::Protocol {
        protected:
            // Only children can safely access constructor/destructor.
            FromCbor(
                satcat5::net::Dispatch* src,        // Incoming message interface
                satcat5::net::Type filter);         // Incoming message type
            ~FromCbor() SATCAT5_OPTIONAL_DTOR;

            // Event handler for incoming messages.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Pointer to the interface object.
            satcat5::net::Dispatch* const m_src;
        public:
            // Set the minimum level (priority). Messages below this level will be ignored.
            void set_min_priority(s8 priority) {m_min_priority = priority;}
        private:
            s8 m_min_priority = satcat5::log::DEBUG;  // default to handle everything
        };

        // Write local logs to a CBOR-formatted network message.
        // (See wrappers below for raw-Ethernet or UDP transport layer.)
        class ToCbor : public satcat5::log::EventHandler {
        protected:
            // Only children can safely access constructor/destructor.
            ToCbor(
                satcat5::datetime::Clock* clk,      // System clock (or NULL)
                satcat5::net::Address* dst);        // Destination interface
            ~ToCbor() {}

            // Implement the required "log_event" handler.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

            // Date/time reference.
            satcat5::datetime::Clock* const m_clk;

            // Destination interface and address.
            satcat5::net::Address* const m_dst;
        public:
            // Set the minimum level (priority). Messages below this level will be ignored.
            void set_min_priority(s8 priority) {m_min_priority = priority;}
        private:
            s8 m_min_priority = satcat5::log::DEBUG;  // default to handle everything
        };
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        // Receive CBOR-formatted raw-Ethernet frames.
        class LogFromCbor final
            : public satcat5::log::FromCbor
        {
        public:
            // Constructor binds to a specific incoming EtherType.
            LogFromCbor(
                satcat5::eth::Dispatch* iface,      // Ethernet interface
                const satcat5::eth::MacType& typ);  // Incoming EtherType
            ~LogFromCbor() {}
        };

        // Send CBOR-formatted raw-Ethernet frames.
        class LogToCbor final
            : public satcat5::eth::AddressContainer
            , public satcat5::log::ToCbor
        {
        public:
            // Constructor defaults to broadcast address.
            LogToCbor(
                satcat5::datetime::Clock* clk,      // System clock (or NULL)
                satcat5::eth::Dispatch* eth,        // Ethernet interface
                const satcat5::eth::MacType& typ);  // Destination EtherType
            ~LogToCbor() {}

            // Set the destination address.
            inline void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type)
                { m_addr.connect(addr, type); }
            inline void close()
                { m_addr.close(); }
        };
    }

    namespace udp {
        // Receive CBOR-formatted UDP packets.
        class LogFromCbor final
            : public satcat5::log::FromCbor
        {
        public:
            // Constructor binds to a specific incoming UDP port.
            LogFromCbor(
                satcat5::udp::Dispatch* iface,      // UDP interface
                const satcat5::udp::Port& port);    // Incoming UDP port
            ~LogFromCbor() {}
        };

        // Send CBOR-formatted UDP packets.
        class LogToCbor final
            : public satcat5::udp::AddressContainer
            , public satcat5::log::ToCbor
        {
        public:
            // Constructor defaults to broadcast address.
            LogToCbor(
                satcat5::datetime::Clock* clk,      // System clock (or NULL)
                satcat5::udp::Dispatch* udp,        // UDP interface
                const satcat5::udp::Port& dstport); // Destination port
            ~LogToCbor() {}

            // Set the destination address.
            inline void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport)
                { m_addr.connect(dstaddr, dstport, 0);}
            inline void close()
                { m_addr.close(); }
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
