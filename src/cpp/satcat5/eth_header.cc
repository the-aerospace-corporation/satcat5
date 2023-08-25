//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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

#include <satcat5/eth_header.h>

using satcat5::eth::Header;
using satcat5::eth::MacAddr;

bool MacAddr::operator==(const eth::MacAddr& other) const {
    return (addr[0] == other.addr[0])
        && (addr[1] == other.addr[1])
        && (addr[2] == other.addr[2])
        && (addr[3] == other.addr[3])
        && (addr[4] == other.addr[4])
        && (addr[5] == other.addr[5]);
}

bool MacAddr::operator<(const eth::MacAddr& other) const {
    for (unsigned a = 0 ; a < 6 ; ++a) {
        if (addr[a] < other.addr[a]) return true;
        if (addr[a] > other.addr[a]) return false;
    }
    return false;   // All bytes equal
}

void Header::write_to(io::Writeable* wr) const
{
    dst.write_to(wr);
    src.write_to(wr);
    #if SATCAT5_VLAN_ENABLE
    if (vtag.value) {
        satcat5::eth::ETYPE_VTAG.write_to(wr);
        vtag.write_to(wr);
    }
    #endif
    type.write_to(wr);
}

bool Header::read_from(io::Readable* rd)
{
    if (rd->get_read_ready() < 14) {
        return false;               // Error (incomplete header)
    } else {
        dst.read_from(rd);          // Read primary header
        src.read_from(rd);
        type.read_from(rd);
        #if SATCAT5_VLAN_ENABLE
        if (type == ETYPE_VTAG) {
            if (rd->get_read_ready() >= 4) {
                vtag.read_from(rd); // Tagged frame
                type.read_from(rd);
            } else {
                return false;       // Error (incomplete tag)
            }
        } else {
            vtag.value = 0;         // Untagged frame
        }
        #endif
        return true;                // Success
    }
}
