//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
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
