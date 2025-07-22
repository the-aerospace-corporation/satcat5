//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! CoAP resource handler definition and resource server creation
//!
//!\details
//! The coap::Resource base class is derived to create different types of
//! handlers for CoAP GET, POST, PUT, and DELETE requests registered to respond
//! to a given URI specified by one or more Uri-Path CoAP request options. Each
//! Resource is registered to a URI that MUST be unique and should not contain
//! any leading or trailing slashes. Two examples are included:
//! coap::ResourceEcho responds to any GET request with a copy of its payload and
//! coap::ResourceLog will create a Log entry from the payload of any incoming
//! POST request.
//!
//! One or more Resources can be added to a coap::ResourceServer class, which
//! acts as a CoAP server to route requests to the correct coap::Resource
//! according to the Uri-Path option. While not recommended, a Resource can be
//! registered to the server root and therefore accessible without any Uri-Path
//! options by declaring the path string to be "".
//!
//! There are a few important notes to keep in mind when declaring URIs:
//!  * Resource Uri-Paths may optionally include one leading slash but MUST NOT
//!    include tailing slashes.
//!    * Valid examples: "top1/nested2/target3" or "/top1/nested2/target3".
//!    * Violating this WILL cause a lookup failure in ResourceServer.
//!  * Uri-Host, Uri-Port, and Uri-Query are not implemented and their inclusion
//!    WILL trigger an error since these are Critical options. Host and Port are
//!    implicit from lower-layer routing, and Query options are not supported.
//!  * Nested paths are supported; however, this is a simple URI string match.
//!  * There is a compile-time maximum length for the fully assembled URI string
//!    (`SATCAT5_COAP_MAX_URI_PATH_LEN`) that MUST NOT be violated in the given
//!    Uri-Path, else the Resource can never be matched.

#pragma once

#include <satcat5/coap_connection.h>
#include <satcat5/coap_endpoint.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace coap {
        //! Define a single CoAP resource.
        //! \see coap_resource.h, ResourceEcho, ResourceLog, ResourceServer.
        class Resource {
        protected:
            //! Simple constructor sets the URI path for the resource.
            //! Use this constructor if you need `constexpr`, then call
            //! ResourceServer::add_resource() directly.
            constexpr explicit Resource(const char* uri_path)
                : m_uri_path(normalize_uri(uri_path))
                , m_server(nullptr)
                , m_next(nullptr) {}

            //! Alternate constructor automatically calls add_resource().
            //! Use this constructor to call ResourceServer::add_resource()
            //! and remove_resource() automatically.
            Resource(ResourceServer* server, const char* uri_path);

            //! Destructor is only accessible to the child object.
            ~Resource() SATCAT5_OPTIONAL_DTOR;

            //! Remove leading slash from a user-provided path.
            static constexpr const char* normalize_uri(const char* uri)
                { return (uri[0] == '/') ? (uri + 1) : (uri); }

        public:
            //! Comparison operators for comparing two URI-paths.
            //!@{
            bool operator==(const Resource& other) const;
            inline bool operator!=(const Resource& other) const
                { return !(*this == other); }
            //!@}

            //! Pointer to the parent's network interface.
            //!@{
            satcat5::ip::Dispatch* ip() const;
            satcat5::udp::Dispatch* udp() const;
            //!@}

            //! Event handlers for GET, POST, PUT, and DELETE queries.
            //! The Child class SHOULD override at least one of the following
            //! event handlers corresponding to GET, POST, PUT, and DELETE
            //! requests, respectively. Default behavior is to respond with the
            //! 4.05 Method Not Allowed error code.
            //!@{
            virtual bool request_get(Connection* obj, Reader* msg)
                { return obj->error_response(CODE_BAD_METHOD); }
            virtual bool request_post(Connection* obj, Reader* msg)
                { return obj->error_response(CODE_BAD_METHOD); }
            virtual bool request_put(Connection* obj, Reader* msg)
                { return obj->error_response(CODE_BAD_METHOD); }
            virtual bool request_delete(Connection* obj, Reader* msg)
                { return obj->error_response(CODE_BAD_METHOD); }
            //!@}

        protected:
            //! URI-Path for this resource.
            const char* const m_uri_path;

            //! Optional pointer to the server object.
            ResourceServer* const m_server;

        private:
            // Member variables
            friend satcat5::util::ListCore;
            Resource* m_next; // Linked list next node
        };

        //! Resource that echos back any incoming payload.
        class ResourceEcho : public Resource {
        public:
            //! Constructor (user calls add_resource).
            constexpr explicit ResourceEcho(const char* uri_path)
                : Resource(uri_path) {}
            //! Constructor (parent class calls add_resource).
            ResourceEcho(ResourceServer* server, const char* uri_path)
                : Resource(server, uri_path) {}

            //! GET requests respond with the payload from the request.
            bool request_get(Connection* obj, Reader* msg) override;
        };

        //! Resource that returns a fixed status code for all requests.
        //! This is usually set to an error code such as 4.03 Forbidden.
        class ResourceError final : public Resource {
        public:
            //! Constructor (user calls add_resource).
            constexpr explicit ResourceError(const char* uri_path, Code errcode)
                : Resource(uri_path), m_errcode(errcode) {}
            //! Constructor (parent class calls add_resource).
            ResourceError(ResourceServer* server, const char* uri_path, Code errcode)
                : Resource(server, uri_path), m_errcode(errcode) {}

            //! All request types respond with the specified error code.
            //!@{
            bool request_get(Connection* obj, Reader* msg) override
                { return obj->error_response(m_errcode); }
            bool request_post(Connection* obj, Reader* msg) override
                { return obj->error_response(m_errcode); }
            bool request_put(Connection* obj, Reader* msg) override
                { return obj->error_response(m_errcode); }
            bool request_delete(Connection* obj, Reader* msg) override
                { return obj->error_response(m_errcode); }
            //!@{

        protected:
            const satcat5::coap::Code m_errcode;
        };

        //! Resource that creates a log::Log entry.
        class ResourceLog : public Resource {
        public:
            //! Constructor (user calls add_resource).
            constexpr ResourceLog(const char* uri_path, s8 priority)
                : Resource(uri_path), m_priority(priority) {}
            //! Constructor (parent class calls add_resource).
            ResourceLog(ResourceServer* server, const char* uri_path, s8 priority)
                : Resource(server, uri_path), m_priority(priority) {}

            //! POST requests create a log::Log entry.
            bool request_post(Connection* obj, Reader* msg) override;

        protected:
            s8 m_priority; //!< Priority for created log messages
        };

        //! The NullResource does not implement GET, POST, PUT, or DELETE.
        //! This wrapper is required because the base constructor is private.
        class ResourceNull : public Resource {
        public:
            explicit ResourceNull(const char* uri)
                : Resource(uri) {}
            ResourceNull(ResourceServer* server, const char* uri)
                : Resource(server, uri) {}
        };

        //! Manager for several Resource objects available on an Endpoint.
        //! This implementation of a CoAP server inspects the URI-Path,
        //! and forwards requests to the matching Resource, if one exists.
        class ResourceServer : public satcat5::coap::EndpointUdp {
        public:
            //! Constructor. By default, bind this server to port 5683.
            explicit ResourceServer(satcat5::udp::Dispatch* udp,
                satcat5::udp::Port port = satcat5::udp::PORT_COAP)
                : satcat5::coap::EndpointUdp(udp, port), m_connection(this, udp) {}

            //! Add a Resource to the linked list.
            inline void add_resource(Resource* resource)
                { m_resources.add(resource); }

            //! Remove a Resource from the linked list.
            inline void remove_resource(Resource* resource)
                { m_resources.remove(resource); }

        protected:
            // Member variables
            satcat5::util::List<Resource> m_resources; //!< List of resources
            satcat5::coap::ConnectionUdp m_connection; //!< Single UDP connection

            //! Handler for an incoming request.
            void coap_request(Connection* obj, Reader* msg) override;
        };
    }
}
