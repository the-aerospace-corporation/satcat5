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
// Interface driver for the cfgbus_uart block

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/log.h>

namespace satcat5 {
    namespace cfg {
        // Device driver for a 2x16 character LCD screen.
        class TextLcd
        {
        public:
            // Initialize this UART and link to a specific register bank.
            TextLcd(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr = 0);

            // Reset and clear display.
            void clear();

            // Write a string to the display (max 32 characters).
            void write(const char* msg);

        private:
            // Interface control register.
            satcat5::cfg::Register m_ctrl;
        };

        // Adapter for connecting Log messages to a TextLcd object.
        class LogToLcd final : public satcat5::log::EventHandler {
        public:
            explicit LogToLcd(satcat5::cfg::TextLcd* lcd);
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;
        protected:
            satcat5::cfg::TextLcd* const m_lcd;
        };
    }
}
