//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Console application for viewing Chat/Log messages
//
// The application prompts the user to select an interface, then prints each
// received Chat/Log message until the user hits Ctrl+C.

#include <clocale>
#include <iostream>
#include <string>
#include <hal_pcap/hal_pcap.h>
#include <hal_posix/chat_printer.h>
#include <hal_posix/posix_uart.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/eth_chat.h>

using namespace satcat5;

// Global background services.
log::ToConsole logger;          // Print Log messages to console
util::PosixTimekeeper timer;    // Link system time to internal timers

// Set up a network stack and print received messages.
void chat_forever(io::Writeable* dst, io::Readable* src,
    eth::MacAddr local_mac = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC})
{
    // Set up a network stack for the chat protocol.
    eth::Dispatch* dispatch = new eth::Dispatch(
        local_mac, dst, src);
    eth::ChatProto* proto = new eth::ChatProto(
        dispatch, "log-viewer");
    util::ChatPrinter* chat = new util::ChatPrinter(proto);

    // Forward user input to the chat protocol.
    // (Type message and hit enter to send.)
    io::KeyboardStream* kb = new io::KeyboardStream(chat);

    // Poll until user hits Ctrl+C.
    while(1) {
        poll::service();
        util::sleep_msec(1);
    }

    // Cleanup.
    delete kb;
    delete chat;
    delete proto;
    delete dispatch;
}

int main(int argc, const char* argv[])
{
    // Set console mode for UTF-8 support.
    setlocale(LC_ALL, SATCAT5_WIN32 ? ".UTF8" : "");

    // Parse command-line arguments.
    std::string ifname;
    unsigned baud = 921600;
    if (argc == 3) {
        ifname = argv[1];                       // UART device
        baud = atoi(argv[2]);                   // Baud rate
    } else if (argc == 2) {
        ifname = argv[1];                       // Eth or UART device
    } else if (argc == 1) {
        ifname = pcap::prompt_for_ifname();     // Select Eth from list.
        if (ifname.length() == 0) return 2;     // User selected "exit"?
    }

    // Print the usage prompt?
    if (argc > 3 || ifname == "help" || ifname == "--help") {
        std::cout << "log_viewer displays received SatCat5 log messages." << std::endl
            << "Usage: log_viewer <ifname>" << std::endl
            << "       log_viewer <ifname> <baud>" << std::endl
            << "Where 'ifname' is an Ethernet or UART device name." << std::endl
            << "UART devices may also specify a baud rate, defaulting to 921,600." << std::endl
            << "An empty ifname will instead prompt the user to select a device." << std::endl;
        return 0;
    }

    // Attempt to open the network interface.
    static const unsigned RX_BUFF_SIZE = 65536;
    pcap::Socket* sock = 0;
    io::SlipUart* uart = 0;

    if (pcap::is_device(ifname.c_str())) {
        sock = new pcap::Socket(ifname.c_str(), RX_BUFF_SIZE, eth::ETYPE_CHAT_TEXT);
    } else {
        uart = new io::SlipUart(ifname.c_str(), baud, RX_BUFF_SIZE);
    }

    // Interface ready?
    if (sock && sock->ok()) {
        std::cout << "Log viewer ready! Ethernet" << std::endl
            << "  " << sock->name() << std::endl
            << "  " << sock->desc() << std::endl;
        chat_forever(sock, sock);
        return 0;
    } else if (uart && uart->ok()) {
        std::cout << "Log viewer ready! SLIP-UART" << std::endl
            << "  " << ifname << " @ " << baud << std::endl;
        chat_forever(uart, uart);
        return 0;
    } else {
        std::cerr << "Couldn't open Ethernet/UART interface: " << ifname << std::endl;
        return 1;
    }
}
