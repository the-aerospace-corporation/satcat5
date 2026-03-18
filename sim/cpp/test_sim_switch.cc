//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for configuring managed Ethernet switches

#include <hal_posix/file_pcap.h>
#include <hal_test/catch.hpp>
#include <hal_test/eth_endpoint.h>
#include <hal_test/sim_sw_core.h>
#include <hal_test/sim_utils.h>
#include <satcat5/eth_socket.h>
#include <satcat5/port_adapter.h>
#include <satcat5/switch_cfg.h>

using satcat5::eth::SwitchConfig;

// Device address for test switch
static const unsigned CFG_DEVADDR = 42;

// Define the MAC and IP address for each test device.
static const satcat5::eth::MacAddr
    MAC0 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00}},
    MAC1 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x11, 0x11}},
    MAC2 = {{0xDE, 0xAD, 0xBE, 0xEF, 0x22, 0x22}};
static const satcat5::ip::Addr
    IP0(192, 168, 0, 0),
    IP1(192, 168, 0, 1),
    IP2(192, 168, 0, 2);

TEST_CASE("sim_switch") {
    // Simulation infrastructure.
    SATCAT5_TEST_START;
    satcat5::io::WritePcap pcap;
    pcap.open(satcat5::test::sim_filename(__FILE__, "pcap"));
    satcat5::test::TimerSimulation timer;

    // Endpoints for the simulated LAN.
    satcat5::test::EthernetEndpoint nic0(MAC0, IP0);
    satcat5::test::EthernetEndpoint nic1(MAC1, IP1);
    satcat5::test::SlipEndpoint     nic2(MAC2, IP2);
    nic2.set_rate(921600);

    // Unit under test.
    satcat5::test::SimSwitchCore uut;
    uut.core()->set_debug(&pcap);
    auto core = uut.core();
    auto tbl  = uut.table();
    auto vlan = uut.vlan();

    // Create switch ports connected to each simulated endpoint.
    // (Two regular ports and one SLIP-encoded port.)
    satcat5::port::MailAdapter port0(core, &nic0, &nic0);
    satcat5::port::MailAdapter port1(core, &nic1, &nic1);
    satcat5::port::SlipAdapter port2(core, &nic2, &nic2);

    // Driver for controlling the simulated switch.
    satcat5::eth::SwitchConfig cfg(&uut, CFG_DEVADDR);

    SECTION("basics") {
        CHECK(cfg.port_count() == 3);
        CHECK(cfg.get_frame_min() == 18);
        CHECK(cfg.get_frame_max() == 1522);
        CHECK(cfg.mactbl_size() == tbl->mactbl_size());
    }

    SECTION("miss-broadcast") {
        CHECK(tbl->get_miss_mask() == satcat5::eth::PMASK_ALL);
        cfg.set_miss_mask(0);                           // Clear all
        CHECK(tbl->get_miss_mask() == 0x0000);          // Confirm update
        cfg.set_miss_bcast(3, true);                    // Set port 3 (0x08)
        CHECK(tbl->get_miss_mask() == 0x0008);          // Confirm update
        cfg.set_miss_bcast(2, true);                    // Set port 2 (0x04)
        CHECK(tbl->get_miss_mask() == 0x000C);          // Confirm update
        cfg.set_miss_bcast(3, false);                   // Clear port 3
        CHECK(tbl->get_miss_mask() == 0x0004);          // Confirm update
    }

    SECTION("promiscuous_mask") {
        CHECK(core->get_promiscuous_mask() == 0x0000);  // Initial state = 0
        cfg.set_promiscuous(3, true);                   // Set port 3 (0x08)
        CHECK(core->get_promiscuous_mask() == 0x0008);  // Confirm update
        cfg.set_promiscuous(2, true);                   // Set port 2 (0x04)
        CHECK(core->get_promiscuous_mask() == 0x000C);  // Confirm update
        cfg.set_promiscuous(3, false);                  // Clear port 3
        CHECK(core->get_promiscuous_mask() == 0x0004);  // Confirm update
    }

    SECTION("traffic_filter") {
        // Configure two traffic sources with different EtherTypes.
        satcat5::eth::SocketTx sock0(nic0.eth()), sock1(nic1.eth());
        sock0.connect(satcat5::eth::MACADDR_BROADCAST, {0x1234});
        sock1.connect(satcat5::eth::MACADDR_BROADCAST, {0x4321});
        // Count packets without a filter.
        CHECK(satcat5::test::write(&sock0, "Test message 1"));
        CHECK(satcat5::test::write(&sock1, "Test message 2"));
        timer.sim_wait(1);
        CHECK(cfg.get_traffic_count() == 2);            // Two packets total
        CHECK(cfg.get_traffic_count() == 0);            // Read clears counter
        // Count packets with a filter enabled (0x1234 = Sock0 only).
        cfg.set_traffic_filter(0x1234);
        CHECK(satcat5::test::write(&sock0, "Test message 3"));
        CHECK(satcat5::test::write(&sock1, "Test message 4"));
        timer.sim_wait(1);
        CHECK(cfg.get_traffic_count() == 1);            // One matches filter
        CHECK(cfg.get_traffic_count() == 0);            // Read clears counter
    }

    SECTION("ptp_offset") {
        cfg.ptp_set_offset_rx(1, 111);
        cfg.ptp_set_offset_rx(2, 222);
        cfg.ptp_set_offset_rx(3, 333);
        cfg.ptp_set_offset_tx(1, 444);
        cfg.ptp_set_offset_tx(2, 555);
        cfg.ptp_set_offset_tx(3, 666);
        CHECK(cfg.ptp_get_offset_rx(1) == 111);
        CHECK(cfg.ptp_get_offset_rx(2) == 222);
        CHECK(cfg.ptp_get_offset_rx(3) == 333);
        CHECK(cfg.ptp_get_offset_tx(1) == 444);
        CHECK(cfg.ptp_get_offset_tx(2) == 555);
        CHECK(cfg.ptp_get_offset_tx(3) == 666);
    }

    SECTION("vlan_reset") {
        cfg.vlan_reset(false);                          // Reset in normal mode
        CHECK(cfg.vlan_get_mask(12) == satcat5::eth::VLAN_CONNECT_ALL);
        CHECK(cfg.vlan_get_mask(34) == satcat5::eth::VLAN_CONNECT_ALL);
        CHECK(vlan->vlan_get_mask(12) == satcat5::eth::VLAN_CONNECT_ALL);
        CHECK(vlan->vlan_get_mask(34) == satcat5::eth::VLAN_CONNECT_ALL);
        cfg.vlan_reset(true);                           // Reset in lockdown mode
        CHECK(cfg.vlan_get_mask(12) == satcat5::eth::VLAN_CONNECT_NONE);
        CHECK(cfg.vlan_get_mask(34) == satcat5::eth::VLAN_CONNECT_NONE);
        CHECK(vlan->vlan_get_mask(12) == satcat5::eth::VLAN_CONNECT_NONE);
        CHECK(vlan->vlan_get_mask(34) == satcat5::eth::VLAN_CONNECT_NONE);
    }

    SECTION("vlan_masks") {
        // Set and confirm membership masks for several VLANs.
        cfg.vlan_set_mask(42, 0x002345);                // Set port mask for VID = 42
        CHECK(vlan->vlan_get_mask(42) == 0x002345);     // Confirm new setting
        cfg.vlan_join(42, 16);                          // Port 16 joins VID = 42
        CHECK(vlan->vlan_get_mask(42) == 0x012345);     // Confirm new setting
        cfg.vlan_leave(42, 0);                          // Port 0 leaves VID = 42
        CHECK(vlan->vlan_get_mask(42) == 0x012344);     // Confirm new setting
        // Set rate parameters, without confirmation.
        cfg.vlan_set_rate(42, satcat5::eth::VRATE_UNLIMITED);
        cfg.vlan_set_rate(43, satcat5::eth::VRATE_1GBPS);
    }

    SECTION("vlan_ports") {
        for (u16 a = 0 ; a < 3 ; ++a) {
            satcat5::eth::VtagPolicy ref(a, satcat5::eth::VTAG_RESTRICT);
            cfg.vlan_set_port(ref);
            auto rd = vlan->vlan_get_port(a);
            CHECK(rd.value == ref.value);
        }
    }
    SECTION("mac_table") {
        // Disable auto-learning mode.
        CHECK(tbl->mactbl_learn());
        CHECK(cfg.mactbl_learn(false));
        CHECK_FALSE(tbl->mactbl_learn());
        // Fill the MAC address table directly.
        CHECK(tbl->mactbl_write(0, MAC0));
        CHECK(tbl->mactbl_write(1, MAC1));
        // Read back contents.
        unsigned rd_port; satcat5::eth::MacAddr rd_addr;
        CHECK(cfg.mactbl_read(0, rd_port, rd_addr));
        CHECK(rd_port == 0);
        CHECK(rd_addr == MAC0);
        CHECK(cfg.mactbl_read(1, rd_port, rd_addr));
        CHECK(rd_port == 1);
        CHECK(rd_addr == MAC1);
        // Clear table contents, then load through the test interface.
        CHECK(cfg.mactbl_clear());
        CHECK(cfg.mactbl_write(2, MAC2));
        CHECK(cfg.mactbl_read(0, rd_port, rd_addr));
        CHECK(rd_port == 2);
        CHECK(rd_addr == MAC2);
    }
}
