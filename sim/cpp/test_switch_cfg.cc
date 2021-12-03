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
// Test cases for the ConfigBus Timer controller

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/switch_cfg.h>

// Address constants:
static const unsigned CFG_DEVADDR   = 42;
static const unsigned REG_PORTCOUNT = 0;    // Number of ports (read-only)
static const unsigned REG_DATAPATH  = 1;    // Datapath width, in bits (read-only)
static const unsigned REG_CORECLOCK = 2;    // Core clock frequency, in Hz (read-only)
static const unsigned REG_MACCOUNT  = 3;    // MAC-address table size (read-only)
static const unsigned REG_PROMISC   = 4;    // Promisicuous port mask (read-write)
static const unsigned REG_PRIORITY  = 5;    // Packet prioritization (read-write, optional)
static const unsigned REG_PKTCOUNT  = 6;    // Packet-counting w/ filter (read-write)
static const unsigned REG_FRAMESIZE = 7;    // Min/max frame size limits (read-only)
static const unsigned REG_VLAN_PORT = 8;    // VLAN port configuration
static const unsigned REG_VLAN_VID  = 9;    // VLAN connections (VID)
static const unsigned REG_VLAN_MASK = 10;   // VLAN connections (port-mask)

// Other configuration constants:
static const unsigned PORT_COUNT    = 5;    // Number of ports on this switch
static const unsigned TBL_PRIORITY  = 4;    // Max number of high-priority EtherTypes

TEST_CASE("switch_cfg") {
    // Print any severe SatCat5 messages to console.
    // (We do expect a few warnings during these tests; ignore them.)
    satcat5::log::ToConsole log(satcat5::log::ERROR);

    // Configure simulated register-map.
    satcat5::test::CfgDevice regs;
    regs[REG_PORTCOUNT].read_default(PORT_COUNT);   // N-port switch
    regs[REG_DATAPATH].read_default(24);            // 24-bit datapath
    regs[REG_CORECLOCK].read_default(100e6);        // 100 MHz clock
    regs[REG_MACCOUNT].read_default(32);            // Up to 32 MAC-addresses
    regs[REG_PROMISC].read_default_echo();          // Promiscuous port mask
    regs[REG_PRIORITY].read_default(TBL_PRIORITY);  // Max priority filters
    regs[REG_PKTCOUNT].read_default_none();         // Packet-counting filter
    regs[REG_FRAMESIZE].read_default(0x05F20040);   // Default: Max = 1522, Min = 64
    regs[REG_VLAN_PORT].read_default_none();        // Port-config = write-only
    regs[REG_VLAN_VID].read_default_none();         // VID register = write-only
    regs[REG_VLAN_MASK].read_default_echo();        // Mask register = echo

    // Unit under test.
    satcat5::eth::SwitchConfig uut(&regs, CFG_DEVADDR);

    // Confirm startup process clears the priority table.
    // (This also implicitly tests the "priority_reset" method.)
    CHECK(regs[REG_PRIORITY].write_count() == TBL_PRIORITY);
    for (unsigned a = 0 ; a < TBL_PRIORITY ; ++a) {
        CHECK(regs[REG_PRIORITY].write_pop() == (a << 24));
    }

    SECTION("priority_set") {
        // Note: Expected register-write format is 0xAABBCCCC, where
        //  AA = Table index (0-3)
        //  BB = Wildcard length (0 = exact match, 1+ = wildcard LSBs)
        //  CC = EtherType
        bool ok;
        ok = uut.priority_set(0x1234, 17);  // Invalid length
        CHECK(!ok); CHECK(regs[REG_PRIORITY].write_count() == 0);
        ok = uut.priority_set(0x1234, 16);  // 0x1234 only
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x00001234u);
        ok = uut.priority_set(0x2340, 12);  // 0x2340 - 0x234F
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x01042340u);
        ok = uut.priority_set(0x3400, 8);   // 0x3400 - 0x34FF
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x02083400u);
        ok = uut.priority_set(0x4000, 4);   // 0x4000 - 0x4FFF
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x030C4000u);
        ok = uut.priority_set(0x5678, 16);  // Table overflow
        CHECK(!ok); CHECK(regs[REG_PRIORITY].write_count() == 0);
    }

    SECTION("promiscuous_mask") {
        // Set port #3 (0x0008)
        CHECK(uut.get_promiscuous_mask() == 0x0000);    // Initial state = 0
        uut.set_promiscuous(3, true);
        CHECK(regs[REG_PROMISC].write_pop() == 0x0008); // Confirm HW register
        CHECK(uut.get_promiscuous_mask() == 0x0008);    // Confirm SW register

        // Set port #2 (0x0004) and clear port #3.
        uut.set_promiscuous(2, true);
        CHECK(regs[REG_PROMISC].write_pop() == 0x000C); // Confirm HW register
        uut.set_promiscuous(3, false);
        CHECK(regs[REG_PROMISC].write_pop() == 0x0004); // Confirm HW register
        CHECK(uut.get_promiscuous_mask() == 0x0004);    // Confirm SW register

        // Set port #1 (0x0002)
        uut.set_promiscuous(1, true);
        CHECK(regs[REG_PROMISC].write_pop() == 0x0006); // Confirm HW register
        CHECK(uut.get_promiscuous_mask() == 0x0006);    // Confirm SW register
    }

    SECTION("traffic_filter") {
        // Preset reads for this simulation.
        regs[REG_PKTCOUNT].read_push(0x0000);           // Read-on-configure
        regs[REG_PKTCOUNT].read_push(0x0005);           // End of 1st interval
        regs[REG_PKTCOUNT].read_push(0x0007);           // End of 2nd interval

        // Configure the filter.
        CHECK(uut.get_traffic_filter() == 0x0000);      // Initial state
        uut.set_traffic_filter(0x1234);                 // Set filter mode
        CHECK(uut.get_traffic_filter() == 0x1234);      // New filter mode
        CHECK(regs[REG_PKTCOUNT].write_pop() == 0x1234);

        // Poll for a few intervals.
        CHECK(uut.get_traffic_count() == 0x0005);       // End of 1st interval
        CHECK(regs[REG_PKTCOUNT].write_pop() == 0x1234);
        CHECK(uut.get_traffic_count() == 0x0007);       // End of 2nd interval
        CHECK(regs[REG_PKTCOUNT].write_pop() == 0x1234);
    }

    SECTION("frame_size") {
        CHECK(uut.get_frame_min() == 64);
        CHECK(uut.get_frame_max() == 1522);
    }

    SECTION("log_info") {
        log.disable();                                  // Suppress test message
        uut.log_info("Test");
    }

    SECTION("port_count") {
        CHECK(uut.port_count() == PORT_COUNT);
    }

    SECTION("vlan_reset") {
        uut.vlan_reset(false);                          // Reset in normal mode
        CHECK(uut.vlan_get_mask(123) == satcat5::eth::VLAN_CONNECT_ALL);
        CHECK(uut.vlan_get_mask(456) == satcat5::eth::VLAN_CONNECT_ALL);
        uut.vlan_reset(true);                           // Reset in lockdown mode
        CHECK(uut.vlan_get_mask(123) == satcat5::eth::VLAN_CONNECT_NONE);
        CHECK(uut.vlan_get_mask(456) == satcat5::eth::VLAN_CONNECT_NONE);
    }

    SECTION("vlan_masks") {
        uut.vlan_set_mask(789, 0x2345);                 // Set port mask for VID = 789
        CHECK(regs[REG_VLAN_VID].write_pop() == 789);
        CHECK(regs[REG_VLAN_MASK].write_pop() == 0x2345);
        CHECK(uut.vlan_get_mask(789) == 0x02345);       // Confirm new setting
        uut.vlan_join(789, 16);                         // Port 16 joins VID = 789
        CHECK(uut.vlan_get_mask(789) == 0x12345);       // Confirm new setting
        uut.vlan_leave(789, 0);                         // Port 0 leaves VID = 789
        CHECK(uut.vlan_get_mask(789) == 0x12344);       // Confirm new setting
    }

    SECTION("vlan_ports") {
        for (u32 a = 0 ; a < 5 ; ++a) {
            uut.vlan_set_port(a);
            CHECK(regs[REG_VLAN_PORT].write_pop() == a);
        }
    }
}
