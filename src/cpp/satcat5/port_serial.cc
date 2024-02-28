//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/port_serial.h>
#include <satcat5/utils.h>

namespace port  = satcat5::port;
namespace util  = satcat5::util;

// Duplicate definitions required for C++0x11 compatibility, fixed in 0x17.
// See also: https://en.cppreference.com/w/cpp/language/static
#if __cplusplus < 201703L
    constexpr u8 port::SerialAuto::MODE_AUTO;
    constexpr u8 port::SerialAuto::MODE_SPI;
    constexpr u8 port::SerialAuto::MODE_UART1;
    constexpr u8 port::SerialAuto::MODE_UART2;
#endif

// Generators for commonly-used command formats:
inline u32 cmd_uart(u32 ref, u32 baud, bool ignore_cts) {
    static const u32 CTS_OVERRIDE = (1u << 31);
    u32 flags = (ignore_cts ? CTS_OVERRIDE : 0);
    return util::div_round_u32(ref, baud) | flags;
}
inline u32 cmd_i2c_controller(u32 ref, u32 baud, u32 devaddr) {
    u32 clkdiv = util::div_ceil_u32(ref, 4*baud) - 1;
    return (devaddr << 16) | clkdiv;
}
inline u32 cmd_i2c_peripheral(u32 devaddr) {
    return (devaddr << 16);
}
inline u32 cmd_spi_controller(u32 ref, u32 baud, u32 mode) {
    u32 clkdiv = util::div_ceil_u32(ref, 2*baud);
    return (mode << 8) | clkdiv;
}
inline u32 cmd_spi_peripheral(u32 mode, u32 gfilt) {
    return (mode << 8) | gfilt;
}

// Most ports use the same set of control registers:
static const unsigned REGADDR_STATUS    = 0;    // Port status (interpretation varies)
static const unsigned REGADDR_CLKREF    = 1;    // Reference clock frequency, in Hz
static const unsigned REGADDR_CTRL0     = 2;    // Main control register
static const unsigned REGADDR_CTRL1     = 3;    // Aux control register, if applicable
static const unsigned REGADDR_MODE      = 4;    // Mode/autodetect register, if applicable

port::SerialGeneric::SerialGeneric(
        satcat5::cfg::ConfigBus* cfg, unsigned devaddr)
    : m_ctrl(cfg->get_register(devaddr))
{
    // No other initialization required.
}

u8 port::SerialGeneric::status() {
    return (u8)m_ctrl[REGADDR_STATUS];
}

void port::SerialAuto::config_mode(u8 mode) {
    m_ctrl[REGADDR_MODE] = (u32)mode;
}

void port::SerialAuto::config_spi(u8 mode, u8 gfilt) {
    m_ctrl[REGADDR_CTRL0] = cmd_spi_peripheral(mode, gfilt);
}

void port::SerialAuto::config_uart(unsigned baud, bool ignore_cts) {
    u32 clk_hz = m_ctrl[REGADDR_CLKREF];
    m_ctrl[REGADDR_CTRL1] = cmd_uart(clk_hz, baud, ignore_cts);
}

u8 port::SerialAuto::read_mode() {
    return (u8)m_ctrl[REGADDR_MODE];
}

void port::SerialI2cController::config_i2c(const util::I2cAddr& devaddr, unsigned baud) {
    u32 clk_hz = m_ctrl[REGADDR_CLKREF];
    m_ctrl[REGADDR_CTRL0] = cmd_i2c_controller(clk_hz, baud, devaddr.m_addr);
}

void port::SerialI2cPeripheral::config_i2c(const util::I2cAddr& devaddr) {
    m_ctrl[REGADDR_CTRL0] = cmd_i2c_peripheral(devaddr.m_addr);
}

void port::SerialSpiController::config_spi(unsigned baud, u8 mode) {
    u32 clk_hz = m_ctrl[REGADDR_CLKREF];
    m_ctrl[REGADDR_CTRL0] = cmd_spi_controller(clk_hz, baud, mode);
}

void port::SerialSpiPeripheral::config_spi(u8 mode, u8 gfilt) {
    m_ctrl[REGADDR_CTRL0] = cmd_spi_peripheral(mode, gfilt);
}

void port::SerialUart::config_uart(unsigned baud, bool ignore_cts) {
    u32 clk_hz = m_ctrl[REGADDR_CLKREF];
    m_ctrl[REGADDR_CTRL0] = cmd_uart(clk_hz, baud, ignore_cts);
}
