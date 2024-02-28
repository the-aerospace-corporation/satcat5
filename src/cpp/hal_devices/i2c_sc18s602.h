//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Device driver for the NXP SC18IS602B I2C-to-SPI bridge
//
// The SC18IS602B is an SPI master that is controlled through an I2C bus,
// allowing indirect control of downstream SPI peripherals.  This driver
// concerts each SPI transaction into a series of I2C commands.
//
// Note: One SPI transaction at a time; no queueing is provided.
//
// Reference: https://www.nxp.com/docs/en/data-sheet/SC18IS602B.pdf
//

#pragma once

#include <satcat5/cfg_i2c.h>
#include <satcat5/cfg_spi.h>

namespace satcat5 {
    namespace device {
        namespace i2c {
            class Sc18is602
                : public satcat5::cfg::I2cEventListener
                , public satcat5::cfg::SpiGeneric
            {
            public:
                // Constructor links to specified control register.
                Sc18is602(
                    satcat5::cfg::I2cGeneric* i2c,          // Parent interface
                    const satcat5::util::I2cAddr& devaddr); // Device address

                // Configure the SPI mode (0/1/2/3 sets CPOL, CPHA)
                bool configure(unsigned spi_mode);

                // Is the SPI controller currently busy?
                bool busy() override;

                // Queue an SPI bus transaction. (Return true if successful.)
                bool exchange(
                    u8 devidx, const u8* wrdata, u8 rwbytes,
                    satcat5::cfg::SpiEventListener* callback = 0) override;
                bool query(
                    u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
                    satcat5::cfg::SpiEventListener* callback = 0) override;

            protected:
                // I2C callback handler.
                void i2c_done(
                    bool noack, const satcat5::util::I2cAddr& devaddr,
                    u32 regaddr, unsigned nread, const u8* rdata) override;

                // Execute a series of I2C commands.
                bool execute(u8 devidx, const u8* wrdata, u8 rwbytes, u8 skip);

                // Pointer to the parent interface.
                satcat5::cfg::I2cGeneric* const m_parent;
                const satcat5::util::I2cAddr m_devaddr;

                // Current command state.
                satcat5::cfg::SpiEventListener* m_callback;
                u8 m_busy;
                u8 m_skip;
            };
        }
    }
}
