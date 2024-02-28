//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
