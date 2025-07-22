//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Configuration for the various Ethernet-over-Serial ports.
//!
//!\details
//! The various SatCat5 "port_serial_*" blocks are completely automonomous,
//! but can accept an optional ConfigBus interface for runtime configuration
//! changes (e.g., changing the baud rate or SPI mode).
//!
//! This file defines configuration interfaces for the following VHDL blocks:
//!  * port_serial_auto = `port::SerialAuto`
//!  * port_serial_i2c_controller = `port::SerialI2cController`
//!  * port_serial_i2c_peripheral = `port::SerialI2cPeripheral`
//!  * port_serial_spi_controller = `port::SerialSpiController`
//!  * port_serial_spi_peripheral = `port::SerialSpiPeripheral`
//!  * port_serial_uart_2wire = `port::SerialUart`
//!  * port_serial_uart_4wire = `port::SerialUart`
//!
//! All I2C ports use the address-conversion functions defined in
//! cfgbus_i2c.h; refer to that file for more information.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_i2c.h>

namespace satcat5 {
    namespace port {
        //! Parent class for each of the Serial* objects.
        //! This class provides a basic skeleton, but doesn't do much on its own.
        class SerialGeneric {
        public:
            //! Link this object to a specific ConfigBus address.
            SerialGeneric(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            //! Read the port-status register.
            //! Interpretation varies by port type; see VHDL comments.
            u8 status();

        protected:
            struct ctrl_reg;
            satcat5::cfg::Register m_ctrl;
        };

        //! Driver for "port_serial_auto.vhd".
        class SerialAuto : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Manually select auto/SPI/UART mode.
            //! \see MODE_AUTO, MODE_SPI, MODE_UART1, MODE_UART2.
            void config_mode(u8 mode);
            //! Set the SPI clock mode (0/1/2/3) and glitch-filter parameters.
            void config_spi(u8 mode, u8 gfilt=1);
            //! Set the UART baud rate and flow-control options.
            void config_uart(unsigned baud, bool ignore_cts=false);
            //! Report the current mode (auto/SPI/UART). \see config_mode.
            u8 read_mode();

            //! Constants for config_mode() and read_mode().
            //!@{
            static constexpr u8 MODE_AUTO   = 0;
            static constexpr u8 MODE_SPI    = 1;
            static constexpr u8 MODE_UART1  = 2;
            static constexpr u8 MODE_UART2  = 3;
            //!@}
        };

        //! Driver for "port_serial_i2c_controller.vhd".
        class SerialI2cController : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Configure the remote I2C address and baud rate.
            void config_i2c(const satcat5::util::I2cAddr& devaddr, unsigned baud=100000);
        };

        //! Driver for "port_serial_i2c_peripheral.vhd".
        class SerialI2cPeripheral : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Configure the local I2C address.
            void config_i2c(const satcat5::util::I2cAddr& devaddr);
        };

        //! Driver for "port_serial_spi_controller.vhd".
        class SerialSpiController : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Set the SPI baud-rate and clock mode (0/1/2/3).
            void config_spi(unsigned baud, u8 mode);
        };

        //! Driver for "port_serial_spi_peripheral.vhd".
        class SerialSpiPeripheral : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Set the SPI clock mode (0/1/2/3) and glitch-filter parameters.
            void config_spi(u8 mode, u8 gfilt=1);
        };

        //! Driver for "port_serial_uart_*.vhd".
        //! Configures both 2-wire UARTs ("port_serial_uart_2wire.vhd")
        //! and 4-wire UARTs ("port_serial_uart_4wire.vhd").
        class SerialUart : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            //! Set the UART baud rate and flow-control options.
            void config_uart(unsigned baud, bool ignore_cts=false);
        };
    }
}
