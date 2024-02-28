//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

#include <satcat5/cfgbus_core.h>
#include <satcat5/list.h>

namespace satcat5 {
    namespace cfg {
        // Event-handler for the shared ConfigBus interrupt.
        class Interrupt {
        public:
            // Check if this interrupt may need service, then call irq_event.
            void irq_check();

            // Interrupt service routine.
            // (Child class must override this method.)
            virtual void irq_event() = 0;

            // Optionally enable or disable this interrupt.
            // (Not generally required, but helpful in certain edge cases.)
            void irq_enable();
            void irq_disable();

        protected:
            // Note: Only children should create or destroy base class.
            // Register this interrupt (nonstandard control)
            explicit Interrupt(satcat5::cfg::ConfigBus* cfg);

            // Register this interrupt (standard control register)
            Interrupt(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr);
            ~Interrupt() SATCAT5_OPTIONAL_DTOR;

        private:
            friend satcat5::cfg::ConfigBus;
            friend satcat5::util::ListCore;
            satcat5::cfg::ConfigBus* const m_cfg;
            satcat5::cfg::Register m_ctrl;
            satcat5::cfg::Interrupt* m_next;
        };
    }
}
