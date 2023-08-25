//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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

#include <hal_devices/pll_clk104.h>
#include <satcat5/log.h>

using satcat5::cfg::GpoRegister;
using satcat5::cfg::I2cGeneric;
using satcat5::device::pll::Clk104;
using satcat5::util::I2cAddr;
using satcat5::util::min_unsigned;
namespace log = satcat5::log;

constexpr I2cAddr   ADDR_SWITCH = I2cAddr::addr7(0x74);     // TCA9548 on ZCU208
constexpr I2cAddr   ADDR_BRIDGE = I2cAddr::addr7(0x2F);     // SC18S602 on CLK104
constexpr u8        I2C_SW_PORT = 5;    // CLK104 port on the I2C switch
constexpr u8        DEV_LMK_ALL = 1;    // LMK04828B affects ADC and DAC
constexpr u8        DEV_LMX_ADC = 3;    // LMX2594 for ADC
constexpr u8        DEV_LMX_DAC = 2;    // LMX2594 for DAC
constexpr u8        RETRY_MAX   = 5;    // Max retries per step
constexpr unsigned  RETRY_MSEC  = 100;  // Delay after I2C/SPI error
constexpr u32       STEP_START  = 0;
constexpr u32       STEP_DONE   = (u32)(-1);

Clk104::Clk104(I2cGeneric* i2c, GpoRegister* gpo)
    : m_i2c(i2c, ADDR_SWITCH)
    , m_spi(&m_i2c, ADDR_BRIDGE)
    , m_gpo(gpo)
    , m_step(STEP_START)
    , m_retry(0)
    , m_verbose(0)
    , m_lmk_refsel(0)
    , m_lmk_refdiv(0)
{
    // Nothing else to initialize.
}

void Clk104::configure(u8 ref_sel, u32 ref_hz, bool verbose)
{
    m_verbose = verbose ? 1 : 0;

    // Configure LMK input stage: PLL1 divider and input select.
    m_lmk_refsel = 0x0A | (ref_sel << 4);   // Register 0x147
    m_lmk_refdiv = ref_hz / 5000000;        // Register 0x154, 0x156, 0x158

    // Are we already busy?
    if (m_retry > 0) {
        // Busy, go back to START on next event.
        m_retry = RETRY_MAX;
        m_step = STEP_START;
    } else {
        // Start new process from idle.
        m_retry = RETRY_MAX;
        m_step = STEP_START;
        timer_event();
    }
}

bool Clk104::busy() const
{
    return m_retry > 0;
}

bool Clk104::ready() const
{
    return m_step == STEP_DONE;
}

void Clk104::spi_done(unsigned nread, const u8* rbytes)
{
    timer_event();
}

// Define a generic struct for basic startup commands.
struct spi_cmd_t {
    u8 dev_idx;     // SPI device-index
    u8 wrdata[3];   // Always three bytes data
};

// Shortcuts for creating commands:
constexpr spi_cmd_t CMD_LMK(u16 regaddr, u8 regval)
    {return spi_cmd_t {DEV_LMK_ALL, {(u8)(regaddr >> 8), (u8)(regaddr >> 0), regval}};}
constexpr spi_cmd_t CMD_ADC(u8 regaddr, u16 regval)
    {return spi_cmd_t {DEV_LMX_ADC, {regaddr, (u8)(regval >> 8), (u8)(regval >> 0)}};}
constexpr spi_cmd_t CMD_DAC(u8 regaddr, u16 regval)
    {return spi_cmd_t {DEV_LMX_DAC, {regaddr, (u8)(regval >> 8), (u8)(regval >> 0)}};}

// Startup sequence.
static constexpr spi_cmd_t COMMANDS[] = {
    // LMK04828B:
    //  Dual loop mode as shown in Figure 18.
    //  PLL1 = Phase detect @ 5 MHz, external VCO @ 160 MHz
    //  PLL2 = Phase detect @ 80 MHz, internal VCO @ 2400 MHz
    CMD_LMK(0x000, 0x90),   // Reset, 4-wire mode
    CMD_LMK(0x100, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x107, 0x01),   // (Off) RF1_ADC_SYNC / (On)  REFIN_RF1
    CMD_LMK(0x108, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x10F, 0x00),   // (Off) AMS_SYSREF   / (Off) No-connect
    CMD_LMK(0x110, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x117, 0x01),   // (Off) RF2_DAC_SYNC / (On)  REFIN_RF2
    CMD_LMK(0x118, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x11F, 0x00),   // (Off) DDR_PLY_CAP  / (Off) DAC_REFCLK
    CMD_LMK(0x120, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x127, 0x00),   // (Off) PL_SYSREF    / (Off) PL_CLK
    CMD_LMK(0x128, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x12F, 0x10),   // (On)  EXT_REF_OUT  / (Off) No-connect
    CMD_LMK(0x130, 24),     // Divide by 24 = 100 MHz
    CMD_LMK(0x137, 0x00),   // (Off) No-connect   / (Off) ADC_REFCLK
    CMD_LMK(0x13F, 0x00),   // Dual-loop mode (See Figure 18)
    CMD_LMK(0x145, 0x7F),   // Required (Section 9.5.1)
    CMD_LMK(0x147, 0x00),   // CLKIN_SEL = [Replaced with m_lmk_refsel]
    CMD_LMK(0x154, 0x00),   // PLL1_R = [Replaced with m_lmk_refdiv]
    CMD_LMK(0x156, 0x00),   // PLL1_R = [Replaced with m_lmk_refdiv]
    CMD_LMK(0x158, 0x00),   // PLL1_R = [Replaced with m_lmk_refdiv]
    CMD_LMK(0x15A, 32),     // PLL1_N = 32
    CMD_LMK(0x161, 2),      // PLL2_R = 2
    CMD_LMK(0x162, 0x48),   // PLL2_P = 2, OSCIN = 127-255 MHz
    CMD_LMK(0x171, 0xAA),   // Required (Section 9.5.1)
    CMD_LMK(0x172, 0x02),   // Required (Section 9.5.1)
    CMD_LMK(0x17C, 21),     // Required (Section 9.7.9.3)
    CMD_LMK(0x17D, 51),     // Required (Section 9.7.9.4)
    CMD_LMK(0x168, 15),     // PLL2_N = 15
    // LMX2594 for ADC: Input at 100 MHz, VCO at 9.6 GHz
    CMD_ADC(0, 0x2412),     // Reset enable
    CMD_ADC(0, 0x2410),     // Reset clear
    CMD_ADC(75, 0x0980),    // Channel divider = 24
    CMD_ADC(45, 0xC0C0),    // Enable channel divider
    CMD_ADC(36, 96),        // Set PLL_N
    CMD_ADC(31, 0x43EC),    // Set CHDIV_DIV2 flag
    CMD_ADC(0x00, 0x2418),  // Start calibration
    // LMX2594 for DAC: Input at 100 MHz, VCO at 10 GHz
    CMD_DAC(0, 0x2412),     // Reset enable
    CMD_DAC(0, 0x2410),     // Reset clear
    CMD_DAC(75, 0x0980),    // Channel divider = 24
    CMD_DAC(45, 0xC0C0),    // Enable channel divider
    CMD_DAC(36, 96),        // Set PLL_N
    CMD_DAC(31, 0x43EC),    // Set CHDIV_DIV2 flag
    CMD_DAC(0x00, 0x2418),  // Start calibration
};

static constexpr unsigned NUM_COMMANDS =
    sizeof(COMMANDS) / sizeof(spi_cmd_t);

void Clk104::timer_event()
{
    bool ok = true;

    // Have we finished the all steps?
    if (m_step >= NUM_COMMANDS) {
        m_retry = 0;
        m_step = STEP_DONE;
        return;
    }

    // Basic command lookup from table.
    spi_cmd_t cmd = COMMANDS[m_step];

    // Override the register value for specific commands.
    if (cmd.dev_idx == DEV_LMK_ALL) {
        if (cmd.wrdata[1] == 0x47) cmd.wrdata[2] = m_lmk_refsel;
        if (cmd.wrdata[1] == 0x54) cmd.wrdata[2] = m_lmk_refdiv;
        if (cmd.wrdata[1] == 0x56) cmd.wrdata[2] = m_lmk_refdiv;
        if (cmd.wrdata[1] == 0x58) cmd.wrdata[2] = m_lmk_refdiv;
    }

    // Special case for first step only:
    if (m_step == 0) {
        ok = ok && m_i2c.select_channel(I2C_SW_PORT);   // Set I2C channel
        ok = ok && m_spi.configure(0);                  // Set SPI mode = 0
    }

    // Configure the SPI MUX (selects one of four MISO lines).
    // Note: Channel indexing is reversed compared to I2C/SPI bridge.
    if (ok && m_gpo) {
        u32 mux_idx = 3 - cmd.dev_idx;
        m_gpo->write(mux_idx);
    }

    // Attempt to issue the SPI command.
    ok = ok && m_spi.query(cmd.dev_idx, cmd.wrdata, 3, 0, this);

    // Did we successfully issue the SPI command?
    if (ok) {
        ++m_step;                   // Wait for spi_done() event
        m_retry = RETRY_MAX;
        if (m_verbose) log::Log(log::DEBUG, "CLK104: Reached step").write10(m_step);
    } else if (--m_retry) {
        timer_once(RETRY_MSEC);     // Retry after a short delay
    } else {
        log::Log(log::WARNING, "CLK104: Error at step").write10(m_step);
    }
}

u8 Clk104::progress() const
{
    unsigned step = min_unsigned(m_step, NUM_COMMANDS + 1);
    return (u8)((100 * step) / (NUM_COMMANDS + 1));
}
