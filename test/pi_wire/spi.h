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

#ifndef PIWIRE_SPI_H
#define PIWIRE_SPI_H

#include <stdint.h>

// Initializes the SPI device at the given port using the given mode
int spi_init(const char* dev, uint8_t spi_mode);

// Performs a simultaneous read and write operation for an SPI bus.
int spi_rw(int fd, const uint8_t* tx, uint8_t* rx, unsigned len, unsigned speed_hz);

// Structure for storing parameters for spi_run_forever.
struct spi_params {
    unsigned speed_hz;      // SPI baud rate
    int spi_fd;             // SPI device (file descriptor, see spi_init)
    const char* fifo_tx;    // Transmit buffer (filename)
    const char* fifo_rx;    // Receive buffer (filename)
};

// This thread constantly runs SPI clock and copies data to/from FIFO.
// Input should be a pointer to spi_params. Return value is null.
void* spi_run_forever(void* param_ptr);

#endif
