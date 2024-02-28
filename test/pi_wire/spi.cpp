//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "spi.h"

// STD includes
#include <errno.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

// System includes
#include <fcntl.h>
#include <linux/spi/spidev.h>
#include <pthread.h>
#include <sys/ioctl.h>

// Local includes
#include "slip.h"

// Set debugging verbosity level (0/1/2)
#define DEBUG_VERBOSE   0

// Initialize the SPI device at the given port using the given mode
int spi_init(const char* dev, uint8_t spi_mode)
{
    int fd;
    char mode;

    // Convert mode index to appropriate IOCTL flag
    switch (spi_mode) {
        case 0:
            mode = SPI_MODE_0;
            break;
        case 1:
            mode = SPI_MODE_1;
            break;
        case 2:
            mode = SPI_MODE_2;
            break;
        case 3:
            mode = SPI_MODE_3;
            break;
        default:
            mode = SPI_MODE_3;
            break;
    }

    // Open and configure the device
    fd = open(dev, O_RDWR);
    if (fd < 0) {
        printf("%s\n","failed to open SPI BUS");
        return -1;
    } else if (DEBUG_VERBOSE > 0) {
        printf("%s\n","succesfully opened SPI BUS");
    }

    if (ioctl(fd, SPI_IOC_WR_MODE, &mode)<0) {
        printf("Failed to set SPI mode.\n");
        return -1;
    } else if (DEBUG_VERBOSE > 0) {
        printf("Succesfully set SPI mode.\n");
    }
    return fd;
}

// Performs a simultaneous read and write operation for an SPI bus.
// (Specify buffers, buffer size, and baud rate.)
int spi_rw(int fd, const uint8_t* tx, uint8_t* rx, unsigned len, unsigned speed_hz)
{
    struct spi_ioc_transfer tr;
    memset(&tr, 0, sizeof(tr));
    tr.tx_buf = (unsigned long)tx;
    tr.rx_buf = (unsigned long)rx;
    tr.len = len;
    tr.delay_usecs = 0;
    tr.speed_hz = speed_hz;
    tr.cs_change = 0;
    tr.bits_per_word = 8;

    return ioctl(fd, SPI_IOC_MESSAGE(1), &tr);
}

// Parameters object for copy_helper_* threads.  There are three threads:
//   * Thread #1: Copy for Ethernet receive buffer (already SLIP-encoded)
//                to a working input array (i.e., buff_rda / buff_rdb)
//   * Thread #2: Concurrently executes the SPI read/write operation.
//                SPI transmit data is read from buff_rda / buff_rdb.
//                SPI received data is written to buff_wra / buff_wrb.
//   * Thread #3: Copy from the working output array (buff_wra / buff_wra)
//                to the Ethernet transmit buffer (data remains SLIP-encoded).
// The threads are ping-pong between two sets of working arrays as follows:
//   Time-slice:    1 2 3 4 5 6 ...
//   T1 writes to:  A B A B A B ...
//   T2 reads from:   A B A B A ...
//   T2 writes to:    A B A B A ...
//   T3 reads from:     A B A B ...
// Since all threads read and write fixed-size blocks, they simply operate in
// lockstep.  Timing is coordinated using a pthread synchronization barrier.
// Note: Buffer size sets polling rate; no relation to Ethernet frame size.
static const unsigned SPI_BUFF_SIZE = 512;
struct copy_params {
    pthread_barrier_t barrier;          // Synchronization object
    int fifo_tx, fifo_rx;               // FIFO file descriptors
    uint8_t buff_rda[SPI_BUFF_SIZE];    // Double-buffers for read
    uint8_t buff_rdb[SPI_BUFF_SIZE];
    uint8_t buff_wra[SPI_BUFF_SIZE];    // Double-buffers for write
    uint8_t buff_wrb[SPI_BUFF_SIZE];
};

// Helper functions for reading or writing one block of working-buffer data.
void helper_btof_once(int fd, const uint8_t* buff)
{
    // Copy data directly, no processing until later.
    write(fd, buff, SPI_BUFF_SIZE);
}

void helper_ftob_once(int fd, uint8_t* buff)
{
    // Non-blocking read of up to N bytes.
    ssize_t result = read(fd, buff, SPI_BUFF_SIZE);
    unsigned nread = (result < 0) ? 0 : result;

    // If there's any remaining space, fill it with idle tokens.
    while (nread < SPI_BUFF_SIZE) {
        buff[nread++] = SLIP_END;
    }
}

// Helper thread that copies array data from working buffer to FIFO.
void* helper_btof_forever(void* params_void)
{
    copy_params* params = reinterpret_cast<copy_params*>(params_void);

    // Startup delay (nothing to do for first two blocks).
    pthread_barrier_wait(&params->barrier);

    // Ping-pong between A and B buffers forever...
    int fd = params->fifo_rx;
    while (1) {
        pthread_barrier_wait(&params->barrier); // Wait until A ready
        helper_btof_once(fd, params->buff_rda); // Consume A buffer
        pthread_barrier_wait(&params->barrier); // Wait until B ready
        helper_btof_once(fd, params->buff_rdb); // Consume B buffer
    }

    // Cleanup (should never be reached).
    return 0;
}

// Helper thread that copies array data from FIFO to working buffer.
void* helper_ftob_forever(void* params_void)
{
    copy_params* params = reinterpret_cast<copy_params*>(params_void);

    // Ping-pong between A and B buffers forever...
    int fd = params->fifo_tx;
    while (1) {
        helper_ftob_once(fd, params->buff_wra); // Prepare A buffer
        pthread_barrier_wait(&params->barrier); // Signal A ready
        helper_ftob_once(fd, params->buff_wrb); // Prepare B buffer
        pthread_barrier_wait(&params->barrier); // Signal B ready
    }

    // Cleanup (should never be reached).
    return 0;
}

// This thread constantly runs SPI clock and copies data to/from FIFO.
void* spi_run_forever(void* params_void)
{
    spi_params params = *reinterpret_cast<spi_params*>(params_void);

    // Open FIFOs and start the two helper threads.
    copy_params* cparams = new copy_params;
    cparams->fifo_tx = open(params.fifo_tx, O_RDONLY | O_NONBLOCK);
    cparams->fifo_rx = open(params.fifo_rx, O_WRONLY);
    pthread_barrier_init(&cparams->barrier, NULL, 3);

    pthread_t help_btof, help_ftob;
    pthread_create(&help_btof, NULL, helper_btof_forever, cparams);
    pthread_create(&help_ftob, NULL, helper_ftob_forever, cparams);

    // Ping-pong between A and B buffers forever...
    while (1) {
        pthread_barrier_wait(&cparams->barrier);    // Wait for A ready
        spi_rw(params.spi_fd,                       // Read/write A buffers
            cparams->buff_wra, cparams->buff_rda,
            SPI_BUFF_SIZE, params.speed_hz);
        pthread_barrier_wait(&cparams->barrier);    // Wait for B ready
        spi_rw(params.spi_fd,                       // Read/write B buffers
            cparams->buff_wrb, cparams->buff_rdb,
            SPI_BUFF_SIZE, params.speed_hz);
    }

    // Cleanup (should never be reached).
    pthread_join(help_btof, NULL);
    pthread_join(help_ftob, NULL);
    pthread_barrier_destroy(&cparams->barrier);
    close(cparams->fifo_tx);
    close(cparams->fifo_rx);
    delete cparams;
    return 0;
}
