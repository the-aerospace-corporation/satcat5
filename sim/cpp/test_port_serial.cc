//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for configuring Ethernet-over-Serial ports

#include <cstring>
#include <hal_test/catch.hpp>
#include <hal_test/sim_utils.h>
#include <satcat5/port_serial.h>
#include <satcat5/utils.h>

using satcat5::util::I2cAddr;
using satcat5::port::SerialAuto;

// Define register map (see "port_mailmap.vhd")
static const unsigned CFG_DEVADDR       = 42;
static const unsigned REGADDR_STATUS    = 0;    // Port status (interpretation varies)
static const unsigned REGADDR_CLKREF    = 1;    // Reference clock frequency, in Hz
static const unsigned REGADDR_CTRL0     = 2;    // Main control register
static const unsigned REGADDR_CTRL1     = 3;    // Aux control register, if applicable
static const unsigned REGADDR_MODE      = 4;    // Mode/autodetect register, if applicable

// Other test parameters.
static const u32 TEST_STATUS        = 0x47;
static const u32 CLKREF             = 100e6;
static const I2cAddr I2C_DEVADDR1   = I2cAddr::addr7(21);   // 8-bit = 0x42
static const I2cAddr I2C_DEVADDR2   = I2cAddr::addr7(22);   // 8-bit = 0x44
static const u32 I2C_CFGADDR1       = I2C_DEVADDR1.m_addr << 16;
static const u32 I2C_CFGADDR2       = I2C_DEVADDR2.m_addr << 16;
static const u32 CTS_OVERRIDE       = (1u << 31);

// Hardware configuration to achieve specified baud-rate.
// (Refer to io_i2c_controller.vhd, io_spi_controller.vhd, and io_uart.vhd)
u32 clkdiv_i2c(unsigned baud)
    {return satcat5::util::div_ceil_u32(CLKREF, 4*baud) - 1;}
u32 clkdiv_spi(unsigned baud)
    {return satcat5::util::div_ceil_u32(CLKREF, 2*baud);}
u32 clkdiv_uart(unsigned baud, bool cts_ovr = false) {
    return (cts_ovr ? CTS_OVERRIDE : 0)
         | satcat5::util::div_round_u32(CLKREF, baud);
}

class MockSerial : public satcat5::test::MockConfigBusMmap {
public:
    explicit MockSerial(unsigned devaddr)
        : m_dev(m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE)
    {
        m_dev[REGADDR_STATUS] = TEST_STATUS;    // Hardware status reporting
        m_dev[REGADDR_CLKREF] = CLKREF;         // Reference clock frequency
    }

    // Register accessors.
    u32 status() const  {return m_dev[REGADDR_STATUS];}
    u32 ctrl0() const   {return m_dev[REGADDR_CTRL0];}
    u32 ctrl1() const   {return m_dev[REGADDR_CTRL1];}

private:
    u32* const m_dev;
};

TEST_CASE("port_serial") {
    MockSerial mock(CFG_DEVADDR);

    SECTION("StatusRegister") {
        satcat5::port::SerialGeneric uut(&mock, CFG_DEVADDR);
        CHECK(mock.status() == TEST_STATUS);
        CHECK((u32)uut.status() == TEST_STATUS);
    }

    SECTION("SerialAuto") {
        SerialAuto uut(&mock, CFG_DEVADDR);
        CHECK(uut.read_mode() == SerialAuto::MODE_AUTO);
        uut.config_mode(SerialAuto::MODE_UART1);
        CHECK(uut.read_mode() == SerialAuto::MODE_UART1);
        uut.config_spi(3, 1);       // SPI Mode = 3, Filt = 1
        CHECK(mock.ctrl0() == 0x0301);
        uut.config_spi(2, 3);       // SPI Mode = 2, Filt = 3
        CHECK(mock.ctrl0() == 0x0203);
        uut.config_uart(921600);    // Set UART baud rate
        CHECK(mock.ctrl1() == clkdiv_uart(921600));
        uut.config_uart(115200, true);  // UART baud rate + CTS override
        CHECK(mock.ctrl1() == clkdiv_uart(115200, true));
    }

    SECTION("SerialI2cController") {
        satcat5::port::SerialI2cController uut(&mock, CFG_DEVADDR);
        uut.config_i2c(I2C_DEVADDR1, 200e3);
        CHECK(mock.ctrl0() == (I2C_CFGADDR1 | clkdiv_i2c(200e3)));
        uut.config_i2c(I2C_DEVADDR2, 400e3);
        CHECK(mock.ctrl0() == (I2C_CFGADDR2 | clkdiv_i2c(400e3)));
    }

    SECTION("SerialI2cPeripheral") {
        satcat5::port::SerialI2cPeripheral uut(&mock, CFG_DEVADDR);
        uut.config_i2c(I2C_DEVADDR1);
        CHECK(mock.ctrl0() == I2C_CFGADDR1);
        uut.config_i2c(I2C_DEVADDR2);
        CHECK(mock.ctrl0() == I2C_CFGADDR2);
    }

    SECTION("SerialSpiController") {
        satcat5::port::SerialSpiController uut(&mock, CFG_DEVADDR);
        uut.config_spi(2e6, 0);
        CHECK(mock.ctrl0() == clkdiv_spi(2e6));
        uut.config_spi(1e6, 3);
        CHECK(mock.ctrl0() == (0x0300 | clkdiv_spi(1e6)));
    }

    SECTION("SerialSpiPeripheral") {
        satcat5::port::SerialSpiPeripheral uut(&mock, CFG_DEVADDR);
        uut.config_spi(3, 1);       // SPI Mode = 3, Filt = 1
        CHECK(mock.ctrl0() == 0x0301);
        uut.config_spi(2, 3);       // SPI Mode = 2, Filt = 3
        CHECK(mock.ctrl0() == 0x0203);
    }

    SECTION("SerialUart") {
        satcat5::port::SerialUart uut(&mock, CFG_DEVADDR);
        uut.config_uart(921600);
        CHECK(mock.ctrl0() == clkdiv_uart(921600));
        uut.config_uart(115200, true);
        CHECK(mock.ctrl0() == clkdiv_uart(115200, true));
    }
}
