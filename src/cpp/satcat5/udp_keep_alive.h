//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Send and receive keep-alive messages.

#pragma once
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace udp {
        //! Send and receive keep-alive messages.
        //!
        //! In some networks, idle endpoints may be expected to periodically
        //! send UDP messages to a designated UDP port, to indicate that the
        //! connection is still valid.  Recipients should immediately discard
        //! such messages with no further action.
        //!
        //! This class binds the incoming UDP port, to prevent false-alarm
        //! "port-unreachable" ICMP errors from being sent in response.
        //!
        //! Optionally, this class may also be used to send keep-alive messages,
        //! defaulting to the broadcast addresss (255.255.255.255).  To enable
        //! this feature, call `timer_once` or `timer_every`.
        class KeepAlive
            : public satcat5::net::Protocol
            , public satcat5::poll::Timer {
        public:
            //! Bind this object to a network interface and UDP port.
            //! \param iface    UDP network interface.
            //! \param port     UDP port number (incoming + outgoing).
            //! \param label    Optional message for each outgoing packet.
            explicit KeepAlive(
                satcat5::udp::Dispatch* iface,
                satcat5::udp::Port port,
                const char* label = nullptr);
            ~KeepAlive();

            //! Connect to a specific destination address.
            //! During object creation, the destination defaults to broadcast
            //! (255.255.255.255). This method changes the destination address.
            void connect(
                const satcat5::ip::Addr& dstaddr,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);

            //! Immediately send a keep-alive, with an optional message.
            void send_now(const char* msg);

        protected:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            satcat5::udp::Address m_addr;
            const char* const m_label;
        };
    }
}
