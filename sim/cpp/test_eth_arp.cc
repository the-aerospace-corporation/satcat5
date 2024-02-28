//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test the Address Resolution Protocol handler

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_arp.h>
#include <satcat5/eth_dispatch.h>

using satcat5::test::write;
using satcat5::test::read;

TEST_CASE("ethernet-arp") {
    const satcat5::eth::MacAddr MAC_UUT =
        {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}};
    const satcat5::ip::Addr IP_UUT = {0x12345678};
    const satcat5::ip::Addr IP_ALT = {0x55555555};

    // Transmit and receive buffers.
    // (Named with respect to the test device.)
    satcat5::io::PacketBufferHeap tx, rx;

    // Unit under test.
    satcat5::log::ToConsole logger;
    satcat5::eth::Dispatch dispatch(MAC_UUT, &rx, &tx);
    satcat5::eth::ProtoArp uut(&dispatch, IP_UUT);

    // Reference packets:
    const u8 REF_QUERY1[] = {   // "Who has 12.34.56.78?"
        // Eth-DST
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x08, 0x06,
        // HTYPE    PTYPE       HLEN  PLEN  OPER
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01,
        // SHA                              SPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x87, 0x65, 0x43, 0x21,
        // THA                              TPA
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x12, 0x34, 0x56, 0x78,
    };
    const u8 REF_QUERY2[] = {   // "Who has 55.55.55.55?"
        // Eth-DST
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x08, 0x06,
        // HTYPE    PTYPE       HLEN  PLEN  OPER
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01,
        // SHA                              SPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x87, 0x65, 0x43, 0x21,
        // THA                              TPA
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x55, 0x55, 0x55, 0x55,
    };
    const u8 REF_REPLY1[] = {   // "UUT has 12.34.56.78."
        // Eth-DST
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x08, 0x06,
        // HTYPE    PTYPE       HLEN  PLEN  OPER
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x02,
        // SHA                              SPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78,
        // THA                              TPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x87, 0x65, 0x43, 0x21,
    };
    const u8 REF_REPLY2[] = {   // "UUT has 55.55.55.55."
        // Eth-DST
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x08, 0x06,
        // HTYPE    PTYPE       HLEN  PLEN  OPER
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x02,
        // SHA                              SPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x55, 0x55, 0x55, 0x55,
        // THA                              TPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11, 0x87, 0x65, 0x43, 0x21,
    };
    const u8 REF_ANNOUNCE[] = {   // "I have 12.34.56.78."
        // Eth-DST
        0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
        // Eth-SRC                          Eth-TYPE
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x08, 0x06,
        // HTYPE    PTYPE       HLEN  PLEN  OPER
        0x00, 0x01, 0x08, 0x00, 0x06, 0x04, 0x00, 0x01,
        // SHA                              SPA
        0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78,
        // THA                              TPA
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x34, 0x56, 0x78,
    };

    #define TEST_WRITE(x) write(&tx, sizeof(x), x)
    #define TEST_READ(x)  read(&rx, sizeof(x), x)

    SECTION("query1") {
        // Query1 expects a response (matching address).
        CHECK(TEST_WRITE(REF_QUERY1));
        satcat5::poll::service_all();
        CHECK(TEST_READ(REF_REPLY1));
    }

    SECTION("query2") {
        // Query2 should be ignored (non-matching address).
        CHECK(TEST_WRITE(REF_QUERY2));
        satcat5::poll::service_all();
        CHECK(rx.get_read_ready() == 0);
    }

    SECTION("announce") {
        // Send a gratuitous announcement.
        CHECK(uut.send_announce());
        satcat5::poll::service_all();
        CHECK(TEST_READ(REF_ANNOUNCE));
    }

    SECTION("ipchange") {
        // Once IP is changed, Query2 expects a response.
        uut.set_ipaddr(IP_ALT);
        CHECK(TEST_WRITE(REF_QUERY2));
        satcat5::poll::service_all();
        CHECK(TEST_READ(REF_REPLY2));
    }

    SECTION("runtpkt") {
        // Send a few runt packets, all should be ignored.
        logger.disable();                   // Suppress error messages
        CHECK(write(&tx, 13, REF_QUERY1));  // Incomplete Eth header
        CHECK(write(&tx, 19, REF_QUERY1));  // Incomplete ARP header
        satcat5::poll::service_all();
        CHECK(rx.get_read_ready() == 0);
    }
}
