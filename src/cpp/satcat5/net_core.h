//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
// Generic network Dispatch API
//
// This file is a catch-all for the SatCat5 generic "network" API:
//  * net::Address (net_address.h)
//    An "Address" is able to send data to a specific destination.
//  * net::Dispatch (net_dispatch.h)
//    A "Dispatch" unit sorts incoming packets to one of several Protocols.
//  * net::Protocol (net_protocol.h)
//    A "Protocol" accepts packets with a specific type, destination port,
//    etc. Some Protocols also act as Dispatch for the next layer.
//  * net::Type (net_type.h)
//    A "Type" is the numeric value that each Protocol uses to identify
//    the type of traffic it wants from the preceding Dispatch layer.
//
// New projects should typically include the above files directly, but this
// file is included for backwards-compatibility.
//

#pragma once

#include <satcat5/net_address.h>
#include <satcat5/net_dispatch.h>
#include <satcat5/net_protocol.h>
#include <satcat5/net_type.h>
