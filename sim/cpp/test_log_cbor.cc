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
// Test cases for the SatCat5 logging system

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/datetime.h>
#include <satcat5/eth_socket.h>
#include <satcat5/ip_stack.h>
#include <satcat5/log_cbor.h>
#include <satcat5/udp_socket.h>

static void log_something() {
    satcat5::log::Log(satcat5::log::INFO, "Test message");
}

static bool echo_buffer(satcat5::io::BufferedIO* buff) {
    u8 temp[2048];
    unsigned copy_len = buff->get_read_ready();
    if (copy_len == 0 || copy_len > sizeof(temp)) return false;
    buff->read_bytes(copy_len, temp);
    buff->read_finalize();
    buff->write_bytes(copy_len, temp);
    return buff->write_finalize();
}

TEST_CASE("log_cbor") {
    // Configuration constants.
    constexpr satcat5::eth::MacAddr MAC_CLIENT = {0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11};
    constexpr satcat5::eth::MacAddr MAC_SERVER = {0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22};
    constexpr satcat5::ip::Addr IP_CLIENT(192, 168, 0, 11);
    constexpr satcat5::ip::Addr IP_SERVER(192, 168, 0, 22);
    constexpr satcat5::eth::MacType TYPE_ETH = {0x4321};
    constexpr satcat5::udp::Port    PORT_UDP = {0x4321};

    // Logging and timing infrastructure.
    satcat5::test::TimerAlways timekeeper;
    satcat5::test::FastPosixTimer timer;
    satcat5::log::ToConsole log;
    satcat5::datetime::Clock clock(&timer);
    log.disable();  // Suppress console output

    // Network infrastructure for client and server.
    satcat5::io::PacketBufferHeap c2s, s2c;
    satcat5::ip::Stack client(MAC_CLIENT, IP_CLIENT, &c2s, &s2c, &timer);
    satcat5::ip::Stack server(MAC_SERVER, IP_SERVER, &s2c, &c2s, &timer);

    // Server-side infrastructure is an echo service.
    satcat5::eth::Socket echo_eth(&server.m_eth);
    satcat5::udp::Socket echo_udp(&server.m_udp);
    echo_eth.connect(MAC_CLIENT, TYPE_ETH, TYPE_ETH);
    echo_udp.connect(IP_CLIENT, MAC_CLIENT, PORT_UDP, PORT_UDP);

    SECTION("basic-eth") {
        // Separate send/echo/receive blocks, since having LogToCbor and
        // LogFromCbor running simultaneously causes an infinite loop.
        {   // Write CBOR message to buffer
            satcat5::eth::LogToCbor uut(&clock, &client.m_eth, TYPE_ETH);
            log_something();
            timekeeper.sim_wait(10);
        }
        REQUIRE(echo_buffer(&echo_eth));
        log.clear();
        {   // Read CBOR message from buffer.
            satcat5::eth::LogFromCbor uut(&client.m_eth, TYPE_ETH);
            timekeeper.sim_wait(10);
            CHECK(log.contains("Test"));
        }
    }

    SECTION("basic-udp") {
        {   // Write CBOR message to buffer
            satcat5::udp::LogToCbor uut(&clock, &client.m_udp, PORT_UDP);
            log_something();
            timekeeper.sim_wait(10);
        }
        REQUIRE(echo_buffer(&echo_udp));
        log.clear();
        {   // Read CBOR message from buffer.
            satcat5::udp::LogFromCbor uut(&client.m_udp, PORT_UDP);
            timekeeper.sim_wait(10);
            CHECK(log.contains("Test"));
        }
    }

    SECTION("no-clock") {
        {   // Write CBOR message to buffer
            satcat5::eth::LogToCbor uut(0, &client.m_eth, TYPE_ETH);
            log_something();
            timekeeper.sim_wait(10);
        }
        REQUIRE(echo_buffer(&echo_eth));
        log.clear();
        {   // Read CBOR message from buffer.
            satcat5::eth::LogFromCbor uut(&client.m_eth, TYPE_ETH);
            timekeeper.sim_wait(10);
            CHECK(log.contains("Test"));
        }
    }

    SECTION("min-priority-filtered-at-send") {
        {   // Write CBOR message to buffer below minimum
            satcat5::eth::LogToCbor uut(0, &client.m_eth, TYPE_ETH);
            uut.set_min_priority(satcat5::log::WARNING);
            log_something();  // Uses INFO level
            timekeeper.sim_wait(10);
        }
        CHECK(!echo_buffer(&echo_eth));  // Nothing should be echoed
    }

    SECTION("min-priority-filtered-at-receive") {
        {   // Write CBOR message to buffer below minimum
            satcat5::eth::LogToCbor uut(0, &client.m_eth, TYPE_ETH);
            log_something();  // Uses INFO level
            timekeeper.sim_wait(10);
        }
        REQUIRE(echo_buffer(&echo_eth));
        log.clear();
        {   // Read CBOR message from buffer.
            satcat5::eth::LogFromCbor uut(&client.m_eth, TYPE_ETH);
            uut.set_min_priority(satcat5::log::WARNING);
            timekeeper.sim_wait(10);
            CHECK(! log.contains("Test"));  // Should not be there
        }
    }

    SECTION("min-priority-same-as-message") {
        {   // Write CBOR message to buffer below minimum
            satcat5::eth::LogToCbor uut(0, &client.m_eth, TYPE_ETH);
            uut.set_min_priority(satcat5::log::INFO);
            log_something();  // Uses INFO level
            timekeeper.sim_wait(10);
        }
        REQUIRE(echo_buffer(&echo_eth));
        log.clear();
        {   // Read CBOR message from buffer.
            satcat5::eth::LogFromCbor uut(&client.m_eth, TYPE_ETH);
            uut.set_min_priority(satcat5::log::INFO);
            timekeeper.sim_wait(10);
            CHECK(log.contains("Test"));
        }
    }

}
