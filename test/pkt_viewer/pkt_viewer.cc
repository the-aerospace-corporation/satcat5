//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Console application for viewing Packet-Log messages
//
// The application prompts the user to select an interface, then prints each
// received Packet-Log message until the user hits Ctrl+C.

#include <clocale>
#include <iostream>
#include <string>
#include <hal_posix/posix_uart.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/codec_slip.h>
#include <satcat5/eth_sw_log.h>

using namespace satcat5;

// Global background services.
log::ToConsole logger;          // Print Log messages to console
util::PosixTimekeeper timer;    // Link system time to internal timers

// Set up a decoder to print received messages.
void log_forever(io::Readable* src) {
    // Read and decode the SLIP stream from the UART.
    io::PacketBufferHeap buff;
    io::SlipDecoder decode(&buff);
    io::BufferedCopy copy(src, &decode, io::CopyMode::STREAM);

    // Convert each descriptor to a human-readable message.
    eth::SwitchLogFormatter fmt(&buff);

    // Poll until user hits Ctrl+C.
    while(1) {
        poll::service();
        util::sleep_msec(1);
    }
}

int main(int argc, const char* argv[]) {
    // Set console mode for UTF-8 support.
    setlocale(LC_ALL, SATCAT5_WIN32 ? ".UTF8" : "");

    // Parse command-line arguments.
    std::string ifname;
    unsigned baud = 921600;
    if (argc == 3) {
        ifname = argv[1];                       // UART device
        baud = atoi(argv[2]);                   // Baud rate
    } else if (argc == 2) {
        ifname = argv[1];                       // UART device
    }

    // Print the usage prompt?
    if (ifname == "" || ifname == "help" || ifname == "--help") {
        std::cout << "pkt_viewer displays UART Packet-log messages." << std::endl
            << "Usage: pkt_viewer <ifname>" << std::endl
            << "       pkt_viewer <ifname> <baud>" << std::endl
            << "Where 'ifname' is a UART device name." << std::endl
            << "UART devices may also specify a baud rate, defaulting to 921,600." << std::endl
            << "An empty ifname will instead display this help message." << std::endl;
        return 0;
    }

    // Attempt to open the network interface.
    io::PosixUart uart(ifname.c_str(), baud);

    // Interface ready?
    if (uart.ok()) {
        std::cout << "Packet-Log viewer ready! SLIP-UART" << std::endl
            << "  " << ifname << " @ " << baud << std::endl;
        log_forever(&uart);
        return 0;
    } else {
        std::cerr << "Couldn't open UART interface: " << ifname << std::endl;
        return 1;
    }
}
