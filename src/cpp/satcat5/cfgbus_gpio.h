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
// ConfigBus general-purpose input and output registers
//
// The general-purpose output (GPO) is often used for "bit-banged" outputs
// that don't need rapid control, like discrete LEDs or status flags.
// The underlying block is usually cfgbus_register or cfgbus_register_sync.
//
// The general-purpose input (GPI) is often used for "bit-banged" inputs
// that don't need continuous monitoring.  The underlying block is usually
// cfgbus_readonly or cfgbus_readonly_sync.  For blocks configured with
// AUTO_UPDATE = false, use "read_sync" to refresh before reading.
//

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {
        // Wrapper for a simple read-only register, often used for GPIO.
        // (e.g., cfgbus_gpi, cfgbus_readonly, cfgbus_readonly_sync)
        class GpiRegister {
        public:
            GpiRegister(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr);

            // Normal read.
            inline u32 read() {return *m_reg;}

            // Read with sync-request.
            u32 read_sync();

        protected:
            satcat5::cfg::Register m_reg;
        };

        // Wrapper for a read/write register, often used for GPIO or LEDs.
        // (e.g., cfgbus_gpo, cfgbus_register, cfgbus_register_sync)
        class GpoRegister {
        public:
            GpoRegister(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr);

            // Read or write the register directly.
            inline void write(u32 val)     {*m_reg = val;}
            inline u32 read()              {return *m_reg;}

            // Set or clear only the masked bit(s).
            void out_clr(u32 mask);
            void out_set(u32 mask);

            // Alias for backwards compatibility (deprecated).
            inline void mask_clr(u32 mask) {out_clr(mask);}
            inline void mask_set(u32 mask) {out_set(mask);}

        protected:
            satcat5::cfg::Register m_reg;
        };

        // Wrapper for the combined input/output register (cfgbus_gpio).
        class GpioRegister {
        public:
            GpioRegister(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Read or write each register directly.
            void mode(u32 val);
            void write(u32 val);
            u32 read();

            // Set or clear only the masked bits.
            // Note: Mode flag '1' = Output, '0' = Input
            void mode_clr(u32 mask);
            void mode_set(u32 mask);
            void out_clr(u32 mask);
            void out_set(u32 mask);

        protected:
            satcat5::cfg::Register m_reg;
        };
    }
}
