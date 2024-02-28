//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "slip.h"

// STD includes
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// Network includes
#include <arpa/inet.h>
#include <linux/if_packet.h>
#include <net/if.h>

// Local includes
#include "ethernet.h"

// Set debugging verbosity level (0/1/2)
#define DEBUG_VERBOSE   0

// Encode array data and write to device.
int slip_encode_write(int fd, const uint8_t* rbuff, unsigned rlen)
{
    // Encode the entire array at once.  Max output size is 2N+1.
    uint8_t wbuff[rlen * 2 + 1];
    unsigned widx = 0;

    // SLIP-encode each input byte.
    for (unsigned i = 0; i < rlen; ++i) {
        switch (rbuff[i]) {
            case SLIP_END:
                // Escape the byte
                wbuff[widx++] = SLIP_ESC;
                wbuff[widx++] = SLIP_ESC_END;
                break;

            case SLIP_ESC:
                // Escape the byte
                wbuff[widx++] = SLIP_ESC;
                wbuff[widx++] = SLIP_ESC_ESC;
                break;

            default:
                // No escape needed, just copy
                wbuff[widx++] = rbuff[i];
                break;
        }
    }

    // Terminate the output and write
    wbuff[widx++] = SLIP_END;
    return write(fd, wbuff, widx);
}

// Read and decode data from file or device.
unsigned slip_read_decode(int fd, uint8_t* buffer, unsigned maxlen)
{
    unsigned wcount = 0;
    uint8_t next = SLIP_END;

    // Ignore any preceding interframe token(s)
    while (next == SLIP_END) {
        read(fd, &next, 1);
    }

    // Reads from the FIFO until the buffer is full or the END byte is seen
    while (wcount < maxlen) {
        // Byte-at-a-time SLIP decoder state machine
        switch (next) {
            case SLIP_END:
                // End of frame
                return wcount;
            case SLIP_ESC:
                // Get the next byte to determine which byte was escaped
                read(fd, &next, 1);
                if (next == SLIP_ESC_END) {
                    buffer[wcount++] = SLIP_END;
                } else if (next == SLIP_ESC_ESC) {
                    buffer[wcount++] = SLIP_ESC;
                } else {
                    return 0;   // Invalid token, abort
                }
                break;
            // If we see any other byte
            default:
                // Add the input byte to the buffer
                buffer[wcount++] = next;
                break;
        }

        // Read the next byte
        read(fd, &next, 1);
    }

    // Reached end of output buffer
    return maxlen;
}

// Helper function calls "slip_encode_write" if the file descriptor is valid.
void send_if_valid(const char* lbl, int fd, const uint8_t* data, unsigned nbytes)
{
    if (fd >= 0) {
        int result = slip_encode_write(fd, data, nbytes);
        if (DEBUG_VERBOSE == 0) {
            // Do nothing.
        } else if (result > 0) {
            printf("%s Sent: %u\n", lbl, nbytes);
        } else {
            printf("%s Drop: %u\n", lbl, nbytes);
        }
    }
}

// Open a buffer for writing.
int open_if_valid(const char* path)
{
    // Ignore NULL or empty filenames.
    if ((!path) || (*path == 0)) return -1;

    // Otherwise, open the designated FIFO object in write mode.
    // Note: This blocks until the read side is also opened.
    int fd = open(path, O_WRONLY);

    // Once open, set non-blocking flag to allow overflows to be discarded.
    // (Ethernet is always faster, so we set a fairly small buffer size.)
    int flags = fcntl(fd, F_GETFL);
    fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    fcntl(fd, F_SETPIPE_SZ, 65536);

    return fd;
}

// Loop forever, reading SLIP data from file/device and relaying to Ethernet.
void* slip_stoe_forever(void* fd_ptr)
{
    fd_stoe params = *reinterpret_cast<fd_stoe*>(fd_ptr);
    uint8_t buffer[ETH_FRAME_SIZE];

    while (1) {
        // Attempt to read a full frame from the serial line.
        int bytes_read = slip_read_decode(params.src, buffer, ETH_FRAME_SIZE);
        if (DEBUG_VERBOSE > 0)
            printf("Serial Rcvd: %d\n", bytes_read);

        // Send received packet, if any, through the Ethernet device.
        // Truncate the checksum (last 4 bytes); device adds its own.
        if (bytes_read >= 4) {
            params.sink->send(buffer, (unsigned)(bytes_read-4));
            if (DEBUG_VERBOSE > 0)
                printf("Ethernet Sent: %d\n", bytes_read);
        } else if (DEBUG_VERBOSE > 1) {
            printf("Ethernet Idle.\n");
        }
    }

    return 0;
}

// Loop forever, reading from Ethernet and writing SLIP data to a file/device.
void* slip_etos_forever(void* fd_ptr)
{
    fd_etos params = *reinterpret_cast<fd_etos*>(fd_ptr);
    uint8_t buffer[ETH_FRAME_SIZE];

    // Open each applicable buffer object for writing.
    int fd_buff1 = open_if_valid(params.sink1);
    int fd_buff2 = open_if_valid(params.sink2);

    // Keep reading data forever...
    while (1) {
        // Attempt to read a packet from the Ethernet device.
        // Note: Leave at least 4-bytes so we can append CRC safely.
        unsigned bytes_read = params.src->receive(buffer, ETH_FRAME_SIZE-4);
        if (DEBUG_VERBOSE > 0)
            printf("Ethernet Rcvd: %u\n", bytes_read);

        // For a valid packet, append CRC and relay to each output.
        // If we didn't get anything, send a keep-alive placeholder.
        if (bytes_read > 0) {
            append_crc32(buffer, bytes_read);
            send_if_valid("Serial1", fd_buff1, buffer, bytes_read+4);
            send_if_valid("Serial2", fd_buff2, buffer, bytes_read+4);
        } else {
            send_if_valid("Serial1", fd_buff1, 0, 0);
            send_if_valid("Serial2", fd_buff2, 0, 0);
        }
    }

    // Cleanup (never reached).
    if (fd_buff1 >= 0) close(fd_buff1);
    if (fd_buff2 >= 0) close(fd_buff2);
    return 0;
}
