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

#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/net_echo.h>
#include <satcat5/udp_dispatch.h>

using satcat5::net::ProtoEcho;
using satcat5::net::Type;
namespace log = satcat5::log;

// Set verbosity level (0/1)
static const unsigned DEBUG_VERBOSE = 0;

// Define each of the thin wrappers:
satcat5::eth::ProtoEcho::ProtoEcho(
        satcat5::eth::Dispatch* iface,
        satcat5::eth::MacType type_req,
        satcat5::eth::MacType type_ack)
    : satcat5::net::ProtoEcho(iface,
        Type(type_req.value), Type(type_ack.value))
{
    // Nothing else to initialize.
}

satcat5::udp::ProtoEcho::ProtoEcho(
        satcat5::udp::Dispatch* iface,
        satcat5::udp::Port port)
    : satcat5::net::ProtoEcho(iface,
        Type(port.value), Type(port.value))
{
    // Nothing else to initialize.
}

// Main class definition:
ProtoEcho::ProtoEcho(
        satcat5::net::Dispatch* iface,
        const Type& type_req,
        const Type& type_ack)
    : satcat5::net::Protocol(type_req)
    , m_iface(iface)
    , m_replytype(type_ack)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
ProtoEcho::~ProtoEcho()
{
    m_iface->remove(this);
}
#endif

void ProtoEcho::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // Attempt to open a reply object.
    unsigned nreply = src.get_read_ready();
    satcat5::io::Writeable* dst = m_iface->open_reply(m_replytype, nreply);

    if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "ProtoEcho").write((u16)nreply);
    }

    // If successful, copy input to output.
    if (dst) {
        while (nreply--)
            dst->write_u8(src.read_u8());
        dst->write_finalize();
    }
}
