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

#include <satcat5/eth_chat.h>
#include <satcat5/eth_dispatch.h>
#include <cstring>

namespace eth = satcat5::eth;
namespace net = satcat5::net;
using eth::ChatEcho;
using eth::ChatProto;
using eth::LogToChat;
using satcat5::io::LimitedRead;
using satcat5::io::Writeable;

ChatProto::ChatProto(
        eth::Dispatch* dispatch,
        const char* username)
    : eth::Protocol(dispatch, eth::ETYPE_CHAT_TEXT)
    , m_reply_type(eth::ETYPE_CHAT_TEXT.value)
    , m_username(username)
    , m_userlen(strlen(username))
    , m_vtag(eth::VTAG_NONE)
    , m_callback(0)
{
    timer_every(1000);  // Heartbeat every N msec
}

#if SATCAT5_VLAN_ENABLE
ChatProto::ChatProto(
        eth::Dispatch* dispatch,
        const char* username,
        const eth::VlanTag& vtag)
    : eth::Protocol(dispatch, eth::ETYPE_CHAT_TEXT, vtag)
    , m_reply_type(vtag.value, eth::ETYPE_CHAT_TEXT.value)
    , m_username(username)
    , m_userlen(strlen(username))
    , m_vtag(vtag)
    , m_callback(0)
{
    timer_every(1000);  // Heartbeat every N msec
}
#endif

void ChatProto::send_inner(
    const eth::MacAddr& dst,
    const eth::MacType& typ,
    unsigned nbytes, const void* msg)
{
    // All the chat-protocol messages have the same format.
    #ifdef SATCAT5_VLAN_ENABLE
    Writeable* wr = m_iface->open_write(dst, typ, m_vtag);
    #else
    Writeable* wr = m_iface->open_write(dst, typ);
    #endif

    if (wr) {
        wr->write_u16((u16)nbytes);
        wr->write_bytes(nbytes, msg);
        wr->write_finalize();
    }
}
    
void ChatProto::send_heartbeat()
{
    send_inner(
        eth::MACADDR_BROADCAST,
        eth::ETYPE_CHAT_HEARTBEAT,
        m_userlen, m_username);
}

void ChatProto::send_text(
    const eth::MacAddr& dst, unsigned nbytes, const char* msg)
{
    send_inner(dst, eth::ETYPE_CHAT_TEXT, nbytes, msg);
}

void ChatProto::send_data(
    const eth::MacAddr& dst, unsigned nbytes, const void* msg)
{
    send_inner(dst, eth::ETYPE_CHAT_DATA, nbytes, msg);
}

Writeable* ChatProto::open_reply(unsigned len)
{
    Writeable* wr = m_iface->open_reply(m_reply_type, len + 2);
    wr->write_u16(len);
    return wr;
}

void ChatProto::frame_rcvd(LimitedRead& src)
{
    // Ignore all messages if there's no callback.
    if (!m_callback) return;

    // Attempt to read length field.
    if (src.get_read_ready() < 2) return;
    unsigned len = src.read_u16();

    // Sanity check for complete message contents.
    if (src.get_read_ready() < len) return;

    // Deliver message to callback object.
    LimitedRead src2(&src, len);
    m_callback->frame_rcvd(src2);
}

void ChatProto::timer_event()
{
    send_heartbeat();
}

LogToChat::LogToChat(eth::ChatProto* dst, satcat5::log::EventHandler* cc)
    : m_dst(dst)
    , m_cc(cc)
{
    // Automatically set ourselves as the log destination.
    satcat5::log::start(this);
}

#if SATCAT5_ALLOW_DELETION
LogToChat::~LogToChat()
{
    // Object deleted, point to next hop in chain.
    // (If this is NULL, this shuts down the logging system.)
    satcat5::log::start(m_cc);
}
#endif

void LogToChat::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    m_dst->send_text(eth::MACADDR_BROADCAST, nbytes, msg);
}

ChatEcho::ChatEcho(eth::ChatProto* service)
    : net::Protocol(net::TYPE_NONE)
    , m_chat(service)
{
    m_chat->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
ChatEcho::~ChatEcho()
{
    m_chat->set_callback(0);
}
#endif

void ChatEcho::frame_rcvd(LimitedRead& src)
{
    // Echo input message with a wrapper: You said, "..."
    // (Counting header and footer, wrapper adds 12 bytes total.)
    unsigned nreply = src.get_read_ready() + 12;
    Writeable* wr = m_chat->open_reply(nreply);

    if (wr) {
        wr->write_str("You said, \"");
        src.copy_to(wr);
        wr->write_str("\"");
        wr->write_finalize();
    }
}
