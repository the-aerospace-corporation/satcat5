//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_chat.h>
#include <satcat5/eth_dispatch.h>
#include <cstring>

namespace eth = satcat5::eth;
namespace log = satcat5::log;
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
    if (dispatch->macaddr() == eth::MACADDR_NONE) return;
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
    if (dispatch->macaddr() == eth::MACADDR_NONE) return;
    timer_every(1000);  // Heartbeat every N msec
}
#endif

Writeable* ChatProto::open_inner(
    const eth::MacAddr& dst,
    const eth::MacType& typ,
    unsigned msg_bytes)
{
    // All the chat-protocol messages have the same format.
    #ifdef SATCAT5_VLAN_ENABLE
    Writeable* wr = m_iface->open_write(dst, typ, m_vtag);
    #else
    Writeable* wr = m_iface->open_write(dst, typ);
    #endif

    if (wr) {wr->write_u16((u16)msg_bytes);}

    return wr;
}

void ChatProto::send_heartbeat()
{
    Writeable* wr = open_inner(
        eth::MACADDR_BROADCAST,
        eth::ETYPE_CHAT_HEARTBEAT,
        m_userlen);

    if (wr) {
        wr->write_bytes(m_userlen, m_username);
        wr->write_finalize();
    }
}

void ChatProto::send_text(
    const eth::MacAddr& dst, unsigned nbytes, const char* msg)
{
    Writeable* wr = open_inner(dst, eth::ETYPE_CHAT_TEXT, nbytes);

    if (wr) {
        wr->write_bytes(nbytes, msg);
        wr->write_finalize();
    }
}

void ChatProto::send_data(
    const eth::MacAddr& dst, unsigned nbytes, const void* msg)
{
    Writeable* wr = open_inner(dst, eth::ETYPE_CHAT_DATA, nbytes);

    if (wr) {
        wr->write_bytes(nbytes, msg);
        wr->write_finalize();
    }
}

Writeable* ChatProto::open_reply(unsigned len)
{
    Writeable* wr = m_iface->open_reply(m_reply_type, len + 2);
    if (wr) wr->write_u16(len);
    return wr;
}

Writeable* ChatProto::open_text(const eth::MacAddr& dst, unsigned len)
{
    return open_inner(dst, eth::ETYPE_CHAT_TEXT, len);
}

satcat5::eth::MacAddr ChatProto::local_mac() const
{
    return m_iface->macaddr();
}

satcat5::eth::MacAddr ChatProto::reply_mac() const
{
    return m_iface->reply_mac();
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

LogToChat::LogToChat(eth::ChatProto* dst, const eth::MacAddr& addr)
    : m_chat(dst)
    , m_addr(addr)
{
    // Nothing else to initialize.
}

void LogToChat::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    // Prepend a human-readable priority label.
    const char* pstr = log::priority_label(priority);
    unsigned    plen = strlen(pstr);
    unsigned   total = plen + nbytes + 1;

    // Write header, append each message field, and send.
    Writeable* wr = m_chat->open_text(m_addr, total);
    if (wr) {
        wr->write_bytes(plen, pstr);
        wr->write_u8((u8)'\t');
        wr->write_bytes(nbytes, msg);
        wr->write_finalize();
    }
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
