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

#include <satcat5/cfgbus_text_lcd.h>

using satcat5::cfg::TextLcd;
using satcat5::cfg::LogToLcd;

TextLcd::TextLcd(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_ctrl(cfg->get_register(devaddr, regaddr))
{
    clear();
}

void TextLcd::clear()
{
    // Send the "reset" opcode.
    *m_ctrl = (1u << 31);
}

void TextLcd::write(const char* msg)
{
    // Copy each character until we reach a null terminator.
    // Skip over UTF-8 codepoints outside the basic ASCII range.
    while (*msg) {
        u8 tmp = (unsigned char)(*msg);
        if (tmp < 128) *m_ctrl = (u32)tmp;
        ++msg;
    }
}

LogToLcd::LogToLcd(satcat5::cfg::TextLcd* lcd)
    : m_lcd(lcd)
{
    // Nothing else to initialize.
}

void LogToLcd::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    // Space is limited, so use a very short label.
    const char* lbl = 0;
    if (priority >= satcat5::log::ERROR)        lbl = "Err: ";
    else if (priority >= satcat5::log::WARNING) lbl = "Wrn: ";
    else if (priority >= satcat5::log::INFO)    lbl = "Inf: ";
    else                                        lbl = "Dbg: ";

    // LCD will concatenate the message automatically.
    m_lcd->write(lbl);
    m_lcd->write(msg);
    m_lcd->write("\n");
}
