//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface driver for the cfgbus_spi_controller block
//
// An SPI Controller is the device that drives the CS and SCK signals
// of a four-wire or three-wire SPI bus.  This driver operates the
// controller block defined in "cfgbus_spi_controller.vhd".
//
// The ::configure() method sets the baud-rate and SPI mode.  This method
// should only be called when the bus is idle.  The mode parameter is
// defined in the SPI specification and sets the clock-polarity (CPOL)
// and clock-phase (CPHA) options.
//
// For more information on the SPI bus:
//  https://en.wikipedia.org/wiki/Serial_Peripheral_Interface
//

#pragma once

#include <satcat5/cfg_spi.h>
#include <satcat5/cfgbus_multiserial.h>

// Default sizes for the SPI working buffers
// For reference: 256 bytes = 2.0 msec buffer @ 1 Mbaud
#ifndef SATCAT5_SPI_TXBUFF
#define SATCAT5_SPI_TXBUFF  256     // Up to N bytes of queued commands
#endif

#ifndef SATCAT5_SPI_RXBUFF
#define SATCAT5_SPI_RXBUFF  64      // Up to N bytes of queued replies
#endif

#ifndef SATCAT5_SPI_MAXCMD
#define SATCAT5_SPI_MAXCMD  16      // Each queue up to N transactions
#endif

namespace satcat5 {
    namespace cfg {
        // Interface controller class.
        class Spi
            : public satcat5::cfg::SpiGeneric
            , public satcat5::cfg::MultiSerial
        {
        public:
            // Constructor.
            Spi(ConfigBus* cfg, unsigned devaddr);

            // Initialize SPI controller.
            void configure(
                unsigned clkref_hz,     // ConfigBus clock frequency
                unsigned baud_hz,       // SPI baud-rate
                unsigned mode = 3);     // SPI mode (0/1/2/3)

            // Is the SPI controller currently busy?
            bool busy() override;

            // Queue a bus transaction. (Return true if successful.)
            bool exchange(
                u8 devidx, const u8* wrdata, u8 rwbytes,
                satcat5::cfg::SpiEventListener* callback = 0) override;
            bool query(
                u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
                satcat5::cfg::SpiEventListener* callback = 0) override;

        protected:
            // Event handlers:
            void read_done(unsigned cidx);

            // Metadata for queued commands.
            satcat5::cfg::SpiEventListener* m_callback[SATCAT5_SPI_MAXCMD];

            // Working buffer for transmit and receive data.
            u8 m_txbuff[SATCAT5_SPI_TXBUFF];
            u8 m_rxbuff[SATCAT5_SPI_RXBUFF];
        };
    }
}
