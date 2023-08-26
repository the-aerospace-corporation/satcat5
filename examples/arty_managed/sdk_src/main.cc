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
// Microblaze software top-level for the "Arty Managed" example design

#include <hal_ublaze/interrupts.h>
#include <hal_ublaze/uart16550.h>
#include <satcat5/build_date.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_mdio.h>
#include <satcat5/cfgbus_led.h>
#include <satcat5/cfgbus_stats.h>
#include <satcat5/cfgbus_timer.h>
#include <satcat5/eth_chat.h>
#include <satcat5/ip_dhcp.h>
#include <satcat5/ip_stack.h>
#include <satcat5/log.h>
#include <satcat5/net_cfgbus.h>
#include <satcat5/port_mailmap.h>
#include <satcat5/port_serial.h>
#include <satcat5/switch_cfg.h>
#include "arty_devices.h"

using satcat5::cfg::LedActivity;
using satcat5::cfg::LedWave;
using satcat5::log::Log;
namespace ip = satcat5::ip;

// Enable diagnostic options?
#define DEBUG_DHCP_CLIENT   false
#define DEBUG_DHCP_SERVER   false
#define DEBUG_MAC_TABLE     true
#define DEBUG_MDIO_REG      false
#define DEBUG_PING_HOST     true
#define DEBUG_PORT_STATUS   false
#define DEBUG_REMOTE_CTRL   true
#define DEBUG_VLAN_DEMO     false
#define DEBUG_VLAN_LOCKDOWN true

// Global interrupt controller.
static XIntc irq_xilinx;
static satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);

// Xilinx peripherals.
satcat5::ublaze::Uart16550 uart_usb("UART",
        XPAR_INTC_0_UARTNS550_0_VEC_ID,
        XPAR_UARTNS550_0_DEVICE_ID);

// ConfigBus peripherals.
satcat5::cfg::ConfigBusMmap cfgbus((void*)XPAR_UBLAZE_CFGBUS_HOST_AXI_0_BASEADDR,
        XPAR_UBLAZE_MICROBLAZE_0_AXI_INTC_UBLAZE_CFGBUS_HOST_AXI_0_IRQ_OUT_INTR);
satcat5::port::Mailmap      eth_port        (&cfgbus, DEVADDR_MAILMAP);
satcat5::port::SerialAuto   pmod1           (&cfgbus, DEVADDR_PMOD1);
satcat5::port::SerialAuto   pmod2           (&cfgbus, DEVADDR_PMOD2);
satcat5::port::SerialAuto   pmod3           (&cfgbus, DEVADDR_PMOD3);
satcat5::port::SerialAuto   pmod4           (&cfgbus, DEVADDR_PMOD4);
satcat5::eth::SwitchConfig  eth_switch      (&cfgbus, DEVADDR_SWCORE);
satcat5::cfg::NetworkStats  traffic_stats   (&cfgbus, DEVADDR_TRAFFIC);
satcat5::cfg::Mdio          eth_mdio        (&cfgbus, DEVADDR_MDIO);
satcat5::cfg::Timer         timer           (&cfgbus, DEVADDR_TIMER);

// Balance red/green/blue brightness of Arty LEDs.
// Note: Full scale = 255 is overpoweringly bright.
static const u8 BRT_RED = 16;
static const u8 BRT_GRN = 10;
static const u8 BRT_BLU = 6;

// Status LED controllers.
satcat5::cfg::LedActivityCtrl   led_activity(&traffic_stats);
satcat5::cfg::LedWaveCtrl       led_wave;

LedWave led_rgb[] = {
    LedWave(&cfgbus, DEVADDR_LEDS, LED_BLU0, BRT_BLU),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_GRN0, BRT_GRN),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_RED0, BRT_RED),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_BLU1, BRT_BLU),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_GRN1, BRT_GRN),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_RED1, BRT_RED),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_BLU2, BRT_BLU),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_GRN2, BRT_GRN),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_RED2, BRT_RED),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_BLU3, BRT_BLU),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_GRN3, BRT_GRN),
    LedWave(&cfgbus, DEVADDR_LEDS, LED_RED3, BRT_RED),
};
LedActivity led_aux[] = {
    LedActivity(&cfgbus, DEVADDR_LEDS, LED_AUX0, PORT_IDX_PMOD1),
    LedActivity(&cfgbus, DEVADDR_LEDS, LED_AUX1, PORT_IDX_PMOD2),
    LedActivity(&cfgbus, DEVADDR_LEDS, LED_AUX2, PORT_IDX_PMOD3),
    LedActivity(&cfgbus, DEVADDR_LEDS, LED_AUX3, PORT_IDX_PMOD4),
};

constexpr unsigned LED_RGB_COUNT = sizeof(led_rgb) / sizeof(led_rgb[0]);
constexpr unsigned LED_AUX_COUNT = sizeof(led_aux) / sizeof(led_aux[0]);

// UDP network stack
static constexpr satcat5::eth::MacAddr LOCAL_MAC
    = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
static constexpr ip::Addr LOCAL_IP
    = DEBUG_DHCP_CLIENT ? ip::ADDR_NONE : ip::Addr(192, 168, 1, 42);
static constexpr ip::Addr PING_TARGET
    = DEBUG_PING_HOST ? ip::ADDR_NONE : ip::Addr(192, 168, 1, 1);

ip::Stack ip_stack(LOCAL_MAC, LOCAL_IP, &eth_port, &eth_port, &timer);

// DHCP client is dormant if user sets a static IP.
ip::DhcpClient ip_dhcp(&ip_stack.m_udp);

// Optional DHCP server for range 192.168.1.64 to 192.168.1.95
// (Do not enable client and server simultaneously.)
#if DEBUG_DHCP_SERVER && !DEBUG_DHCP_CLIENT
    ip::DhcpPoolStatic<32> ip_dhcp_pool(ip::Addr(192, 168, 1, 64));
    ip::DhcpServer ip_dhcp_server(&ip_stack.m_udp, &ip_dhcp_pool);
#endif

// Optional remote control of the local ConfigBus.
#if DEBUG_REMOTE_CTRL
    satcat5::eth::ProtoConfig cfgbus_server_eth(&ip_stack.m_eth, &cfgbus);
    satcat5::udp::ProtoConfig cfgbus_server_udp(&ip_stack.m_udp, &cfgbus);
#endif

// Chat message service with echo, bound to a specific VLAN ID.
// (The chat-echo service only responds to requests from this VID.)
const satcat5::eth::VlanTag VTAG_ECHO = {42};
satcat5::eth::ChatProto     chat_proto(&ip_stack.m_eth, "Arty", VTAG_ECHO);
satcat5::eth::ChatEcho      chat_echo(&chat_proto);

// Per-port VLAN configuration for the "toggling VID" example.
// (This is not a realistic network configuration, but works for a demo.)
static const u32 MAILMAP_MODE   = satcat5::eth::vlan_portcfg(
    PORT_IDX_MAILMAP, satcat5::eth::VTAG_MANDATORY);        // Always specify VID
static const u32 PMOD1_MODE     = satcat5::eth::vlan_portcfg(
    PORT_IDX_PMOD1, satcat5::eth::VTAG_RESTRICT, {1});      // Default VID = 1
static const u32 PMOD2_MODE     = satcat5::eth::vlan_portcfg(
    PORT_IDX_PMOD2, satcat5::eth::VTAG_RESTRICT, {1});      // Default VID = 1
static const u32 PMOD3_MODE     = satcat5::eth::vlan_portcfg(
    PORT_IDX_PMOD3, satcat5::eth::VTAG_RESTRICT, {1});      // Default VID = 1
static const u32 PMOD4_MODE     = satcat5::eth::vlan_portcfg(
    PORT_IDX_PMOD4, satcat5::eth::VTAG_RESTRICT, {1});      // Default VID = 1
static const u32 RMII_ECHO_ON   = satcat5::eth::vlan_portcfg(
    PORT_IDX_RMII, satcat5::eth::VTAG_ADMIT_ALL, {42});     // Default VID = 42
static const u32 RMII_ECHO_OFF  = satcat5::eth::vlan_portcfg(
    PORT_IDX_RMII, satcat5::eth::VTAG_ADMIT_ALL, {1});      // Default VID = 1

// Connect logging system to Ethernet-chat and to Arty's USB-UART.
satcat5::log::ToWriteable   log_uart(&uart_usb);
satcat5::eth::LogToChat     log_chat(&chat_proto);

// Also enable echo/loopback on the USB-UART.
satcat5::io::BufferedCopy   uart_echo(&uart_usb, &uart_usb);

// Timer object for general househeeping.
class HousekeepingTimer : satcat5::poll::Timer
{
public:
    HousekeepingTimer() : m_ctr(0) {
        timer_every(1000);  // Poll about once per second
    }
    void timer_event() override {
        // Send something on the UART to show we're still alive.
        Log(satcat5::log::DEBUG, "Heartbeat index").write(m_ctr++);
        // Optionally toggle the VLAN configuration every N seconds.
        // Note: VLAN_INTERVAL must be a power of two.
        static const unsigned VLAN_INTERVAL = 4;
        if (DEBUG_VLAN_DEMO && (m_ctr % VLAN_INTERVAL == 0)) {
            if (m_ctr & VLAN_INTERVAL) {
                Log(satcat5::log::INFO, "Chat-echo enabled.");
                eth_switch.vlan_set_port(RMII_ECHO_ON);
            } else {
                Log(satcat5::log::INFO, "Chat-echo disabled.");
                eth_switch.vlan_set_port(RMII_ECHO_OFF);
            }
        }
        // Optionally log key registers from the Ethernet PHY.
        // (Refer to DP83848 datasheet, Section 6.6 for more info.)
        if (DEBUG_MDIO_REG) {
            satcat5::cfg::MdioGenericMmd rmii(&eth_mdio, RMII_PHYADDR);
            rmii.read(0x00, &m_logger);     // BMCR
            rmii.read(0x01, &m_logger);     // BMSR
            rmii.read(0x10, &m_logger);     // PHYSTS
        }
        // Optionally log the SatCat5 port status register.
        // (Refer to port_rmii and port_statistics for more info.)
        if (DEBUG_PORT_STATUS) {
            u32 status = traffic_stats.get_port(PORT_IDX_RMII).status;
            Log(satcat5::log::DEBUG, "RMII status").write(status);
        }
    }
    u8 m_ctr;
    satcat5::cfg::MdioLogger m_logger;
} housekeeping;

// A slower timer object that activates once every minute.
class SlowHousekeepingTimer : satcat5::poll::Timer
{
public:
    SlowHousekeepingTimer() {
        timer_every(60000);
    }

    void timer_event() override {
        // Log the contents of the MAC routing table.
        if (DEBUG_MAC_TABLE) {
            eth_switch.mactbl_log("Arty-Switch");
        }
    }
} slowkeeping;

// Main loop: Initialize and then poll forever.
int main()
{
    // VLAN setup for the managed Ethernet switch.
    eth_switch.vlan_reset(DEBUG_VLAN_LOCKDOWN); // Lockdown or open mode?
    eth_switch.vlan_set_mask(1,                 // All ports allow VID = 1
        satcat5::eth::VLAN_CONNECT_ALL);
    eth_switch.vlan_set_mask(42,                // Some ports allow VID = 42
        PORT_MASK_MAILMAP | PORT_MASK_RMII);
    eth_switch.vlan_set_rate(1,                 // Rate control for VID = 1
        satcat5::eth::VRATE_10MBPS);
    eth_switch.vlan_set_rate(1,                 // Rate control for VID = 42
        satcat5::eth::VRATE_10MBPS);
    eth_switch.vlan_set_port(MAILMAP_MODE);     // Configure uBlaze port
    eth_switch.vlan_set_port(PMOD1_MODE);       // Configure PMOD ports 1-4
    eth_switch.vlan_set_port(PMOD2_MODE);
    eth_switch.vlan_set_port(PMOD3_MODE);
    eth_switch.vlan_set_port(PMOD4_MODE);
    eth_switch.vlan_set_port(RMII_ECHO_OFF);    // Configure RMII port
    ip_stack.m_eth.set_default_vid({1});        // Default outbound VID

    // Ping the specified IP-address every second?
    if (DEBUG_PING_HOST) {
         ip_stack.m_ping.ping(PING_TARGET);
    }

    // Set up the status LEDs.
    for (unsigned a = 0 ; a < LED_RGB_COUNT ; ++a)
        led_wave.add(led_rgb + a);
    for (unsigned a = 0 ; a < LED_AUX_COUNT ; ++a)
        led_activity.add(led_aux + a);
    led_wave.start();

    // Link timer callback to the SatCat5 polling service.
    timer.timer_callback(&satcat5::poll::timekeeper);

    // Enable interrupts.
    irq_satcat5.irq_start(XPAR_UBLAZE_MICROBLAZE_0_AXI_INTC_DEVICE_ID, &timer);

    // Startup message for the UART. Includes some UTF-8 emoji. :)
    {
        timer.busywait_usec(1000);
        Log(satcat5::log::INFO,
            "Welcome to SatCat5: "
            "\xf0\x9f\x9b\xb0\xef\xb8\x8f\xf0\x9f\x90\xb1\xf0\x9f\x95\x94\r\n\t"
            "Arty-Managed Demo, built ").write(satcat5::get_sw_build_string());
        eth_switch.log_info("Arty-Switch");
    }

    // Run the main polling loop forever.
    while (1) {
        satcat5::poll::service();
    }

    return 0;
}
