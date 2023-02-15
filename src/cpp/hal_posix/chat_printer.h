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
// Callback object that prints incoming "ChatProto" messages

#pragma once

#include <satcat5/eth_dispatch.h>
#include <satcat5/io_core.h>
#include <string>

namespace satcat5 {
    namespace eth {
        // Prototype for the ChatProto class.
        class ChatProto;
    }

    namespace util {
        // Callback object that prints incoming messages.
        class ChatPrinter final
            : public satcat5::net::Protocol
            , public satcat5::io::Writeable
        {
        public:
            // Attach to the designated ChatProto service.
            ChatPrinter(satcat5::eth::ChatProto* chat, bool loopback=true);
            ~ChatPrinter();

            // Send a message string to all other chat clients.
            void send_message(const std::string& msg);

        private:
            // Pretty formatting for incoming or outgoing messages.
            void print_message(
                const satcat5::eth::MacAddr& from,
                const std::string& msg);

            // Handle incoming data from eth::ChatProto.
            void frame_rcvd(satcat5::io::LimitedRead& rd) override;

            // Writeable endpoint: Accumulate characters from input stream.
            // End-of-packet sends accumulated message to the chat client.
            unsigned get_write_space() const override;
            void write_next(u8 ch);
            bool write_finalize() override;

            // Internal state.
            satcat5::eth::ChatProto* const m_chat;
            std::string m_line;
            bool m_loopback;
        };
    }
}
