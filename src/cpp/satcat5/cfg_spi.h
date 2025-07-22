//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Generic SPI interface

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace cfg {
        //! SPI Event Handler callback for use with SpiGeneric.
        //! To use, inherit from this class and override the spi_done() method.
        class SpiEventListener {
        public:
            virtual void spi_done(unsigned nread, const u8* rbytes) = 0;
        protected:
            ~SpiEventListener() {}
        };

        //! Polymorphic API for a generic SPI interface.
        //! This a generic interface for issuing SPI transactions, to be
        //! implemented by any SPI controller.  \see cfg::Spi.
        //! The child class must define all three virtual methods.
        class SpiGeneric {
        public:
            //! Is the SPI controller currently busy?
            virtual bool busy() = 0;

            //! Queue an exchange transaction (simultaneous write+read).
            //! Returns true if the command was added to the queue.
            //! Returns false if the user should try again later.
            virtual bool exchange(
                u8 devidx, const u8* wrdata, u8 rwbytes,
                satcat5::cfg::SpiEventListener* callback = 0) = 0;

            //! Queue a query transaction (write, read, or write-then-read).
            //! Returns true if the command was added to the queue.
            //! Returns false if the user should try again later.
            virtual bool query(
                u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
                satcat5::cfg::SpiEventListener* callback = 0) = 0;
        };
    }
}
