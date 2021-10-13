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
// Test cases for the ConfigBus MDIO controller

#include <vector>
#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_mdio.h>

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const unsigned CFG_REGADDR = 0;
static const u32 RD_VALID = (1u << 30);

// Helper function for making MDIO register commands.
u32 make_cmd(bool rd, unsigned phy, unsigned reg, unsigned data=0)
{
    unsigned cmd = rd ? (2u << 26) : (1u << 26);
    cmd |= (phy << 21);
    cmd |= (reg << 16);
    cmd |= (data << 0);
    return (u32)cmd;
}

// Helper object for checking read response.
class MdioEventCheck final : public satcat5::cfg::MdioEventListener {
public:
    MdioEventCheck(u16 regaddr, u16 regval)
        : m_regaddr(regaddr), m_regval(regval), m_count(0) {}

    void mdio_done(u16 regaddr, u16 regval) {
        CHECK(regaddr == m_regaddr);
        CHECK(regval == m_regval);
        ++m_count;
    }

    unsigned events() const {return m_count;}

private:
    u16 m_regaddr;
    u16 m_regval;
    unsigned m_count;
};

TEST_CASE("cfgbus_mdio") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate emulator and the unit under test.
    satcat5::test::CfgRegister cfg;
    cfg.read_default(0);
    satcat5::cfg::Mdio uut(&cfg, CFG_DEVADDR, CFG_REGADDR);

    SECTION("write-simple") {
        // Execute a few writes...
        static const unsigned NWRITE = 20;
        for (unsigned a = 0 ; a < NWRITE ; ++a) {
            REQUIRE(uut.write(a, a, a));
        }
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == NWRITE);
        for (unsigned a = 0 ; a < NWRITE ; ++a) {
            u32 ref = make_cmd(false, a, a, a);
            CHECK(cfg.write_pop() == ref);
        }
    }

    SECTION("write-indirect") {
        // Execute a single indirect write.
        REQUIRE(uut.write(7, 42, 43));
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == 4);
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x001F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 42));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x401F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 43));
    }

    SECTION("write-full") {
        cfg.read_default(1u << 31);     // Status register = full
        CHECK(!uut.write(9, 9, 9));     // Should overflow.
    }

    SECTION("read-simple") {
        // Queue up as many reads as possible...
        std::vector<MdioEventCheck*> reads;
        for (unsigned a = 0 ; 1 ; ++a) {
            MdioEventCheck* evt = new MdioEventCheck(a, a);
            if (uut.read(a, a, evt)) {;
                reads.push_back(evt);   // Command accepted.
            } else {
                delete evt;             // Cleanup (abort)
                break;                  // Queue is full.
            }
        }
        // Poll once (emulated hardware is still busy)
        satcat5::poll::service();
        // Reads are ready after a short delay.
        for (unsigned a = 0 ; a < reads.size() ; ++a) {
            cfg.read_push(RD_VALID | a);
        }
        // Poll again (emulated hardware now "done")
        satcat5::poll::service();
        // Confirm the resulting command sequence.
        REQUIRE(reads.size() >= 7);
        REQUIRE(cfg.write_count() == reads.size());
        for (unsigned a = 0 ; a < reads.size() ; ++a) {
            u32 ref = make_cmd(true, a, a);
            CHECK(cfg.write_pop() == ref);
            CHECK(reads[a]->events() == 1);
            delete reads[a];            // Cleanup (success)
        }
    }

    SECTION("read-log") {
        satcat5::cfg::MdioLogger mlog;          // Unit under test
        log.disable();                          // Suppress printout
        uut.read(9, 9, &mlog);                  // Read command
        cfg.read_push(RD_VALID | 0x1234);       // Load hardware register
        satcat5::poll::service();               // Should post log event...
        CHECK(log.contains("0x1234"));
    }

    SECTION("read-safety") {
        // Queue up a single read.
        MdioEventCheck evt(4, 42);
        REQUIRE(uut.read(0, 4, &evt));
        // Poll once (emulated hardware is still busy)
        satcat5::poll::service();
        // Simulate unexpected-read anomaly, two reads instead of one.
        // (e.g., Due to an unexpected hardware fault or race-condition.)
        cfg.read_push(RD_VALID | 42);   // Expected read (keep)
        cfg.read_push(RD_VALID | 43);   // Off-nominal (discard)
        // Poll again (emulated hardware now "done")
        satcat5::poll::service();
        // Confirm we don't crash.
        REQUIRE(cfg.write_count() == 1);
        CHECK(cfg.write_pop() == make_cmd(true, 0, 4));
        CHECK(evt.events() == 1);
    }

    SECTION("read-indirect") {
        // Execute a single indirect read.
        MdioEventCheck evt(42, 43);
        REQUIRE(uut.read(7, 42, &evt));
        // Activate polling loop once.
        cfg.read_push(RD_VALID | 43);
        satcat5::poll::service();
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == 4);
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x001F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 42));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x401F));
        CHECK(cfg.write_pop() == make_cmd(true, 7, 0x0E));
        CHECK(evt.events() == 1);
    }
}
