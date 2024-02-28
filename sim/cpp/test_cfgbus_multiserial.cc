//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus "Multiserial" controller
// The Multiserial controller is the common core for I2C and SPI, and those
// unit tests provide the bulk of the coverage for this block.  This file
// covers additional corner-cases that are otherwise difficult to reach.

#include <hal_test/catch.hpp>
#include <hal_test/sim_multiserial.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_multiserial.h>

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const unsigned CMD_BUFFSIZE = 256;

// Mock implementation of a MultiSerial driver, which allows
// for injection of invalid commands for internal validation.
class TestMultiSerial : public satcat5::cfg::MultiSerial {
public:
    TestMultiSerial(satcat5::cfg::ConfigBus* cfg)
        : satcat5::cfg::MultiSerial(
            cfg, CFG_DEVADDR, 16,
            m_txbuff, CMD_BUFFSIZE,
            m_rxbuff, CMD_BUFFSIZE)
        , m_count_rcvd(0)
    {
        // Nothing else to initialize
    }

    // Attempt to queue write with mismatched length.
    void bad_write() {
        CHECK(write_check(5, 0));   // Expect 5 opcodes, no reply
        CHECK(write4() == 0);       // Actually write 4!? Should abort.
    }

    // Queue a normal write.
    void write() {
        CHECK(write_check(4, 0));   // Expect 4 opcodes, no reply
        CHECK(write4() == 9);       // Queue 4 opcodes = 9 bytes total
    }

    // Queue a normal read.
    void read() {
        CHECK(write_check(4, 4));   // Expect 4 opcodes, 4 byte reply
        CHECK(write4() == 9);       // Queue 4 opcodes = 9 bytes total
    }

    void read_done(unsigned cidx) override {
        // This is where we'd normally issue a callback function.
        // Count received bytes now, since buffer is cleared on return.
        m_count_rcvd += m_rx.get_read_ready();
    }
    unsigned count_rcvd() const {return m_count_rcvd;}

private:
    unsigned write4() {
        m_tx.write_u16(1111);
        m_tx.write_u16(2222);
        m_tx.write_u16(3333);
        m_tx.write_u16(4444);
        write_finish();
        return m_tx.get_read_ready();
    }

    unsigned m_count_rcvd;
    u8 m_txbuff[CMD_BUFFSIZE];
    u8 m_rxbuff[CMD_BUFFSIZE];
};

TEST_CASE("cfgbus_multiserial") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate emulator and the unit under test.
    satcat5::test::MultiSerial mst;
    TestMultiSerial uut(&mst);

    SECTION("bad_write") {
        log.suppress("mismatch");   // Suppress expected error message
        uut.bad_write();            // Invalid prediction to MST core.
        CHECK(log.contains("mismatch"));
    }

    SECTION("busy") {
        // Setup emulated hardware.
        mst.force_busy(true);
        mst.load_refcmd(1111, satcat5::test::MST_START);
        mst.load_refcmd(2222);
        mst.load_refcmd(3333);
        mst.load_refcmd(4444);
        // Queue write sequence.
        uut.write();
        // Poll a few times before releasing BUSY flag.
        for (unsigned a = 0 ; a < 10 ; ++a) mst.poll();
        mst.force_busy(false);
        for (unsigned a = 0 ; a < 10 ; ++a) mst.poll();
        CHECK(mst.done());
        CHECK(uut.count_rcvd() == 1); // Status byte
    }

    SECTION("read") {
        // Setup emulated hardware.
        mst.load_refcmd(1111, satcat5::test::MST_START);
        mst.load_refcmd(2222);
        mst.load_refcmd(3333);
        mst.load_refcmd(4444);
        // Queue read sequence.
        uut.read();
        // Poll a few times without any reply data.
        for (unsigned a = 0 ; a < 10 ; ++a) mst.poll();
        CHECK(uut.count_rcvd() == 0);
        // Send the expected reply and poll again.
        mst.reply_rcvd(4);
        for (unsigned a = 0 ; a < 10 ; ++a) mst.poll();
        CHECK(mst.done());
        CHECK(uut.count_rcvd() == 5); // Status + 4 data
    }
}
