//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CoAP endpoint (i.e., client, server, or combined client+server)

#pragma once

#include <satcat5/ccsds_spp.h>
#include <satcat5/coap_connection.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace coap {
        //! CoAP endpoint (i.e., client, server, or combined client+server).
        //!
        //! This class implements a user-extensible endpoint (i.e., a client or
        //! server or both) for the Constrained Applications Protocol (CoAP):
        //!  https://www.rfc-editor.org/rfc/rfc7252
        //!
        //! As defined in RFC7252, CoAP endpoints are a "client" whenever they
        //! issue a request, or a "server" whenever they respond to one.  In
        //! practical terms, either requires a coap::Connection object for each
        //! open transaction.  That object automatically handles retransmission
        //! and timeouts to ensure reliable delivery of requests and responses.
        //!
        //! This file defines the coap::Endpoint base class.  This class binds
        //! the shared port for incoming connection(s) and forwards them to the
        //! appropriate coap::Connection object.  User-defined CoAP systems must
        //! inherit from this class, override the "coap_*" methods, and allocate
        //! one or more coap::Connection objects.
        //!
        //! All Connection objects must be the same type (i.e., ConnectionSpp or
        //! ConnectionUdp), mixed types are not allowed. To add the appropriate
        //! connect() method, inherit from ManageSpp or ManageUdp.
        //!
        //! Endpoints (and associatec coap::Connection objects) can be connected
        //! over UDP (coap::EndpointUdp) or over CCSDS-SPP (coap::EndpointSpp).
        //! For cross-protocol forwarding, see coap::EndpointSppFwd.
        class Endpoint : public satcat5::net::Protocol {
        public:
            //! Fetch the associated network interface.
            inline satcat5::net::Dispatch* iface() const
                { return m_iface; }
            //! For UDP only, query the local port number.
            inline satcat5::udp::Port srcport() const
                { return satcat5::udp::Port(m_filter.as_u16()); }

            //! Scan connections for a matching proxy-ID. \see coap::ProxyServer.
            Connection* find_token(u32 token) const;

            //! Get the first idle connection, or null if all are busy.
            satcat5::coap::Connection* get_idle_connection() const;

            //! Set the preferred connection for outgoing requests.
            //! Usually called indirectly through ManageSpp or ManageUdp.
            void set_connection(satcat5::coap::Connection* obj)
                { m_prefer = obj; }

            //! Set network interface filter.
            //! Usually called indirectly through ManageSpp or ManageUdp.
            inline void set_filter(const satcat5::net::Type& filter)
                { m_filter = filter; }

        protected:
            //! Constructor is only accessible to the child object.
            explicit Endpoint(satcat5::net::Dispatch* iface);
            ~Endpoint() SATCAT5_OPTIONAL_DTOR;

            friend satcat5::coap::EndpointSppFwd;

            //! The Child class overrides these event-handlers:
            //!  * coap_request = Received incoming request.
            //!      The default implementation always responds with "5.01 Not
            //!      Implemented". The child class SHOULD override this method
            //!      if it accepts incoming requests. Call open_response() or
            //!      open_separate() to send the reply. \see coap::Connection.
            //!  * coap_response = Received the response to a pending request.
            //!      The default implementation discards the incoming response.
            //!      The child class SHOULD override this method if it issues
            //!      requests. \see Connection::open_request.
            //!      Multicast queries may result in multiple responses.
            //!  * coap_reqwait = Received duplicate request in "await" state.
            //!      Child classes that require special event handling, such
            //!      as reverse-proxies, MAY override this method as needed.
            //!  * coap_separate = Received separated-response notification.
            //!      Child classes that require special event handling, such
            //!      as reverse-proxies, MAY override this method as needed.
            //!  * coap_error = A pending request failed (i.e., reset or
            //!      timeout). The child class SHOULD override this method
            //!      if it issues requests, in order to process errors.
            //!  * coap_ping = Received response to a ping request.
            //!      The child class MAY override this method if it issues
            //!      ping requests. \see Connection::ping.
            //!  * coap_timeout = Benign timeout for a non-confirmable request.
            //!      For unicast queries, this event indicates no response.
            //!      For multicast queries, this event marks the end of the
            //!      waiting period, whether or not request(s) were received.
            //!@{
            virtual void coap_request(Connection* obj, Reader* msg)     // GCOVR_EXCL_LINE
                { obj->error_response(CODE_NOT_IMPL); }                 // GCOVR_EXCL_LINE
            virtual void coap_response(Connection* obj, Reader* msg) {} // GCOVR_EXCL_LINE
            virtual void coap_reqwait(Connection* obj, Reader* msg) {}  // GCOVR_EXCL_LINE
            virtual void coap_separate(Connection* obj, Reader* msg) {} // GCOVR_EXCL_LINE
            virtual void coap_error(Connection* obj) {}                 // GCOVR_EXCL_LINE
            virtual void coap_ping(const Reader* msg) {}                // GCOVR_EXCL_LINE
            virtual void coap_timeout(Connection* obj) {}               // GCOVR_EXCL_LINE
            //!@}

            // Network event handling.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Internal event handling.
            friend satcat5::coap::Connection;
            inline void add_connection(Connection* item)
                { m_list.add(item); }
            inline void remove_connection(Connection* item)
                { m_list.remove(item); }
            bool reply(u8 type, const satcat5::coap::ReadHeader* msg);

            // Internal state.
            satcat5::net::Dispatch* const m_iface;
            satcat5::util::List<satcat5::coap::Connection> m_list;
            satcat5::coap::Connection* m_prefer;
            satcat5::coap::Endpoint* m_aux_ep;
        };

        //! Connection manager for CoAP endpoints using CCSDS-SPP.
        //! This class adds a management API suitable for CoAP over SPP.
        //! User-classes should inherit from this class and coap::Endpoint.
        class ManageSpp {
        public:
            //! Accessor for the internal connection object.
            inline satcat5::coap::ConnectionSpp* connection()
                { return &m_connection; }

        protected:
            //! Constructor and destructor should only be called by the child.
            //! Immediately binds to the specified interface and APID.
            ManageSpp(satcat5::coap::Endpoint* coap, u16 apid);
            ~ManageSpp() {}

            //! Point-to-point link, only one Connection is required.
            satcat5::coap::ConnectionSpp m_connection;
        };

        //! Variant of coap::Endpoint for a CCSDS-SPP client or server.
        //! User must define coap_* event handlers (e.g., coap_request).
        class EndpointSpp
            : public satcat5::coap::Endpoint
            , public satcat5::coap::ManageSpp
        {
        protected:
            //! Constructor and destructor should only be called by the child.
            //! Immediately binds to the specified interface and APID.
            EndpointSpp(satcat5::ccsds_spp::Dispatch* iface, u16 apid);
            ~EndpointSpp() {}
        };

        //! EndpointSpp variant that forwards all requests to another Endpoint.
        //! Variant CCSDS-SPP server used in conjunction with another CoAP
        //! server on a different network interface.  This allows one backing
        //! Endpoint to serve the same CoAP resources to multiple networks.
        class EndpointSppFwd : public satcat5::coap::EndpointSpp {
        public:
            EndpointSppFwd(
                satcat5::ccsds_spp::Dispatch* iface, u16 apid,
                satcat5::coap::Endpoint* backing_endpoint);

        protected:
            void coap_request(Connection* obj, Reader* msg) override;
            void coap_response(Connection* obj, Reader* msg) override;
            void coap_error(Connection* obj) override;
            void coap_ping(const Reader* msg) override;

            satcat5::coap::Endpoint* const m_endpoint;
        };

        //! Connection manager for CoAP endpoints using UDP.
        //! This class adds a management API suitable for CoAP over UDP.
        //! User-classes should inherit from this class and coap::Endpoint.
        class ManageUdp {
        public:
            //! Begin accepting incoming requests on the designated UDP port.
            void bind(satcat5::udp::Port req_port = satcat5::udp::PORT_COAP);

            //! Open a connection to the designated remote UDP endpoint.
            //! In most cases, the source port should be left as PORT_NONE,
            //! which automatically chooses an unoccupied local port.
            //! (Use the returned coap::Connection object to issue requests.)
            satcat5::coap::ConnectionUdp* connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport = satcat5::udp::PORT_COAP,
                const satcat5::udp::Port& srcport = satcat5::udp::PORT_NONE);

            //! Pointer to the parent's network interface.
            //!@{
            inline satcat5::ip::Dispatch* ip() const
                { return udp()->iface(); }
            inline satcat5::udp::Dispatch* udp() const
                { return (satcat5::udp::Dispatch*)m_endpoint->iface(); }
            //!@}

        protected:
            //! Constructor and destructor should only be called by the child.
            //! The default (req_port = PORT_NONE) allows outgoing connections
            //! but rejects incoming requests; to change this, provide a port
            //! number or call bind() at any time.
            explicit ManageUdp(satcat5::coap::Endpoint* coap,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE);
            ~ManageUdp() {}

            //! Pointer to the associated Endpoint.
            satcat5::coap::Endpoint* const m_endpoint;
        };

        //! Variant for a UDP client or server with multiple active connections.
        //! User must allocate ConnectionUdp objects ONLY (i.e., no mixed types).
        //! User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdp
            : public satcat5::coap::Endpoint
            , public satcat5::coap::ManageUdp
        {
        protected:
            //! Constructor and destructor should only be called by the child.
            //! The default (req_port = PORT_NONE) allows outgoing connections
            //! but rejects incoming requests; to change this, provide a port
            //! number or call bind() at any time.
            explicit EndpointUdp(satcat5::udp::Dispatch* iface,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE);
            ~EndpointUdp() {}
        };

        //! Variant of EndpointUdp with a single active connection.
        //! This is sufficient for most clients, or single-user servers.
        //! User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdpSimple : public satcat5::coap::EndpointUdp {
        protected:
            //! Constructor and destructor should only be called by the child.
            explicit EndpointUdpSimple(satcat5::udp::Dispatch* iface,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE)
                : EndpointUdp(iface, req_port), m_connection(this, iface) {}
            ~EndpointUdpSimple() {}

            //! Connection to the remote server.
            satcat5::coap::ConnectionUdp m_connection;
        };

        //! Variant of EndpointUdp with a static array of connections.
        //! For a dynamically-allocated variant, \see EndpointUdpHeap.
        template <unsigned SIZE>
        class EndpointUdpStatic : public satcat5::coap::EndpointUdp {
        public:
            //! Access an internal connection object by index.
            inline ConnectionUdp& connections(unsigned idx)
                { return m_connections[idx]; }

        protected:
            //! Constructor and destructor should only be called by the child.
            explicit EndpointUdpStatic(satcat5::udp::Dispatch* iface,
                satcat5::udp::Port req_port = satcat5::udp::PORT_NONE)
                : EndpointUdp(iface, req_port), m_connections(this, iface) {}
            ~EndpointUdpStatic() {}

            //! Connections to remote server(s).
            satcat5::coap::ConnectionUdpArray<SIZE> m_connections;
        };
    }
}
