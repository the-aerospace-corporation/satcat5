//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus HDLC driver

#include <deque>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_hdlc.h>
#include <satcat5/polling.h>
#include <satcat5/utils.h>

namespace cfg = satcat5::cfg;

// Set debugging verbosity (0/1/2)
#define DEBUG_VERBOSE   0

// Define register map (see "cfgbus_hdlc.vhd")
static const unsigned CFG_DEVADDR = 42;
static const unsigned REG_IRQ   = 0;
static const unsigned REG_CFG   = 1;
static const unsigned REG_STAT  = 2;
static const unsigned REG_DATA  = 3;
static const unsigned HW_CLKREF = 100e6;
static const unsigned HW_QUEUE  = 16;

// Define control-register commands:
static const u32 CMD_EOF = 0x0100u;

// Define status flags.
static const u32 MS_RD_READY    = (1u << 0);
static const u32 MS_CMD_FULL    = (1u << 1);
static const u32 MS_DVALID      = (1u << 8);

// Simulate the HDLC interface.
class MockHdlc : public cfg::ConfigBus {
public:
    MockHdlc() : m_cfg(0) {}

    void check_baud(unsigned baud) {
        CHECK(m_cfg == satcat5::util::div_round_u32(HW_CLKREF, baud));
    }

    // Write a string of bytes to the HDLC receive buffer.
    void buf_wr(const std::string& msg) {
        for (unsigned a = 0 ; a < msg.length() ; ++a)
            m_rx.push_back((u8)msg[a]);
        irq_poll();
    }

    // Read to EOF marker (0x0100) or end-of-buffer, whichever comes first.
    // (If it is present, this method also consumes the end-of-frame marker.)
    std::string buf_rd() {
        auto eof = find(m_tx.begin(), m_tx.end(), 0x0100);
        std::string str(m_tx.begin(), eof);
        if (eof != m_tx.end()) ++eof;
        m_tx.erase(m_tx.begin(), eof);
        return str;
    }

    std::deque<u16> m_tx, m_rx;

protected:
    cfg::IoStatus read(unsigned regaddr, u32& rdval) override {
        regaddr = regaddr % cfg::REGS_PER_DEVICE;
        if (regaddr == REG_IRQ) {
            if (DEBUG_VERBOSE > 1) printf("Interrupt polled.\n");
            rdval = m_rx.empty() ? 0 : 3;   // Data in Rx queue?
        } else if (regaddr == REG_CFG) {
            m_tx.clear();                   // Reset HW buffers
            m_rx.clear();
            rdval = m_cfg;                  // Echo last write
        } else if (regaddr == REG_STAT) {
            u32 status = 0;                 // Report status word
            if (m_rx.size() > 0) status |= MS_RD_READY;
            if (m_tx.size() >= HW_QUEUE) status |= MS_CMD_FULL;
            if (DEBUG_VERBOSE > 1) printf("Status = %u\n", status);
            rdval = status;
        } else if (regaddr == REG_DATA && m_rx.empty()) {
            if (DEBUG_VERBOSE > 1) printf("Reading = Empty\n");
            rdval = 0;                      // Rx empty
        } else if (regaddr == REG_DATA) {
            u8 next = m_rx.front(); m_rx.pop_front();
            if (DEBUG_VERBOSE > 0) printf("Reading = '%c'\n", (char)next);
            rdval = MS_DVALID | next;       // Rx data
        } else {
            CATCH_ERROR("Invalid read");
            rdval = 0; return cfg::IOSTATUS_BUSERROR;
        }
        return cfg::IOSTATUS_OK;
    }

    cfg::IoStatus write(unsigned regaddr, u32 val) override {
        regaddr = regaddr % satcat5::cfg::REGS_PER_DEVICE;
        if (regaddr == REG_IRQ) {
            if (DEBUG_VERBOSE > 1) printf("Interrupt serviced.\n");
        } else if (regaddr == REG_CFG) {
            if (DEBUG_VERBOSE > 0) printf("Config = %u\n", val);
            m_cfg = val;                    // Store new configuration
        } else if (regaddr == REG_DATA) {
            if (DEBUG_VERBOSE > 0) printf("Writing = '%c' (0x%02X)\n", (char)val, val);
            CHECK(m_tx.size() < HW_QUEUE);  // FIFO overflow?
            m_tx.push_back((u16)val);        // Write new byte
        } else {
            CATCH_ERROR("Invalid write");
            return cfg::IOSTATUS_BUSERROR;
        }
        return cfg::IOSTATUS_OK;
    }

    u32 m_cfg;
};

TEST_CASE("cfgbus_hdlc") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;

    // Unit under test.
    MockHdlc mock;
    cfg::Hdlc uut(&mock, CFG_DEVADDR);

    SECTION("configure") {
        uut.configure(HW_CLKREF, 921600);
        mock.check_baud(921600);
        uut.configure(HW_CLKREF, 115200);
        mock.check_baud(115200);
    }

    SECTION("Tx-short") {
        uut.write_str("Short test.");
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "Short test.");
    }

    SECTION("Tx-long") {
        uut.write_str("Longer test exceeds hardware queue size.");
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "Longer test exce");
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "eds hardware que");
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "ue size.");
    }

    SECTION("Tx-multi") {
        uut.write_str("1st Packet");
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "1st Packet");
        uut.write_str("2nd Packet");
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "2nd Packet");
        uut.write_str("3rd Packet");
        uut.write_finalize();
        satcat5::poll::service();
        CHECK(mock.buf_rd() == "3rd Packet");
    }

    SECTION("Rx-short") {
        mock.buf_wr("Short test.");
        satcat5::poll::service();
        CHECK(read_str(&uut) == "Short test.");
    }

    SECTION("Rx-long") {
        mock.buf_wr("Longer test exce");
        mock.buf_wr("eds hardware que");
        mock.buf_wr("ue size.");
        satcat5::poll::service();
        CHECK(read_str(&uut) == "Longer test exceeds hardware queue size.");
    }
}
