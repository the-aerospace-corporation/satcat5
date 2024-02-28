//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
