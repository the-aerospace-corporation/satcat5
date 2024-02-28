//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Microblaze software top-level for the "NetFPGA-Managed" example design

#include <hal_ublaze/interrupts.h>
#include <hal_ublaze/uartlite.h>
#include <satcat5/build_date.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_mdio.h>
#include <satcat5/cfgbus_led.h>
#include <satcat5/cfgbus_ptpref.h>
#include <satcat5/cfgbus_stats.h>
#include <satcat5/cfgbus_timer.h>
#include <satcat5/cfgbus_uart.h>
#include <satcat5/eth_chat.h>
#include <satcat5/ip_dhcp.h>
#include <satcat5/ip_stack.h>
#include <satcat5/log.h>
#include <satcat5/port_mailmap.h>
#include <satcat5/port_serial.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/switch_telemetry.h>
#include <satcat5/udp_tftp.h>
#include "netfpga_devices.h"

using satcat5::cfg::LedWave;
using satcat5::log::Log;
namespace ip = satcat5::ip;

// Enable diagnostic options?
#define DEBUG_DHCP_CLIENT   false
#define DEBUG_DHCP_SERVER   false
#define DEBUG_MAC_TABLE     true
#define DEBUG_PING_HOST     true
#define DEBUG_PORT_STATUS   false

// Global interrupt controller.
static XIntc irq_xilinx;
static satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);

// ConfigBus peripherals.
satcat5::cfg::ConfigBusMmap cfgbus((void*)XPAR_UBLAZE0_CFGBUS_HOST_AXI_0_BASEADDR,
        XPAR_UBLAZE0_MICROBLAZE_0_AXI_INTC_UBLAZE0_CFGBUS_HOST_AXI_0_IRQ_OUT_INTR);
satcat5::port::Mailmap      eth_port        (&cfgbus, DEVADDR_MAILMAP);
satcat5::cfg::Uart          uart_status     (&cfgbus, DEVADDR_SWSTATUS);
satcat5::port::SerialAuto   eth_pmod_ja     (&cfgbus, DEVADDR_PMOD_JA);
satcat5::port::SerialAuto   eth_pmod_jb     (&cfgbus, DEVADDR_PMOD_JB);
satcat5::cfg::Timer         timer           (&cfgbus, DEVADDR_TIMER);
satcat5::cfg::PtpReference  ptpref          (&cfgbus, DEVADDR_PTPREF);
satcat5::cfg::Mdio          eth_mdio        (&cfgbus, DEVADDR_MDIO);
satcat5::eth::SwitchConfig  eth_switch      (&cfgbus, DEVADDR_SWCORE);
satcat5::cfg::NetworkStats  traffic_stats   (&cfgbus, DEVADDR_TRAFFIC);

// Status LEDs generate a "wave" pattern.
static const u8 LED_BRT = 255;
satcat5::cfg::LedWaveCtrl led_wave;
LedWave led_status[] = {
    LedWave(&cfgbus, DEVADDR_LEDS, 0, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 1, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 2, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 3, LED_BRT),
};

constexpr unsigned LED_COUNT = sizeof(led_status) / sizeof(led_status[0]);

// UDP network stack
static constexpr satcat5::eth::MacAddr LOCAL_MAC
    = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};
static constexpr ip::Addr LOCAL_IP
    = DEBUG_DHCP_CLIENT ? ip::ADDR_NONE : ip::Addr(192, 168, 1, 42);
static constexpr ip::Addr PING_TARGET
    = DEBUG_PING_HOST ? ip::Addr(192, 168, 1, 1) : ip::ADDR_NONE;

ip::Stack ip_stack(LOCAL_MAC, LOCAL_IP, &eth_port, &eth_port, &timer);

// Read-only TFTP server sends a fixed message for any requested file.
// From an attached PC, run the command: "curl tftp://192.168.1.42/test.txt"
static constexpr char TFTP_MESSAGE[] =
    "SatCat5 is FPGA gateware that implements a low-power, mixed-media Ethernet switch.\n";
satcat5::io::ArrayRead tftp_source(TFTP_MESSAGE, sizeof(TFTP_MESSAGE)-1);
satcat5::udp::TftpServerSimple tftp_server(&ip_stack.m_udp, &tftp_source, 0);

// State-of-health telemetry for the switch status and traffic statistics.
satcat5::udp::Telemetry tlm(&ip_stack.m_udp, satcat5::udp::PORT_CBOR_TLM);
satcat5::eth::SwitchTelemetry tlm_sw(&tlm, &eth_switch, &traffic_stats);

// DHCP client is dormant if user sets a static IP.
ip::DhcpClient ip_dhcp(&ip_stack.m_udp);

// Optional DHCP server for range 192.168.1.64 to 192.168.1.95
// (Do not enable client and server simultaneously.)
#if DEBUG_DHCP_SERVER && !DEBUG_DHCP_CLIENT
    ip::DhcpPoolStatic<32> ip_dhcp_pool(ip::Addr(192, 168, 1, 64));
    ip::DhcpServer ip_dhcp_server(&ip_stack.m_udp, &ip_dhcp_pool);
#endif

// Connect logging system to the MDM's virtual UART
satcat5::ublaze::UartLite   uart_mdm("UART",
        XPAR_UBLAZE0_MICROBLAZE_0_AXI_INTC_UBLAZE0_MDM_1_INTERRUPT_INTR,
        XPAR_UBLAZE0_MDM_1_DEVICE_ID);
satcat5::log::ToWriteable   log_uart(&uart_mdm);

// Connect logging system to Ethernet (with carbon-copy to UART).
satcat5::eth::ChatProto     eth_chat(&ip_stack.m_eth, "NetFPGA");
satcat5::eth::LogToChat     log_chat(&eth_chat);

// TODO: Set up MDIO for each Realtek RTL8211 PHY.
// Note: Requires ~40 msec delay before attempting MDIO access.

// Timer object for general househeeping.
class HousekeepingTimer : satcat5::poll::Timer
{
public:
    HousekeepingTimer() : m_first(1) {
        // Set callback delay for first-time startup message.
        // (Need a little extra time for the Realtek PHYs to reset.)
        timer_once(1500);
    }

    void timer_event() override {
        // First-time setup?
        if (m_first) {
            m_first = false;    // Clear initial-setup flag.
            Log(LOG_INFO,       // Startup message (with emoji)
                "Welcome to SatCat5: " SATCAT5_WELCOME_EMOJI "\r\n\t"
                "NetFPGA-Managed Demo, built ").write(satcat5::get_sw_build_string());
            eth_switch.log_info("NetFPGA-Switch");
            timer_every(1000);  // After first time, poll once per second
            return;
        }
        // Optionally log the SatCat5 port status register.
        // (Refer to port_rmii and port_statistics for more info.)
        if (DEBUG_PORT_STATUS) {
            Log log(LOG_DEBUG, "Port status");
            for (unsigned a = 0 ; a < eth_switch.port_count() ; ++a) {
                log.write(traffic_stats.get_port(a).status);
            }
        }
    }

    bool m_first;
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
            eth_switch.mactbl_log("NetFPGA-Switch");
        }
    }
} slowkeeping;

// Main loop: Initialize and then poll forever.
int main()
{
    // VLAN setup for the managed Ethernet switch.
    eth_switch.vlan_reset();    // Reset in open mode

    // Ping the default gateway every second?
    if (DEBUG_PING_HOST) {
         ip_stack.m_ping.ping(PING_TARGET);
    }

    // Set up the status LEDs.
    for (unsigned a = 0 ; a < LED_COUNT ; ++a)
        led_wave.add(led_status + a);
    led_wave.start();

    // Link timer callback to the SatCat5 polling service.
    timer.timer_callback(&satcat5::poll::timekeeper);

    // Enable interrupts.
    irq_satcat5.irq_start(XPAR_UBLAZE0_MICROBLAZE_0_AXI_INTC_DEVICE_ID, &timer);

    // Run the main polling loop forever.
    while (1) {
        satcat5::poll::service();
    }

    return 0;
}
