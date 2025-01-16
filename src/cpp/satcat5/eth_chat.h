//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Protocol handler for a simple text-messaging protocol

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/log.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace eth {
        constexpr satcat5::eth::MacType
            ETYPE_CHAT_HEARTBEAT    = {0x999B},
            ETYPE_CHAT_TEXT         = {0x999C},
            ETYPE_CHAT_DATA         = {0x999D};

        //! Protocol handler for a simple text-messaging protocol
        //! This class implements a simple as-hoc text-messaging protocol
        //! using raw Ethernet frames. This is used by some SatCat5 example
        //! designs, such as "examples/arty_managed" and "test/chat_client".
        //! This class implements both transmit and receive functions.
        class ChatProto final
            : public satcat5::eth::Protocol
            , public satcat5::poll::Timer
        {
        public:
            //! Bind this handler to a specified Ethernet interface.
            ChatProto(
                satcat5::eth::Dispatch* dispatch,
                const char* username,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE);
            ~ChatProto() {}

            //! Set callback for processing incoming messages.
            inline void set_callback(satcat5::net::Protocol* callback)
                {m_callback = callback;}

            //! Send a heartbeat message indicating our presence on the LAN.
            void send_heartbeat();
            //! Send a human-readable text message.
            void send_text(
                const satcat5::eth::MacAddr& dst,
                unsigned nbytes, const char* msg);
            //! Send machine-readable data.
            //! In example designs, this is used for throughput stress-tests
            //! with data that isn't suitable for human-readable displays.
            void send_data(
                const satcat5::eth::MacAddr& dst,
                unsigned nbytes, const void* msg);

            //! Open a reply to the sender of the most recent message.
            satcat5::io::Writeable* open_reply(unsigned len);

            //! As "open_reply", but to any destination address.
            satcat5::io::Writeable* open_text(
                const satcat5::eth::MacAddr& dst, unsigned len);

            //! Get the local device's source MAC address.
            satcat5::eth::MacAddr local_mac() const;
            //! Source MAC address of the most recent received message.
            satcat5::eth::MacAddr reply_mac() const;

        protected:
            satcat5::io::Writeable* open_inner(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& typ,
                unsigned msg_bytes);
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            const satcat5::net::Type m_reply_type;
            const char* const m_username;
            const unsigned m_userlen;
            const satcat5::eth::VlanTag m_vtag;
            satcat5::net::Protocol* m_callback;
        };

        //! Service for forwarding Log events as text messages.
        //! This class implements the `log::EventHandler` API, and forwards
        //! each generated `Log` message to the designated `ChatProto` object.
        //! \see satcat5::eth::ChatProto
        class LogToChat final : public satcat5::log::EventHandler {
        public:
            //! Bind to the designated `ChatProto` object.
            //! Optionally set destination-MAC address, defaulting to broadcast.
            explicit LogToChat(
                satcat5::eth::ChatProto* dst,
                const satcat5::eth::MacAddr& addr = satcat5::eth::MACADDR_BROADCAST);

            //! Event handler for the `log::EventHandler` API.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::eth::ChatProto* const m_chat;
            const satcat5::eth::MacAddr m_addr;
        };

        //! Service for echoing ChatProto text messages.
        //! For each received `ChatProto` message, send a reply containing
        //! prefix "You said..." followed by the received message contents.
        //! To avoid amplification with multiple `ChatEcho` services, it
        //! always replies to the sender, never to the broadcast address.
        //! \see satcat5::eth::ChatProto
        class ChatEcho final : public satcat5::net::Protocol {
        public:
            //! Bind to the designated `ChatProto` object.
            ChatEcho(satcat5::eth::ChatProto* service);
            ~ChatEcho() SATCAT5_OPTIONAL_DTOR;

        protected:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            satcat5::eth::ChatProto* const m_chat;
        };
    }
}
