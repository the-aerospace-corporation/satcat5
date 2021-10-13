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
// Test cases for ConfigBus "Mailmap" driver

#include <cstring>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/port_mailmap.h>

namespace cfg   = satcat5::cfg;
namespace io    = satcat5::io;

// Define register map (see "port_mailmap.vhd")
static const unsigned CFG_DEVADDR = 42;
static const unsigned REG_RXFRAME = 0;      //   0 - 399
static const unsigned REG_RXRSVD  = 400;    // 400 - 509
static const unsigned REG_IRQCTRL = 510;
static const unsigned REG_RXCTRL  = 511;
static const unsigned REG_TXFRAME = 512;    // 512 - 911
static const unsigned REG_TXRSVD  = 912;    // 912 - 1022
static const unsigned REG_TXCTRL  = 1023;

// Simulate the single-register Mailbox interface.
class MockMailmap : public satcat5::test::MockConfigBusMmap {
public:
    explicit MockMailmap(unsigned devaddr)
        : m_dev(m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE)
    {
        m_dev[REG_TXCTRL] = 0;                  // Initial state = idle
    }

    // Update the received-packet buffer, if it's clear.
    bool buf_wr(const std::string& frm) {
        if (m_dev[REG_RXCTRL]) return false;    // Still occupied?
        memcpy(m_dev + REG_RXFRAME, frm.c_str(), frm.length());
        m_dev[REG_RXCTRL] = frm.length();       // Store the new length.
        m_dev[REG_IRQCTRL] = -1;                // Interrupt ready for service
        irq_event();                            // Notify interrupt handler
        m_dev[REG_IRQCTRL] = 0;                 // Revert to idle
        return true;                            // Success
    }

    // Return contents of the transmit-packet buffer, if any.
    std::string buf_rd() {
        std::string tmp;
        if (m_dev[REG_TXCTRL]) {                // Any outgoing data?
            const u8* src = (const u8*)(m_dev + REG_TXFRAME);
            for (unsigned a = 0 ; a < m_dev[REG_TXCTRL] ; ++a)
                tmp.push_back(src[a]);          // Append each byte...
            m_dev[REG_TXCTRL] = 0;              // Frame consumed, clear length
        }
        return tmp;
    }

    io::ArrayRead get_reader() {
        unsigned len = m_dev[REG_TXCTRL];       // Length of frame, in bytes
        const u8* data = (const u8*)(m_dev + REG_TXFRAME);
        m_dev[REG_TXCTRL] = 0;                  // Frame consumed, clear length
        return io::ArrayRead(data, len);        // Construct wrapper object
    }

private:
    u32* const m_dev;
};

TEST_CASE("port_mailmap") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Create the hardware-emulator and the driver under test.
    MockMailmap mock(CFG_DEVADDR);
    satcat5::port::Mailmap uut(&mock, CFG_DEVADDR);

    // Sanity check on initial state.
    CHECK(uut.get_write_space() > 1500);
    CHECK(uut.get_read_ready() == 0);

    SECTION("Register-Test") {
        // Read/write a random register to test basic Mmap functionality.
        u32 tmp; const unsigned regaddr = 47;
        CHECK(mock.read(regaddr, tmp) == cfg::IOSTATUS_OK);
        CHECK(tmp == 0);
        CHECK(mock.write(regaddr, 0x1234) == cfg::IOSTATUS_OK);
        CHECK(mock.read(regaddr, tmp) == cfg::IOSTATUS_OK);
        CHECK(tmp == 0x1234);
    }

    SECTION("Tx-str") {
        uut.write_str("Short test 1.");
        CHECK(uut.write_finalize());
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "Short test 1.");

        uut.write_str("Short test 2.");
        CHECK(uut.write_finalize());
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "Short test 2.");
    }

    SECTION("Tx-int") {
        for (unsigned a = 0 ; a < 10 ; ++a)
            uut.write_u16(a);
        CHECK(uut.write_finalize());
        satcat5::poll::service();

        satcat5::io::ArrayRead rd = mock.get_reader();
        for (unsigned a = 0 ; a < 10 ; ++a)
            CHECK(rd.read_u16() == a);
        rd.read_finalize();
    }

    SECTION("Tx-abort") {
        uut.write_str("This string is discarded.");
        uut.write_abort();

        uut.write_str("Short test.");
        CHECK(uut.write_finalize());
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "Short test.");
    }

    SECTION("Tx-block") {
        uut.write_str("1st packet OK");
        CHECK(uut.write_finalize());
        uut.write_str("2nd should overflow.");
        CHECK(!uut.write_finalize());
    }

    SECTION("Tx-empty") {
        CHECK(!uut.write_finalize());
    }

    SECTION("Tx-overflow") {
        for (u16 a = 0 ; a < 1024 ; ++a)
            uut.write_u16(a);                   // Overflow (eventually)
        CHECK(uut.get_write_space() == 0);      // Already full
        CHECK(!uut.write_finalize());           // Bad frame, must abort
        CHECK(uut.get_write_space() > 1500);    // Reset to known-good state
    }

    SECTION("Rx") {
        CHECK(mock.buf_wr("Short test 1."));
        satcat5::poll::service();
        CHECK(read_str(&uut) == "Short test 1.");

        CHECK(mock.buf_wr("Short test 2."));
        satcat5::poll::service();
        CHECK(read_str(&uut) == "Short test 2.");
    }

    SECTION("Rx-bytes") {
        u8 temp[2];
        CHECK(mock.buf_wr("\x12\x34\x56"));         // 3 bytes exactly
        satcat5::poll::service();

        CHECK(uut.read_bytes(sizeof(temp), temp));  // Normal read
        CHECK(temp[0] == 0x12);
        CHECK(temp[1] == 0x34);

        CHECK(uut.get_read_ready() > 0);            // Expect one more byte
        CHECK(!uut.read_bytes(sizeof(temp), temp)); // Underflow
        CHECK(uut.get_read_ready() == 0);
    }

    SECTION("Rx-underflow") {
        CHECK(uut.read_u8() == 0);  // Underflow (empty)
        CHECK(uut.get_read_ready() == 0);
    }
}
