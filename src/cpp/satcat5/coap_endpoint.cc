//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/coap_endpoint.h>
#include <satcat5/coap_reader.h>
#include <satcat5/coap_writer.h>
#include <satcat5/log.h>
#include <satcat5/udp_dispatch.h>

using satcat5::coap::Connection;
using satcat5::coap::ConnectionUdp;
using satcat5::coap::Endpoint;
using satcat5::coap::EndpointSpp;
using satcat5::coap::EndpointSppFwd;
using satcat5::coap::EndpointUdp;
using satcat5::coap::ManageSpp;
using satcat5::coap::ManageUdp;
namespace log = satcat5::log;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

Endpoint::Endpoint(satcat5::net::Dispatch* iface)
    : Protocol(satcat5::net::TYPE_NONE)
    , m_iface(iface)
    , m_prefer(nullptr)
    , m_aux_ep(nullptr)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
Endpoint::~Endpoint() {
    m_iface->remove(this);
}
#endif

Connection* Endpoint::find_token(u32 token) const {
    Connection* item = m_list.head();
    while (item && item->get_proxy_token() != token) {
        item = m_list.next(item);
    }
    return item;
}

Connection* Endpoint::get_idle_connection() const {
    Connection* item = m_list.head();
    while (item && !item->is_idle()) {
        item = m_list.next(item);
    }
    return item;
}

void Endpoint::frame_rcvd(satcat5::io::LimitedRead& src) {
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "CoAP: frame_rcvd");

    // Any matches by remote address?
    //  * For CCSDS-SPP, this checks APID.
    //  * For UDP, this checks IP address + UDP port.
    Connection* item = m_list.head();
    while (item && !item->is_match_addr()) {
        item = m_list.next(item);
    }

    // Response without a matching request?
    satcat5::coap::ReadSimple msg(&src);
    if (msg.is_response() && !item) {
        // Sender is confused and needs a reset.
        reply(TYPE_RST, &msg); return;
    }

    // If there's no address match, accept any idle connection.
    // (i.e., Prioritize re-use of open Connection when possible.)
    if (!item) item = get_idle_connection();

    // Parse and process the message...
    if (item) {
        // Deliver and process the message.
        item->deliver(&msg);
    } else {
        // Unable to deliver because all connections are busy.
        log::Log(log::WARNING, "CoAP: All connections busy.");
    }
}

bool Endpoint::reply(u8 type, const ReadHeader* rcvd) {
    // Send empty ACK or RST reply in response to certain events.
    // Does NOT alter connection state or working buffer contents.
    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "CoAP: Reply").write(rcvd->msg_id());

    // Construct the outgoing message in a temporary buffer.
    // (This is easier than trying to predict the total length.)
    // Do not echo the token in the empty message (Section 3).
    satcat5::io::ArrayWriteStatic<64> buff;
    satcat5::coap::Writer reply(&buff);
    reply.write_header(type, CODE_EMPTY, rcvd->msg_id());
    reply.write_finalize();         // Empty message (no options or data)

    // Send a reply directly through the UDP interface.
    // TODO: This will result in out-of-order sequence IDs in CCSDS mode.
    satcat5::io::Writeable* wr = m_iface->open_reply(
        satcat5::net::TYPE_NONE, buff.written_len());
    if (wr) wr->write_bytes(buff.written_len(), buff.buffer());
    return wr && wr->write_finalize();
}

ManageSpp::ManageSpp(Endpoint* coap, u16 apid)
    : m_connection(coap, (satcat5::ccsds_spp::Dispatch*)coap->iface())
{
    m_connection.connect(apid);
    coap->set_filter(satcat5::net::Type(apid));
}

EndpointSpp::EndpointSpp(satcat5::ccsds_spp::Dispatch* iface, u16 apid)
    : Endpoint(iface)
    , ManageSpp(this, apid)
{
    // Nothing else to initialize.
}

EndpointSppFwd::EndpointSppFwd(
    satcat5::ccsds_spp::Dispatch* iface, u16 apid,
    satcat5::coap::Endpoint* backing_endpoint)
    : EndpointSpp(iface, apid)
    , m_endpoint(backing_endpoint)
{
    // Link ourselves as an auxiliary endpoint.
    // (e.g., Allows cross-protocol forwarding in proxy servers.)
    m_endpoint->m_aux_ep = this;
}

void EndpointSppFwd::coap_request(Connection* obj, Reader* msg)
    { m_endpoint->coap_request(obj, msg); }
void EndpointSppFwd::coap_response(Connection* obj, Reader* msg)
    { m_endpoint->coap_response(obj, msg); }
void EndpointSppFwd::coap_error(Connection* obj)
    { m_endpoint->coap_error(obj); }
void EndpointSppFwd::coap_ping(const Reader* msg)
    { m_endpoint->coap_ping(msg); }

ManageUdp::ManageUdp(satcat5::coap::Endpoint* coap, satcat5::udp::Port req_port)
    : m_endpoint(coap)
{
    if (req_port.value) bind(req_port);
}

void ManageUdp::bind(satcat5::udp::Port port) {
    m_endpoint->set_filter(satcat5::net::Type(port.value));
}

ConnectionUdp* ManageUdp::connect(
    const satcat5::udp::Addr& dstaddr,
    const satcat5::udp::Port& dstport,
    const satcat5::udp::Port& srcport)
{
    // This class requires that all attached Connection objects are
    // actually ConnectionUdp, so this coersion should succeed.
    ConnectionUdp* udp = (ConnectionUdp*)m_endpoint->get_idle_connection();
    m_endpoint->set_connection(udp);
    if (udp) udp->connect(dstaddr, dstport, srcport);
    return udp;
}

EndpointUdp::EndpointUdp(satcat5::udp::Dispatch* iface, satcat5::udp::Port req_port)
    : Endpoint(iface), ManageUdp(this, req_port)
{
    // Nothing else to initialize.
}
