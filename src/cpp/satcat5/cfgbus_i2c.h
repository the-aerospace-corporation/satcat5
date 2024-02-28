//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

            // Configure the I2C controller.
            void configure(
                unsigned refclk_hz,         // ConfigBus reference clock
                unsigned baud_hz,           // Desired I2C baud rate
                bool clock_stretch = true); // Allow clock-stretching?

            // Is the I2C controller currently busy?
            bool busy() override;

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
