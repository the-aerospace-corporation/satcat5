//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation
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
// ConfigBus-controlled PTP reference counter (ptp_counter_gen.vhd)
//
// The PTP reference counter can operate in free-running mode, or as a
// software-adjustable NCO.  This file is the driver for the latter case.
//

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {
        class PtpReference {
        public:
            // PtpReference is just a thin-wrapper for its control register.
            PtpReference(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr = satcat5::cfg::REGADDR_ANY)
                : m_reg(cfg->get_register(devaddr, regaddr)) {}

            // Read or write the frequency offset, in units of N / 2^32
            // nanoseconds per output clock.  Since most references operate
            // at 10 MHz, one LSB is about 0.002 nanoseconds per second.
            inline s32 get()            {return (s32)*m_reg;}
            inline void set(s32 dt)     {*m_reg = (u32)dt;}

        protected:
            satcat5::cfg::Register m_reg;   // Base control register
        };
    }
}
