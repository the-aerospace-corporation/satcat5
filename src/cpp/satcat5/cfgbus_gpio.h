//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus general-purpose input and output registers

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {
        //! ConfigBus general-purpose input register.
        //! Wrapper for a simple read-only register, often used for GPIO.
        //! (e.g., cfgbus_gpi, cfgbus_readonly, cfgbus_readonly_sync)
        //!
        //! The general-purpose input (GPI) is often used for "bit-banged" inputs
        //! that don't need continuous monitoring.  The underlying block is usually
        //! cfgbus_readonly or cfgbus_readonly_sync.  For blocks configured with
        //! AUTO_UPDATE = false, use "read_sync" to refresh before reading.
        class GpiRegister {
        public:
            //! Constructor sets the ConfigBus address.
            GpiRegister(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr);

            //! Normal read.
            inline u32 read() {return *m_reg;}

            //! Read with sync-request.
            u32 read_sync();

        protected:
            satcat5::cfg::Register m_reg;
        };

        //! ConfigBus general-purpose output register.
        //! Wrapper for a read/write register, often used for GPIO or LEDs.
        //! (e.g., cfgbus_gpo, cfgbus_register, cfgbus_register_sync)
        //!
        //! The general-purpose output (GPO) is often used for "bit-banged" outputs
        //! that don't need rapid control, like discrete LEDs or status flags.
        //! The underlying block is usually cfgbus_register or cfgbus_register_sync.
        class GpoRegister {
        public:
            //! Constructor sets the ConfigBus address.
            GpoRegister(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr);

            //! Write to the register directly.
            inline void write(u32 val)     {*m_reg = val;}
            //! Read from the register directly.
            inline u32 read()              {return *m_reg;}

            //! Clear only the masked bit(s).
            void out_clr(u32 mask);
            //! Set only the masked bit(s).
            void out_set(u32 mask);

            //! Aliases for backwards compatibility (deprecated).
            //!@{
            inline void mask_clr(u32 mask) {out_clr(mask);}
            inline void mask_set(u32 mask) {out_set(mask);}
            //!@}

        protected:
            satcat5::cfg::Register m_reg;
        };

        //! ConfigBus general-purpose input/output register.
        //! Wrapper for the combined input/output register (cfgbus_gpio).
        class GpioRegister {
        public:
            //! Constructor sets the ConfigBus address.
            //! This device uses several register addresses, starting from zero.
            GpioRegister(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            //! Read or write each register directly.
            //!@{
            void mode(u32 val);
            void write(u32 val);
            u32 read();
            //!@}

            //! Set or clear only the masked bits.
            //! Note: Mode flag '1' = Output, '0' = Input
            //!@{
            void mode_clr(u32 mask);
            void mode_set(u32 mask);
            void out_clr(u32 mask);
            void out_set(u32 mask);
            //!@}

        protected:
            satcat5::cfg::Register m_reg;
        };
    }
}
