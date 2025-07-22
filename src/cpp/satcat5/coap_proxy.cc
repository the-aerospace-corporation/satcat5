//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_proxy.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <satcat5/utils.h>

using satcat5::coap::Connection;
using satcat5::coap::ConnectionUdp;
using satcat5::coap::ProxyResource;
using satcat5::coap::ProxyServer;

// Option to force separated-response mode for all proxy requests.
// * When set to 0, always use separated-response mode immediately.
//   (i.e., All proxy requests send the separated-response message.)
// * When set to 1, prefer silent mode, switching to separated mode
//   only if the forwarded request/response is taking a long time.
#ifndef SATCAT5_COAP_PROXY_SILENT
#define SATCAT5_COAP_PROXY_SILENT 1
#endif

// Use even/odd tokens to identify client (LSB=0) and server (LSB=1).
constexpr u32 TOKEN_MASK = 0xFFFFFFFEu;
constexpr u32 token_client(u32 x)
    { return (x & TOKEN_MASK) + 0; }
constexpr u32 token_server(u32 x)
    { return (x & TOKEN_MASK) + 1; }

ProxyResource::ProxyResource(
        satcat5::coap::ProxyServer* server,
        const char* local_uri,
        const satcat5::ip::Addr& fwd_addr,
        const satcat5::udp::Port& fwd_port,
        const char* fwd_uri)
    : Resource(server, local_uri)
    , m_pool(server)
    , m_fwd_addr(fwd_addr)
    , m_fwd_port(fwd_port)
    , m_fwd_uri(normalize_uri(fwd_uri ? fwd_uri : local_uri))
{
    // No other initialization required.
}

bool ProxyResource::request_any(Connection* client, Reader* msg) {
    // Reuse an existing next-hop connection if practical.
    // Otherwise, claim any idle connection from the pool.
    ConnectionUdp* server = m_pool->find_server(client->get_proxy_token());
    if (!server) server = (ConnectionUdp*)m_pool->get_idle_connection();

    // If there's no available connections, abort.
    if (!server) return client->error_response(CODE_SERVER_ERROR, "Proxy busy");

    // If we're not already connected, attempt to do so now.
    // (And set flag to allow immediate reuse once finished.)
    bool ok = server->is_match_addr(m_fwd_addr, m_fwd_port)
           || server->connect(m_fwd_addr, m_fwd_port, udp::PORT_NONE, true);

    // Set unique IDs for the new transaction.
    u16 msgid = m_pool->next_msgid();
    u32 token = m_pool->next_token();
    client->set_proxy_token(token_client(token));
    server->set_proxy_token(token_server(token));

    // Copy message header, including the GET/POST/PUT/DELETE code.
    satcat5::coap::Writer fwd(server->open_request());
    if (ok) ok = fwd.write_header(msg->type(), msg->code(), msgid, token);

    // Copy simple options in numerical order.
    // TODO: Is there a practical way to copy *ALL* safe options?  This meets
    //  our needs, but may not be compatible with third-party clients/servers.
    if (ok) ok = fwd.write_uri(OPTION_URI_PATH, m_fwd_uri);
    if (ok && msg->format()) ok = fwd.write_option(OPTION_FORMAT, msg->format().value());
    if (ok && msg->block2()) ok = fwd.write_option(OPTION_BLOCK2, msg->block2().value());
    if (ok && msg->block1()) ok = fwd.write_option(OPTION_BLOCK1, msg->block1().value());
    if (ok && msg->size1())  ok = fwd.write_option(OPTION_SIZE1, msg->size1().value());

    // Copy message contents and send the forwarded request.
    satcat5::io::Readable* src = msg->read_data();
    satcat5::io::Writeable* dst = fwd.write_data();
    if (ok && src && dst) ok = src->copy_and_finalize(dst, io::CopyMode::ALWAYS);
    if (!ok) return client->error_response(CODE_SERVER_ERROR);

    // If we're in silent mode, no immediate response (see "coap_reqwait").
    // Otherwise, immediately switch to separated-response mode.
    return SATCAT5_COAP_PROXY_SILENT || client->open_separate(msg);
}

ProxyServer::ProxyServer(satcat5::udp::Dispatch* udp, satcat5::udp::Port port)
    : ResourceServer(udp, port)
    , m_msgid(satcat5::util::prng.next())
    , m_token(satcat5::util::prng.next())
    , m_extra_connection(this, udp)
{
    // Nothing else to initialize.
}

Connection* ProxyServer::find_client(u32 token) const {
    // Check both auxiliary and local Connection objects.
    Connection* tmp = nullptr;
    if (m_aux_ep) tmp = m_aux_ep->find_token(token_client(token));
    if (!tmp) tmp = find_token(token_client(token));
    return tmp;
}

ConnectionUdp* ProxyServer::find_server(u32 token) const {
    // Check local ConnectionUdp objects only.
    return (ConnectionUdp*)find_token(token_server(token));
}

u16 ProxyServer::next_msgid() {
    // Sequential numbering of outgoing messages.
    return m_msgid++;
}

u32 ProxyServer::next_token() {
    // Increment counter by two for unique client and server IDs.
    return (m_token += 2) & TOKEN_MASK;
}

void ProxyServer::coap_response(Connection* obj, Reader* msg) {
    // Is this a valid proxy response?
    u32 rcvd_token = token_server(msg->token());
    Connection* client = nullptr;
    if (rcvd_token == obj->get_proxy_token())
        client = find_client(rcvd_token);

    // Notify the local or proxy callback accordingly.
    if (client) {
        proxy_response(client, msg);
    } else {
        local_response(obj, msg);
    }
}

void ProxyServer::proxy_response(Connection* client, Reader* msg) {
    // Forward the response, using whichever mode is expected.
    // Copy message header, then known options in numerical order.
    satcat5::coap::Writer fwd(client->open_response_auto());
    bool ok = fwd.write_header(msg->code(), client);
    if (ok && msg->uri_path()) ok = fwd.write_uri(OPTION_URI_PATH, msg->uri_path().value());
    if (ok && msg->format()) ok = fwd.write_option(OPTION_FORMAT, msg->format().value());
    if (ok && msg->block2()) ok = fwd.write_option(OPTION_BLOCK2, msg->block2().value());
    if (ok && msg->block1()) ok = fwd.write_option(OPTION_BLOCK1, msg->block1().value());
    if (ok && msg->size1())  ok = fwd.write_option(OPTION_SIZE1, msg->size1().value());

    // Copy message contents and send the message.
    satcat5::io::Readable* src = msg->read_data();
    satcat5::io::Writeable* dst = fwd.write_data();
    if (ok && src && dst) ok = src->copy_and_finalize(dst, io::CopyMode::ALWAYS);
    if (!ok) client->error_response(CODE_SERVER_ERROR);
}

void ProxyServer::coap_reqwait(Connection* obj, Reader* msg) {
    // If we're in SATCAT5_COAP_PROXY_SILENT mode, use the second request
    // as a clue that the forwarded request is taking a while.
    if (!obj->is_separate()) obj->open_separate(msg);
}

void ProxyServer::coap_separate(Connection* obj, Reader* msg) {
    // If the next-hop server says the response may take a while, forward
    // the same message to the upstream requestor.
    if (!obj->is_separate()) obj->open_separate(msg);
}

void ProxyServer::coap_error(Connection* obj) {
    // Server timeout, attempt to find the matching client connection.
    Connection* client = find_client(obj->get_proxy_token());
    if (client && client != obj)
        client->error_response(CODE_GATE_TIMEOUT, "Proxy timeout");
}
