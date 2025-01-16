//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CoAP resource handler definition and resource server creation
//
// The coap::Resource base class is derived to create different types of
// handlers for CoAP GET, POST, PUT, and DELETE requests registered to respond
// to a given URI specified by one or more Uri-Path CoAP request options. Each
// Resource is registered to a URI that MUST be unique and should not contain
// any leading or trailing slashes. Two examples are included:
// coap::ResourceEcho responds to any GET request with a copy of its payload and
// coap::ResourceLog will create a Log entry from the payload of any incoming
// POST request.
//
// One or more Resources can be added to a coap::ResourceServer class, which
// acts as a CoAP server to route requests to the correct coap::Resource
// according to the Uri-Path option. While not recommended, a Resource can be
// registered to the server root and therefore accessible without any Uri-Path
// options by declaring the path string to be "".
//
// There are a few important notes to keep in mind when declaring URIs:
//  * Resource Uri-Paths may optionally include one leading slash but MUST NOT
//    include tailing slashes.
//    * Valid examples: "top1/nested2/target3" or "/top1/nested2/target3".
//    * Violating this WILL cause a lookup failure in ResourceServer.
//  * Uri-Host, Uri-Port, and Uri-Query are not implemented and their inclusion
//    WILL trigger an error since these are Critical options. Host and Port are
//    implicit from lower-layer routing, and Query options are not supported.
//  * Nested paths are supported; however, this is a simple URI string match.
//  * There is a compile-time maximum length for the fully assembled URI string
//    (`SATCAT5_COAP_MAX_URI_PATH_LEN`) that MUST NOT be violated in the given
//    Uri-Path, else the Resource can never be matched.
//

#pragma once

#include <satcat5/coap_connection.h>
#include <satcat5/coap_endpoint.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace coap {

        // Single resource definition
        class Resource {
        public:
            // Constructor
            constexpr explicit Resource(const char* const uri_path)
                : m_uri_path(uri_path[0] == '/' ? uri_path+1 : uri_path)
                , m_next(nullptr) {}

            // Allow use of == and != operators
            bool operator==(const Resource& other) const;
            inline bool operator!=(const Resource& other) const
                { return !(*this == other); }

            // The Child class SHOULD override at least one of the following
            // event handlers corresponding to GET, POST, PUT, and DELETE
            // requests, respectively. Default behavior is to respond with the
            // 4.05 Method Not Allowed error code.
            virtual bool request_get(Connection* obj, Reader& msg)
                { return obj->error_response(CODE_BAD_METHOD, msg); }
            virtual bool request_post(Connection* obj, Reader& msg)
                { return obj->error_response(CODE_BAD_METHOD, msg); }
            virtual bool request_put(Connection* obj, Reader& msg)
                { return obj->error_response(CODE_BAD_METHOD, msg); }
            virtual bool request_delete(Connection* obj, Reader& msg)
                { return obj->error_response(CODE_BAD_METHOD, msg); }

        protected:
            // Member variables
            const char* const m_uri_path; // Path for this resource

        private:
            // Member variables
            friend satcat5::util::ListCore;
            Resource* m_next; // Linked list next node
        };

        // Resource that echos back any incoming payload
        class ResourceEcho : public Resource {
        public:
            // Constructor
            constexpr explicit ResourceEcho(const char* const uri_path)
                : Resource(uri_path) {}

            // Responds with the same payload as the request
            bool request_get(Connection* obj, Reader& msg) override;
        };

        // Resource that creates a Log entry
        class ResourceLog : public Resource {
        public:
            // Constructor
            constexpr ResourceLog(const char* const uri_path, s8 priority)
                : Resource(uri_path), m_priority(priority) {}

            // Creates a log entry with the given payload
            bool request_post(Connection* obj, Reader& msg) override;

        protected:
            // Member variables
            s8 m_priority; // Priority for created log messages
        };

        // Manager for several resources available on an Endpoint
        class ResourceServer : public satcat5::coap::EndpointUdp {
        public:
            // Constructor. By default, bind this server to port 5683.
            explicit ResourceServer(satcat5::udp::Dispatch* udp,
                satcat5::udp::Port port = satcat5::udp::PORT_COAP)
                : satcat5::coap::EndpointUdp(udp, port), m_connection(this, udp) {}

            // Add a resource to the linked list
            inline void add_resource(Resource* resource)
                { m_resources.add(resource); }

        protected:
            // Member variables
            satcat5::util::List<Resource> m_resources; // List of resources
            satcat5::coap::ConnectionUdp m_connection; // Single UDP connection

            // Handler for an incoming request
            void coap_request(Connection* obj, Reader& msg) override;
        };
    }
}
