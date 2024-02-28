//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Console demo for remote control of the "arty_managed" OLED
//
// The application opens the designated UART interface, then begins sending
// a repeating sequence of updates to the OLED display.
//

#include <clocale>
#include <cstdio>
#include <ctime>
#include <iostream>
#include <string>
#include <hal_devices/i2c_ssd1306.h>
#include <hal_posix/posix_uart.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/cfgbus_i2c.h>
#include <satcat5/cfgbus_remote.h>

using namespace satcat5;

// Global background services.
log::ToConsole logger;          // Print Log messages to console
util::PosixTimekeeper timer;    // Link system time to internal timers

// MAC addresses for the Ethernet-over-UART interface.
eth::MacAddr LOCAL_MAC  = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC};
eth::MacAddr REMOTE_MAC = {0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE};

// ConfigBus address for the I2C controller:
const unsigned DEVADDR_I2C = 10;

// Configuration of ZCU208 design.
class ArtyDemo final : public poll::Timer
{
public:
    explicit ArtyDemo(cfg::ConfigBus* cfg)
        : m_cycle(0)
        , m_cfg(cfg)
        , m_i2c(cfg, DEVADDR_I2C)
        , m_oled(&m_i2c)
    {
        // Disable interrupts to avoid disrupting the Microblaze CPU.
        // (Since it doesn't know we're remote-controlling this interface.)
        m_i2c.irq_disable();

        // Update screen once per second.
        timer_every(1000);
    }

    // Connectivity test
    bool ok()
    {
        u32 rdval;
        unsigned regaddr = m_cfg->get_regaddr(DEVADDR_I2C, 0);
        return m_cfg->read(regaddr, rdval) == cfg::IOSTATUS_OK;
    }

    // Service loop including simulated interrupt.
    void service()
    {
        m_i2c.request_poll();
        poll::service_all();
    }

private:
    // Timer event handler.
    void timer_event() override {
        // Buffer = 16x2 characters + NULL termination
        char day[11], now[9], msg[33];

        // Format the current time.
        time_t rawtime;
        struct tm* timeinfo;
        time(&rawtime);
        timeinfo = localtime(&rawtime);
        strftime(day, sizeof(day), "%Y-%m-%d", timeinfo);
        strftime(now, sizeof(now), "%H:%M:%S", timeinfo);

        // Generate the complete message...
        switch (m_cycle) {
            case 0:
                snprintf(msg, sizeof(msg), "Time: %9s Date: %s", now, day);
                break;
            case 1:
                snprintf(msg, sizeof(msg), "Time: %9s SatCat5 demo!", now);
                break;
            case 2:
                snprintf(msg, sizeof(msg), "Time: %9s Meow meow meow.", now);
                break;
        }

        // Update message index and write to screen.
        if (m_oled.display(msg)) {
            m_cycle = (m_cycle + 1) % 3;
            std::cout << msg << std::endl;
        }
    }

    // Counter cycles between various messages.
    unsigned m_cycle;

    // Remotely-controlled ConfigBus peripherals.
    cfg::ConfigBus* const m_cfg;
    cfg::I2c m_i2c;
    device::i2c::Ssd1306 m_oled;
};

void oled_demo(io::SlipUart* uart)
{
    // Open remote-control interface.
    auto dispatch = new eth::Dispatch(LOCAL_MAC, uart, uart);
    auto cfgbus = new eth::ConfigBus(dispatch, timer.timer());
    cfgbus->connect(REMOTE_MAC);
    cfgbus->set_timeout_rd(200000);

    // Attach the OLED driver.
    auto oled = new ArtyDemo(cfgbus);

    // Poll until communications fail or user hits Ctrl+C.
    poll::service_all();
    while (oled->ok()) {
        util::sleep_msec(10);
        oled->service();
    }

    delete oled;
    delete cfgbus;
    delete dispatch;
}

int main(int argc, const char* argv[])
{
    // Set console mode for UTF-8 support.
    setlocale(LC_ALL, SATCAT5_WIN32 ? ".UTF8" : "");

    // Parse command-line arguments.
    std::string ifname;
    unsigned baud = 921600;
    if (argc == 3) {
        ifname = argv[1];       // UART device
        baud = atoi(argv[2]);   // Baud rate
    } else if (argc == 2) {
        ifname = argv[1];       // UART device
    }

    // Print the usage prompt?
    if (argc > 3 || ifname == "" || ifname == "help" || ifname == "--help") {
        std::cout << "oled_demo uses arty_managed to control an OLED screen." << std::endl
            << "Usage: oled_demo.bin <ifname>" << std::endl
            << "       oled_demo.bin <ifname> <baud>" << std::endl
            << "Where 'ifname' is the USB-UART attached to the arty_managed FPGA." << std::endl;
        return 0;
    }

    // Open the specified UART interface.
    io::SlipUart* uart = new io::SlipUart(ifname.c_str(), baud);

    // Interface ready?
    if (uart && uart->ok()) {
        std::cout << "Starting oled_demo on " << ifname << std::endl;
        oled_demo(uart);
        return 0;
    } else {
        std::cerr << "Couldn't open UART interface: " << ifname << std::endl;
        return 1;
    }
}
