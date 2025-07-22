//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! CoAP reverse-proxy for specific resources
//!
//!\details
//! The CoAP specification (RFC 7252) section 5.7 defines:
//! * Forward-proxies: In which the client that issues a request specifies
//!   where it should be forwarded, using the Proxy-Uri option.
//! * Reverse-proxies: In which the server decides that a request for a given
//!   resource should be forwarded to another server, and acts as a middleman.
//!
//! This file defines classes used for reverse-proxies, which build on the
//! coap::Resource concept (\see coap_resource.h):
//! * coap::ProxyResource defines a CoAP resource whose requests should be
//!   forwarded to a CoAP server at a designated IP address and UDP port.
//!   The next-hop address can be configured separately for each resource.
//! * coap::ProxyServer defines a CoAP endpoint that can service a mixture
//!   of local and/or proxy Resource objects.
//!
//! To forward a request, coap::ProxyServer uses two coap::Connection objects:
//! * The first Connection is to the client, opened by an incoming request.
//! * That event calls ResourceServer::coap_request(), which reads the URI-Path
//!   option to identify the matching coap::Resource or coap::ProxyResource.
//! * If the URI matches a coap::ProxyResource, then that object processes
//!   the get/post/put/delete request. \see ProxyResource::request_any.
//! * The `request_any` callback opens (or reuses) a coap::Connection to the
//!   downstream server, then forwards the request contents.  The outgoing
//!   message-ID is stored in both client and server objects.
//! * When a response is received, that triggers ProxyServer::coap_response(),
//!   which tries to match the response's message-ID against the ID stored
//!   in the previous step, to find the original client Connection object.
//! * If a match is found, ProxyServer::proxy_response forwards the response.
//!   Otherwise, it notifies a callback. \see ProxyServer::local_response.
//!
//! TODO: Support caching, etags, and the PROXY_URI tag.
//!

#pragma once

#include <satcat5/coap_connection.h>
#include <satcat5/coap_resource.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace coap {
        //! Define a reverse-proxy CoAP resource.
        //! \see coap_proxy.h, coap::Resource, coap::ProxyServer.
        class ProxyResource final : public satcat5::coap::Resource {
        public:
            //! Constructor sets the URI path for the resource.
            //! \param local_uri    URI for incoming requests.
            //! \param fwd_addr     Forwarding IP address.
            //! \param fwd_port     Forwarding UDP port.
            //! \param fwd_uri      Optional forwarding URI, if different.
            ProxyResource(
                satcat5::coap::ProxyServer* server,
                const char* local_uri,
                const satcat5::ip::Addr& fwd_addr,
                const satcat5::udp::Port& fwd_port,
                const char* fwd_uri = nullptr);

            //! Forward GET, POST, PUT, and DELETE requests.
            //! Each handler is aliased to the same underlying function.
            //!@{
            bool request_get(Connection* obj, Reader* msg) override
                { return request_any(obj, msg); }
            bool request_post(Connection* obj, Reader* msg) override
                { return request_any(obj, msg); }
            bool request_put(Connection* obj, Reader* msg) override
                { return request_any(obj, msg); }
            bool request_delete(Connection* obj, Reader* msg) override
                { return request_any(obj, msg); }
            //!@}

        protected:
            //! Event handler for all incoming requests.
            //! (The GET/POST/PUT/DELETE code is forwarded verbatim.)
            bool request_any(Connection* obj, Reader* msg);

            satcat5::coap::ProxyServer* const m_pool;
            const satcat5::ip::Addr m_fwd_addr;
            const satcat5::udp::Port m_fwd_port;
            const char* const m_fwd_uri;
        };

        //! CoAP server with a mix of local and reverse-proxy resources.
        //! Handles incoming requests according to the URI-Path. Different
        //! URIs may point to local resources (i.e., the Resource base class)
        //! or proxy resources (i.e., the ProxyResource class). In the latter
        //! case, this server forwards requests to the next-hop server and
        //! matches incoming response metadata to the original requestor.
        //! \see coap_proxy.h, coap::ProxyResource, coap::ResourceServer.
        class ProxyServer : public satcat5::coap::ResourceServer {
        public:
            //! Constructor. By default, bind this server to port 5683.
            explicit ProxyServer(satcat5::udp::Dispatch* udp,
                satcat5::udp::Port port = satcat5::udp::PORT_COAP);

            //! Given a token, find associated client connection.
            //! Clients may be Connection objects of any type.
            Connection* find_client(u32 token) const;

            //! Given a token, find associated server connection.
            //! Servers must always be ConnectionUDP objects.
            ConnectionUdp* find_server(u32 token) const;

            //! Outgoing messages are numbered sequentially.
            u16 next_msgid();

            //! Unique transaction tokens match client and server.
            u32 next_token();

        protected:
            //! Event handler for non-proxy responses.
            //! By default, this placeholder method does nothing.
            //! If a child class issues non-proxy requests, then it should
            //! override this callback method to receive incoming responses.
            virtual void local_response(Connection* obj, Reader* msg) {} // GCOVR_EXCL_LINE

            //! Internal handler for proxy responses.
            void proxy_response(Connection* client, Reader* msg);

            // Override all proxy-related coap::Endpoint callbacks.
            // (The coap_request callback is handled by the parent class.)
            void coap_response(Connection* obj, Reader* msg) override;
            void coap_reqwait(Connection* obj, Reader* msg) override;
            void coap_separate(Connection* obj, Reader* msg) override;
            void coap_error(Connection* obj) override;

            // Internal state
            u16 m_msgid;    //!< Counter for outgoing message-IDs.
            u32 m_token;    //!< Counter for client/server tokens.

            //! Proxy operation requires at least two ConnectionUdp objects.
            //! The child class may add more as needed for concurrency.
            //! Note: Do not add other types of coap::Connection objects.
            satcat5::coap::ConnectionUdp m_extra_connection;
        };
    }
}
