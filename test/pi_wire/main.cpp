//////////////////////////////////////////////////////////////////////////
// Copyright 2019 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

// STD includes
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

// Linux includes
#include <pthread.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <time.h>

// Local includes
#include "ethernet.h"
#include "uart.h"
#include "slip.h"
#include "spi.h"

// The names of the devices and interfaces used
#define UART_DEV    "/dev/ttyAMA0"
#define ETH_DEV     "eth0"
#define SPI_DEV     "/dev/spidev0.0"

// Software FIFO buffers filepaths
const char* FIFO_ETH_TO_UART = "/tmp/fifo_eth_to_uart";
const char* FIFO_ETH_TO_SPI = "/tmp/fifo_eth_to_spi";
const char* FIFO_SPI_TO_ETH = "/tmp/fifo_spi_to_eth";

// The settings for the SPI protocol
static const int SPI_MODE = 3;
static const unsigned SPI_BAUD = 3400000;

// Convert SPI and/or UART to Ethernet and back.
int serial_to_ethernet(int enable_spi, int enable_uart)
{
    // Attempt to initialize the Ethernet device.
    printf("Initializing ethernet device... ");
    ethernet_if eth(ETH_DEV);
    if (!eth.is_open()) {
        printf("Failed\n");
        return 1;
    } else {
        printf("Ready\n");
    }

    // Attempt to initialize SPI device, if enabled.
    int spi_fd = -1, spi_fifo = -1;
    if (enable_spi) {
        printf("Initializing SPI device... ");
        spi_fd = spi_init(SPI_DEV, SPI_MODE);
        if (spi_fd < 0) {
            printf("Failed\n");
            return 1;
        } else {
            printf("Ready\n");
        }
    }

    // Attempt to initialize UART device, if enabled.
    int uart_fd = -1;
    if (enable_uart) {
        printf("Initializing UART device... ");
        uart_fd = uart_init(UART_DEV);
        if (uart_fd < 0) {
            printf("Failed\n");
            return 1;
        } else {
            printf("Ready\n");
        }
    }

    // Create the FIFO objects, which are basically named pipes.
    // HOWEVER, we must open them in careful sequence because:
    //  * Blocking read --> Blocks until write is opened.
    //  * Blocking write --> Blocks until read is opened.
    //  * Non-blocking read --> OK.
    //  * Non-blocking write --> Fails if read is not opened.
    mkfifo(FIFO_ETH_TO_SPI, 0666);
    mkfifo(FIFO_SPI_TO_ETH, 0666);
    mkfifo(FIFO_ETH_TO_UART, 0666);

    // Ready to start the worker threads.
    pthread_t eth_thread;
    pthread_t spi_thread1, spi_thread2;
    pthread_t uart_thread1, uart_thread2;

    if (enable_spi || enable_uart) {
        // Ethernet Rx thread. (Copy to one or both buffers.)
        fd_etos params;
        params.src = &eth;
        params.sink1 = enable_spi ? FIFO_ETH_TO_SPI : 0;
        params.sink2 = enable_uart ? FIFO_ETH_TO_UART : 0;
        pthread_create(&eth_thread, NULL, slip_etos_forever, &params);
    }

    if (enable_spi) {
        // SPI working thread. (Combined Tx/Rx using buffers.)
        spi_params params;
        params.speed_hz = SPI_BAUD;
        params.spi_fd = spi_fd;
        params.fifo_tx = FIFO_ETH_TO_SPI;
        params.fifo_rx = FIFO_SPI_TO_ETH;
        pthread_create(&spi_thread1, NULL, spi_run_forever, &params);
        // Open our end of the Rx buffer (blocking).
        spi_fifo = open(FIFO_SPI_TO_ETH, O_RDONLY);
        // SPI Rx thread. (Decode and forward to Ethernet.)
        fd_stoe stoe;
        stoe.src = spi_fifo;
        stoe.sink = &eth;
        pthread_create(&spi_thread2, NULL, slip_stoe_forever, &stoe);
    }

    if (enable_uart) {
        // UART Tx thread. (Copy from buffer to UART.)
        uart_params params;
        params.src_fifo = FIFO_ETH_TO_UART;
        params.uart_fd = uart_fd;
        pthread_create(&uart_thread1, NULL, uart_send_forever, &params);
        // UART Rx thread. (Decode and forward to Ethernet.)
        fd_stoe stoe;
        stoe.src = uart_fd;
        stoe.sink = &eth;
        pthread_create(&uart_thread2, NULL, slip_stoe_forever, &stoe);
    }

    // Wait for the threads to end.
    printf("Running!");
    if (enable_spi || enable_uart) {
        pthread_join(eth_thread, NULL);
    }
    if (enable_spi) {
        pthread_join(spi_thread1, NULL);
        pthread_join(spi_thread2, NULL);
    }
    if (enable_uart) {
        pthread_join(uart_thread1, NULL);
        pthread_join(uart_thread2, NULL);
    }
    printf("Stopped!");

    // Cleanup (should never be reached)
    if (spi_fifo >= 0) close(spi_fifo);
    if (spi_fd >= 0) close(spi_fd);
    if (uart_fd >= 0) close(uart_fd);
    eth.close();
    return 0;
}

int print_help()
{
    printf("Usage: pi_wire [type]\n");
    printf("    Where [type] is either 'spi' or 'uart' or 'both'.\n");
    return -1;
}

int main(int argc, char** argv)
{
    if (argc < 2) {
        return print_help();
    } else if (strcmp(argv[1], "both") == 0) {
        return serial_to_ethernet(1, 1);
    } else if (strcmp(argv[1], "spi") == 0) {
        return serial_to_ethernet(1, 0);
    } else if (strcmp(argv[1], "uart") == 0) {
        return serial_to_ethernet(0, 1);
    } else {
        return print_help();
    }
}
