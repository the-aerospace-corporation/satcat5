//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_header.h>
#include <satcat5/log.h>

using satcat5::eth::Header;
using satcat5::eth::MacAddr;
using satcat5::eth::MacType;
using satcat5::eth::VlanTag;

bool MacAddr::operator==(const eth::MacAddr& other) const
{
    return (addr[0] == other.addr[0])
        && (addr[1] == other.addr[1])
        && (addr[2] == other.addr[2])
        && (addr[3] == other.addr[3])
        && (addr[4] == other.addr[4])
        && (addr[5] == other.addr[5]);
}

bool MacAddr::operator<(const eth::MacAddr& other) const
{
    for (unsigned a = 0 ; a < 6 ; ++a) {
        if (addr[a] < other.addr[a]) return true;
        if (addr[a] > other.addr[a]) return false;
    }
    return false;   // All bytes equal
}

bool MacAddr::is_broadcast() const
{
    // Match the broadcast address only (FF:FF:FF:FF:FF:FF).
    return (*this == MACADDR_BROADCAST);
}

bool MacAddr::is_l2multicast() const
{
    // Match the L2 multicast block:    (01:80:C2:**:**:**),
    // except for link-local addresses: (01:80:C2:00:00:**).
    return (addr[0] == BASEADDR_L2MULTICAST.addr[0])
        && (addr[1] == BASEADDR_L2MULTICAST.addr[1])
        && (addr[2] == BASEADDR_L2MULTICAST.addr[2])
        && !is_swcontrol();
}

bool MacAddr::is_l3multicast() const
{
    // Match the reserved UDP multicast block (01:00::5E:*:*:*).
    return (addr[0] == BASEADDR_L3MULTICAST.addr[0])
        && (addr[1] == BASEADDR_L3MULTICAST.addr[1])
        && (addr[2] == BASEADDR_L3MULTICAST.addr[2]);
}

bool MacAddr::is_multicast() const
{
    // Match any type of broadcast or multicast address range.
    return is_broadcast() || is_l2multicast() || is_l3multicast();
}

bool MacAddr::is_swcontrol() const
{
    // Address block (01:80:C2:00:00:*) is reserved for link-local control
    // messages, such as pause frames, Spanning Tree Protocol, etc.
    return (addr[0] == BASEADDR_LINKLOCAL.addr[0])
        && (addr[1] == BASEADDR_LINKLOCAL.addr[1])
        && (addr[2] == BASEADDR_LINKLOCAL.addr[2])
        && (addr[3] == BASEADDR_LINKLOCAL.addr[3])
        && (addr[4] == BASEADDR_LINKLOCAL.addr[4]);
}

bool MacAddr::is_unicast() const
{
    // Is this a normal unicast MAC? (i.e., Not from a reserved block.)
    return is_valid() && !(is_multicast() || is_swcontrol());
}

bool MacAddr::is_valid() const
{
    // Is this a valid MAC of any kind? (i.e., Not zero).
    return (*this != MACADDR_NONE);
}

void MacAddr::log_to(satcat5::log::LogBuffer& wr) const
{
    // Convention is six hex bytes with ":" delimeter.
    // e.g., "DE:AD:BE:EF:CA:FE"
    for (unsigned a = 0 ; a < 6 ; ++a) {
        if (a) wr.wr_str(":");
        wr.wr_h32(addr[a], 2);
    }
}

void MacType::log_to(satcat5::log::LogBuffer& wr) const
{
    wr.wr_str(" = 0x");
    wr.wr_h32(value, 4);
}

void VlanTag::log_to(satcat5::log::LogBuffer& wr) const
{
    wr.wr_str("\r\n  VlanID = 0x"); wr.wr_h32(vid(), 3);
    wr.wr_str("\r\n  DropOK = ");   wr.wr_d32(dei());
    wr.wr_str("\r\n  Priority = "); wr.wr_d32(pcp());
}

void Header::log_to(satcat5::log::LogBuffer& wr) const
{
    wr.wr_str("\r\n  DstMAC = ");   dst.log_to(wr);
    wr.wr_str("\r\n  SrcMAC = ");   src.log_to(wr);
    wr.wr_str("\r\n  EType ");      type.log_to(wr);
    if (vtag.value)                 vtag.log_to(wr);
}

void Header::write_to(io::Writeable* wr) const
{
    dst.write_to(wr);
    src.write_to(wr);
    if (SATCAT5_VLAN_ENABLE && vtag.value) {
        satcat5::eth::ETYPE_VTAG.write_to(wr);
        vtag.write_to(wr);
    }
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
        if (SATCAT5_VLAN_ENABLE && type == ETYPE_VTAG) {
            if (rd->get_read_ready() >= 4) {
                vtag.read_from(rd); // Tagged frame
                type.read_from(rd);
            } else {
                return false;       // Error (incomplete tag)
            }
        } else {
            vtag.value = 0;         // Untagged frame
        }
        return true;                // Success
    }
}
