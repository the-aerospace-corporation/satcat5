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
// Controller for a remote ConfigBus, connected over network
//
// The file implements a ConfigBus wrapper that is connected over LAN/WAN.
// Write and read operations send a command packet to the designated address
// and wait for a response.  The protocol is the client-side counterpart to
// the server implemented in "cfgbus_host_eth.vhd" or "net_cfgbus.h".
//
// Implementations are provided for raw-Ethernet and UDP networks.
//
// Reads are always blocking; writes may block depending on the flow-control
// mode.  Blocking operations call poll::service() in a loop to ensure that
// replies are processed and delivered.  The timeout is adjustable with a
// default of 50 msec, which is adequate on any reasonable LAN.
//
// Refer to cfgbus_host_eth.vhd for details of the packet format.
//

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/net_core.h>
#include <satcat5/polling.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace cfg {
        class ConfigBusRemote
            : public satcat5::cfg::ConfigBus
            , public satcat5::net::Protocol
            , public satcat5::poll::Timer
        {
        public:
            // Basic read and write operations (ConfigBus API).
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& rdval) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

            // Bulk read and write operations.
            // "Array" indicates auto-increment mode (regaddr, regaddr+1, ...)
            // "Repeat" indicates no-increment mode (same register N times)
            satcat5::cfg::IoStatus read_array(
                unsigned regaddr, unsigned count, u32* result) override;
            satcat5::cfg::IoStatus read_repeat(
                unsigned regaddr, unsigned count, u32* result) override;
            satcat5::cfg::IoStatus write_array(
                unsigned regaddr, unsigned count, const u32* data) override;
            satcat5::cfg::IoStatus write_repeat(
                unsigned regaddr, unsigned count, const u32* data) override;

            // Adjust read/write timeout (0 = Non-blocking)
            void set_timeout_rd(unsigned usec) {m_timeout_rd = usec;}
            void set_timeout_wr(unsigned usec) {m_timeout_wr = usec;}

            // Adjust polling rate for interrupt status (0 = None).
            void set_irq_polling(unsigned msec) {timer_every(msec);}

        protected:
            // Create a link to the designated remote address, with commands
            // and replies routed through the designated Dispatcher object.
            ConfigBusRemote(
                satcat5::net::Address* dst,             // Remote iface + address
                const satcat5::net::Type& ack,          // Ack type parameter
                satcat5::util::GenericTimer* timer);    // Reference for timeouts
            ~ConfigBusRemote() SATCAT5_OPTIONAL_DTOR;

            // Callback for incoming reply frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Callback for timer events.
            void timer_event() override;

            // Send, then wait if requested.
            satcat5::cfg::IoStatus send_and_wait(
                u8 opcode, unsigned addr,
                unsigned len, const u32* ptr, unsigned timeout);

            // Send the specified opcode.
            bool send_command(
                u8 opcode, unsigned addr,
                unsigned len, const u32* ptr);

            // Busywait until response is received.
            satcat5::cfg::IoStatus wait_response(unsigned timeout);

            // MAC address for the remote interface.
            satcat5::net::Address* const m_dst;

            // Timer for measuring timeouts.
            satcat5::util::GenericTimer* const m_timer;
            unsigned m_timeout_rd;
            unsigned m_timeout_wr;

            // Stored state for pending responses.
            u32 m_status;
            u8 m_sequence;
            u8 m_response_opcode;
            u32* m_response_ptr;
            unsigned m_response_len;
            satcat5::cfg::IoStatus m_response_status;
        };
    }

    // Wrappers for commonly used network interfaces:
    namespace eth {
        class ConfigBus final
            : protected satcat5::eth::AddressContainer
            , public satcat5::cfg::ConfigBusRemote
        {
        public:
            ConfigBus(
                satcat5::eth::Dispatch* iface,          // Network interface
                satcat5::util::GenericTimer* timer);    // Reference for timeouts

            void connect(const satcat5::eth::MacAddr& dst);

            inline void close()             {m_addr.close();}
            inline bool ready() const       {return m_addr.ready();}
        };
    }

    namespace udp {
        class ConfigBus final
            : protected satcat5::udp::AddressContainer
            , public satcat5::cfg::ConfigBusRemote
        {
        public:
            explicit ConfigBus(
                satcat5::udp::Dispatch* udp);           // UDP interface

            void connect(
                const satcat5::ip::Addr& dstaddr);      // Remote address

            inline void close()             {m_addr.close();}
            inline bool ready() const       {return m_addr.ready();}
        };
    }
}
