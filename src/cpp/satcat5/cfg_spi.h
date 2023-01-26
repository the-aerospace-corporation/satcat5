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
// Generic SPI interface
//
// This a generic interface for issuing SPI transactions, to be implemented
// by any SPI controller.  See also: cfgbus_spi.h.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace cfg {
        // Prototype for the SPI Event Handler callback interface.
        // To use, inherit from this class and override the spi_done() method.
        class SpiEventListener {
        public:
            virtual void spi_done(unsigned nread, const u8* rbytes) = 0;
        protected:
            ~SpiEventListener() {}
        };

        // Generic pure-virtual API definition.
        class SpiGeneric
        {
        public:
            // Queue an exchange transaction (simultaneous write+read).
            // Returns true if the command was added to the queue.
            // Returns false if the user should try again later.
            virtual bool exchange(
                u8 devidx, const u8* wrdata, u8 rwbytes,
                satcat5::cfg::SpiEventListener* callback = 0) = 0;

            // Queue a query transaction (write, read, or write-then-read).
            // Returns true if the command was added to the queue.
            // Returns false if the user should try again later.
            virtual bool query(
                u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
                satcat5::cfg::SpiEventListener* callback = 0) = 0;
        };
    }
}
