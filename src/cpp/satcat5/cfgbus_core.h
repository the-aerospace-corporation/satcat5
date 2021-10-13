//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// ConfigBus core definitions
//
// Define the ConfigBus interrupt handler and the basic interface(s)
// for accessing ConfigBus registers.
//
// On bare-metal embedded systems, ConfigBus is directly memory-mapped
// to a volatile pointer in the local address space.  This is, by far,
// the simplest and most direct way to access ConfigBus and provides
// native support for byte-at-a-time writes (e.g., for MailMap).  This
// simplified interface is enabled by setting SATCAT5_CFGBUS_DIRECT = 1.
//
// If the "simple" flag is not set, we instead define an object-oriented
// interface that overloads the array-index and assignment operators.
//
// In many cases, code written with this in mind should be compatible
// with both options, e.g.:
//      my_register[n] = writeval;
//      readval = my_register[n];
// The object-oriented interface allows hooks for unit tests or even
// for remote commanding of an Ethernet-enabled ConfigBus host.
//

#pragma once

#include <satcat5/interrupts.h>
#include <satcat5/list.h>

// By default, use the general-purpose interface (see above).
// If your platform supports it, set this to 1 for better performance.
#ifndef SATCAT5_CFGBUS_DIRECT
#define SATCAT5_CFGBUS_DIRECT   0
#endif

namespace satcat5 {
    namespace cfg {
        // Fixed ConfigBus parameters:
        const unsigned DEVS_PER_CFGBUS  = 256;
        const unsigned REGS_PER_DEVICE  = 1024;
        const unsigned MAX_DEVICES      = 256;
        const unsigned MAX_TOTAL_REGS   = REGS_PER_DEVICE * MAX_DEVICES;

        // Shortcut for don't-care register address.
        const unsigned REGADDR_ANY      = 0;

        // Generic wrapper for a specific ConfigBus register.
        // Note: Most devices should use the "Register" alias defined below.
        class WrappedRegister {
        public:
            WrappedRegister(ConfigBus* cfg, unsigned reg);
            operator u32();                             // Read from register
            void operator=(u32 wrval);                  // Write to register
        protected:
            satcat5::cfg::ConfigBus* const m_cfg;       // Parent interface
            const unsigned m_reg;                       // Device + register index
        };

        // Pointer-like wrapper for one or more ConfigBus registers.
        // Note: Most devices should use the "Register" alias defined below.
        class WrappedRegisterPtr {
        public:
            WrappedRegisterPtr(ConfigBus* cfg, unsigned reg);
            bool operator!() const;                     // Valid register?
            satcat5::cfg::WrappedRegister operator*();  // Pointer dereference
            satcat5::cfg::WrappedRegister operator[](unsigned idx);
        protected:
            satcat5::cfg::ConfigBus* const m_cfg;       // Parent interface
            const unsigned m_reg;                       // Device + register index
        };

        // Prefer the direct or indirect interface?
        #if SATCAT5_CFGBUS_DIRECT
            typedef volatile u32* Register;
            #define SATCAT5_NULL_REGISTER   0
        #else
            typedef satcat5::cfg::WrappedRegisterPtr Register;
            #define SATCAT5_NULL_REGISTER   WrappedRegisterPtr(0,0)
        #endif

        // Status codes for ConfigBus read/write operations.
        enum IoStatus {
            IOSTATUS_OK = 0,        // Operation successful
            IOSTATUS_BUSERROR,      // ConfigBus error
            IOSTATUS_CMDERROR,      // Invalid command
            IOSTATUS_TIMEOUT,       // Network timeout
        };

        // Generic ConfigBus interface.
        class ConfigBus
        {
        public:
            // Basic read and write operations.
            virtual satcat5::cfg::IoStatus read(unsigned regaddr, u32& wrval) = 0;
            virtual satcat5::cfg::IoStatus write(unsigned regaddr, u32 rdval) = 0;

            // TODO: Add I/O operations to match "cfgbus_host_eth":
            //  * Maskable write (single byte, etc.)
            //  * Read no-increment
            //  * Read auto-increment

            // Add or remove an interrupt handler.
            void register_irq(satcat5::cfg::Interrupt* obj);
            void unregister_irq(satcat5::cfg::Interrupt* obj);

            // Count attached interrupt handlers.
            unsigned count_irq() const;

            // Create register-map for the given device address.
            // (Or for a specific register, if the second address is specified.)
            satcat5::cfg::Register get_register(unsigned dev, unsigned reg = 0);

        protected:
            // Constructor should only be called by children.
            // (Only children should create or destroy base class.)
            explicit ConfigBus(void* base_ptr = 0);
            ~ConfigBus() {}

            // Interrupt handler notifies all children.
            void irq_poll();

            // Direct-access pointer, if applicable.
            volatile u32* const m_base_ptr;

            // Linked-list of interrupt handlers.
            satcat5::util::List<satcat5::cfg::Interrupt> m_irq_list;
        };

        // Memory-mapped local ConfigBus.
        class ConfigBusMmap
            : public satcat5::cfg::ConfigBus
            , public satcat5::irq::Handler
        {
        public:
            // Constructor accepts the base pointer for the memory-map interface,
            // and the interrupt-index for the shared ConfigBus interrupt, if any.
            ConfigBusMmap(void* base_ptr, int irq);

            // Basic read and write operations.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& val) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 val) override;

            // Get a raw pointer to the designated device-address.
            void* get_device_mmap(unsigned dev) const;

            // Get a raw pointer to the designated combined-address.
            inline volatile u32* get_register_mmap(unsigned addr) const
                {return m_base_ptr + addr;}

        protected:
            void irq_event() override;
        };
    }
}
