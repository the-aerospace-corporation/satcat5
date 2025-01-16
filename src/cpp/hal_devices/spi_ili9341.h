//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Display device driver for the ILI9341
//
// The ILI9341 is an ASIC for driving 320x240 TFT LCD displays.
// It uses an SPI interface to update an internal frame buffer.
// (Other interface options are not supported by this driver.)
//
// The ILI9341 ASIC is used in several off-the-shelf display modules:
//  * Adafruit 2.8" display: https://www.adafruit.com/products/1651
//  * Adafruit 2.8" display: https://www.adafruit.com/product/1770
//  * Adafruit 2.4" display: https://www.adafruit.com/product/2478
//  * Adafruit 2.4" display: https://www.adafruit.com/product/3315
//
// This driver supports all API methods, including scrolling viewports.
// Due to the limited SPI bandwidth, a complete screen refresh takes at
// least 122 msec.  As a result, this gui::Display driver must always be
// used with a buffered gui::Canvas object.
//
// The SPI controller is required to drive the "DCX" pin.  The ILI9341
// uses this to distinguish commands from data, deasserting DCX for the
// first byte in each SPI transaction.
//
// The complete ISI9341 datasheet can be found here:
//  http://www.adafruit.com/datasheets/ILI9341.pdf
//
// Startup sequence and color definitions are adapted from the Adafruit
// ILI9341 Arduino Library, which uses the MIT license:
//  https://github.com/adafruit/Adafruit_ILI9341
//

#pragma once

#include <satcat5/cfg_spi.h>
#include <satcat5/gui_display.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace device {
        namespace spi {
            class Ili9341
                : public satcat5::poll::Timer
                , public satcat5::gui::Display
                , public satcat5::cfg::SpiEventListener
            {
            public:
                // Constants for the MADCTL register (Section 8.2.29)
                // This sets the panel type and panel rotation.
                static constexpr u8
                    MADCTL_MY   = 0x80,
                    MADCTL_MX   = 0x40,
                    MADCTL_MV   = 0x20,
                    MADCTL_ML   = 0x10,
                    MADCTL_BGR  = 0x08,
                    MADCTL_MH   = 0x04;

                // Adafruit panels all use BGR mode with MH = 0.
                // Use the MX, MY, and MV bits to set orientation.
                static constexpr u8
                    ADAFRUIT_ROT0   = MADCTL_BGR | MADCTL_MX,
                    ADAFRUIT_ROT90  = MADCTL_BGR | MADCTL_MV,
                    ADAFRUIT_ROT180 = MADCTL_BGR | MADCTL_MY,
                    ADAFRUIT_ROT270 = MADCTL_BGR | MADCTL_MX | MADCTL_MY | MADCTL_MV;

                // Constructor links to the specified SPI interface.
                // SPI rate is controlled by parent, recommend 10 Mbps.
                // A separate GPO pin is required for the D/CX signal.
                Ili9341(
                    satcat5::cfg::SpiGeneric* spi, u8 devidx,   // SPI interface
                    u8 madctl = ADAFRUIT_ROT0);                 // LCD configuration

                // Busy with initialization or a previous command?
                bool busy() const;

                // Invert entire display.
                // (Returns true if command was accepted.)
                bool invert(bool inv);

                // Software reset.
                void reset();

                // Current scroll position.
                inline u16 scroll_pos() const {return m_scroll;}

                // Configure the scrolling viewport:
                //  * Rows above above "top" are fixed.
                //  * Next "size" rows enable scrolling.
                //  * Any remaining rows are also fixed.
                // Note: This feature can only be used if MADCTL_MV = 0.
                bool viewport(u16 top, u16 size);

                // Definitions for 16-bit color mode:
                static constexpr u16            //   R    G    B
                    COLOR_BLACK     = 0x0000,   //   0,   0,   0
                    COLOR_NAVY      = 0x000F,   //   0,   0, 123
                    COLOR_DARKGREEN = 0x03E0,   //   0, 125,   0
                    COLOR_DARKCYAN  = 0x03EF,   //   0, 125, 123
                    COLOR_MAROON    = 0x7800,   // 123,   0,   0
                    COLOR_PURPLE    = 0x780F,   // 123,   0, 123
                    COLOR_OLIVE     = 0x7BE0,   // 123, 125,   0
                    COLOR_LIGHTGREY = 0xC618,   // 198, 195, 198
                    COLOR_DARKGREY  = 0x7BEF,   // 123, 125, 123
                    COLOR_BLUE      = 0x001F,   //   0,   0, 255
                    COLOR_GREEN     = 0x07E0,   //   0, 255,   0
                    COLOR_CYAN      = 0x07FF,   //   0, 255, 255
                    COLOR_RED       = 0xF800,   // 255,   0,   0
                    COLOR_MAGENTA   = 0xF81F,   // 255,   0, 255
                    COLOR_YELLOW    = 0xFFE0,   // 255, 255,   0
                    COLOR_WHITE     = 0xFFFF,   // 255, 255, 255
                    COLOR_ORANGE    = 0xFD20,   // 255, 165,   0
                    COLOR_GRELLOW   = 0xAFE5,   // 173, 255,  41
                    COLOR_PINK      = 0xFC18;   // 255, 130, 198

                // Recommended colors for dark theme (white text on a dark
                // background) and light theme (black text on white):
                static constexpr satcat5::gui::LogColors DARK_THEME = {
                    COLOR_BLACK,        COLOR_LIGHTGREY,    // Text
                    COLOR_BLACK,        COLOR_RED,          // Error
                    COLOR_BLACK,        COLOR_ORANGE,       // Warning
                    COLOR_BLACK,        COLOR_CYAN,         // Info
                    COLOR_BLACK,        COLOR_BLUE};        // Debug
                static constexpr satcat5::gui::LogColors LIGHT_THEME = {
                    COLOR_WHITE,        COLOR_DARKGREY,     // Text
                    COLOR_RED,          COLOR_BLACK,        // Error
                    COLOR_ORANGE,       COLOR_BLACK,        // Warning
                    COLOR_LIGHTGREY,    COLOR_BLACK,        // Info
                    COLOR_LIGHTGREY,    COLOR_BLACK};       // Debug

            protected:
                // Required event handlers from parent classes.
                bool draw(
                    const satcat5::gui::Cursor& cursor,
                    const satcat5::gui::DrawCmd& cmd) override;
                bool scroll(s16 rows) override;
                void spi_done(unsigned nread, const u8* rbytes) override;
                void timer_event() override;

                // Internal event handlers.
                bool in_viewport(u16 row) const;
                void draw_next();
                void init_next();
                bool spi_cmd(u8 len, const u8* cmd, Ili9341* callback);
                bool spi_madctl();
                bool spi_vscrdef();
                void try_twidth(u16 width);

                // Internal state.
                satcat5::cfg::SpiGeneric* const m_spi;
                satcat5::gui::Cursor m_cursor;
                satcat5::gui::DrawCmd m_draw_cmd;
                const u8 m_devidx, m_madctl;
                u16 m_init_step, m_scroll, m_viewtop, m_viewsize;
                u16 m_draw_step, m_draw_done, m_tile_col, m_tile_row, m_tile_width, m_tile_height;
            };
        }
    }
}
