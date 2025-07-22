//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Dispatch API for incoming L2 and L3 PTP messages.

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_header.h>
#include <satcat5/ptp_interface.h>
#include <satcat5/ptp_time.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace ptp {
        //! Destination selection for ptp::Dispatch.
        enum class DispatchTo {
            BROADCAST_L2,       // L2/Ethernet broadcast
            BROADCAST_L3,       // L3/UDP broadcast
            REPLY,              // To current reply address
            STORED,             // To stored unicast address
        };

        //! Dispatch and formatting for L2 and L3 PTP messages.
        //! The ptp::Client class uses this helper to send and receive messages.
        //!
        //! Because of the need for precision timestamps, the Precision Time
        //! Protocol (PTP / IEEE-1588) must often bypass the normal network
        //! stack. This class provides a minimal API used by ptp::Client,
        //! as well as basic support for:
        //!  * Sending messages to a specific L2 address (unicast or broadcast).
        //!  * Sending messages to a specific L3 address (unicast or multicast).
        //!  * Sending messages as a reply to the most recent message.
        //!
        //! Network interfaces with PTP support (e.g., port::MailMap) should
        //! inherit from ptp::Interface so they can be used with this class.
        //!
        //! The constructor requires a pointer to an ip::Dispatch object to
        //! correctly configure the local MAC- and IP-address. It is otherwise
        //! unused, since intermediate buffering of incoming and outgoing
        //! packets is incompatible with PTP operations.
        class Dispatch : public satcat5::poll::OnDemand {
        public:
            //! Attach this object to the network port and IP stack.
            explicit Dispatch(
                satcat5::ptp::Interface* iface,
                satcat5::ip::Dispatch* ip);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Network interface accessors:
            inline satcat5::ip::Dispatch* iface() const
                { return m_ip; }                // IP interface
            inline satcat5::eth::MacAddr macaddr() const
                { return m_ip->macaddr(); }     // Source MAC address

            //! Set the callback object for incoming messages.
            inline void ptp_callback(satcat5::ptp::Client* client)
                { m_callback = client; }

            //! Accessors for one-step and two-step timestamps.
            //! \see "ptp_interface.h" for more information.
            //!@{
            inline satcat5::ptp::Time ptp_time_now()
                { return m_iface->ptp_time_now(); }
            inline satcat5::ptp::Time ptp_tx_start()
                { return m_iface->ptp_tx_start(); }
            inline satcat5::ptp::Time ptp_tx_timestamp()
                { return m_iface->ptp_tx_timestamp(); }
            inline satcat5::ptp::Time ptp_rx_timestamp()
                { return m_iface->ptp_rx_timestamp(); }
            //!@}

            //! Send a PTP message to the designated address(es).
            //! Dispatch writes packet header, caller writes PTP message.
            satcat5::io::Writeable* ptp_send(
                satcat5::ptp::DispatchTo where, unsigned num_bytes, u8 ptp_msg_type);

            //! Set the address for use with DispatchTo::STORED.
            //!@{
            void store_reply_addr();    // Reply to most recent sender.
            void store_addr(            // Send to a specific L2/L3 address.
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip = satcat5::ip::ADDR_NONE,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);
            //!@}

        protected:
            // Incoming message notification.
            void poll_demand() override;

            // Helper functions for assigning header parameters
            satcat5::eth::Header get_dst_eth(satcat5::ptp::DispatchTo addr) const;
            satcat5::udp::Port get_dst_port(u8 ptp_msg_type) const;
            satcat5::ip::Addr get_dst_ip(satcat5::ptp::DispatchTo addr) const;

            // Pointers to interfaces and event handlers.
            satcat5::ptp::Interface* const m_iface;
            satcat5::ip::Dispatch* const m_ip;
            satcat5::ptp::Client* m_callback;

            // Internal configuration.
            satcat5::eth::MacAddr m_reply_mac;
            satcat5::eth::MacAddr m_stored_mac;
            satcat5::eth::VlanTag m_reply_vtag;
            satcat5::eth::VlanTag m_stored_vtag;
            satcat5::ip::Addr m_reply_ip;
            satcat5::ip::Addr m_stored_ip;
        };
    }
}
