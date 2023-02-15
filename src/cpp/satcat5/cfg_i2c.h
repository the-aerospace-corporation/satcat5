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
// Generic I2C interface
//
// This a generic interface for issuing I2C commands, to be implemented
// by any I2C controller.  See also: cfgbus_i2c.h.
//

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    namespace util {
        // Conversion function for I2C device addresses.
        // Natively, I2C device addresses are 7-bits followed by the read/write flag.
        // There are two common conventions for representing this in software:
        //  * 7-bit addresses (e.g., 0x77 = 1110111) are right-justified.
        //  * 8-bit addresses (e.g., 0xEE/0xEF = 1110111x) are left-justified
        //    and come in pairs, treating read and write as a "separate" address.
        // These two examples ultimately refer to the same underlying I2C address.
        // This wrapper is intended to allow unambiguous use of either convention.
        struct I2cAddr final {      // GCOVR_EXCL_START
        public:
            // Create I2C address from a 7-bit input (right-justified)
            // Example: I2cAddr my_addr = I2cAddr::addr7(0x77);
            static constexpr I2cAddr addr7(u8 addr)
                {return I2cAddr(2 * addr);}

            // Create I2C address from an 8-bit input (left-justified)
            // Example: I2cAddr my_addr = I2cAddr::addr8(0xEE);
            static constexpr I2cAddr addr8(u8 addr)
                {return I2cAddr(addr & 0xFE);}

            // Native internal representation for SatCat5.
            const u8 m_addr;

        private:
            explicit constexpr I2cAddr(u8 addr) : m_addr(addr) {}
        };                          // GCOVR_EXCL_STOP
    }

    namespace cfg {
        // Prototype for the I2C Event Handler callback interface.
        // To use, inherit from this class and override the i2c_done() method.
        class I2cEventListener {
        public:
            virtual void i2c_done(
                u8 noack,           // Missing ACK during this command?
                u8 devaddr,         // Device address
                u32 regaddr,        // Register address (if applicable)
                unsigned nread,     // Number of bytes read (if applicable)
                const u8* rdata)    // Pointer to read buffer
                = 0;                // Child MUST override this method
        protected:
            ~I2cEventListener() {}
        };

        // Generic pure-virtual API definition.
        class I2cGeneric
        {
        public:
            // Add a read operation to the queue:
            //  * If regbytes = 0:
            //      Start - Addr(R) - Read - Read - Stop
            //  * If regbytes > 0:
            //      Start - Addr(W) - Addr - Addr
            //      Start - Addr(R) - Data - Data - Stop
            // Returns true if the command was added to the queue.
            // Returns false if the user should try again later.
            // (Child class MUST implement this method.
            virtual bool read(const satcat5::util::I2cAddr& devaddr,
                u8 regbytes, u32 regaddr, u8 nread,
                satcat5::cfg::I2cEventListener* callback = 0) = 0;

            // Add a write operation to the queue.
            //  * If regbytes = 0:
            //      Start - Addr(W) - Data - Data - Stop
            //  * If regbytes > 0:
            //      Start - Addr(W) - Addr - Addr - Data - Data - Stop
            // Returns true if the command was added to the queue.
            // Returns false if the user should try again later.
            // (Child class MUST implement this method.
            virtual bool write(const satcat5::util::I2cAddr& devaddr,
                u8 regbytes, u32 regaddr, u8 nwrite, const u8* data,
                satcat5::cfg::I2cEventListener* callback = 0) = 0;
        };
    }
}
