//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test the "Chat" dispatch and protocol handlers

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_chat.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>

TEST_CASE("ethernet-chat") {
    const satcat5::eth::MacAddr MAC_UUT =
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}};
    const satcat5::eth::MacAddr MAC_DST =
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};

    // Transmit and receive buffers.
    // (Named with respect to the test device.)
    satcat5::io::PacketBufferHeap tx, rx;

    // Unit under test.
    satcat5::eth::Dispatch dispatch(MAC_UUT, &rx, &tx);
    satcat5::eth::ChatProto uut(&dispatch, "TestUser");

    // Reference packets:
    const u8 REF_HEARTBEAT[] = {
        // Eth-DST
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x99, 0x9B,
        // Heartbeat for "TestUser"
        0x00, 0x08, 'T', 'e', 's', 't', 'U', 's', 'e', 'r',
    };
    const u8 REF_TEXT[] = {
        // Eth-DST
        0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x99, 0x9C,
        // Text message "Hello!"
        0x00, 0x06, 'H', 'e', 'l', 'l', 'o', '!',
    };
    const u8 REF_DATA[] = {
        // Eth-DST
        0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x99, 0x9D,
        // Data message "Beep boop"
        0x00, 0x09, 'B', 'e', 'e', 'p', ' ', 'b', 'o', 'o', 'p',
    };
    const u8 REF_VLAN[] = {
        // Eth-DST
        0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22,
        // Eth-SRC
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11,
        // VLAN-tag             Eth-TYPE
        0x81, 0x00, 0x01, 0x23, 0x99, 0x9C,
        // Text message "VLAN!"
        0x00, 0x05, 'V', 'L', 'A', 'N', '!',
    };

    #define TEST_WRITE(x) satcat5::test::write(&tx, sizeof(x), x)
    #define TEST_READ(x)  satcat5::test::read(&rx, sizeof(x), x)

    SECTION("send_heartbeat") {
        // Byte-by-byte inspection of a "heartbeat" message.
        uut.send_heartbeat();
        CHECK(TEST_READ(REF_HEARTBEAT));
    }

    SECTION("send_text") {
        // Byte-by-byte inspection of a "text" message.
        uut.send_text(MAC_DST, 6, "Hello!");
        CHECK(TEST_READ(REF_TEXT));
    }

    SECTION("send_data") {
        // Byte-by-byte inspection of a "data" message.
        uut.send_data(MAC_DST, 9, "Beep boop");
        CHECK(TEST_READ(REF_DATA));
    }

    SECTION("send_vlan") {
        // Register a ChatProto object on a specific VLAN.
        const satcat5::eth::VlanTag vtag = {0x0123};
        satcat5::eth::ChatProto uut_vlan(&dispatch, "VlanUser", vtag);
        // Outgoing messages should have a VLAN tag.
        uut_vlan.send_text(MAC_DST, 5, "VLAN!");
        CHECK(TEST_READ(REF_VLAN));
    }

    SECTION("timer") {
        // Simulate passage of time by polling the global Timekeeper object.
        for (unsigned n = 0 ; n < 1500 ; ++n) {
            satcat5::poll::timekeeper.request_poll();
            satcat5::poll::service_all();
        }
        // Confirm that we got a heartbeat message.
        CHECK(TEST_READ(REF_HEARTBEAT));
    }

    SECTION("log2chat") {
        // Link logger object to the ChatProto.
        satcat5::eth::LogToChat logger(&uut);
        CHECK(rx.get_read_ready() == 0);
        // Confirm that log event produces a message.
        // (No need to check contents byte-by-byte.)
        {satcat5::log::Log(satcat5::log::INFO, "Log event");}
        CHECK(rx.get_read_ready() > 0);
    }

    SECTION("echo") {
        CHECK(uut.local_mac() == MAC_UUT);
        // Create echo service and attach to ChatProto.
        satcat5::eth::ChatEcho echo(&uut);
        // Send and process a text message (reference from earlier test).
        TEST_WRITE(REF_TEXT);
        satcat5::poll::service_all();
        // Confirm a response exists, no need for byte-by-byte check.
        CHECK(rx.get_read_ready() > 0);
        // Confirm that the reply-MAC matches expected value.
        CHECK(uut.reply_mac() == MAC_UUT);
    }
}
