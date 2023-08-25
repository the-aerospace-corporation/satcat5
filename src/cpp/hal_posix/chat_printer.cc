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
// Console application for viewing Chat/Log messages
//
// The application prompts the user to select an interface, then prints each
// received Chat/Log message until the user hits Ctrl+C.

#include <hal_posix/chat_printer.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/eth_chat.h>
#include <iostream>

using satcat5::util::ChatPrinter;

ChatPrinter::ChatPrinter(satcat5::eth::ChatProto* chat, bool loopback)
    : satcat5::net::Protocol(satcat5::net::TYPE_NONE)
    , m_chat(chat)
    , m_loopback(loopback)
{
    m_chat->set_callback(this);
}

ChatPrinter::~ChatPrinter()
{
    m_chat->set_callback(0);
}

void ChatPrinter::frame_rcvd(satcat5::io::LimitedRead& rd)
{
    std::string msg;
    while (rd.get_read_ready())
        msg.push_back((char)rd.read_u8());
    print_message(m_chat->reply_mac(), msg);
}

void ChatPrinter::print_message(
    const satcat5::eth::MacAddr& from, const std::string& msg)
{
    // Cross-platform: printf(...) works in cases where cout fails
    // silently, even after calling cout.flush().  May be unicode-related?
    std::string from_str = satcat5::log::format(from);
    printf("From: %s\n%s\n\n", from_str.c_str(), msg.c_str());
}

void ChatPrinter::send_message(const std::string& msg)
{
    if (m_loopback)
        print_message(m_chat->local_mac(), msg);
    m_chat->send_text(satcat5::eth::MACADDR_BROADCAST,
        msg.length(), msg.c_str());
}

bool ChatPrinter::write_finalize()
{
    if (m_line.length() > 0) {
        send_message(m_line);
        m_line.clear();
        return true;
    } else {
        return false;
    }
}

unsigned ChatPrinter::get_write_space() const
{
    // Always ready to accept new data.
    return 1000;
}

void ChatPrinter::write_next(u8 ch)
{
    m_line.push_back(ch);
}
