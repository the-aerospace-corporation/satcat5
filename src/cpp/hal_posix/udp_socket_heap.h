//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Heap-allocated equivalent to udp::Socket.

#pragma once

#include <satcat5/udp_socket.h>

namespace satcat5 {
    namespace udp {
        class SocketHeap : public satcat5::udp::SocketCore {
        public:
            explicit SocketHeap(satcat5::udp::Dispatch* iface,
                unsigned txbytes=8192, unsigned rxbytes=8192);
            virtual ~SocketHeap();
        };
    }
}
