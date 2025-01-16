//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/gui_display.h>

using satcat5::gui::Canvas;
using satcat5::gui::Cursor;
using satcat5::gui::Display;
using satcat5::gui::DrawArg;
using satcat5::gui::DrawCmd;
using satcat5::gui::Font8x8;
using satcat5::gui::Font16x16;
using satcat5::gui::Font32x32;
using satcat5::gui::Icon8x8;
using satcat5::gui::Icon16x16;
using satcat5::gui::Icon32x32;
using satcat5::gui::LogColors;
using satcat5::gui::LogToDisplay;

// Macros for each DrawArg format.
// (Disable false-alarm CppCheck warnings for unused union variables.)
inline constexpr DrawArg arg_ptr(const void* x) {
    return DrawArg{.ptr = x};       // cpplint-suppress unreadVariable
}
inline constexpr DrawArg arg_color(u32 x) {
    return DrawArg{.color = x};     // cpplint-suppress unreadVariable
}
inline constexpr DrawArg arg_count(u32 x) {
    return DrawArg{.count = x};     // cpplint-suppress unreadVariable
}
inline constexpr DrawArg arg_rc(u16 r, u16 c) {
    return DrawArg{.rc = {r,c}};    // cpplint-suppress unreadVariable
}
inline constexpr DrawArg arg_scroll(s16 x) {
    return DrawArg{.scroll = x};    // cpplint-suppress unreadVariable
}

// Define DrawCmd opcodes:
static constexpr u8
    CMD_NONE        = 0,    // No-op
    CMD_COLOR_FG    = 1,    // Foreground color
    CMD_COLOR_BG    = 2,    // Background color
    CMD_ICON8       = 3,    // Icon8x8
    CMD_ICON16      = 4,    // Icon16x16
    CMD_ICON32      = 5,    // Icon32x32
    CMD_MOVE        = 6,    // Move cursor
    CMD_RECT        = 7,    // Solid rectangle
    CMD_SCROLL      = 8;    // Scroll viewport

bool DrawCmd::rc(u16 r, u16 c) const {
    // For this DrawCmd's update region, is the pixel at (r,c) the
    // foreground color (true) or the background color (false)?
    //  * Solid rectangle (CMD_RECT):
    //    The entire update region uses the same color.
    //    Use m_arg1 to select the true/false pixel value.
    //  * Icon (CMD_ICON8, CMD_ICON16, CMD_ICON32):
    //    Query the underlying icon for the true/false pixel value.
    //    Use m_arg1 to set a magnification factor, so we can upscale
    //    an 8x8 icon to fill 16x16 or 24x24 pixels as needed.
    // Note: Text is rendered using a series of icon commands.
    switch (m_opcode) {
    case CMD_RECT:          // Rectangle: Arg1 = Color
        return !!m_arg1;
    case CMD_ICON8:         // Icon: Arg1 = Magnification
        return icon8()->rc(r / m_arg1, c / m_arg1);
    case CMD_ICON16:        // Icon: Arg1 = Magnification
        return icon16()->rc(r / m_arg1, c / m_arg1);
    case CMD_ICON32:        // Icon: Arg1 = Magnification
        return icon32()->rc(r / m_arg1, c / m_arg1);
    default:                // All others -> Undefined
        return false;
    }
}

u16 DrawCmd::height() const {
    switch (m_opcode) {
    case CMD_RECT:          // Rectangle: Arg2 = Size (rows, cols)
        return m_arg2.rc[0];
    case CMD_ICON8:         // Icon: Arg1 = Magnification
        return icon8()->h() * m_arg1;
    case CMD_ICON16:        // Icon: Arg1 = Magnification
        return icon16()->h() * m_arg1;
    case CMD_ICON32:        // Icon: Arg1 = Magnification
        return icon32()->h() * m_arg1;
    default:                // All others -> Undefined
        return 0;
    }
}

u16 DrawCmd::width() const {
    switch (m_opcode) {
    case CMD_RECT:          // Rectangle: Arg2 = Size (rows, cols)
        return m_arg2.rc[1];
    case CMD_ICON8:         // Icon: Arg1 = Magnification
        return icon8()->w() * m_arg1;
    case CMD_ICON16:        // Icon: Arg1 = Magnification
        return icon16()->w() * m_arg1;
    case CMD_ICON32:        // Icon: Arg1 = Magnification
        return icon32()->w() * m_arg1;
    default:                // All others -> Undefined
        return 0;
    }
}

void DrawCmd::update(Cursor& cursor) const {
    switch (m_opcode) {
    case CMD_COLOR_FG:
        cursor.fg = m_arg2.color;
        break;
    case CMD_COLOR_BG:
        cursor.bg = m_arg2.color;
        break;
    case CMD_MOVE:
        cursor.r = m_arg2.rc[0];
        cursor.c = m_arg2.rc[1];
        break;
    default:
        cursor.c += width();
    }
}

Canvas::Canvas(Display* display)
    : m_display(display)
    , m_cursor_draw{0, 0, 0, 0}
    , m_cursor_user{0, 0, 0, 0}
    , m_buffer(0, 0)
{
    // Nothing else to initialize.
}

Canvas::Canvas(Display* display, u8* buffer, unsigned bsize)
    : m_display(display)
    , m_cursor_draw{0, 0, 0, 0}
    , m_cursor_user{0, 0, 0, 0}
    , m_buffer(buffer, bsize)
{
    // Nothing else to initialize.
}

bool Canvas::color_fg(u32 color) {
    if (m_cursor_user.fg == color) return true;         // Skip unchanged
    DrawCmd cmd(CMD_COLOR_FG, 0, arg_color(color));
    return enqueue(cmd) && finalize();
}

bool Canvas::color_bg(u32 color) {
    if (m_cursor_user.bg == color) return true;         // Skip unchanged
    DrawCmd cmd(CMD_COLOR_BG, 0, arg_color(color));
    return enqueue(cmd) && finalize();
}

bool Canvas::cursor(u16 r, u16 c) {
    if (m_cursor_user.r == r && m_cursor_user.c == c) return true;
    DrawCmd cmd(CMD_MOVE, 0, arg_rc(r, c));
    return enqueue(cmd) && finalize();
}

bool Canvas::clear(u32 color) {
    return color_bg(color) && cursor(0, 0)
        && draw_rect(m_display->height(), m_display->width(), false);
}

bool Canvas::draw_icon(const Icon8x8* icon, u8 mag) {
    DrawCmd cmd(CMD_ICON8, mag, arg_ptr(icon));
    return enqueue(cmd) && finalize();
}

bool Canvas::draw_icon(const Icon16x16* icon, u8 mag) {
    DrawCmd cmd(CMD_ICON16, mag, arg_ptr(icon));
    return enqueue(cmd) && finalize();
}

bool Canvas::draw_icon(const Icon32x32* icon, u8 mag) {
    DrawCmd cmd(CMD_ICON32, mag, arg_ptr(icon));
    return enqueue(cmd) && finalize();
}

bool Canvas::draw_rect(u16 h, u16 w, bool fg) {
    DrawCmd cmd(CMD_RECT, fg ? 1 : 0, arg_rc(h, w));
    return enqueue(cmd) && finalize();
}

u16 Canvas::draw_text(const char* msg, const Font8x8& font, u8 mag) {
    u16 rows = raw_text(msg, font, mag);
    return (draw_eol(8*mag, rows) && finalize()) ? rows : 0;
}

u16 Canvas::draw_text(const char* msg, const Font16x16& font, u8 mag) {
    u16 rows = raw_text(msg, font, mag);
    return (draw_eol(16*mag, rows) && finalize()) ? rows : 0;
}

u16 Canvas::draw_text(const char* msg, const Font32x32& font, u8 mag) {
    u16 rows = raw_text(msg, font, mag);
    return (draw_eol(32*mag, rows) && finalize()) ? rows : 0;
}

u16 Canvas::raw_text(const char* msg, const Font8x8& font, u8 mag) {
    u16 rows = 0;
    while (*msg) {
        DrawCmd cmd(CMD_ICON8, mag, arg_ptr(font.icon(*msg)));
        if (!draw_char(*msg++, cmd, rows)) return 0;
    }
    return rows;
}

u16 Canvas::raw_text(const char* msg, const Font16x16& font, u8 mag) {
    u16 rows = 0;
    while (*msg) {
        DrawCmd cmd(CMD_ICON16, mag, arg_ptr(font.icon(*msg)));
        if (!draw_char(*msg++, cmd, rows)) return 0;
    }
    return rows;
}

u16 Canvas::raw_text(const char* msg, const Font32x32& font, u8 mag) {
    u16 rows = 0;
    while (*msg) {
        DrawCmd cmd(CMD_ICON32, mag, arg_ptr(font.icon(*msg)));
        if (!draw_char(*msg++, cmd, rows)) return 0;
    }
    return rows;
}

bool Canvas::scroll(s16 rows) {
    DrawCmd cmd(CMD_SCROLL, 0, arg_scroll(rows));
    return enqueue(cmd) && finalize();
}

bool Canvas::cmd_retry() {
    // Attempt or re-attempt execution of m_cmd_retry;
    bool done = execute(m_cmd_retry);
    if (done) m_cmd_retry.m_opcode = CMD_NONE;          // Mark as executed?
    if (!done) request_poll();                          // Try again later?
    return done;                                        // Ready to proceed?
}

// Draw a single character at the current cursor position,
// plus special handling for newline, tab, etc.
bool Canvas::draw_char(char ch, const DrawCmd& cmd, u16& total_rows) {
    bool ok = true;
    // Calculate remaining columns in this row.
    u16 rem_cols = width() - m_cursor_user.c;
    // If we've reached end-of-line, clear remainder and move cursor.
    if ((ch == '\n') || (cmd.width() > rem_cols))
        ok = ok && draw_eol(cmd.height(), total_rows);
    // Render each printable character, special handling for others.
    if (cmd.m_arg2.ptr) {
        ok = ok && enqueue(cmd);
    } else if (ch == '\t') {
        DrawCmd tab(CMD_RECT, 0, arg_rc(cmd.height(), cmd.width()));
        ok = ok && enqueue(tab);
    }
    return ok;
}

bool Canvas::draw_eol(u16 height, u16& total_rows) {
    // End-of-line: Fill remainder of line and move cursor position.
    total_rows += height;
    u16 rem_cols = width() - m_cursor_user.c;
    DrawCmd fill(CMD_RECT, 0, arg_rc(height, rem_cols));
    DrawCmd wrap(CMD_MOVE, 0, arg_rc(m_cursor_user.r + height, 0));
    return (!rem_cols || enqueue(fill)) && enqueue(wrap);
}

bool Canvas::enqueue(const DrawCmd& cmd) {
    // Immediate mode: Commands go directly to the display device.
    // Buffered mode: Write data to the queue instead.
    bool ok = true;
    if (!m_buffer.get_buff_size()) ok = execute(cmd);
    else m_buffer.write_bytes(sizeof(DrawCmd), &cmd);
    if (ok) cmd.update(m_cursor_user);
    return true;
}

bool Canvas::execute(const DrawCmd& cmd) {
    // Pass this command to the display device?
    bool ok = true;
    if (cmd.m_opcode == CMD_SCROLL) {
        ok = m_display->scroll(cmd.m_arg2.scroll);
    } else if (cmd.width() && cmd.height()) {
        ok = m_display->draw(m_cursor_draw, cmd);
    }

    // Update cursor state.
    if (ok) cmd.update(m_cursor_draw);
    return ok;
}

bool Canvas::finalize() {
    if (!m_buffer.get_buff_size()) return true;         // Immediate mode
    bool ok = m_buffer.write_finalize();                // Buffered mode
    if (ok) request_poll();
    return ok;
}

void Canvas::poll_demand() {
    // Retry previous command if applicable, then pull new commands from queue.
    while (cmd_retry() && m_buffer.get_read_ready() >= sizeof(DrawCmd)) {
        m_buffer.read_bytes(sizeof(DrawCmd), &m_cmd_retry);
    }
}

LogToDisplay::LogToDisplay(
    Canvas* canvas, const LogColors& colors,
    u16 row_min, u16 row_count)
    : m_canvas(canvas)
    , m_colors(colors)
    , m_row_min(row_min)
    , m_row_count(row_count ? row_count : (canvas->height() - row_min))
    , m_row_next(0)
{
    // Nothing else to initialize.
    // TODO: Allow user to set the font?
}

// Implement the required API from log::EventHandler.
void LogToDisplay::log_event(s8 priority, unsigned nbytes, const char* msg) {
    // Set cursor position to the start of the current row.
    m_canvas->cursor(m_row_next + m_row_min, 0);

    // Write the DEBUG / INFO / WARN / ERROR banner in the designated color.
    if (priority <= satcat5::log::DEBUG) {
        m_canvas->color_bg(m_colors.bg_debug);
        m_canvas->color_fg(m_colors.fg_debug);
        m_canvas->raw_text("DEBUG: ");
    } else if (priority <= satcat5::log::INFO) {
        m_canvas->color_bg(m_colors.bg_info);
        m_canvas->color_fg(m_colors.fg_info);
        m_canvas->raw_text("INFO:  ");
    } else if (priority <= satcat5::log::WARNING) {
        m_canvas->color_fg(m_colors.fg_warn);
        m_canvas->color_bg(m_colors.bg_warn);
        m_canvas->raw_text("WARN:  ");
    } else {
        m_canvas->color_bg(m_colors.bg_error);
        m_canvas->color_fg(m_colors.fg_error);
        m_canvas->raw_text("ERROR: ");
    }

    // Write the rest of the log message.
    m_canvas->color_bg(m_colors.bg_text);
    m_canvas->color_fg(m_colors.fg_text);
    u16 new_rows = m_canvas->draw_text(msg);

    // Scroll and update write position for next time.
    m_canvas->scroll(new_rows);
    m_row_next = (m_row_next + new_rows) % m_row_count;
}
