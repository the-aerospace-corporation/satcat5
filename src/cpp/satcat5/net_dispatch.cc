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

#include <satcat5/net_dispatch.h>
#include <satcat5/net_protocol.h>
#include <satcat5/net_type.h>

using satcat5::net::Dispatch;
using satcat5::net::Protocol;
using satcat5::net::Type;

bool Dispatch::bound(const Type& type) const
{
    Protocol* item = m_list.head();
    while (item) {
        if (item->m_filter.m_value == type.m_value)
            return true;    // Found a match!
        item = m_list.next(item);
    }
    return false;           // No match found.
}

bool Dispatch::deliver(const Type& type,
    satcat5::io::Readable* src, unsigned len)
{
    Protocol* item = m_list.head();
    while (item) {
        if (item->m_filter.m_value == type.m_value) {
            satcat5::io::LimitedRead tmp(src, len);
            item->frame_rcvd(tmp);
            return true;    // Delivery successful!
        }
        item = m_list.next(item);
    }
    return false;           // No match found.
}
