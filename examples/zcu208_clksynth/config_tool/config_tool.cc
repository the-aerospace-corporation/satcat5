//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Console application for configuring the "zcu208_clksynth" example design
//
// The application opens the designated UART interface, then prompts the user
// to configure the DAC reference clock or make output phase adjumtments.
//

#include <clocale>
#include <iomanip>
#include <iostream>
#include <string>
#include <hal_devices/pll_clk104.h>
#include <hal_posix/posix_uart.h>
#include <hal_posix/posix_utils.h>
#include <satcat5/cfgbus_gpio.h>
#include <satcat5/cfgbus_i2c.h>
#include <satcat5/cfgbus_ptpref.h>
#include <satcat5/cfgbus_remote.h>
#include <satcat5/ip_stack.h>
#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tracking.h>

using namespace satcat5;

// Global verbosity level for diagnostic logs.
unsigned verbosity = 1;

// Global background services.
log::ToConsole logger;          // Print Log messages to console
util::PosixTimekeeper timer;    // Link system time to internal timers

// MAC and IP address for the Ethernet-over-UART interface.
eth::MacAddr LOCAL_MAC  = {0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC};
eth::MacAddr REMOTE_MAC = {0x5A, 0x5A, 0xDE, 0xAD, 0xBE, 0xEF};

// ConfigBus addresses from "zcu208_clksynth.vhd"
const unsigned DEV_RFDAC    = 1;    // AXI map for Xilinx IP
const unsigned DEV_I2C      = 2;    // I2C interface to CLK104
const unsigned DEV_OTHER    = 3;    // Individual registers
const unsigned REG_IDENT    = 0;    // Read-only identifier
const unsigned REG_SPIMUX   = 1;    // Control CLK104 SPI MUX
const unsigned REG_VPLL     = 2;    // VPLL offset
const unsigned REG_LEDMODE  = 3;    // Status LED mode
const unsigned REG_RESET    = 4;    // Software reset flags
const unsigned REG_VLOCK    = 5;    // VPLL lock/unlock counter
const unsigned REG_VREF     = 6;    // VREF fine adjustment
const unsigned REG_VCMP     = 7;    // VREF phase reporting

// Bit-mask for the REG_RESET register.
const u32 RESET_DAC = (1u << 0);

// Scaling for the phase-shift register.
const s32 ONE_NSEC = (1u << 16);

// Polling rate for util::poll_msec.
const unsigned POLL_MSEC = 10;

// Set control parameters for phase-locking the reference.
// Note: Each LSB of the slew rate is about 0.01 ps/sec
const unsigned PHASE_LOCK_SLEW  = 512;  // Slew-rate (bang-bang mode)
const double PHASE_LOCK_TAU     = 2.0;  // Time-constant (linear mode)
const double PHASE_LOCK_SCALE   = cfg::ptpref_scale(10e6);

inline ptp::CoeffPI trk_coeff(double tau)
    { return ptp::CoeffPI(PHASE_LOCK_SCALE, tau); }

// Configuration of ZCU208 design.
class Zcu208 final
{
public:
    Zcu208(cfg::ConfigBus* cfg)
        : m_i2c(cfg, DEV_I2C)
        , m_ident(cfg, DEV_OTHER, REG_IDENT)
        , m_spimux(cfg, DEV_OTHER, REG_SPIMUX)
        , m_vphase(cfg, DEV_OTHER, REG_VPLL)
        , m_ledmode(cfg, DEV_OTHER, REG_LEDMODE)
        , m_reset(cfg, DEV_OTHER, REG_RESET)
        , m_vlock(cfg, DEV_OTHER, REG_VLOCK)
        , m_vref(cfg, DEV_OTHER, REG_VREF)
        , m_vcmp(cfg, DEV_OTHER, REG_VCMP)
        , m_clk104(&m_i2c, &m_spimux)
        , m_coeff(trk_coeff(PHASE_LOCK_TAU))
        , m_ctrl(m_coeff)
        , m_track(timer.timer(), &m_vref, 0)
    {
        m_track.add_filter(&m_ctrl);
        m_vref.clock_rate(0);
    }

    // Use the IDENT register as a connectivity test.
    bool ok() {
        return m_ident.read() == 0x5A323038;
    }

    // Configure the CLK104 (may take several seconds).
    // Set "ref_hz" to use an external reference, or zero for internal VCXO.
    bool configure(unsigned ref_hz = 0) {
        // Reset DAC while we configure its clock.
        m_reset.write(RESET_DAC);

        // Set configuration parameters.
        if (ref_hz) {   // External clock? (INPUT_REF)
            m_clk104.configure(m_clk104.REF_EXT, ref_hz, verbosity > 1);
        } else {        // 10 MHz built-in TCXO
            m_clk104.configure(m_clk104.REF_TCXO, 10000000, verbosity > 1);
        }

        // Wait for configuration to complete (or timeout).
        wait_for_clk104();

        // After a short delay, release DAC from reset.
        // TODO: Why isn't this working? Need to manually press CPU_RESET.
        util::service_msec(50, POLL_MSEC);
        m_reset.write(0);

        // Rapid slew to the expected clock phase.
        phase_slew(false);

        return m_clk104.ready();
    }

    // Idle loop closes the loop on the vernier reference counter.
    // (This prevents ~1 ps/sec drift in the final output phase.)
    // Returns true if user should reset the coarse alignment.
    bool idle_loop(unsigned duration_msec, unsigned slew_rate) {
        u32 err_count = 0;
        u32 usec = duration_msec * 1000;
        u32 tref = timer.timer()->now();
        while (1) {
            if (slew_adjust(slew_rate)) ++err_count;
            util::service_msec(POLL_MSEC, POLL_MSEC);
            if (timer.timer()->elapsed_test(tref, usec)) break;
        }
        return err_count > 0;
    }

    // Set LED mode:
    //  0 = Clock and reset (default)
    //  1 = VPLL diagnostics
    //  2 = DAC2 time counter
    //  3 = DAC3 time counter
    //  4 = VAUX diagnostics
    void led_mode(u32 mode) {
        m_ledmode.write(mode);
    }

    // Update VPLL time offset to adjust synth output phase.
    // Units are in sub-nanoseconds (i.e., 1 LSB = 1/65536 nsec)
    void phase_set(s32 phase) {
        m_vphase.write((u32)phase);
    }
    void phase_incr(s32 delta) {
        s32 phase = (s32)m_vphase.read();
        m_vphase.write((u32)(phase + delta));
    }

    // Set time-constant for linear-mode phase-tracking.
    void phase_lock_tau(double tau) {
        m_coeff = trk_coeff(tau);
        m_ctrl.set_coeff(m_coeff);
    }

    // Rapid slew to the expected clock phase.
    void phase_slew(bool slew_mode) {
        if (slew_mode) {
            // Bang-bang control mode: Operate the control loop with
            // a very coarse slew rate, then get progressively finer.
            std::cout << "VREF slew starting..." << std::endl;
            idle_loop(800, 2000000);
            idle_loop(200, 500000);
            idle_loop(200, 125000);
            idle_loop(200, 33000);
            idle_loop(200, 10000);
            idle_loop(200, 3300);
            idle_loop(200, 1000);
            std::cout << "VREF slew completed." << std::endl;
        } else {
            // Linear control mode: Temporarily increase loop bandwidth.
            std::cout << "VREF fast-track starting..." << std::endl;
            m_ctrl.set_coeff(trk_coeff(1.0));
            m_track.reset();
            idle_loop(2000, 0);
            m_ctrl.set_coeff(m_coeff);
            std::cout << "VREF fast-track completed." << std::endl;
        }
    }

    // Report lock/unlock events since the last query.
    void vlock_report() {
        u32 vlock = m_vlock.read();
        u16 vrise = (u16)(vlock >> 16);
        u16 vfall = (u16)(vlock >> 0);
        std::cout << "VPLL events: lock " << vrise
                  << ", unlock " << vfall << std::endl;
    }

private:
    // Rate adjustment for the vernier reference.
    // Returns true if error exceeds normal operating tolerances.
    // Note: Cannot use a timer because of ConfigBusRemote conflicts.
    bool slew_adjust(s64 slew) {
        // Calculate difference from ideal phase, modulo 8 nsec.
        const u32 MASK = u32(8 * ONE_NSEC - 1);  // e.g., 0x7FFFF
        s32 diff_subns = (s32)(m_vcmp.read() & MASK) - MASK/2;

        // Choose control mode...
        if (slew) {
            // Bang-bang control loop with a constant slew rate.
            // (Normal operating rate is only ~2 ps/sec, so this is fine.)
            if (diff_subns > 0) {
                m_vref.clock_rate(+slew);
            } else {
                m_vref.clock_rate(-slew);
            }
        } else {
            // Update the linear 2nd-order control loop.
            m_track.update(ptp::Time(diff_subns));
        }

        // Optional diagnostic output.
        if (verbosity > 1) {
            std::cout << "VREF Diff = " << std::setw(8) << diff_subns
                      << ", Rate = " << std::setw(8) << m_vref.get_rate()
                      << std::endl;
        }

        // A large error indicates we are not locked.
        return abs(diff_subns) > 100000;
    }

    // Poll CLK104 driver until it is finished or stuck.
    bool wait_for_clk104() {
        u32 tref = timer.timer()->now();
        unsigned percent_done = 0;
        // Poll until finished or timeout.
        while (m_clk104.busy()) {
            // Any visible progress?
            unsigned elapsed_msec = timer.timer()->elapsed_usec(tref) / 1000;
            if (percent_done != m_clk104.progress()) {
                // Progress resets the timeout interval.
                tref = timer.timer()->now();
                percent_done = m_clk104.progress();
                // Print update? (Note: Redundant with raw status if verbosity > 1.)
                if (verbosity == 1) {
                    std::cout << "Progress " << percent_done << "%..." << std::endl;
                }
            } else if (elapsed_msec > 4000) {
                std::cout << "Configuration timeout." << std::endl;
                return false;
            }
            // Keep polling the main service loop.
            poll::service_all();
            util::sleep_msec(1);
        }
        return true;
    }

    // Remotely-controlled ConfigBus peripherals.
    cfg::I2c m_i2c;
    cfg::GpiRegister m_ident;
    cfg::GpoRegister m_spimux;
    cfg::GpoRegister m_vphase;
    cfg::GpoRegister m_ledmode;
    cfg::GpoRegister m_reset;
    cfg::GpiRegister m_vlock;
    cfg::PtpReference m_vref;
    cfg::GpiRegister m_vcmp;

    // Driver for the CLK104 board.
    device::pll::Clk104 m_clk104;

    // Linear-mode offset tracking.
    ptp::CoeffPI m_coeff;
    ptp::ControllerPI m_ctrl;
    ptp::TrackingController m_track;
};

// Interactive menu for controlling the ZCU208.
class ConfigMenu final {
public:
    ConfigMenu(Zcu208* board)
        : m_key_rcvd()
        , m_key_stream(&m_key_rcvd, false)
        , m_auto_slew(true)
        , m_slew_mode(0)
        , m_board(board)
    {
        // Nothing else to initialize.
    }

    void help() {
        std::cout << "Main menu:" << std::endl
            << "  ?     To print this help menu." << std::endl
            << "  q     To exit the program." << std::endl
            << "  \\     To perform initial setup." << std::endl
            << "  `     To cycle verbosity level (0/1/2)." << std::endl
            << "  1-5   To select LED mode." << std::endl
            << "  v     To report VPLL lock/unlock counts." << std::endl
            << "  b     To recenter the VREF output phase." << std::endl
            << "  r     To toggle automatic recentering." << std::endl
            << "  t     To toggle automatic tracking mode." << std::endl
            << "  w     To adjust tracking time-constant." << std::endl
            << "  J     To shift output phase left 1000 ps." << std::endl
            << "  j     To shift output phase left 100 ps." << std::endl
            << "  k     To shift output phase left 10 ps." << std::endl
            << "  K     To shift output phase left 1 ps." << std::endl
            << "  L     To shift output phase right 1 ps." << std::endl
            << "  l     To shift output phase right 10 ps." << std::endl
            << "  ;     To shift output phase right 100 ps." << std::endl
            << "  :     To shift output phase right 1000 ps." << std::endl;
    }

    bool next_action() {
        char key = next_key();
        if (key == '?') {
            help();
        } else if (key == 'q' || key == 'Q') {
            std::cout << "Quitting..." << std::endl;
            return false;
        } else if (key == '\\') {
            std::cout << "Clock setup (internal)..." << std::endl;
            m_board->configure(0);
        } else if (key == '`') {
            verbosity = (verbosity + 1) % 3;
            std::cout << "Verbosity = " << verbosity << std::endl;
        } else if (key == '|') {
            unsigned ref_hz = prompt("External reference (Hz)?");
            if (ref_hz) {
                std::cout << "Clock setup (external)..." << std::endl;
                m_board->configure(ref_hz);
            } else {
                std::cout << "Clock setup cancelled." << std::endl;
            }
        } else if (key == '1') {
            std::cout << "LED mode: Clocks" << std::endl;
            m_board->led_mode(0);
        } else if (key == '2') {
            std::cout << "LED mode: VPLL status" << std::endl;
            m_board->led_mode(1);
        } else if (key == '3') {
            std::cout << "LED mode: Counter-VPLL" << std::endl;
            m_board->led_mode(2);
        } else if (key == '4') {
            std::cout << "LED mode: Counter-Free" << std::endl;
            m_board->led_mode(3);
        } else if (key == '5') {
            std::cout << "LED mode: VAUX status" << std::endl;
            m_board->led_mode(4);
        } else if (key == 'v' || key == 'V') {
            m_board->vlock_report();
        } else if (key == 'b' || key == 'B') {
            m_board->phase_slew(m_slew_mode);
        } else if (key == 'r' || key == 'R') {
            m_auto_slew = !m_auto_slew;
            const char* status = m_auto_slew ? "On" : "Off";
            std::cout << "Auto-slew: " << status << std::endl;
        } else if (key == 't' || key == 'T') {
            m_slew_mode = !m_slew_mode;
            const char* status = m_slew_mode ? "Bang-bang" : "Linear";
            std::cout << "Tracking mode: " << status << std::endl;
        } else if (key == 'w' || key == 'W') {
            unsigned tau = prompt("Tracking time-constant (sec)");
            m_board->phase_lock_tau(double(tau));
        } else if (key == 'J') {
            m_board->phase_incr(ONE_NSEC);
        } else if (key == 'j') {
            m_board->phase_incr(ONE_NSEC / 10);
        } else if (key == 'k') {
            m_board->phase_incr(ONE_NSEC / 100);
        } else if (key == 'K') {
            m_board->phase_incr(ONE_NSEC / 1000);
        } else if (key == 'L') {
            m_board->phase_incr(-ONE_NSEC / 1000);
        } else if (key == 'l') {
            m_board->phase_incr(-ONE_NSEC / 100);
        } else if (key == ';') {
            m_board->phase_incr(-ONE_NSEC / 10);
        } else if (key == ':') {
            m_board->phase_incr(-ONE_NSEC);
        }
        return true;
    }

    char next_key() {
        // Flush buffer contents.
        poll::service_all();
        m_key_rcvd.clear();

        // Prompt and wait for keypress.
        std::cout << "Command? (? = help)" << std::endl;
        while (!m_key_rcvd.get_read_ready()) {
            unsigned slew_mode = m_slew_mode ? PHASE_LOCK_SLEW : 0;
            if (m_board->idle_loop(50, slew_mode) && m_auto_slew) {
                std::cout << "Automatic recentering..." << std::endl;
                m_board->phase_slew(m_slew_mode);
            }
        }
        return (char)(m_key_rcvd.read_u8());
    }

    unsigned prompt(const char* label) {
        // Prompt user using normal cout/cin functions.
        unsigned value = 0;
        std::cout << label << std::endl;
        std::cin >> value;
        return value;
    }

private:
    io::PacketBufferHeap m_key_rcvd;
    io::KeyboardStream m_key_stream;
    bool m_auto_slew;
    bool m_slew_mode;
    Zcu208* m_board;
};

void config_tool(cfg::ConfigBus* cfg)
{
    // Create remote-control interface for the example design.
    Zcu208 board(cfg);
    if (!board.ok()) {
        std::cout << "No reply from ZCU208." << std::endl;
        return;
    }

    // Keyboard interface for menu prompts.
    ConfigMenu menu(&board);
    menu.help();

    // Execute menu actions until user selects "quit".
    while (menu.next_action()) {}
}

int main(int argc, const char* argv[])
{
    // Set console mode for UTF-8 support.
    setlocale(LC_ALL, SATCAT5_WIN32 ? ".UTF8" : "");

    // Parse command-line arguments.
    std::string ifname;
    unsigned baud = 921600;
    if (argc == 4) {
        ifname = argv[1];       // UART device
        baud = atoi(argv[2]);   // Baud rate
        verbosity = atoi(argv[3]);
    } else if (argc == 3) {
        ifname = argv[1];       // UART device
        baud = atoi(argv[2]);   // Baud rate
    } else if (argc == 2) {
        ifname = argv[1];       // UART device
    }

    // Print the usage prompt?
    if (argc > 3 || ifname == "" || ifname == "help" || ifname == "--help") {
        std::cout << "Config_tool configures the zcu208_clksynth example design." << std::endl
            << "Usage: config_tool.bin <ifname>" << std::endl
            << "       config_tool.bin <ifname> <baud>" << std::endl
            << "       config_tool.bin <ifname> <baud> <verbosity>" << std::endl
            << "Where 'ifname' is the USB-UART attached to the ZCU208 FPGA." << std::endl
            << "Verbosity level may be set to 0, 1 (default), or 2." << std::endl;
        return 0;
    }

    // Attach an IP stack to the specified UART interface.
    io::SlipUart* uart = new io::SlipUart(ifname.c_str(), baud);

    // Interface ready?
    if (uart && uart->ok()) {
        // Open remote-control interface.
        std::cout << "Starting config_tool on " << ifname << std::endl;
        eth::Dispatch dispatch(LOCAL_MAC, uart, uart);
        eth::ConfigBus cfgbus(&dispatch, timer.timer());
        cfgbus.connect(REMOTE_MAC);
        cfgbus.set_irq_polling(30);
        // Start the configuration tool.
        config_tool(&cfgbus);
        return 0;
    } else {
        std::cerr << "Couldn't open UART interface: " << ifname << std::endl;
        return 1;
    }
}
