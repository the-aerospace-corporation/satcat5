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
