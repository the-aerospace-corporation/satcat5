//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "uart.h"

// STD includes
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>
#include <sys/select.h>

// Local includes
#include "slip.h"

// Initializes the serial device with the given name and directory
int uart_init(const char* dev)
{
    // Opens the serial device
    int fd = open(dev, O_RDWR | O_NOCTTY);

    // Creates a termios structure to hold IO flags
    struct termios tty;
    memset(&tty, 0, sizeof(struct termios));
    if (tcgetattr(fd, &tty) != 0)
    return -1;

    // Sets the input and output baud rate for the serial device
    cfsetospeed(&tty, (speed_t)B921600);
    cfsetispeed(&tty, (speed_t)B921600);

    // Sets the serial port to be in raw mode (no flow control)
    cfmakeraw(&tty);

    // Sets the port to use the specififed parameters
    if (tcsetattr(fd, TCSANOW, &tty) != 0)
    return -1;

    // Flushes all unread input and output from the serial port
    tcflush(fd, TCIOFLUSH);

    // Returns the file descriptor for the serial device
    return fd;
}

// Wait up to N microseconds for data to be available.
bool wait_for_data(int fd, unsigned msec)
{
    // Create file-set object.
    fd_set set;
    FD_ZERO(&set);
    FD_SET(fd, &set);

    // Call select to check read availability.
    struct timeval timeout;
    timeout.tv_sec  = 0;
    timeout.tv_usec = 1000*msec;
    int rv = select(fd+1, &set, NULL, NULL, &timeout);

    // Is data available?
    return (rv > 0);
}

// This thread perpetually copies data from FIFO to UART.
void* uart_send_forever(void* params_void)
{
    uart_params params = *reinterpret_cast<uart_params*>(params_void);

    // Open the buffer object.
    int fifo_fd = open(params.src_fifo, O_RDONLY);

    // Whenever SLIP data is available, copy it to the UART.
    // Note: Buffer size sets polling rate, unrelated to frame size.
    static const unsigned UART_BUFF_SIZE = 32;
    uint8_t buff[UART_BUFF_SIZE];
    while (1) {
        // Wait up to N seconds for data to be available.
        bool avail = wait_for_data(params.uart_fd, 1000);
        if (avail) {
            // Read and copy up to N bytes (already SLIP encoded)
            unsigned nbytes = read(fifo_fd, buff, UART_BUFF_SIZE);
            write(params.uart_fd, buff, nbytes);
        } else {
            // Read timeout: Send idle / keep-alive token.
            slip_encode_write(params.uart_fd, 0, 0);
        }
    }

    // Cleanup (should never be reached).
    close(fifo_fd);
    return 0;
}
