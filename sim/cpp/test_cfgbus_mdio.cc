//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the ConfigBus MDIO controller

#include <vector>
#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_mdio.h>

using satcat5::cfg::Mdio;
using satcat5::cfg::MdioEventListener;
using satcat5::cfg::MdioGenericMmd;
using satcat5::cfg::MdioLogger;
using satcat5::cfg::MdioMarvell;

// Constants relating to the unit under test:
static const unsigned CFG_DEVADDR = 42;
static const unsigned CFG_REGADDR = 0;
static const u32 RD_VALID = (1u << 30);
static const u32 WR_FULL  = (1u << 31);

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
class MdioEventCheck final : public MdioEventListener {
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

// Helper function for queueing up read commands.
MdioEventCheck* attempt_read(Mdio& mdio, unsigned n) {
    MdioEventCheck* evt = new MdioEventCheck(n, n);
    if (mdio.direct_read(n % 8, n % 32, n, evt)) {;
        return evt;     // Command accepted.
    } else {
        delete evt;     // Cleanup (abort)
        return 0;       // Queue is full.
    }
}

TEST_CASE("cfgbus_mdio") {
    // Print any SatCat5 messages to console.
    satcat5::log::ToConsole log;

    // Instantiate emulator and the unit under test.
    satcat5::test::CfgDevice dev;
    satcat5::test::CfgRegister& cfg = dev[0];
    cfg.read_default(0);
    Mdio uut(&dev, CFG_DEVADDR, CFG_REGADDR);

    SECTION("write-simple") {
        // Execute a few writes...
        static const unsigned NWRITE = 20;
        for (unsigned a = 0 ; a < NWRITE ; ++a) {
            REQUIRE(uut.direct_write(a, a, a));
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
        MdioGenericMmd mmd(&uut, 7);
        REQUIRE(mmd.write(24, 25));             // Direct (address < 32)
        REQUIRE(mmd.write(42, 43));             // Indirect (address >= 32)
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == 5);
        CHECK(cfg.write_pop() == make_cmd(false, 7, 24, 25));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x001F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 42));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x401F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 43));
    }

    SECTION("write-hwfull") {
        cfg.read_default(WR_FULL);              // Status register = full
        CHECK(!uut.direct_write(9, 9, 9));      // Should overflow.
        cfg.read_default(0);                    // Status register = ready
        CHECK(uut.direct_write(9, 9, 9));       // Should succeed.
    }

    SECTION("read-hwfull") {
        cfg.read_default(WR_FULL);              // Status register = full
        CHECK(!uut.direct_read(9, 9, 9, 0));    // Should overflow.
        cfg.read_default(0);                    // Status register = ready
        CHECK(uut.direct_read(9, 9, 9, 0));     // Should succeed.
    }

    SECTION("read-swfull") {
        // Queue up as many reads as possible...
        std::vector<MdioEventCheck*> reads;
        unsigned rdidx = 0;
        MdioEventCheck* evt = 0;
        while (evt = attempt_read(uut, reads.size())) {
            reads.push_back(evt);
        }
        CHECK(reads.size() >= SATCAT5_MDIO_BUFFSIZE);
        // Poll once (emulated hardware is still busy)
        satcat5::poll::service();
        // Reads are ready after a short delay.
        while (rdidx < reads.size()) {
            cfg.read_push(RD_VALID | rdidx++);
        }
        // Poll again (emulated hardware now "done")
        satcat5::poll::service();
        // Queue up an additional batch of reads.
        while (evt = attempt_read(uut, reads.size())) {
            reads.push_back(evt);
        }
        CHECK(reads.size() >= 2*SATCAT5_MDIO_BUFFSIZE);
        // Another round of poll / ready / poll.
        satcat5::poll::service();
        while (rdidx < reads.size()) {
            cfg.read_push(RD_VALID | rdidx++);
        }
        satcat5::poll::service();
        // Confirm the resulting command/response sequence.
        REQUIRE(rdidx == reads.size());
        REQUIRE(cfg.write_count() == reads.size());
        for (unsigned a = 0 ; a < reads.size() ; ++a) {
            u32 ref = make_cmd(true, a % 8, a % 32);
            CHECK(cfg.write_pop() == ref);
            CHECK(reads[a]->events() == 1);
            delete reads[a];            // Cleanup (success)
        }
    }

    SECTION("read-log") {
        MdioLogger mlog;                        // Unit under test
        log.suppress("0x1234");                 // Suppress printout
        uut.direct_read(9, 9, 9, &mlog);        // Read command
        cfg.read_push(RD_VALID | 0x1234);       // Load hardware register
        satcat5::poll::service();               // Should post log event...
        CHECK(log.contains("0x1234"));
    }

    SECTION("read-safety") {
        // Queue up a single read.
        MdioEventCheck evt(4, 42);
        REQUIRE(uut.direct_read(0, 4, 4, &evt));
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
        MdioEventCheck evt0(24, 25);
        MdioEventCheck evt1(42, 43);
        MdioGenericMmd mmd(&uut, 7);
        REQUIRE(mmd.read(24, &evt0));   // Direct (address < 32)
        REQUIRE(mmd.read(42, &evt1));   // Indirect (address >= 32)
        // Activate polling loop once.
        cfg.read_push(RD_VALID | 25);   // Direct read response
        cfg.read_push(RD_VALID | 43);   // Indirect read response
        satcat5::poll::service();
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == 5);
        CHECK(cfg.write_pop() == make_cmd(true, 7, 24));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x001F));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0E, 42));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x0D, 0x401F));
        CHECK(cfg.write_pop() == make_cmd(true, 7, 0x0E));
        CHECK(evt0.events() == 1);
        CHECK(evt1.events() == 1);
    }

    SECTION("read-write-marvell") {
        // Issue a write command and a read command.
        MdioMarvell mmd(&uut, 7);
        MdioEventCheck evt(0x203, 0x456);
        REQUIRE(mmd.write(0x102, 0x789));   // Write register 1.2
        REQUIRE(mmd.read(0x203, &evt));     // Read register 2.3
        // Confirm the resulting command sequence.
        REQUIRE(cfg.write_count() == 4);
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x16, 0x0001));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x02, 0x0789));
        CHECK(cfg.write_pop() == make_cmd(false, 7, 0x16, 0x0002));
        CHECK(cfg.write_pop() == make_cmd(true, 7, 0x03));
        // Confirm read result.
        satcat5::poll::service();
        CHECK(evt.events() == 0);
        cfg.read_push(RD_VALID | 0x456);
        satcat5::poll::service();
        CHECK(evt.events() == 1);
    }
}
