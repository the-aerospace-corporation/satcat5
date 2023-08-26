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
// This file defines a text-rendering utility for the SSD1306 OLED display,
// which is controlled over I2C.  It accepts most regular ASCII characters,
// with anything else rendered as an empty space.
//

#pragma once

#include <satcat5/cfg_i2c.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace device {
        namespace i2c {
            class Ssd1306 : public satcat5::poll::Timer
            {
            public:
                // Constructor links to the specified I2C bus.
                explicit Ssd1306(satcat5::cfg::I2cGeneric* i2c);

                // Reset display and set initial configuration.
                void reset();

                // Display a null-terminated message string.
                // Returns true if successful, false if already busy.
                bool display(const char* text);

            protected:
                void timer_event() override;
                bool next();

                // Internal state:
                satcat5::cfg::I2cGeneric* const m_i2c;
                u8 m_step;          // Current step (initialization)
                u8 m_page;          // Index of SSD1306 frame buffer
                u8 m_text[64];      // Buffer 16 columns x 4 rows
            };
        }
    }
}
