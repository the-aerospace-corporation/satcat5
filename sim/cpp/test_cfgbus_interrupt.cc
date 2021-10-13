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
// Test cases for ConfigBus shared-interrupt handler

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/cfgbus_interrupt.h>

class MockInterrupt : public satcat5::cfg::Interrupt {
public:
    explicit MockInterrupt(satcat5::test::CfgDevice* cfg)
        : satcat5::cfg::Interrupt(cfg)
        , m_cfg(cfg)
        , m_count(0)
        , m_regaddr(0)
    {
        // Nothing else to initialize.
    }

    MockInterrupt(satcat5::test::CfgDevice* cfg, unsigned regaddr)
        : satcat5::cfg::Interrupt(cfg, 0, regaddr)
        , m_cfg(cfg)
        , m_count(0)
        , m_regaddr(regaddr)
    {
        // Nothing else to initialize.
    }

    unsigned count() const {return m_count;}

    void fire() {
        if (m_regaddr) m_cfg->write(m_regaddr, 0x03);
        m_cfg->irq_poll();
    }

protected:
    void irq_event() override {++m_count;}

    satcat5::test::CfgDevice* const m_cfg;
    unsigned m_count;
    unsigned m_regaddr;
};

TEST_CASE("cfgbus_interrupt") {
    satcat5::log::ToConsole log;    // Logging handler
    satcat5::test::CfgDevice cfg;   // ConfigBus interface
    cfg[1].read_default_echo();
    cfg[2].read_default_echo();
    cfg[3].read_default_echo();

    MockInterrupt uut0(&cfg);       // Test device (no control reg)
    MockInterrupt uut1(&cfg, 1);    // Test device (with control reg)
    MockInterrupt uut2(&cfg, 2);    // Test device (with control reg)
    MockInterrupt uut3(&cfg, 3);    // Test device (with control reg)

    SECTION("count_irq") {
        CHECK(cfg.count_irq() == 4);
    }

    SECTION("reg0") {
        uut0.fire();
        CHECK(uut0.count() == 1);
        CHECK(uut1.count() == 0);
        CHECK(uut2.count() == 0);
        CHECK(uut3.count() == 0);
    }

    SECTION("reg1") {
        uut1.fire();
        uut2.fire();
        uut3.fire();
        CHECK(uut0.count() == 3);   // Unfiltered
        CHECK(uut1.count() == 1);
        CHECK(uut2.count() == 1);
        CHECK(uut3.count() == 1);
    }

    SECTION("double-register") {
        log.disable();              // Suppress error message
        cfg.register_irq(&uut1);    // Duplicate registration!?
        CHECK(!log.empty());
        CHECK(cfg.count_irq() == 4);
    }

    SECTION("early-unregister") {
        cfg.unregister_irq(&uut2);      // Pick the one in the middle.
    }
}
