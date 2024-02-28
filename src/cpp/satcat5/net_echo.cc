//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
