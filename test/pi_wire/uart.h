//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#ifndef PIWIRE_UART_H
#define PIWIRE_UART_H

// STL includes
#include <stdint.h>

// Initializes the given UART device
int uart_init(const char* dev);

// Structure for storing three file descriptors.
struct uart_params {
    const char* src_fifo;   // Source FIFO (filename)
    int uart_fd;            // UART device (file descriptor)
};

// This thread perpetually copies data from FIFO to UART.
// Input should be a pointer to uart_params. Return value is null.
void* uart_send_forever(void* param_ptr);

#endif
