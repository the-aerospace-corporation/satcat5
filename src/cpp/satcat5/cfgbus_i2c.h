//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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
// Interface driver for the ConfigBus I2C block
//
// This driver is designed for high-throughput, for example writing large
// blocks of data to I2C-controlled OLED displays.  As such, it has a
// relatively large transmit queue, to ensure throughput is maintained.
//

#pragma once

#include <satcat5/cfg_i2c.h>
#include <satcat5/cfgbus_multiserial.h>

// Default sizes for the I2C working buffers
// For reference: 256 bytes = 5.7 msec buffer @ 400 kbaud
#ifndef SATCAT5_I2C_TXBUFF
#define SATCAT5_I2C_TXBUFF  256     // Up to N bytes of queued commands
#endif

#ifndef SATCAT5_I2C_RXBUFF
#define SATCAT5_I2C_RXBUFF  64      // Up to N bytes of queued replies
#endif

#ifndef SATCAT5_I2C_MAXCMD
#define SATCAT5_I2C_MAXCMD  16      // Each queue up to N transactions
#endif

namespace satcat5 {
    namespace cfg {
        // Interace driver for "cfgbus_i2c_controller"
        class I2c
            : public satcat5::cfg::I2cGeneric
            , public satcat5::cfg::MultiSerial
        {
        public:
            // Constructor links to specified control register.
            I2c(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Configure the I2C device.
            void configure(
                unsigned refclk_hz,         // ConfigBus reference clock
                unsigned baud_hz,           // Desired I2C baud rate
                bool clock_stretch = true); // Allow clock-stretching?

            // Add a bus operation to the queue. (Return true if successful.)
            bool read(const satcat5::util::I2cAddr& devaddr,
                u8 regbytes, u32 regaddr, u8 nread,
                satcat5::cfg::I2cEventListener* callback = 0) override;
            bool write(const satcat5::util::I2cAddr& devaddr,
                u8 regbytes, u32 regaddr, u8 nwrite, const u8* data,
                satcat5::cfg::I2cEventListener* callback = 0) override;

        protected:
            // Shared logic for for read() and write() methods.
            bool enqueue_cmd(
                const satcat5::util::I2cAddr& devaddr,
                u8 regbytes, u32 regaddr,
                u8 nwrite, const u8* data, u8 nread,
                satcat5::cfg::I2cEventListener* callback = 0);

            // Event handlers.
            void read_done(unsigned idx);

            // Metadata for queued commands.
            satcat5::cfg::I2cEventListener* m_callback[SATCAT5_I2C_MAXCMD];
            u16 m_devaddr[SATCAT5_I2C_MAXCMD];
            u32 m_regaddr[SATCAT5_I2C_MAXCMD];

            // Working buffer for transmit and receive data.
            u8 m_txbuff[SATCAT5_I2C_TXBUFF];
            u8 m_rxbuff[SATCAT5_I2C_RXBUFF];
        };
    }
}
