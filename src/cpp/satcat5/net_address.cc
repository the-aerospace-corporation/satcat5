//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_writeable.h>
#include <satcat5/net_address.h>

using satcat5::net::Address;

bool Address::write_packet(unsigned nbytes, const void* data)
{
    auto wr = open_write(nbytes);
    if (!wr) return false;
    wr->write_bytes(nbytes, data);
    return wr->write_finalize();
}
