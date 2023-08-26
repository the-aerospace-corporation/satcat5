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

#include <satcat5/ip_core.h>

// Is a given IP-address in the multicast range?
bool satcat5::ip::Addr::is_multicast() const
{
    if (value == 0xFFFFFFFFu)
        return true;    // Limited broadcast (255.255.255.255 /32)
    else if (0xE0000000u <= value && value <= 0xEFFFFFFFu)
        return true;    // IP multicast (224.0.0.0 /4)
    else
        return false;   // All other addresses
}

// Is this a valid unicast IP?  (Not zero, not multicast.)
bool satcat5::ip::Addr::is_unicast() const
{
    return value && !is_multicast();
}

// Calculate or verify checksum using algorithm from RFC 1071:
// https://datatracker.ietf.org/doc/html/rfc1071
u16 satcat5::ip::checksum(unsigned wcount, const u16* data)
{
    u32 sum = 0;
    for (unsigned a = 0 ; a < wcount ; ++a)
        sum += data[a];
    while (sum >> 16)
        sum = (sum & UINT16_MAX) + (sum >> 16);
    return (u16)(~sum);
}
