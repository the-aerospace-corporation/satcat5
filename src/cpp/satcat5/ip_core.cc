//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

void satcat5::ip::Header::write_to(satcat5::io::Writeable* wr) const
{
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    for (unsigned a = 0 ; a < hdr ; ++a)
        wr->write_u16(data[a]);         // Write each word in network order
}

bool satcat5::ip::Header::read_from(satcat5::io::Readable* rd)
{
    // Sanity check before we start.
    if (rd->get_read_ready() < ip::HDR_MIN_BYTES) return false;

    // Read the initial header contents.
    for (unsigned a = 0 ; a < ip::HDR_MIN_SHORTS ; ++a)
        data[a] = rd->read_u16();       // Read each word in baseline
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    unsigned len = len_inner();         // Length of contained data (bytes)

    // Bytes remaining in header?
    unsigned rem = 2 * (hdr - ip::HDR_MIN_SHORTS);

    // Sanity-check various header fields:
    //  * Unsupported version or invalid length?
    //  * Remaining length matches expectations?
    //  * Ignore packets with fragmentation (not supported)
    if ((ver() != 4) || (hdr < ip::HDR_MIN_SHORTS)) return false;
    if (rd->get_read_ready() < rem + len) return false;
    if (frg()) return false;

    // Read extended header options, if any.
    // (Required for checksum, ICMP echo requests, etc.)
    for (unsigned a = ip::HDR_MIN_SHORTS ; a < hdr ; ++a)
        data[a] = rd->read_u16();

    // Verify checksum over entire header, using algorithm from RFC 1071.
    u16 chk = ip::checksum(hdr, data);
    return (chk == 0);
}
