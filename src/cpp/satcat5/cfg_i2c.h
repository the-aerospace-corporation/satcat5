//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
        //
        // Natively, conventional I2C device addresses are 7-bits followed by
        // the read/write flag.  Two bytes are required for 10-bit address mode.
        //
        // There are conflicting conventions for representing this in software.
        // This wrapper allows unambiguous use of all common conventions:
        //  * 7-bit addresses (e.g., 0x77 = 1110111) are right-justified.
        //  * 8-bit addresses (e.g., 0xEE/0xEF = 1110111x) are left-justified
        //    and come in pairs, treating read and write as a "separate" address.
        //    (This example refers to the same underlying I2C device address.)
        //  * 10-bit addresses (e.g., 0x377 = 1101110111) are right-justified.
        //    See also: https://www.i2c-bus.org/addressing/10-bit-addressing/
        //    We insert the required 11110 prefix at this time, and shift bits
        //    9 and 8 to make room for the R/Wb bit.  Doing more work up front
        //    (i.e., usually at build-time) simplifies downstream processing.
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

            // Create I2C address from a 10-bit input (right-justified)
            // Example: I2cAddr my_addr = I2cAddr::addr10(0x377);
            static constexpr I2cAddr addr10(u16 addr)
                {return I2cAddr(0xF000 | ((addr&0x300)<<1) | (addr&0xFF));}

            // Create I2C address from its native internal representation.
            static constexpr I2cAddr native(u16 addr)
                {return I2cAddr(addr);}

            // Is this a 10-bit address?
            inline bool is_10b() const {return m_addr > 255;}

            // Comparison operators:
            inline bool operator==(const I2cAddr& other) const
                {return m_addr == other.m_addr;}
            inline bool operator!=(const I2cAddr& other) const
                {return m_addr != other.m_addr;}

            // Native internal representation for SatCat5.
            const u16 m_addr;

        private:
            explicit constexpr I2cAddr(u16 addr) : m_addr(addr) {}
        };                          // GCOVR_EXCL_STOP
    }

    namespace cfg {
        // Prototype for the I2C Event Handler callback interface.
        // To use, inherit from this class and override the i2c_done() method.
        class I2cEventListener {
        public:
            virtual void i2c_done(
                bool noack,         // Missing ACK during this command?
                const satcat5::util::I2cAddr& devaddr,  // Device address
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
            // Is the I2C controller currently busy?
            virtual bool busy() = 0;

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
