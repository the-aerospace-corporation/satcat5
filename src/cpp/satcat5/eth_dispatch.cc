//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_dispatch.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/timer.h>

namespace eth = satcat5::eth;
using satcat5::eth::Dispatch;
using satcat5::net::Type;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Baseline Ethenret header is 14 bytes (dst + src + type).
// IEEE 802.1q VLAN tags add another four bytes.
constexpr unsigned ETH_HEADER_BYTES = SATCAT5_VLAN_ENABLE ? 18 : 14;

Dispatch::Dispatch(
        const eth::MacAddr& addr,
        satcat5::io::Writeable* dst,
        satcat5::io::Readable* src,
        satcat5::util::GenericTimer* timer)
    : m_addr(addr)  // MAC address for this endpoint
    , m_dst(dst)    // Destination pipe (Writeable)
    , m_src(src)    // Source pipe (Readable)
    , m_timer(timer)
    , m_reply_macaddr(eth::MACADDR_BROADCAST)
    #if SATCAT5_VLAN_ENABLE
    , m_reply_vtag(eth::VTAG_NONE)
    , m_default_vid(eth::VTAG_NONE)
    #endif
{
    m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
Dispatch::~Dispatch()
{
    m_src->set_callback(0);
}
#endif

satcat5::io::Writeable* Dispatch::open_reply(const Type& type, unsigned len)
{
    eth::MacType etype;
    eth::VlanTag vtag;

    if (DEBUG_VERBOSE > 1) {
        if (SATCAT5_VLAN_ENABLE) {
            log::Log(log::DEBUG, "EthDispatch: open_reply").write(type.as_u32());
        } else {
            log::Log(log::DEBUG, "EthDispatch: open_reply").write(type.as_u16());
        }
    }

    // Abort if there's not enough space for the entire frame.
    if (m_dst->get_write_space() < ETH_HEADER_BYTES + len) return 0;

    if (SATCAT5_VLAN_ENABLE) {
        // VLAN support: Pull EtherType and VLAN tag from "type" parameter.
        type.as_pair(vtag.value, etype.value);
        // Use specified VID if present; otherwise use the stored reply VID.
        if (vtag.vid() == 0) vtag.value |= m_reply_vtag.value;
        return open_write(m_reply_macaddr, etype, vtag);
    } else {
        // No VLAN support, EtherType is the only parameter.
        type.as_u16(etype.value);
        return open_write(m_reply_macaddr, etype);
    }
}

#if SATCAT5_VLAN_ENABLE
satcat5::io::Writeable* Dispatch::open_write(
    const eth::MacAddr& dst,
    const eth::MacType& type,
    eth::VlanTag vtag)
#else
satcat5::io::Writeable* Dispatch::open_write(
    const eth::MacAddr& dst,
    const eth::MacType& type)
#endif
{
    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "EthDispatch: open_write").write(type.value);

    // Sanity check: Valid destination?
    if (dst == satcat5::eth::MACADDR_NONE) return 0;

    // Sanity check: Valid EtherType?
    // (Transmission of ye olde style frame length is not supported.)
    if (type.value < 1536) return 0;

    // Sanity check: Is there room for the frame header?
    // If not, wait a few microseconds and try again before giving up.
    // (Workaround for edge-case where MailMap block is still busy.)
    if (m_dst->get_write_space() < ETH_HEADER_BYTES) {
        if (m_timer) m_timer->busywait_usec(20);
        if (m_dst->get_write_space() < ETH_HEADER_BYTES) return 0;
    }

    // Override outgoing VID, if none is specified.
    // (Useful for ports where VLAN tags are mandatory.)
    #if SATCAT5_VLAN_ENABLE
    if (vtag.vid() == 0) vtag.value |= m_default_vid.value;
    #endif

    // Write out the Ethernet frame header:
    m_dst->write_obj(dst);          // Destination
    m_dst->write_obj(m_addr);       // Source
    #if SATCAT5_VLAN_ENABLE
    if (vtag.value) {
        m_dst->write_obj(satcat5::eth::ETYPE_VTAG);
        m_dst->write_obj(vtag);     // VLAN tag (optional)
    }
    #endif
    m_dst->write_obj(type);         // EtherType

    // Ready to start writing frame contents.
    return m_dst;
}

void Dispatch::set_macaddr(const satcat5::eth::MacAddr& macaddr)
{
    m_addr = macaddr;
}

void Dispatch::data_rcvd()
{
    // Attempt to read the Ethernet frame header.
    eth::Header hdr;
    bool pending = m_src->read_obj(hdr);

    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "EthDispatch: data_rcvd ").write(pending ? "OK" : "Error");

    // Store reply address.
    m_reply_macaddr = hdr.src;

    // Attempt delivery using specific VLAN tag, if applicable (VID > 0)
    // (This allows VLAN-specific handlers to take priority over generic ones.)
    #if SATCAT5_VLAN_ENABLE
    m_reply_vtag.value = hdr.vtag.vid();    // Store VID field only (LSBs)
    if (pending && hdr.vtag.vid()) {
        Type typ_vlan(hdr.vtag.vid(), hdr.type.value);
        pending = !deliver(typ_vlan, m_src, m_src->get_read_ready());
    }
    #endif

    // Attempt delivery using EtherType only (basic service or catch-all).
    if (pending) {
        Type typ_basic(hdr.type.value);
        pending = !deliver(typ_basic, m_src, m_src->get_read_ready());
    }

    // If we reach this point, all delivery attempts failed.
    if (pending && DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "EthDispatch: Unsupported EtherType").write(hdr.type.value);

    // Clean-up rest of packet, if applicable.
    m_src->read_finalize();
}
