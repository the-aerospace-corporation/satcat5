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

        protected:
            void send_inner(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& typ,
                unsigned nbytes, const void* msg);
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
                satcat5::log::EventHandler* cc = 0);
            ~LogToChat() SATCAT5_OPTIONAL_DTOR;
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

        private:
            satcat5::eth::ChatProto* const m_dst;
            satcat5::log::EventHandler* const m_cc;
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
