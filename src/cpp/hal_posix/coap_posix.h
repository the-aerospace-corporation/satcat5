//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CoAP client/server implementations that require POSIX features.

#pragma once
#include <satcat5/coap_client.h>
#include <satcat5/coap_endpoint.h>
#include <vector>

namespace satcat5 {
    namespace coap {
        //! Variant of ManageUdp using heap-allocated Connection objects.
        class ManageUdpHeap : public satcat5::coap::ManageUdp {
        public:
            //! Constructor binds to the specified UDP interface and
            //! immediately allocates each requested Connection object.
            ManageUdpHeap(satcat5::coap::Endpoint* coap, unsigned size);
            ~ManageUdpHeap();

            //! Fetch connection object by index.
            inline ConnectionUdp* connection(unsigned idx)
                { return m_connections[idx]; }

        protected:
            //! Pointers to heap-allocated Connection objects.
            std::vector<ConnectionUdp*> m_connections;
        };

        //! CoAP client/server implementation that requires POSIX features.
        //! User must define coap_* event handlers (e.g., coap_request).
        class EndpointUdpHeap
            : public satcat5::coap::Endpoint
            , public satcat5::coap::ManageUdpHeap {
        protected:
            //! Constructor binds to the specified UDP interface and
            //! immediately allocates each requested Connection object.
            EndpointUdpHeap(satcat5::udp::Dispatch* udp, unsigned size);
            ~EndpointUdpHeap() {}
        };
    }
};
