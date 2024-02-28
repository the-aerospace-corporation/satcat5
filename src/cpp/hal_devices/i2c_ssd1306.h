//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
