//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Test cases for the ConfigBus I2C controller

#include <hal_test/catch.hpp>
#include <hal_test/sim_multiserial.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_i2c.h>

using satcat5::util::I2cAddr;
using satcat5::test::MST_START;
using satcat5::test::MST_READ;
using satcat5::test::MST_ERROR;

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const u16 CMD_DELAY      = 0x0000u;
static const u16 CMD_START      = 0x0100u;
static const u16 CMD_RESTART    = 0x0200u;
static const u16 CMD_STOP       = 0x0300u;
static const u16 CMD_TXBYTE     = 0x0400u;
static const u16 CMD_RXBYTE     = 0x0500u;
static const u16 CMD_RXFINAL    = 0x0600u;
static const u32 CFG_NOSTRETCH  = (1u << 31);

// Shortcuts for device address
static const I2cAddr I2C_DEVADDR = I2cAddr::addr8(42);
#define CMD_ADDR_WR (CMD_TXBYTE | I2C_DEVADDR.m_addr | 0)
#define CMD_ADDR_RD (CMD_TXBYTE | I2C_DEVADDR.m_addr | 1)

TEST_CASE("i2c_addr") {
    I2cAddr a7 = I2cAddr::addr7(21);
    I2cAddr a8 = I2cAddr::addr8(42);
    REQUIRE(a7.m_addr == a8.m_addr);
}

// Confirm that read data matches expected sequence.
class I2cEventCheck : public satcat5::cfg::I2cEventListener {
public:
    I2cEventCheck(unsigned nread, u32 regaddr, bool noack)
        : m_nread(nread), m_regaddr(regaddr), m_noack(noack), m_count(0) {}

    void i2c_done(
        u8 noack,           // Missing ACK during this command?
        u8 devaddr,         // Device address
        u32 regaddr,        // Register address (if applicable)
        unsigned nread,     // Number of bytes read (if applicable)
        const u8* rdata)    // Pointer to read buffer
    {
        ++m_count;          // Count event callbacks
        CHECK(!!noack == m_noack);
        CHECK(devaddr == I2C_DEVADDR.m_addr);
        CHECK(regaddr == m_regaddr);
        REQUIRE(nread == m_nread);
        for (unsigned n = 0 ; n < nread ; ++n) {
            CHECK(rdata[n] == (u8)n);
        }
    }

    const unsigned m_nread;
    const u32 m_regaddr;
    const bool m_noack;
    unsigned m_count;
};

TEST_CASE("cfgbus_i2c") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate emulator and the unit under test.
    satcat5::test::MultiSerial mst;
    satcat5::cfg::I2c uut(&mst, CFG_DEVADDR);

    // Reference data is a simple counter.
    u8 wrdata[16];
    for (unsigned a = 0 ; a < sizeof(wrdata) ; ++a)
        wrdata[a] = a;

    SECTION("config") {
        uut.configure(100e6, 200e3, true);
        CHECK(mst.get_cfg() == 124);
        uut.configure(100e6, 200e3, false);
        CHECK(mst.get_cfg() == (124 | CFG_NOSTRETCH));
        uut.configure(100e6, 400e3, true);
        CHECK(mst.get_cfg() == 62);
    }

    SECTION("read-short") {
        // Expect 3-byte read
        I2cEventCheck evt(3, 0, false);
        // Load the reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_RD);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ);
        mst.load_refcmd(CMD_RXFINAL,    MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue the command.
        uut.read(I2C_DEVADDR, 0, 0, 3, &evt);
        // Process to completion.
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt.m_count == 1);
    }

    SECTION("read-noack") {
        // Expect 3-byte read + noack
        I2cEventCheck evt(3, 0, true);
        // Load the reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_RD);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ | MST_ERROR);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ | MST_ERROR);
        mst.load_refcmd(CMD_RXFINAL,    MST_READ | MST_ERROR);
        mst.load_refcmd(CMD_STOP);
        // Issue the command.
        uut.read(I2C_DEVADDR, 0, 0, 3, &evt);
        // Process to completion.
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt.m_count == 1);
    }

    SECTION("read-long") {
        // Expect 16-byte read w/ regaddr, followed by 3-byte read.
        I2cEventCheck evt1(16, 42, false);
        I2cEventCheck evt2(3, 0, false);
        // Load the first reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_WR);
        mst.load_refcmd(CMD_TXBYTE | 42);
        mst.load_refcmd(CMD_RESTART);
        mst.load_refcmd(CMD_ADDR_RD);
        for (unsigned a = 0 ; a < 15 ; ++a)
            mst.load_refcmd(CMD_RXBYTE, MST_READ);
        mst.load_refcmd(CMD_RXFINAL,    MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Load the second reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_RD);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ);
        mst.load_refcmd(CMD_RXBYTE,     MST_READ);
        mst.load_refcmd(CMD_RXFINAL,    MST_READ);
        mst.load_refcmd(CMD_STOP);
        // Issue each command.
        uut.read(I2C_DEVADDR, 1, 42, 16, &evt1);
        uut.read(I2C_DEVADDR, 0, 0, 3, &evt2);
        // Process to completion.
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt1.m_count == 1);
        CHECK(evt2.m_count == 1);
    }

    SECTION("write-long") {
        // Expect two writes, first has regaddr.
        I2cEventCheck evt1(0, 42, false);
        I2cEventCheck evt2(0, 0, false);
        // Load the first reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_WR);
        mst.load_refcmd(CMD_TXBYTE | 42);
        for (unsigned a = 0 ; a < 16 ; ++a)
            mst.load_refcmd(CMD_TXBYTE | wrdata[a]);
        mst.load_refcmd(CMD_STOP);
        // Load the second reference sequence.
        mst.load_refcmd(CMD_START,      MST_START);
        mst.load_refcmd(CMD_ADDR_WR);
        for (unsigned a = 0 ; a < 3 ; ++a)
            mst.load_refcmd(CMD_TXBYTE | wrdata[a]);
        mst.load_refcmd(CMD_STOP);
        // Issue each command.
        uut.write(I2C_DEVADDR, 1, 42, 16, wrdata, &evt1);
        uut.write(I2C_DEVADDR, 0, 0, 3, wrdata, &evt2);
        // Process to completion.
        for (unsigned n = 0 ; n < 100 ; ++n) mst.poll();
        // Confirm test completed.
        CHECK(mst.done());
        CHECK(evt1.m_count == 1);
        CHECK(evt2.m_count == 1);
    }
}
