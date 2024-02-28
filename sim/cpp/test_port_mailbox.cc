//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus "MailBox" driver

#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/port_mailbox.h>

namespace cfg   = satcat5::cfg;
namespace io    = satcat5::io;

// Define register map (see "port_mailbox.vhd")
static const unsigned CFG_DEVADDR = 42;
static const unsigned CFG_REGADDR = 47;

// Define command and status flags.
static const u32 CMD_NOOP       = (0x00u << 24);
static const u32 CMD_WRNEXT     = (0x02u << 24);
static const u32 CMD_WRFINAL    = (0x03u << 24);
static const u32 CMD_RESET      = (0xFFu << 24);
static const u32 STATUS_DVALID  = (1u << 31);
static const u32 STATUS_EOF     = (1u << 30);
static const u32 STATUS_DMASK   = 0xFF;

// Simulate the single-register Mailbox interface.
class MockMailbox : public cfg::ConfigBus, public io::BufferedIO
{
public:
    MockMailbox()
        : satcat5::io::BufferedIO(
            m_txbuf, SATCAT5_MAILBOX_BUFFSIZE, SATCAT5_MAILBOX_BUFFPKT,
            m_rxbuf, SATCAT5_MAILBOX_BUFFSIZE, SATCAT5_MAILBOX_BUFFPKT)
    {
        // Nothing else to initialize
    }

protected:
    void data_rcvd() override {
        irq_poll();     // New data triggers a ConfigBus interrupt.
    }

    cfg::IoStatus read(unsigned regaddr, u32& rdval) override {
        // Mailbox only has one control/status register.
        if (m_tx.get_read_ready() == 1) {
            rdval = STATUS_EOF | STATUS_DVALID | m_tx.read_u8();
            m_tx.read_finalize();
        } else if (m_tx.get_read_ready()) {
            rdval = STATUS_DVALID | m_tx.read_u8();
        } else {
            rdval = 0;
        }
        return cfg::IoStatus::OK;
    }

    cfg::IoStatus write(unsigned regaddr, u32 wrval) override {
        // Mailbox only has one control/status register.
        u32 opcode = (wrval & 0xFF000000u);
        u32 data   = (wrval & 0x000000FFu);
        if (opcode == CMD_NOOP) {
            // Do nothing.
        } else if (opcode == CMD_WRNEXT) {
            m_rx.write_u8(data);    // Write data
        } else if (opcode == CMD_WRFINAL) {
            m_rx.write_u8(data);    // Write data + EOF
            m_rx.write_finalize();
        } else if (opcode == CMD_RESET) {
            m_tx.clear();           // Clear FIFO contents
            m_rx.clear();
        } else {
            CATCH_ERROR("Unexpected opcode");
        }
        return cfg::IoStatus::OK;
    }

    // Working buffers for BufferedIO.
    u8 m_rxbuf[SATCAT5_MAILBOX_BUFFSIZE];
    u8 m_txbuf[SATCAT5_MAILBOX_BUFFSIZE];
};

TEST_CASE("port_mailbox") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Create the hardware-emulator and the driver under test.
    MockMailbox mock;
    satcat5::port::Mailbox uut(&mock, CFG_DEVADDR, CFG_REGADDR);

    SECTION("Tx") {
        uut.write_str("Short test 1.");
        uut.write_finalize();
        uut.write_str("Short test 2.");
        uut.write_finalize();
        satcat5::poll::service();
        satcat5::poll::service();
        CHECK(read_str(&mock) == "Short test 1.");
        CHECK(read_str(&mock) == "Short test 2.");
    }

    SECTION("Rx") {
        mock.write_str("Short test 1.");
        mock.write_finalize();
        mock.write_str("Short test 2.");
        mock.write_finalize();
        satcat5::poll::service();
        satcat5::poll::service();
        CHECK(read_str(&uut) == "Short test 1.");
        CHECK(read_str(&uut) == "Short test 2.");
    }

    SECTION("Tx-long") {
        for (u16 a = 0 ; a < 321 ; ++a)
            uut.write_u16(a);  // Write a total of 642 bytes.
        uut.write_finalize();
        satcat5::poll::service_all();
        REQUIRE(mock.get_read_ready() == 642);
        for (u16 a = 0 ; a < 321 ; ++a)
            CHECK(mock.read_u16() == a);
        mock.read_finalize();
    }

    SECTION("Rx-long") {
        for (u16 a = 0 ; a < 321 ; ++a)
            mock.write_u16(a);  // Write a total of 642 bytes.
        mock.write_finalize();
        satcat5::poll::service_all();
        REQUIRE(uut.get_read_ready() == 642);
        for (u16 a = 0 ; a < 321 ; ++a)
            CHECK(uut.read_u16() == a);
        uut.read_finalize();
    }

    SECTION("Rx-overflow") {
        // Write one more than the maximum number of frames.
        for (u32 a = 0 ; a <= SATCAT5_MAILBOX_BUFFPKT ; ++a) {
            mock.write_u32(a);
            CHECK(mock.write_finalize());
            satcat5::poll::service();
        }
        // Confirm the last frame was discarded cleanly.
        for (u32 a = 0 ; a < SATCAT5_MAILBOX_BUFFPKT ; ++a) {
            CHECK(uut.read_u32() == a);
            uut.read_finalize();
        }
        CHECK(uut.get_read_ready() == 0);
    }
}
