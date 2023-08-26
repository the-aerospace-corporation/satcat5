
//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {

        // Memory-mapped local ConfigBus.
        class ConfigBusPosix
            : public satcat5::cfg::ConfigBusMmap
        {
        public:
            // Constructor accepts the physical base address for the memory-map interface,
            // and the interrupt-index for the shared ConfigBus interrupt, if any.
            ConfigBusPosix(void* base_addr, int irq);
            ~ConfigBusPosix();

        protected:
            // file descriptor for /dev/mem which provide access to physical
            // memory on posix systems
            int m_fd = 0;
        };
    }
}
