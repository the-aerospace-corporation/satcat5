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

#ifndef PIWIRE_ETHERNET_H
#define PIWIRE_ETHERNET_H

#include <stdint.h>

// Maximum Ethernet frame size is 1530 bytes plus margin. (No jumbo frames)
#define ETH_FRAME_SIZE  2000

class ethernet_if {
public:
    // Open the interface by name.
    explicit ethernet_if(const char* interface);

    // Was the interface opened successfully?
    bool is_open() const;

    // Shut down this interface.
    void close();

    // Sends an Ethernet packet
    unsigned send(const uint8_t* packet, unsigned len);

    // Receives an Ethernet packet
    unsigned receive(uint8_t* packet, unsigned len);

private:
    int m_socket_fd;
    int m_interface_idx;
};

// Calculate Ethernet FCS (CRC32) for a given buffer and append it to end of buffer.
// Note: Requires 4 bytes of leftover space in buffer after end of packet.
uint32_t append_crc32(uint8_t* packet, unsigned len);

#endif
