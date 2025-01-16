//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Additional CoAP client/server implementations that require POSIX features.

#pragma once
#include <satcat5/coap_endpoint.h>
#include <vector>

namespace satcat5 {
    namespace coap {
        // Heap-allocated variant of the coap::EndpointUdp class.
        // User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdpHeap : public satcat5::coap::EndpointUdp {
        public:
            // Fetch connection object by index.
            ConnectionUdp* connection(unsigned idx)
                { return connections[idx]; }

        protected:
            // Constructor binds to the specified UDP interface and
            // immediately allocates each requested Connection object.
            EndpointUdpHeap(satcat5::udp::Dispatch* udp, unsigned size)
                : EndpointUdp(udp)
            {
                for (unsigned a = 0 ; a < size ; ++a)
                    connections.push_back(new ConnectionUdp(this, udp));
            }

            ~EndpointUdpHeap() {
                for (auto a = connections.begin() ; a != connections.end() ; ++a)
                    delete *a;
            }

            // Pointers to heap-allocated Connection objects.
            std::vector<ConnectionUdp*> connections;
        };
    }
};
