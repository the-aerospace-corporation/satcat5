//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022 The Aerospace Corporation
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
// Console application for viewing Chat/Log messages
//
// The application prompts the user to select an interface, then prints each
// received Chat/Log message until the user hits Ctrl+C.

#include <clocale>
#include <iostream>
#include <string>
#include <hal_pcap/hal_pcap.h>
#include <hal_posix/posix_uart.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/eth_chat.h>
#include <satcat5/eth_dispatch.h>

using namespace satcat5;

// Global background services.
log::ToConsole logger;          // Print Log messages to console
util::PosixTimekeeper timer;    // Link system time to internal timers

// Callback object that prints incoming messages.
class ChatPrinter final
    : public net::Protocol
    , public io::Writeable
{
public:
    ChatPrinter(eth::ChatProto* chat)
        : net::Protocol(net::TYPE_NONE)
        , m_chat(chat)
        , m_loopback(true)
    {
        m_chat->set_callback(this);
    }

    ~ChatPrinter() {
        m_chat->set_callback(0);
    }

    // Handle incoming data from eth::ChatProto.
    void frame_rcvd(io::LimitedRead& rd) override {
        std::string msg;
        while (rd.get_read_ready())
            msg.push_back((char)rd.read_u8());
        print_message(m_chat->reply_mac(), msg);
    }

    // Pretty formatting for incoming or outgoing messages.
    void print_message(const eth::MacAddr& from, const std::string& msg) {
        std::cout << "From " << log::format(from) << std::endl
            << msg << std::endl << std::endl;
    }

    // Send a message string to the chat client.
    void send_message(const std::string& msg) {
        if (m_loopback)
            print_message(m_chat->local_mac(), msg);
        m_chat->send_text(eth::MACADDR_BROADCAST,
            msg.length(), msg.c_str());
    }

    // Send accumulated message to the chat client.
    bool write_finalize() {
        if (m_line.length() > 0) {
            send_message(m_line);
            m_line.clear();
            return true;
        } else {
            return false;
        }
    }

    // Always indicate we are ready to accept data.
    unsigned get_write_space() const override {
        return 1000;
    }

private:
    // Accumulate characters from input stream.
    void write_next(u8 ch) {
        m_line.push_back(ch);
    }

    eth::ChatProto* const m_chat;
    std::string m_line;
    bool m_loopback;
};

// Set up a network stack and print received messages.
void chat_forever(io::Writeable* dst, io::Readable* src,
    eth::MacAddr local_mac = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC})
{
    // Set up a network stack for the chat protocol.
    eth::Dispatch* dispatch = new eth::Dispatch(
        local_mac, dst, src);
    eth::ChatProto* proto = new eth::ChatProto(
        dispatch, "log-viewer");
    ChatPrinter* chat = new ChatPrinter(proto);

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