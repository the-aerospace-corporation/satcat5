//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::ip::Header;

void satcat5::ip::Addr::log_to(satcat5::log::LogBuffer& wr) const {
    // Extract individual bytes from the 32-bit IP-address.
    u32 ip_bytes[] = {
        (value >> 24) & 0xFF,   // MSB-first
        (value >> 16) & 0xFF,
        (value >>  8) & 0xFF,
        (value >>  0) & 0xFF,
    };

    // Convention is 4 decimal numbers with "." delimiter.
    // e.g., "192.168.1.42"
    for (unsigned a = 0 ; a < 4 ; ++a) {
        if (a) wr.wr_str(".");
        wr.wr_dec(ip_bytes[a]);
    }
}

void satcat5::ip::Subnet::log_to(satcat5::log::LogBuffer& wr) const {
    // Example: "192.168.1.42 / 255.255.255.0"
    satcat5::ip::Addr base(addr.value & mask.value);
    base.log_to(wr);
    wr.wr_str(" / ");
    mask.log_to(wr);
}

bool satcat5::ip::Addr::is_broadcast() const {
    return (value == 0xFFFFFFFFu);  // Limited broadcast 255.255.255.255
}

bool satcat5::ip::Addr::is_multicast() const {
    if (value == 0xFFFFFFFFu)
        return true;    // Limited broadcast (255.255.255.255 /32)
    else if (0xE0000000u <= value && value <= 0xEFFFFFFFu)
        return true;    // IP multicast (224.0.0.0 /4)
    else
        return false;   // All other addresses
}

bool satcat5::ip::Addr::is_reserved() const {
    if (value <= 0x00FFFFFFu)
        return true;    // Reserved source (0.0.0.0 /8)
    else if (0x7F000000u <= value && value <= 0x7FFFFFFFu)
        return true;    // Local loopback (127.0.0.0 /8)
    else
        return false;   // All other addresses
}

bool satcat5::ip::Addr::is_unicast() const {
    return value && !is_multicast();
}

bool satcat5::ip::Addr::is_valid() const {
    return value != 0;
}

unsigned satcat5::ip::Mask::prefix() const {
    return satcat5::util::popcount(value);
}

// Calculate or verify checksum using algorithm from RFC 1071:
// https://datatracker.ietf.org/doc/html/rfc1071
u16 satcat5::ip::checksum(unsigned wcount, const u16* data, u16 prev) {
    u32 sum = u32(~prev & 0xFFFF);
    for (unsigned a = 0 ; a < wcount ; ++a)
        sum += data[a];
    while (sum >> 16)
        sum = (sum & UINT16_MAX) + (sum >> 16);
    return (u16)(~sum);
}

void Header::write_to(satcat5::io::Writeable* wr) const {
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    for (unsigned a = 0 ; a < hdr ; ++a)
        wr->write_u16(data[a]);         // Write each word in network order
}

void Header::chk_incr16(u16 prev, u16 next) {
    // Apply the ~m + m' method of RFC1624 Section 3.
    u16 tmp[2] = {u16(~prev), next};
    data[5] = satcat5::ip::checksum(2, tmp, chk());
}

void Header::chk_incr32(u32 prev, u32 next) {
    // Apply the ~m + m' method of RFC1624 Section 3.
    u32 tmp[2] = {u32(~prev), next};
    data[5] = satcat5::ip::checksum(4, (u16*)tmp, chk());
}

bool Header::read_core(satcat5::io::Readable* rd) {
    // Sanity check before we start.
    if (rd->get_read_ready() < ip::HDR_MIN_BYTES) return false;

    // Read each word in the "core" header (i.e., first 20 bytes).
    for (unsigned a = 0 ; a < ip::HDR_MIN_SHORTS ; ++a)
        data[a] = rd->read_u16();

    // Sanity-check various header fields:
    return (ver() == 4) && (ihl() >= 5) && (len_total() >= 4*ihl());
}

bool Header::read_from(satcat5::io::Readable* rd) {
    // Attempt to read the initial header (first 20 bytes).
    if (!read_core(rd)) return false;

    // Bytes remaining in header and in packet?
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    unsigned rem = 2 * (hdr - ip::HDR_MIN_SHORTS);
    unsigned len = len_inner();         // Length of contained data (bytes)

    // Sanity-check that we can read the rest of the packet.
    if (rd->get_read_ready() < rem + len) return false;

    // Read extended header options, if any.
    // (Required for checksum, ICMP echo requests, etc.)
    for (unsigned a = ip::HDR_MIN_SHORTS ; a < hdr ; ++a)
        data[a] = rd->read_u16();

    // Verify checksum over entire header, using algorithm from RFC 1071.
    u16 chk = ip::checksum(hdr, data);
    return (chk == 0);
}
