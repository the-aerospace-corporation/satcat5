//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Event-handler for individual ConfigBus interrupts.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/list.h>

namespace satcat5 {
    namespace cfg {
        //! Event-handler for individual ConfigBus interrupts.
        //! ConfigBus defines a single interrupt channel that is shared by
        //! all attached peripherals.  \see interrupts.h, cfg::ConfigBusMmap.
        //! In contrast, this class defines the interrupt servicing and
        //! callback API used for individual ConfigBus peripherals.
        class Interrupt {
        public:
            //! Check if this interrupt may need service.
            //! If the interrupt needs service, this calls irq_event.
            void irq_check();

            //! Interrupt service routine.
            //! (Child class must override this method.)
            virtual void irq_event() = 0;

            //! Enable this interrupt.
            //! Interrupts are enabled by default, but some peripherals
            //! may wish to temporary toggle this setting.
            //! For use with standard "cfgbus_interrupt" only.
            void irq_enable();

            //! Temporarily disable this interrupt.
            //! \copydetails irq_enable
            void irq_disable();

        protected:
            //! Nonstandard constructor.
            //! Use this alternate constructor for peripherals that assert
            //! ConfigBus interrupts without using "cfgbus_interrupt" block.
            //! Registers with the ConfigBus host but takes no further action.
            //! Methods irq_enable and irq_disable cannot be used.
            //! Only children should create or destroy base class.
            explicit Interrupt(satcat5::cfg::ConfigBus* cfg);

            //! Standard constructor.
            //! Only children should create or destroy base class.
            //! Use this constructor with the standard "cfgbus_interrupt"
            //! peripheral defined in "cfgbus_core.vhd".
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
