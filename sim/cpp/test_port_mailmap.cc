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
#include <satcat5/ptp_time.h>
#include <satcat5/cfgbus_ptpref.h>
#include <iostream>

namespace cfg   = satcat5::cfg;
namespace io    = satcat5::io;
namespace ptp   = satcat5::ptp;

// Define register map (see "port_mailmap.vhd")
static const unsigned CFG_DEVADDR   = 42;
static const unsigned REG_RXFRAME   = 0;      //    0 - 399
static const unsigned REG_RXRSVD    = 400;    //  400 - 505
static const unsigned REG_RXPTPTIME = 506;    //  506 - 509
static const unsigned REG_IRQCTRL   = 510;
static const unsigned REG_RXCTRL    = 511;
static const unsigned REG_TXFRAME   = 512;    //  512 - 911
static const unsigned REG_TXRSVD    = 912;    //  912 - 1011
static const unsigned REG_RTCLKCTRL = 1012;   // 1012 - 1017
static const unsigned REG_TXPTPTIME = 1018;   // 1018 - 1021
static const unsigned REG_PTPSTATUS = 1022;
static const unsigned REG_TXCTRL    = 1023;

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

    // Need to overload buf_wr so that zeros can be written to the buffer
    bool buf_wr(const u64* frm, size_t length) {
        if (m_dev[REG_RXCTRL]) return false;    // Still occupied?
        for (size_t i = 0; i < length / sizeof(frm[0]); ++i) {
            satcat5::util::write_be_u64((u8*) (m_dev + REG_RXFRAME + 2*i), frm[i]);
        }
        m_dev[REG_RXCTRL] = length;             // Store the new length.
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

    // PtpRealtime objects for setting timestamps for testing PTP functions
    satcat5::cfg::PtpRealtime rt_clk_ctrl_ptprealtime = satcat5::cfg::PtpRealtime(&mock, CFG_DEVADDR, REG_RTCLKCTRL);
    satcat5::cfg::PtpRealtime tx_ptp_time_ptprealtime = satcat5::cfg::PtpRealtime(&mock, CFG_DEVADDR, REG_TXPTPTIME);
    satcat5::cfg::PtpRealtime rx_ptp_time_ptprealtime = satcat5::cfg::PtpRealtime(&mock, CFG_DEVADDR, REG_RXPTPTIME);

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

    SECTION("PTP") {
        // ptp_tx_start()
        ptp::Time test_time1 = ptp::Time(4660, 86, 120);
        rt_clk_ctrl_ptprealtime.clock_set(test_time1);
        CHECK(uut.ptp_tx_start() == test_time1);

        // ptp_tx_timestamp()
        ptp::Time test_time2 = ptp::Time(1242000, 628, 2009);
        tx_ptp_time_ptprealtime.clock_set(test_time2);
        CHECK(uut.ptp_tx_timestamp() == test_time2);

        // ptp_rx_peak()
        // PTP - L2
        CHECK(mock.buf_wr("abcdefghijkl""\x88\xF7"));
        satcat5::poll::service();
        CHECK(uut.ptp_rx_peek() == satcat5::port::Mailmap::PtpType::PTPL2);
        read_str(&uut);     // Read to clear the buffer for the next test

        // PTP - L3
        // Test message downloaded from https://wiki.wireshark.org/Protocols/ptp
        u64 message1[12] = {
            0x01005e00006b0080, 0x630009ba08004500, 0x005245a200000111, 0xd0dfc0a80206e000,
            0x006b013f013f003e, 0x0000120200360000, 0x0000000000000000, 0x0000000000000080,
            0x63ffff0009ba0001, 0x9e4b050f000045b1, 0x11522825d2fb0000, 0x0000000000000000
        };
        mock.buf_wr(message1, sizeof(message1));
        satcat5::poll::service();
        CHECK(uut.ptp_rx_peek() == satcat5::port::Mailmap::PtpType::PTPL3);
        uut.read_finalize();     // Clear the buffer for the next test

        // non-PTP (IPv4 ether type but wrong protocol)
        // Test message adapted from https://wiki.wireshark.org/Protocols/ptp
        u64 message2[12] = {
            0x01005e00006b0080, 0x630009ba08004500, 0x005245a200000110, 0xd0dfc0a80206e000,
            0x006b013f013f003e, 0x0000120200360000, 0x0000000000000000, 0x0000000000000080,
            0x63ffff0009ba0001, 0x9e4b050f000045b1, 0x11522825d2fb0000, 0x0000000000000000
        };
        mock.buf_wr(message2, sizeof(message2));
        satcat5::poll::service();
        CHECK(uut.ptp_rx_peek() == satcat5::port::Mailmap::PtpType::nonPTP);
        uut.read_finalize();     // Clear the buffer for the next test

        // non-PTP (IPv4 ether type and UDP protocol but wrong ports)
        // Test message adapted from https://wiki.wireshark.org/Protocols/ptp
        u64 message3[12] = {
            0x01005e00006b0080, 0x630009ba08004500, 0x005245a200000111, 0xd0dfc0a80206e000,
            0x006baaaaaaaa003e, 0x0000120200360000, 0x0000000000000000, 0x0000000000000080,
            0x63ffff0009ba0001, 0x9e4b050f000045b1, 0x11522825d2fb0000, 0x0000000000000000
        };
        mock.buf_wr(message3, sizeof(message3));
        satcat5::poll::service();
        CHECK(uut.ptp_rx_peek() == satcat5::port::Mailmap::PtpType::nonPTP);
        uut.read_finalize();     // Clear the buffer for the next test

        // non-PTP (wrong ether type)
        CHECK(mock.buf_wr("\x01\x02\x03\x04\x05\x06\x07\x08\x09\x10\x11\x12\x99\x99"));
        satcat5::poll::service();
        CHECK(uut.ptp_rx_peek() == satcat5::port::Mailmap::PtpType::nonPTP);
        read_str(&uut);     // Read to clear the buffer for the next test

        // ptp_rx_timestamp()
        ptp::Time test_time3 = ptp::Time(1234567890, 321, 456);
        rx_ptp_time_ptprealtime.clock_set(test_time3);
        CHECK(uut.ptp_rx_timestamp() == test_time3);
    }

    SECTION("Rx-underflow") {
        CHECK(uut.read_u8() == 0);  // Underflow (empty)
        CHECK(uut.get_read_ready() == 0);
    }
}
