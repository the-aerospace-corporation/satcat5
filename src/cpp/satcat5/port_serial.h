//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Configuration for the various Ethernet-over-Serial ports
//
// The various SatCat5 "port_serial_*" blocks are completely automonomous,
// but can accept an optional ConfigBus interface for runtime configuration
// changes (e.g., changing the baud rate or SPI mode).
//
// This file defines configuration interfaces for:
//  * port_serial_auto (SPI / UART autodetect)
//  * port_serial_i2c_controller
//  * port_serial_i2c_peripheral
//  * port_serial_spi_controller
//  * port_serial_spi_peripheral
//  * port_serial_serial_uart_2wire
//  * port_serial_serial_uart_4wire
//
// All I2C ports use the address-conversion functions defined in
// cfgbus_i2c.h; refer to that file for more information.
//

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_i2c.h>

namespace satcat5 {
    namespace port {
        // Parent class for each of the Serial* objects.
        class SerialGeneric {
        public:
            SerialGeneric(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            u8 status();
        protected:
            struct ctrl_reg;
            satcat5::cfg::Register m_ctrl;
        };

        // Define each configuration interface:
        class SerialAuto : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            void config_mode(u8 mode);  // Manually set SPI/UART mode
            void config_spi(u8 mode, u8 gfilt=1);
            void config_uart(unsigned baud, bool ignore_cts=false);
            u8 read_mode();             // Report current SPI/UART mode

            // Constants for config_mode() and read_mode().
            static constexpr u8 MODE_AUTO   = 0;
            static constexpr u8 MODE_SPI    = 1;
            static constexpr u8 MODE_UART1  = 2;
            static constexpr u8 MODE_UART2  = 3;
        };

        class SerialI2cController : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            void config_i2c(const satcat5::util::I2cAddr& devaddr, unsigned baud=100000);
        };

        class SerialI2cPeripheral : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            void config_i2c(const satcat5::util::I2cAddr& devaddr);
        };

        class SerialSpiController : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            void config_spi(unsigned baud, u8 mode);
        };

        class SerialSpiPeripheral : public SerialGeneric {
        public:
            using SerialGeneric::SerialGeneric;
            void config_spi(u8 mode, u8 gfilt=1);
        };

        class SerialUart : public SerialGeneric {
        public:
            // Note: This class configures both 2-wire and 4-wire UARTs.
            using SerialGeneric::SerialGeneric;
            void config_uart(unsigned baud, bool ignore_cts=false);
        };
    }
}
