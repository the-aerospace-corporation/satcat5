//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Microblaze software top-level for the "VC707 Managed" example design

#include <hal_devices/i2c_tca9548.h>
#include <hal_ublaze/interrupts.h>
#include <hal_ublaze/uartlite.h>
#include <satcat5/build_date.h>
#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_gpio.h>
#include <satcat5/cfgbus_mdio.h>
#include <satcat5/cfgbus_led.h>
#include <satcat5/cfgbus_ptpref.h>
#include <satcat5/cfgbus_stats.h>
#include <satcat5/cfgbus_text_lcd.h>
#include <satcat5/cfgbus_timer.h>
#include <satcat5/cfgbus_uart.h>
#include <satcat5/datetime.h>
#include <satcat5/eth_chat.h>
#include <satcat5/ip_dhcp.h>
#include <satcat5/ip_stack.h>
#include <satcat5/log.h>
#include <satcat5/port_mailmap.h>
#include <satcat5/port_serial.h>
#include <satcat5/ptp_client.h>
#include <satcat5/ptp_telemetry.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/switch_telemetry.h>
#include <satcat5/udp_tftp.h>
#include "vc707_devices.h"

using satcat5::cfg::LedActivity;
using satcat5::cfg::LedWave;
using satcat5::log::Log;
namespace ip = satcat5::ip;

// Enable diagnostic options?
#define DEBUG_DHCP_CLIENT   false
#define DEBUG_EAVESDROP     true
#define DEBUG_MAC_TABLE     false
#define DEBUG_MDIO_REG      false
#define DEBUG_PING_HOST     true
#define DEBUG_PORT_STATUS   false
#define DEBUG_PTP_FREERUN   false
#define DEBUG_SFP_STATUS    false

// Set PTP filter configuration:
//	0 = Linear regression (LR) control
//  1 = Proportional-integral (PI) control
//  2 = Proportional-double-integral (PII) control
#define PTP_CONTROL_MODE    2
#define PTP_TAU_SECONDS     3.0

// Global interrupt controller.
static XIntc irq_xilinx;
static satcat5::irq::ControllerMicroblaze irq_satcat5(&irq_xilinx);

// ConfigBus peripherals.
satcat5::cfg::ConfigBusMmap cfgbus((void*)XPAR_UBLAZE0_CFGBUS_HOST_AXI_0_BASEADDR,
        XPAR_UBLAZE0_MICROBLAZE_0_AXI_INTC_UBLAZE0_CFGBUS_HOST_AXI_0_IRQ_OUT_INTR);
satcat5::port::Mailmap      eth_port        (&cfgbus, DEVADDR_MAILMAP);
satcat5::port::SerialUart   eth_uart        (&cfgbus, DEVADDR_ETH_UART);
satcat5::eth::SwitchConfig  eth_switch      (&cfgbus, DEVADDR_SWCORE);
satcat5::cfg::NetworkStats  traffic_stats   (&cfgbus, DEVADDR_TRAFFIC);
satcat5::cfg::I2c           i2c_sfp         (&cfgbus, DEVADDR_I2C_SFP);
satcat5::cfg::Mdio          eth_mdio        (&cfgbus, DEVADDR_MDIO);
satcat5::cfg::Timer         timer           (&cfgbus, DEVADDR_TIMER);
satcat5::cfg::Uart          uart_status     (&cfgbus, DEVADDR_SWSTATUS);
satcat5::cfg::TextLcd       text_lcd        (&cfgbus, DEVADDR_TEXTLCD);
satcat5::cfg::GpiRegister   dip_sw          (&cfgbus, DEVADDR_DIP_SW, 0);
satcat5::cfg::PtpRealtime   ptp_clock       (&cfgbus, DEVADDR_MAILMAP, 1012);
satcat5::cfg::GpoRegister   synth_offset    (&cfgbus, DEVADDR_SYNTH, 0);

// Driver for the PCA9548A multiplexer, required for SFP setup.
satcat5::device::i2c::Tca9548 i2c_mux(&i2c_sfp, I2C_ADDR_MUX);

// Status LEDs generate a "wave" pattern.
static const u8 LED_BRT = 255;
satcat5::cfg::LedWaveCtrl led_wave;
LedWave led_status[] = {
    LedWave(&cfgbus, DEVADDR_LEDS, 0, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 1, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 2, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 3, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 4, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 5, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 6, LED_BRT),
    LedWave(&cfgbus, DEVADDR_LEDS, 7, LED_BRT),
};

constexpr unsigned LED_COUNT = sizeof(led_status) / sizeof(led_status[0]);

// UDP network stack
ip::Stack ip_stack(
        satcat5::eth::MACADDR_NONE, ip::ADDR_NONE,
        &eth_port, &eth_port, &timer);

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

// Link PTP client to the network stack.
satcat5::ptp::Client ptp_client(&eth_port, &ip_stack.m_ip);
satcat5::ptp::SyncUnicastL3 ptp_unicast(&ptp_client);
satcat5::ptp::TrackingController trk_ctrl(
    &timer, DEBUG_PTP_FREERUN ? 0 : &ptp_clock, &ptp_client);
satcat5::ptp::Logger ptp_log(&ptp_client, &ptp_clock);
satcat5::ptp::Telemetry ptp_telem(&ptp_client, &ip_stack.m_udp, &ptp_clock);

// Create filters used for feedback control in various modes, including
// both linear-regression (LR) and proportional-integral (PI) controllers.
satcat5::ptp::AmplitudeReject trk_ampl;
satcat5::ptp::CoeffLR trk_coeff_lr(
    satcat5::cfg::ptpref_scale(125000000.0), PTP_TAU_SECONDS);
satcat5::ptp::CoeffPI trk_coeff_pi(
    satcat5::cfg::ptpref_scale(125000000.0), PTP_TAU_SECONDS);
satcat5::ptp::CoeffPII trk_coeff_pii(
    satcat5::cfg::ptpref_scale(125000000.0), PTP_TAU_SECONDS);
satcat5::ptp::ControllerLR<16> trk_ctrl_lr(trk_coeff_lr);
satcat5::ptp::ControllerPI trk_ctrl_pi(trk_coeff_pi);
satcat5::ptp::ControllerPII trk_ctrl_pii(trk_coeff_pii);
satcat5::ptp::MedianFilter<7> trk_median;
satcat5::ptp::BoxcarFilter<4> trk_prebox;
satcat5::ptp::BoxcarFilter<4> trk_postbox;

// Connect logging system to the MDM's virtual UART
satcat5::ublaze::UartLite   uart_mdm("UART",
        XPAR_UBLAZE0_MICROBLAZE_0_AXI_INTC_UBLAZE0_MDM_1_INTERRUPT_INTR,
        XPAR_UBLAZE0_MDM_1_DEVICE_ID);
satcat5::log::ToWriteable   log_uart(&uart_mdm);

// Connect logging system to Ethernet (with carbon-copy to LCD and UART).
satcat5::eth::ChatProto     eth_chat(&ip_stack.m_eth, "VC707");
satcat5::eth::LogToChat     log_chat(&eth_chat);
satcat5::cfg::LogToLcd      log_lcd(&text_lcd);

// Set up MDIO for Marvell M88E1111 PHY.
satcat5::cfg::MdioMarvell   eth_phy(&eth_mdio, RJ45_PHYADDR);

// Timer object for general housekeeping.
class HousekeepingTimer
    : public satcat5::poll::Timer
    , public satcat5::cfg::I2cEventListener
{
public:
    HousekeepingTimer() : m_cycle(0), m_phase(0) {
        // Set callback delay for first setup phase.
        timer_once(10);
    }

    inline bool sfp_write(u8 reg, u8 data)
        {return i2c_mux.write(I2C_ADDR_SFP, 1, reg, 1, &data, 0);}

    // Dispatch each timer event based on step counter...
    void timer_event() override {
        switch (m_phase) {
        case 0: setup0(); break;
        case 1: setup1(); break;
        default: every_second();
        }
    }

    // Some hardware requires a short delay before setup.
    // (e.g., It may still be held in reset during main().)
    void setup0() {
        // Set up the SFP interface.
        i2c_mux.select_channel(I2C_CH_SFP);
        sfp_write(86, 0x00);     // Enable transmit
        sfp_write(93, 0x05);     // Allow modules > 3.5W
        sfp_write(98, 0x00);     // Disable CDR
        // Delay to next phase.
        ++m_phase; timer_once(1500);
    }

    // After a little longer, send the welcome announcement.
    // (Need a little extra time for the RJ45 PHY to reset.)
    void setup1() {
        // Send the welcome message and a configuration overview.
        Log(LOG_INFO, "Welcome to SatCat5: " SATCAT5_WELCOME_EMOJI)
            .write("\r\n\tVC707-PTP-Client Demo, built ")
            .write(satcat5::get_sw_build_string())
            .write("\r\n\tClient type: ")
            .write((dip_sw.read() & GPIO_DIP_MASTER) ? "Master" : "Slave")
            .write("\r\n\tClock source: ")
            .write((dip_sw.read() & GPIO_EXT_SELECT) ? "External" : "Internal");
        eth_switch.log_info("VC707-Switch");
        // Warning for certain anomalous conditions.
        if (i2c_mux.busy()) Log(LOG_WARNING, "I2C is stuck.");
        // Delay to next phase.
        ++m_phase; timer_once(1000);
    }

    // After setup, this method is called at one-second intervals.
    void every_second() {
        // Optionally log key registers from the Ethernet PHY.
        if (DEBUG_MDIO_REG) {
            eth_phy.read(0x00, &m_logger);  // BMCR
            eth_phy.read(0x01, &m_logger);  // BMSR
            eth_phy.read(0x10, &m_logger);  // PHYSTS
        }
        // Optionally log the SatCat5 port status register.
        // (Refer to port_rmii and port_statistics for more info.)
        if (DEBUG_PORT_STATUS) {
            u32 status1 = traffic_stats.get_port(PORT_IDX_ETH_RJ45).status;
            u32 status2 = traffic_stats.get_port(PORT_IDX_ETH_SFP).status;
            u32 status3 = traffic_stats.get_port(PORT_IDX_ETH_SMA).status;
            Log(LOG_DEBUG, "Port status").write(status1).write(status2).write(status3);
        }
        // Optionally poll the SFP status registers, 16 bytes at a time.
        if (DEBUG_SFP_STATUS) {
            i2c_mux.read(I2C_ADDR_SFP, 1, 16 * (m_cycle % 4), 16, this);
        }
        // Repeat this callback once per second.
        ++m_cycle; timer_every(1000);
    }

    void i2c_done(bool noack,
        const satcat5::util::I2cAddr& devaddr,
        u32 regaddr, unsigned nread, const u8* rdata) override {
        if (noack) {
            Log(LOG_DEBUG, "SFP Status: No response.");
        } else {
            Log(LOG_DEBUG, "SFP Status").write((u8)regaddr).write(rdata, nread);
        }
    }

    u32 m_cycle;
    u32 m_phase;
    satcat5::cfg::MdioLogger m_logger;
} housekeeping;

// A faster timer object for dealing with GPIO buttons.
// These are used to control the time-offset of the synthesized outputs.
class FastHousekeepingTimer : satcat5::poll::Timer
{
public:
    // Default one press = 1 nanosecond (2^16 LSB).
    static constexpr u32 DEFAULT_SCALE = 16;

    FastHousekeepingTimer() : m_scale(DEFAULT_SCALE), m_curr(0), m_prev(0) {
        // Moderate poll rate ensures fast response without double-counting due to switch bounce.
        timer_every(5);
    }

    bool key_down(u32 mask) const {
        // Detect rising-edge transitions in the designated bit.
        return (m_curr & mask) && !(m_prev & mask);
    }

    int rotary_decode() const {
        // Decode changes to the EVQ-WK4001 incremental encoder:
        // https://en.wikipedia.org/wiki/Incremental_encoder
        u32 diff0 = m_curr ^ m_prev;
        u32 diff1 = ((m_curr & GPIO_ROTR_INCA) ? 1 : 0)
                  ^ ((m_curr & GPIO_ROTR_INCB) ? 1 : 0);
        if (diff0 & GPIO_ROTR_INCA) {
            return diff1 ? +1 : -1;         // Change on A
        } else if (diff0 & GPIO_ROTR_INCB) {
            return diff1 ? -1 : +1;         // Change on B
        } else {
            return 0;                       // No change
        }
    }

    void timer_event() override {
        // Read the new state of the buttons.
        m_prev = m_curr;
        m_curr = dip_sw.read();
        // Respond to buttons as they are pressed.
        if (key_down(GPIO_BTN_NORTH)) {     // Scale up
            if (m_scale < 30) ++m_scale;
        }
        if (key_down(GPIO_BTN_SOUTH)) {     // Scale down
            if (m_scale > 0) --m_scale;
        }
        if (key_down(GPIO_BTN_WEST)) {      // Offset increment
            synth_offset.write(synth_offset.read() + (1u << m_scale));
        }
        if (key_down(GPIO_BTN_EAST)) {      // Offset decrement
            synth_offset.write(synth_offset.read() - (1u << m_scale));
        }
        if (key_down(GPIO_BTN_CENTER) || key_down(GPIO_ROTR_PUSH)) {
            synth_offset.write(0);
            m_scale = DEFAULT_SCALE;
        }
        // Respond to the jog wheel.
        int diff = rotary_decode();
        if (diff > 0) {
            synth_offset.write(synth_offset.read() + (1u << m_scale));
        } else if (diff < 0) {
            synth_offset.write(synth_offset.read() - (1u << m_scale));
        }
    }

    u32 m_scale, m_curr, m_prev;
} fastkeeping;


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
            eth_switch.mactbl_log("VC707-Switch");
        }
    }
} slowkeeping;

// Main loop: Initialize and then poll forever.
int main()
{
    // VLAN setup for the managed Ethernet switch.
    eth_switch.vlan_reset();    // Reset in open mode
    if (DEBUG_EAVESDROP) {      // Carbon-copy all messages to host PC?
        eth_switch.set_promiscuous(PORT_IDX_ETH_RJ45, true);
    }

    // Set the initial state of the PTP client.
    if (dip_sw.read() & GPIO_DIP_MASTER) {
        // PTP Master = 192.168.3.* subnet
        const s64 DEFAULT_TIME = satcat5::datetime::from_gps(
            satcat5::datetime::GpsTime({1042, 519418})); // Y2K
        ptp_clock.clock_set(satcat5::datetime::to_ptp(DEFAULT_TIME));
        ip_stack.set_macaddr({0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x01});
        if (!DEBUG_DHCP_CLIENT) {
            ip_stack.set_addr(ip::Addr(192, 168, 3, 42));
            ip_stack.m_ip.route_default(ip_stack.ipaddr());
        }
        if (DEBUG_PING_HOST)
            ip_stack.m_ping.ping(ip::Addr(192, 168, 3, 1));
        ptp_client.set_mode(satcat5::ptp::ClientMode::MASTER_L2);
        ptp_client.set_sync_rate(4); // 2^N broadcast/sec
        ptp_client.set_clock(satcat5::ptp::VERY_GOOD_CLOCK);
        ptp_unicast.connect(ip::Addr(192, 168, 4, 42));
        ptp_unicast.timer_every(2); // Unicast every N msec
    } else {
        // PTP Slave = 192.168.4.* subnet
        ip_stack.set_macaddr({0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0x00});
        if (!DEBUG_DHCP_CLIENT) {
            ip_stack.set_addr(ip::Addr(192, 168, 4, 42));
            ip_stack.m_ip.route_default(ip_stack.ipaddr());
        }
        if (DEBUG_PING_HOST)
            ip_stack.m_ping.ping(ip::Addr(192, 168, 4, 1));
        ptp_client.set_mode(satcat5::ptp::ClientMode::SLAVE_ONLY);
        if (PTP_CONTROL_MODE == 0) {
            // PTP control in linear regression mode.
            trk_ctrl.add_filter(&trk_ampl);
            trk_ctrl.add_filter(&trk_ctrl_lr);
        } else if (PTP_CONTROL_MODE == 1) {
            // PTP control in proportional-integral mode.
            trk_ctrl.add_filter(&trk_ampl);
            trk_ctrl.add_filter(&trk_ctrl_pi);
            trk_ctrl.add_filter(&trk_postbox);
        } else {
            // PTP control in proportional-double-integral mode.
            trk_ctrl.add_filter(&trk_ampl);
            trk_ctrl.add_filter(&trk_ctrl_pii);
            trk_ctrl.add_filter(&trk_postbox);
        }
    }

    // Additional PTP telemetry?
    ptp_telem.connect(ip::ADDR_BROADCAST);
    ptp_telem.set_level(1);

    // Set up the status LEDs.
    for (unsigned a = 0 ; a < LED_COUNT ; ++a)
        led_wave.add(led_status + a);
    led_wave.start();

    // Override flow control signals on the UART port.
    eth_uart.config_uart(921600, true);

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
