//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
