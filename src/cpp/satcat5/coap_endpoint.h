//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CoAP endpoint (i.e., client, server, or combined client+server)
//
// This class implements a user-extensible endpoint (i.e., a client or
// server or both) for the Constrained Applications Protocol (CoAP):
//  https://www.rfc-editor.org/rfc/rfc7252
//
// As defined in RFC7252, CoAP endpoints are a "client" whenever they
// issue a request, or a "server" whenever they respond to one.  In
// practical terms, either requires a coap::Connection object for each
// open transaction.  That object automatically handles retransmission
// and timeouts to ensure reliable delivery of requests and responses.
//
// This file defines the coap::Endpoint base class.  This class binds
// the shared port for incoming connection(s) and forwards them to the
// appropriate coap::Connection object.  User-defined CoAP systems must
// inherit from this class, override the "coap_*" methods, and allocate
// one or more coap::Connection objects.
//

#pragma once

#include <satcat5/ccsds_spp.h>
#include <satcat5/coap_connection.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace coap {
        // Base class for a CoAP client or server.
        class Endpoint : public satcat5::net::Protocol {
        public:
            // Simple accessors.
            inline satcat5::net::Dispatch* iface() const
                { return m_iface; }
            inline satcat5::udp::Port srcport() const
                { return satcat5::udp::Port(m_filter.as_u16()); }

        protected:
            explicit Endpoint(satcat5::net::Dispatch* iface);
            ~Endpoint() SATCAT5_OPTIONAL_DTOR;
            friend satcat5::coap::EndpointSppFwd;

            // The Child class overrides these event-handlers:
            //  * coap_connected = Connection completed.
            //      Call open_request() to send a query immediately.
            //      The child class MAY override this method.
            //  * coap_request = Received incoming request.
            //      Call open_response() or open_separate() to send the reply.
            //      The child class MUST override this method.
            //  * coap_response = Received response to an open request.
            //      The child class SHOULD override this method.
            //  * coap_error = Request reset or timeout.
            //      The child class SHOULD override this method.
            //  * coap_ping = Received response to a ping request.
            //      The child class MAY override this method.
            virtual void coap_connected(Connection* obj) {}
            virtual void coap_request(Connection* obj, Reader& msg) = 0;
            virtual void coap_response(Connection* obj, Reader& msg) {} // GCOVR_EXCL_LINE
            virtual void coap_error(Connection* obj) {}                 // GCOVR_EXCL_LINE
            virtual void coap_ping(const Reader& msg) {}                // GCOVR_EXCL_LINE

            // Get the first idle connection, or null if all are busy.
            satcat5::coap::Connection* get_idle_connection();

            // Network event handling.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Internal event handling.
            friend satcat5::coap::Connection;
            inline void add_connection(Connection* item)
                { m_list.add(item); }
            inline void remove_connection(Connection* item)
                { m_list.remove(item); }
            bool reply(u8 type, const satcat5::coap::Reader& msg);

            // Internal state.
            satcat5::net::Dispatch* const m_iface;
            satcat5::util::List<satcat5::coap::Connection> m_list;
        };

        // Variant for a CCSDS-SPP client or server.
        // User must define coap_* event handlers (e.g., coap_request).
        class EndpointSpp : public satcat5::coap::Endpoint {
        public:
            // Accessor for the internal connection object.
            inline satcat5::coap::ConnectionSpp* connection()
                { return &m_connection; }

        protected:
            // Constructor and destructor should only be called by the child.
            // Immediately binds to the specified interface and APID.
            EndpointSpp(satcat5::ccsds_spp::Dispatch* iface, u16 apid);
            ~EndpointSpp() {}

            // Point-to-point link, only one Connection is required.
            satcat5::coap::ConnectionSpp m_connection;
        };

        // Variant CCSDS-SPP server used in conjunction with another CoAP
        // server on a different network interface.  This allows one backing
        // Endpoint to serve the same CoAP resources to multiple networks.
        class EndpointSppFwd : public satcat5::coap::EndpointSpp {
        public:
            EndpointSppFwd(
                satcat5::ccsds_spp::Dispatch* iface, u16 apid,
                satcat5::coap::Endpoint* backing_endpoint);

        protected:
            // Note: CCSDS-SPP has no "coap_connected" events to forward.
            void coap_request(Connection* obj, Reader& msg) override;
            void coap_response(Connection* obj, Reader& msg) override;
            void coap_error(Connection* obj) override;
            void coap_ping(const Reader& msg) override;

            satcat5::coap::Endpoint* const m_endpoint;
        };

        // Variant for a UDP client or server with multiple active connections.
        // User must allocate ConnectionUdp objects ONLY (i.e., no mixed types).
        // User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdp : public satcat5::coap::Endpoint {
        public:
            // Begin accepting incoming requests on the designated UDP port.
            void bind(satcat5::udp::Port req_port = satcat5::udp::PORT_COAP);

            // Open a connection to the designated remote UDP endpoint.
            // In most cases, the source port should be left as PORT_NONE,
            // which automatically chooses an unoccupied local port.
            // (Use the returned coap::Connection object to issue requests.)
            satcat5::coap::ConnectionUdp* connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport = satcat5::udp::PORT_COAP,
                const satcat5::udp::Port& srcport = satcat5::udp::PORT_NONE);

        protected:
            // Constructor and destructor should only be called by the child.
            // The default (req_port = PORT_NONE) allows outgoing connections
            // but rejects incoming requests; to change this, provide a port
            // number or call bind() at any time.
            explicit EndpointUdp(satcat5::udp::Dispatch* iface,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE);
            ~EndpointUdp() {}
        };

        // Variant for a UDP endpoint with a single active connection.
        // This is sufficient for most clients, or single-user servers.
        // User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdpSimple : public satcat5::coap::EndpointUdp {
        protected:
            // Constructor and destructor should only be called by the child.
            explicit EndpointUdpSimple(satcat5::udp::Dispatch* iface,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE)
                : EndpointUdp(iface, req_port), m_connection(this, iface) {}
            ~EndpointUdpSimple() {}

            // Connection to the remote server.
            satcat5::coap::ConnectionUdp m_connection;
        };
    }
}
