//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus SPI controller

#include <hal_test/catch.hpp>
#include <hal_test/sim_multiserial.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_spi.h>

using satcat5::test::MST_START;
using satcat5::test::MST_READ;

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const u16 CMD_START      = 0x0000u;
static const u16 CMD_TXBYTE     = 0x0100u;
static const u16 CMD_TXRXBYTE   = 0x0200u;
static const u16 CMD_RXBYTE     = 0x0300u;
static const u16 CMD_STOP       = 0x0400u;

// Confirm that read data matches expected sequence.
class SpiEventCheck : public satcat5::cfg::SpiEventListener {
public:
    explicit SpiEventCheck(unsigned nread)
        : m_nread(nread), m_count(0) {}

    void spi_done(unsigned nread, const u8* rdata)
    {
        ++m_count;          // Count event callbacks
        REQUIRE(nread == m_nread);
        for (unsigned n = 0 ; n < nread ; ++n) {
            CHECK(rdata[n] == (u8)n);
        }
    }

    const unsigned m_nread;
    unsigned m_count;
};

TEST_CASE("cfgbus_spi") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate emulator and the unit under test.
    satcat5::test::MultiSerial mst;
    satcat5::cfg::Spi uut(&mst, CFG_DEVADDR);
    CHECK_FALSE(uut.busy());

    // Reference data is a simple counter.
    u8 wrdata[16];
    for (unsigned a = 0 ; a < sizeof(wrdata) ; ++a)
        wrdata[a] = a;

    SECTION("config") {
        uut.configure(100e6, 1e6, 0);
        CHECK(mst.get_cfg() == 0x0032);
        uut.configure(100e6, 2e6, 1);
        CHECK(mst.get_cfg() == 0x0119);
        uut.configure(100e6, 3e6, 2);
        CHECK(mst.get_cfg() == 0x0211);
        uut.configure(100e6, 4e6, 3);
        CHECK(mst.get_cfg() == 0x030D);
    }

    SECTION("read-short") {
        // Expect 3-byte read
        SpiEventCheck evt(3);
        // Load the reference sequence.
        mst.load_refcmd(CMD_START | 0, MST_START);
        for (unsigned a = 0 ; a < 3 ; ++a)
            mst.load_refcmd(CMD_RXBYTE, MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue the command.
        uut.query(0, 0, 0, 3, &evt);    // 0wr + 3rd
        // Process to completion.
        CHECK(uut.busy());
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt.m_count == 1);
    }

    SECTION("read-long") {
        // Expect 16-byte read followed by 3-byte read.
        SpiEventCheck evt1(16);
        SpiEventCheck evt2(3);
        // Load the first reference sequence.
        mst.load_refcmd(CMD_START | 1, MST_START);
        for (unsigned a = 0 ; a < 16 ; ++a)
            mst.load_refcmd(CMD_RXBYTE, MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Load the second reference sequence.
        mst.load_refcmd(CMD_START | 2, MST_START);
        for (unsigned a = 0 ; a < 3 ; ++a)
            mst.load_refcmd(CMD_RXBYTE, MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue each command.
        uut.query(1, 0, 0, 16, &evt1);  // 0wr + 16rd
        uut.query(2, 0, 0, 3,  &evt2);  // 0wr + 3rd
        // Process to completion.
        CHECK(uut.busy());
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt1.m_count == 1);
        CHECK(evt2.m_count == 1);
    }

    SECTION("read-write") {
        // Expect a read-write transaction.
        SpiEventCheck evt(7);
        // Load the reference sequence.
        mst.load_refcmd(CMD_START | 42, MST_START);
        for (unsigned a = 0 ; a < 7 ; ++a)
            mst.load_refcmd(CMD_TXRXBYTE | wrdata[a], MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue the read-write command.
        uut.exchange(42, wrdata, 7, &evt);
        // Process to completion.
        CHECK(uut.busy());
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt.m_count == 1);
    }

    SECTION("write-long") {
        // Expect a write followed by a read-write.
        SpiEventCheck evt1(0);
        SpiEventCheck evt2(4);
        // Load the first reference sequence.
        mst.load_refcmd(CMD_START | 3, MST_START);
        for (unsigned a = 0 ; a < 14 ; ++a)
            mst.load_refcmd(CMD_TXBYTE | wrdata[a]);
        mst.load_refcmd(CMD_STOP);
        // Load the second reference sequence.
        mst.load_refcmd(CMD_START | 4, MST_START);
        for (unsigned a = 0 ; a < 2 ; ++a)
            mst.load_refcmd(CMD_TXBYTE | wrdata[a]);
        for (unsigned a = 0 ; a < 4 ; ++a)
            mst.load_refcmd(CMD_RXBYTE, MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue each command.
        uut.query(3, wrdata, 14, 0, &evt1); // 14wr + 0rd
        uut.query(4, wrdata,  2, 4, &evt2); // 2wr + 4rd
        // Process to completion.
        CHECK(uut.busy());
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt1.m_count == 1);
        CHECK(evt2.m_count == 1);
    }

    // End-of-test sanity check;
    CHECK_FALSE(uut.busy());
}
