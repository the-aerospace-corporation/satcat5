//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/tcp_core.h>

using satcat5::tcp::Header;

void Header::chk_incr16(u16 prev, u16 next) {
    // Apply the ~m + m' method of RFC1624 Section 3.
    u16 tmp[2] = {u16(~prev), next};
    data[8] = satcat5::ip::checksum(2, tmp, chk());
}

void Header::chk_incr32(u32 prev, u32 next) {
    // Apply the ~m + m' method of RFC1624 Section 3.
    u32 tmp[2] = {u32(~prev), next};
    data[8] = satcat5::ip::checksum(4, (u16*)tmp, chk());
}

void Header::write_to(satcat5::io::Writeable* wr) const {
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    for (unsigned a = 0 ; a < hdr ; ++a)
        wr->write_u16(data[a]);         // Write each word in network order
}

bool Header::read_core(satcat5::io::Readable* rd) {
    // Sanity check before we start.
    if (rd->get_read_ready() < tcp::HDR_MIN_BYTES) return false;

    // Read each word in the "core" header (i.e., first 20 bytes).
    for (unsigned a = 0 ; a < tcp::HDR_MIN_SHORTS ; ++a)
        data[a] = rd->read_u16();

    // Sanity check the "data offset" field.
    return ihl() >= tcp::HDR_MIN_WORDS;
}

bool Header::read_from(satcat5::io::Readable* rd) {
    // Attempt to read the initial header (first 20 bytes).
    if (!read_core(rd)) return false;

    // Bytes remaining in header options?
    unsigned hdr = 2 * ihl();           // Header length (16-bit words)
    unsigned rem = 2 * hdr - tcp::HDR_MIN_BYTES;
    if (rd->get_read_ready() < rem) return false;

    // Read extended header options, if any.
    for (unsigned a = tcp::HDR_MIN_SHORTS ; a < hdr ; ++a)
        data[a] = rd->read_u16();

    return true;
}
