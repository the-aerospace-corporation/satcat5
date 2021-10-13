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

class TestMultiSerial : public satcat5::cfg::MultiSerial {
public:
    TestMultiSerial(satcat5::cfg::ConfigBus* cfg)
        : satcat5::cfg::MultiSerial(
            cfg, CFG_DEVADDR, 16,
            m_txbuff, CMD_BUFFSIZE,
            m_rxbuff, CMD_BUFFSIZE)
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

    void read_done(unsigned cidx) override {}

private:
    unsigned write4() {
        m_tx.write_u16(1111);
        m_tx.write_u16(2222);
        m_tx.write_u16(3333);
        m_tx.write_u16(4444);
        write_finish();
        return m_tx.get_read_ready();
    }
    u8 m_txbuff[CMD_BUFFSIZE];
    u8 m_rxbuff[CMD_BUFFSIZE];
};

TEST_CASE("cfgbus_multiserial") {
    // Instantiate emulator and the unit under test.
    satcat5::test::MultiSerial mst;
    TestMultiSerial uut(&mst);

    // All the test actions use the same reference commands.

    SECTION("bad_write") {
        uut.bad_write();
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
        mst.poll();
        CHECK(mst.done());
    }
}
