//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! "Display" and "Canvas" API for rendering text and graphics
//!
//!\details
//! The Display API is the parent class for a user-defined display device
//! driver.  Child classes implement the "draw(...)" method to accept each
//! each new command.  An optional "scroll(...)" method can also be used for
//! moving a predefined viewport, if the display supports such a feature.
//!
//! The Canvas class provides user access for generating individual commands.
//! It provides methods for drawing icons, rectangles, text, etc.  Operations
//! may be executed immediately or through a buffer.  The latter is useful
//! for I2C and SPI displays with limited bandwidth for updates.
//!
//! The DrawCmd ("draw command") class defines single primitive command.
//! Most functions paste data onto a rectangular pixel region, suitable
//! for most generic display devices.  Each operation is relative to a
//! "write cursor" that defines location and color parameters.

#pragma once
#include <satcat5/gui_icons.h>
#include <satcat5/log.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace gui {
        //! Cursor object tracks position and foreground/background colors.
        struct Cursor {
            u16 r;      // Row coordinate (0 = top)
            u16 c;      // Column coordinate (0 = left)
            u32 fg;     // Foreground color (format defined by display)
            u32 bg;     // Background color (format defined by display)
        };

        //! Argument for a draw command (see below).
        union DrawArg {
            const void* ptr;        // Pointer to an icon or other object.
            u32 color;              // Display-specific color argument
            s16 scroll;             // Scrolling parameter (signed)
            u32 count;              // Any other counter
            u16 rc[2];              // A row and column (coordinate or size)
        };

        //! Each "draw command" updates a rectangular region of pixels.
        //! These objects are also used for internal state changes, but
        //! only draw and scroll commands are delivered to the Display.
        //! \see gui_display.h, gui::Canvas, gui::Display.
        class DrawCmd {
        public:
            //! Construct an empty command.
            constexpr DrawCmd()
                : m_opcode(0), m_arg1(0), m_arg2{.ptr = 0} {}
            //! Construct a specific command.
            constexpr DrawCmd(u8 opcode, u8 arg1, const DrawArg& arg2)
                : m_opcode(opcode), m_arg1(arg1), m_arg2(arg2) {}

            //! Get the new pixel value at the designated row and column.
            //! Coordinates are relative to the current Cursor position.
            //! Return true = foreground, false = background.
            bool rc(u16 r, u16 c) const;

            //! Size of the rectangular update region.
            //!@{
            u16 height() const;
            u16 width() const;
            //!@}

        protected:
            friend satcat5::gui::Canvas;

            // Shortcuts for typecasting the "m_arg2.ptr" argument.
            inline const satcat5::gui::Icon8x8* icon8() const
                { return (const Icon8x8*)m_arg2.ptr; }
            inline const satcat5::gui::Icon16x16* icon16() const
                { return (const Icon16x16*)m_arg2.ptr; }
            inline const satcat5::gui::Icon32x32* icon32() const
                { return (const Icon32x32*)m_arg2.ptr; }

            //! Update cursor-state automatically for easier chaining.
            void update(Cursor& cursor) const;

            u8 m_opcode;                    // Command opcode (e.g., "draw icon")
            u8 m_arg1;                      // Argument 1 (varies by opcode)
            satcat5::gui::DrawArg m_arg2;   // Argument 2 (varies by opcode)
        };

        //! Required API for display devices.
        //! The generic Display class sets the API for user-defined objects
        //! that executes each DrawCmd, by overriding draw() and scroll().
        //! Boolean methods return true if the command was executed or
        //! discarded, or false if the device is busy (i.e., retry later).
        class Display {
        public:
            //! Draw pixels to the screen at the designated location.
            //! Child class MUST implement this method.
            //! Returns false if the command should be repeated.
            virtual bool draw(
                const satcat5::gui::Cursor& cursor,
                const satcat5::gui::DrawCmd& cmd) = 0;

            //! Optional: Advance the predefined viewport by N pixels.
            //! Positive values scroll down, wrapping upper rows to the
            //! bottom of viewport.  Negative values scroll up.
            //! Child class MAY implement this method if applicable.
            //! Returns false if the command should be repeated.
            virtual bool scroll(s16 rows)   { return true; }

            //! Total size of the display, in pixels.
            //!@{
            inline u16 height() const       { return m_height; }
            inline u16 width() const        { return m_width; }
            //!@}

        protected:
            //! Constructor sets the size of this display in pixels.
            //! (Only the child can access the constructor and destructor.)
            Display(u16 h, u16 w) : m_height(h), m_width(w) {}
            ~Display() {}

            //! Total size of the display, in pixels.
            //! The child must set these parameters in the constructor.
            const u16 m_height, m_width;
        };

        //! User-facing interface for drawing graphical elements on a screen.
        //! \see gui_display.h, gui::Display, gui::DrawCmd.
        class Canvas : public satcat5::poll::OnDemand {
        public:
            //! Link this object to a Display in *immediate mode*.
            //! Preferred when draw commands can always be executed promptly.
            explicit Canvas(satcat5::gui::Display* display);

            //! Link this object to a Display in *buffered mode*.
            //! Preferred when draw commands may take some time to execute.
            Canvas(satcat5::gui::Display* display, u8* buffer, unsigned bsize);

            //! Set foreground color for subsequent commands.
            bool color_fg(u32 color);
            //! Set background color for subsequent commands.
            bool color_bg(u32 color);
            //! Set cursor position for subsequent commands.
            bool cursor(u16 r, u16 c);

            //! Clear the entire display contents.
            bool clear(u32 color);

            //! Draw icon with the designated location and color.
            //! Optionally specify magnification factor to increase size.
            //! Note: Only a pointer to the icon is copied to the queue;
            //!  do not pass a reference to a stack-allocated object.
            //!@{
            bool draw_icon(const satcat5::gui::Icon8x8* icon, u8 mag = 1);
            bool draw_icon(const satcat5::gui::Icon16x16* icon, u8 mag = 1);
            bool draw_icon(const satcat5::gui::Icon32x32* icon, u8 mag = 1);
            //!@}

            //! Draw a solid rectangle using the specified color.
            //! The upper-left corner is the current cursor position.
            //! This function can be used to draw horizontal lines (h = 1),
            //! draw vertical lines (w = 1), or clear screen contents.
            bool draw_rect(u16 h, u16 w, bool fg = true);

            //! Draw a full line of text with the designated font.
            //! Same as raw_text(...) + draw_rect(...) to clear remainder of row.
            //!@{
            u16 draw_text(const char* msg,
                const satcat5::gui::Font8x8& font = BASIC_FONT, u8 mag = 1);
            u16 draw_text(const char* msg,
                const satcat5::gui::Font16x16& font, u8 mag = 1);
            u16 draw_text(const char* msg,
                const satcat5::gui::Font32x32& font, u8 mag = 1);
            //!@}

            //! Draw a partial line of text with the designated font.
            //! Optionally specify magnification factor to increase size.
            //! Long strings will auto-wrap to column zero of the next row.
            //! Note: String contents are internally translated into a series of
            //!  Icon pointers, one per letter.  Therefore, the "msg" input may
            //!  be ephemeral, but the "font" object must have a longer lifetime.
            //! Note: Whitespace characters are processed (space, newline, tab),
            //!  but non-printable characters (e.g., UTF-8 emoji) are ignored.
            //!@{
            u16 raw_text(const char* msg,
                const satcat5::gui::Font8x8& font = BASIC_FONT, u8 mag = 1);
            u16 raw_text(const char* msg,
                const satcat5::gui::Font16x16& font, u8 mag = 1);
            u16 raw_text(const char* msg,
                const satcat5::gui::Font32x32& font, u8 mag = 1);
            //!@}

            //! On supported displays, scroll the designated scrollable window.
            //! For display objects that support the scroll() command, advance
            //! the preconfigured viewport by the specified number of pixels.
            bool scroll(s16 rows);

            // Other accessors.
            inline const satcat5::gui::Cursor& cursor() const
                { return m_cursor_draw; }
            inline satcat5::gui::Display* display()
                { return m_display; }
            inline u16 height() const
                { return m_display->height(); }
            inline u16 width() const
                { return m_display->width(); }

        protected:
            bool cmd_retry();
            bool draw_char(char ch, const satcat5::gui::DrawCmd& cmd, u16& total_rows);
            bool draw_eol(u16 height, u16& total_rows);
            bool enqueue(const satcat5::gui::DrawCmd& cmd);
            bool execute(const satcat5::gui::DrawCmd& cmd);
            bool finalize();
            void poll_demand() override;

            satcat5::gui::Display* const m_display; // Pointer to display device.
            satcat5::gui::Cursor m_cursor_draw;     // Device draw position
            satcat5::gui::Cursor m_cursor_user;     // User-API draw position
            satcat5::gui::DrawCmd m_cmd_retry;      // Retry current command?
            satcat5::io::PacketBuffer m_buffer;     // Optional command queue
        };

        //! Color parameters for the LogToDisplay class.
        //! Display adapters should provide a reasonable default set.
        struct LogColors {
            u32 bg_text,  fg_text;
            u32 bg_error, fg_error;
            u32 bg_warn,  fg_warn;
            u32 bg_info,  fg_info;
            u32 bg_debug, fg_debug;
        };

        //! Service for forwarding Log events to a display adapter.
        class LogToDisplay final : public satcat5::log::EventHandler {
        public:
            //! Link this log service to the designated display/canvas.
            //! By default, logs are written from top-to-bottom using the
            //! entire display as a circular buffer.  Alternately, use the
            //! row_min and row_count parameters to restrict the viewport.
            LogToDisplay(
                satcat5::gui::Canvas* canvas,
                const satcat5::gui::LogColors& colors,
                u16 row_min = 0, u16 row_count = 0);

            //! Implement the required API from log::EventHandler.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

            //! Adjust color parameters.
            inline void set_colors(const satcat5::gui::LogColors& colors)
                { m_colors = colors; }

        protected:
            satcat5::gui::Canvas* const m_canvas;
            satcat5::gui::LogColors m_colors;
            const u16 m_row_min, m_row_count;
            u16 m_row_next;
        };
    }
}
