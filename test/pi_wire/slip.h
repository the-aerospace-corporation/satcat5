//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation
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

#ifndef PIWIRE_SLIP_H
#define PIWIRE_SLIP_H

#include <stdint.h>

// Token definitions for the SLIP protocol
#define SLIP_END        0xC0
#define SLIP_ESC        0xDB
#define SLIP_ESC_END    0xDC
#define SLIP_ESC_ESC    0xDD

// SLIP encoder accepts an input array, encodes it, and writes the result to
// the designated device or file.
// Returns the number of bytes written, as with "write".)
int slip_encode_write(int fd, const uint8_t* buffer, unsigned len);

// SLIP decoder reads from designated device or file. Decode the next frame
// or up to maxlen bytes, whichever comes first, and copy to output array.
// Returns the number of bytes in the output buffer, or zero on error.
unsigned slip_read_decode(int fd, uint8_t* buffer, unsigned maxlen);

// Structure for storing two or three file descriptors.
class ethernet_if;              // Class prototype (see ethernet.h)
struct fd_stoe {
    int src;                    // Source device
    ethernet_if* sink;          // Sink device (Ethernet)
};
struct fd_etos {
    ethernet_if* src;           // Source device (Ethernet)
    const char *sink1, *sink2;  // Sink FIFO(s) (0 to disable)
};

// Loop forever, reading SLIP data from file/device and writing to Ethernet.
// Input should be a pointer to fd_stoe. Return value is null.
void* slip_stoe_forever(void* fd_ptr);

// Loop forever, reading from Ethernet and writing SLIP data to
// one or both FIFO objects, as specified by filename.
void* slip_etos_forever(void* fd_ptr);

#endif
