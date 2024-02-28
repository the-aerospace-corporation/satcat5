//////////////////////////////////////////////////////////////////////////
// Copyright 2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
