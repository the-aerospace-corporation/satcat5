//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Protocol handler for a simple text-messaging protocol
//
// This file implements a handful of classes relating to the simple as-hoc
// text-messaging protocol used by some SatCat5 example designs.  (Such as
// "examples/arty_managed" and "test/chat_client".)

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

        // Protocol handler for incoming messages.
        class ChatProto final
            : public satcat5::eth::Protocol
            , public satcat5::poll::Timer
        {
        public:
            ChatProto(
                satcat5::eth::Dispatch* dispatch,
                const char* username);
            #if SATCAT5_VLAN_ENABLE
            ChatProto(
                satcat5::eth::Dispatch* dispatch,
                const char* username,
                const satcat5::eth::VlanTag& vtag);
            #endif
            ~ChatProto() {}

            // Set callback for incoming messages.
            inline void set_callback(satcat5::net::Protocol* callback)
                {m_callback = callback;}

            // Send various message types.
            void send_heartbeat();
            void send_text(
                const satcat5::eth::MacAddr& dst,
                unsigned nbytes, const char* msg);
            void send_data(
                const satcat5::eth::MacAddr& dst,
                unsigned nbytes, const void* msg);

            // Open a reply to the sender of the most recent message.
            satcat5::io::Writeable* open_reply(unsigned len);

            // As "open_reply", but to any destination address.
            satcat5::io::Writeable* open_text(
                const satcat5::eth::MacAddr& dst, unsigned len);

            // Accessors for local and reply addresses.
            satcat5::eth::MacAddr local_mac() const;
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

        // Service for forwarding Log events as text messages.
        class LogToChat final : public satcat5::log::EventHandler {
        public:
            explicit LogToChat(
                satcat5::eth::ChatProto* dst,
                const satcat5::eth::MacAddr& addr = satcat5::eth::MACADDR_BROADCAST);
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::eth::ChatProto* const m_chat;
            const satcat5::eth::MacAddr m_addr;
        };

        // Service for echoing ChatProto text messages.
        class ChatEcho final : public satcat5::net::Protocol {
        public:
            ChatEcho(satcat5::eth::ChatProto* service);
            ~ChatEcho() SATCAT5_OPTIONAL_DTOR;

        protected:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            satcat5::eth::ChatProto* const m_chat;
        };
    }
}
