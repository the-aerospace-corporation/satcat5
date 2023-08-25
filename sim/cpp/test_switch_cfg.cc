//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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
// Test cases for configuring managed Ethernet switches

#include <hal_test/catch.hpp>
#include <hal_test/sim_cfgbus.h>
#include <hal_test/sim_utils.h>
#include <satcat5/switch_cfg.h>

// Address constants:
static const unsigned REG_PORTCOUNT = 0;    // Number of ports (read-only)
static const unsigned REG_DATAPATH  = 1;    // Datapath width, in bits (read-only)
static const unsigned REG_CORECLOCK = 2;    // Core clock frequency, in Hz (read-only)
static const unsigned REG_MACCOUNT  = 3;    // MAC-address table size (read-only)
static const unsigned REG_PROMISC   = 4;    // Promisicuous port mask (read-write)
static const unsigned REG_PRIORITY  = 5;    // Packet prioritization (read-write, optional)
static const unsigned REG_PKTCOUNT  = 6;    // Packet-counting w/ filter (read-write)
static const unsigned REG_FRAMESIZE = 7;    // Min/max frame size limits (read-only)
static const unsigned REG_VLAN_PORT = 8;    // VLAN port configuration (write-only)
static const unsigned REG_VLAN_VID  = 9;    // VLAN connections: set VID (read-write)
static const unsigned REG_VLAN_MASK = 10;   // VLAN connections: set mask (read-write)
static const unsigned REG_MAC_LSB   = 11;   // MAC-table queries (read-write)
static const unsigned REG_MAC_MSB   = 12;   // MAC-table queries (read-write)
static const unsigned REG_MAC_CTRL  = 13;   // MAC-table queries (read-write)
static const unsigned REG_MISSFLAG  = 14;   // Miss-as-broadcast port mask (read-write)
static const unsigned REG_PTP_2STEP = 15;   // PTP "twoStep" mode flag (read-write)
static const unsigned REG_VLAN_RATE = 16;   // VLAN rate-control configuration (write-only)
static unsigned REG_PORT(unsigned idx)      {return 512 + 16*idx;}
static unsigned REG_PTP_RX(unsigned idx)    {return REG_PORT(idx) + 8;}
static unsigned REG_PTP_TX(unsigned idx)    {return REG_PORT(idx) + 9;}

// Other configuration constants:
static const unsigned CFG_DEVADDR   = 42;   // Device address for test switch
static const unsigned PORT_COUNT    = 5;    // Number of ports on test switch
static const unsigned TBL_PRIORITY  = 4;    // Max number of high-priority EtherTypes
static const unsigned MAC_COUNT     = 32;   // Size of MAC-address table

TEST_CASE("switch_cfg") {
    // Print any severe SatCat5 messages to console.
    // (We do expect a few warnings during these tests; ignore them.)
    satcat5::log::ToConsole log(satcat5::log::ERROR);

    // Configure simulated register-map.
    satcat5::test::CfgDevice regs;
    regs[REG_PORTCOUNT].read_default(PORT_COUNT);   // N-port switch
    regs[REG_DATAPATH].read_default(24);            // 24-bit datapath
    regs[REG_CORECLOCK].read_default(100e6);        // 100 MHz clock
    regs[REG_MACCOUNT].read_default(MAC_COUNT);     // Up to N MAC-addresses
    regs[REG_PROMISC].read_default_echo();          // Promiscuous port mask
    regs[REG_PRIORITY].read_default(TBL_PRIORITY);  // Max priority filters
    regs[REG_PKTCOUNT].read_default_none();         // Packet-counting filter
    regs[REG_FRAMESIZE].read_default(0x05F20040);   // Default: Max = 1522, Min = 64
    regs[REG_VLAN_PORT].read_default_none();        // Port-config = write-only
    regs[REG_VLAN_VID].read_default_none();         // VID register = write-only
    regs[REG_VLAN_MASK].read_default_echo();        // Mask register = echo
    regs[REG_MAC_LSB].read_default_none();          // Only read at designated times
    regs[REG_MAC_MSB].read_default_none();          // Only read at designated times
    regs[REG_MAC_CTRL].read_default(0);             // Default = Idle/done
    regs[REG_MISSFLAG].read_default_echo();         // Miss-as-broadcast port mask
    regs[REG_PTP_2STEP].read_default_echo();        // PTP twoStep = echo
    regs[REG_VLAN_RATE].read_default(16);           // Rate-limiter ACCUM_WIDTH

    for (unsigned a = 0 ; a < PORT_COUNT ; ++a) {
        regs[REG_PTP_RX(a)].read_default_echo();    // PTP time offset (Rx)
        regs[REG_PTP_TX(a)].read_default_echo();    // PTP time offset (Tx)
    }

    // Unit under test.
    satcat5::eth::SwitchConfig uut(&regs, CFG_DEVADDR);

    // Confirm startup process clears the priority table.
    // (This also implicitly tests the "priority_reset" method.)
    CHECK(regs[REG_PRIORITY].write_queue() == TBL_PRIORITY);
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
        CHECK(!ok); CHECK(regs[REG_PRIORITY].write_queue() == 0);
        ok = uut.priority_set(0x1234, 16);  // 0x1234 only
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x00001234u);
        ok = uut.priority_set(0x2340, 12);  // 0x2340 - 0x234F
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x01042340u);
        ok = uut.priority_set(0x3400, 8);   // 0x3400 - 0x34FF
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x02083400u);
        ok = uut.priority_set(0x4000, 4);   // 0x4000 - 0x4FFF
        CHECK(ok);  CHECK(regs[REG_PRIORITY].write_pop() == 0x030C4000u);
        ok = uut.priority_set(0x5678, 16);  // Table overflow
        CHECK(!ok); CHECK(regs[REG_PRIORITY].write_queue() == 0);
    }

    SECTION("miss-broadcast") {
        // Set port #3 (0x0008)
        CHECK(uut.get_miss_mask() == 0x0000);           // Initial state = 0
        uut.set_miss_bcast(3, true);                    // Issue command
        CHECK(regs[REG_MISSFLAG].write_pop() == 0x0008);
        CHECK(uut.get_miss_mask() == 0x0008);           // Confirm SW register

        // Set port #2 (0x0004) and clear port #3.
        uut.set_miss_bcast(2, true);                    // Issue command
        CHECK(regs[REG_MISSFLAG].write_pop() == 0x000C);
        uut.set_miss_bcast(3, false);                   // Issue command
        CHECK(regs[REG_MISSFLAG].write_pop() == 0x0004);
        CHECK(uut.get_miss_mask() == 0x0004);           // Confirm SW register

        // Set port #1 (0x0002)
        uut.set_miss_bcast(1, true);                    // Issue command
        CHECK(regs[REG_MISSFLAG].write_pop() == 0x0006);
        CHECK(uut.get_miss_mask() == 0x0006);           // Confirm SW register
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

    SECTION("ptp_2step") {
        // Set port #3 (0x0008)
        CHECK(uut.ptp_get_2step_mask() == 0x0000);    // Initial state = 0
        uut.ptp_set_2step(3, true);
        CHECK(regs[REG_PTP_2STEP].write_pop() == 0x0008);
        CHECK(uut.ptp_get_2step_mask() == 0x0008);    // Confirm SW register

        // Set port #2 (0x0004) and clear port #3.
        uut.ptp_set_2step(2, true);
        CHECK(regs[REG_PTP_2STEP].write_pop() == 0x000C);
        uut.ptp_set_2step(3, false);
        CHECK(regs[REG_PTP_2STEP].write_pop() == 0x0004);
        CHECK(uut.ptp_get_2step_mask() == 0x0004);    // Confirm SW register

        // Set port #1 (0x0002)
        uut.ptp_set_2step(1, true);
        CHECK(regs[REG_PTP_2STEP].write_pop() == 0x0006);
        CHECK(uut.ptp_get_2step_mask() == 0x0006);    // Confirm SW register
    }

    SECTION("ptp_offset") {
        uut.ptp_set_offset_rx(1, 111);
        uut.ptp_set_offset_rx(2, 222);
        uut.ptp_set_offset_rx(3, 333);
        uut.ptp_set_offset_tx(1, 444);
        uut.ptp_set_offset_tx(2, 555);
        uut.ptp_set_offset_tx(3, 666);

        CHECK(regs[REG_PTP_RX(1)].write_pop() == 111);
        CHECK(regs[REG_PTP_RX(2)].write_pop() == 222);
        CHECK(regs[REG_PTP_RX(3)].write_pop() == 333);
        CHECK(regs[REG_PTP_TX(1)].write_pop() == 444);
        CHECK(regs[REG_PTP_TX(2)].write_pop() == 555);
        CHECK(regs[REG_PTP_TX(3)].write_pop() == 666);

        CHECK(uut.ptp_get_offset_rx(1) == 111);
        CHECK(uut.ptp_get_offset_rx(2) == 222);
        CHECK(uut.ptp_get_offset_rx(3) == 333);
        CHECK(uut.ptp_get_offset_tx(1) == 444);
        CHECK(uut.ptp_get_offset_tx(2) == 555);
        CHECK(uut.ptp_get_offset_tx(3) == 666);
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

    SECTION("vlan_rates") {
        uut.vlan_set_rate(0x123, satcat5::eth::VRATE_UNLIMITED);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 0);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 0);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 0x80000123u);
        uut.vlan_set_rate(0x234, satcat5::eth::VRATE_1GBPS);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 500);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 500);
        CHECK(regs[REG_VLAN_RATE].write_pop() == 0xA8000234u);
    }

    SECTION("mactbl_read") {
        // Queue register reads for this simulation.
        const satcat5::eth::MacAddr REF_ADDR = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC};
        regs[REG_MAC_MSB].read_push(0x00001234);
        regs[REG_MAC_LSB].read_push(0x56789ABC);
        // Function under test.
        unsigned port_idx;
        satcat5::eth::MacAddr mac_addr;
        REQUIRE(uut.mactbl_read(0x42, port_idx, mac_addr));
        // Check writes to each expected control register.
        CHECK(regs[REG_MAC_CTRL].write_pop() == 0x01000042);
        // Check reported results.
        CHECK(port_idx == 0);
        CHECK(mac_addr == REF_ADDR);
    }

    SECTION("mactbl_write") {
        // Function under test.
        const satcat5::eth::MacAddr REF_ADDR = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC};
        REQUIRE(uut.mactbl_write(0x11, REF_ADDR));
        // Check writes to each control register.
        CHECK(regs[REG_MAC_MSB].write_pop() == 0x00001234);
        CHECK(regs[REG_MAC_LSB].write_pop() == 0x56789ABC);
        CHECK(regs[REG_MAC_CTRL].write_pop() == 0x02000011);
    }

    SECTION("mactbl_clear") {
        // Function under test.
        REQUIRE(uut.mactbl_clear());
        // Check writes to each expected control register.
        CHECK(regs[REG_MAC_CTRL].write_pop() == 0x03000000);
    }

    SECTION("mactbl_learn") {
        // Turn learning on.
        REQUIRE(uut.mactbl_learn(true));
        CHECK(regs[REG_MAC_CTRL].write_pop() == 0x04000001);
        // Turn learning off.
        REQUIRE(uut.mactbl_learn(false));
        CHECK(regs[REG_MAC_CTRL].write_pop() == 0x04000000);
    }

    SECTION("mactbl_timeout") {
        // Force a timeout by having control register return "busy" forever.
        regs[REG_MAC_CTRL].read_default(0x12000000);
        CHECK_FALSE(uut.mactbl_clear());
    }

    SECTION("mactbl_log") {
        // Fill the table except for one empty row.
        for (unsigned a = 1 ; a < MAC_COUNT ; ++a) {
            regs[REG_MAC_MSB].read_push(a);
            regs[REG_MAC_LSB].read_push(a);
        }
        regs[REG_MAC_MSB].read_push(0x0000FFFFu);
        regs[REG_MAC_LSB].read_push(0xFFFFFFFFu);
        // Call function under test.
        // (Log output is below the default threshold for this file.)
        uut.mactbl_log("TestLabel");
    }
}
