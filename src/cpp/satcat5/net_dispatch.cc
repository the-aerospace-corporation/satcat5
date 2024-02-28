//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
