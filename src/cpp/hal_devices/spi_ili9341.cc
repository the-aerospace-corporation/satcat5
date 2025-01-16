//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_devices/spi_ili9341.h>
#include <satcat5/cfgbus_spi.h>
#include <satcat5/utils.h>

using satcat5::cfg::SpiGeneric;
using satcat5::device::spi::Ili9341;
using satcat5::gui::Cursor;
using satcat5::gui::Display;
using satcat5::gui::DrawCmd;
using satcat5::util::div_ceil;
using satcat5::util::min_u16;
using satcat5::util::write_be_u16;

// Workaround to ensure C++11 allocates static constants.
// See also: https://stackoverflow.com/questions/8452952/
constexpr satcat5::gui::LogColors Ili9341::DARK_THEME;
constexpr satcat5::gui::LogColors Ili9341::LIGHT_THEME;

// Set the burst size for transfer of pixel data.
#ifndef SATCAT5_ILI9341_BURST
#define SATCAT5_ILI9341_BURST 32
#endif

// Convert burst size from pixels to bytes, including overhead.
// Each burst has a fixed overhead for setup commands, so longer bursts
// are more efficient, up to overflow limit of the SPI transmit buffer.
// (Noting that each SPI byte requires two bytes in the working buffer.)
// Default burst of 32 pixels = 75 bytes yields an efficiency of 85%.
static constexpr u16 BURST_PIXELS = SATCAT5_ILI9341_BURST;
static constexpr u16 BURST_CADDR  = 5;
static constexpr u16 BURST_PADDR  = 5;
static constexpr u16 BURST_RAMWR  = 1 + 2*BURST_PIXELS;
static constexpr u16 BURST_BYTES  = BURST_CADDR + BURST_PADDR + BURST_RAMWR;
static_assert(2*BURST_BYTES <= SATCAT5_SPI_TXBUFF);

// Native size is 240 cols x 320 rows before rotation.
// Rotation parameters may swap effective width and height.
static constexpr u16 TFT_WIDTH  = 240;
static constexpr u16 TFT_HEIGHT = 320;

inline constexpr u16 effective_height(u8 madctl)
    { return (madctl & Ili9341::MADCTL_MV) ? TFT_WIDTH : TFT_HEIGHT; }
inline constexpr u16 effective_width(u8 madctl)
    { return (madctl & Ili9341::MADCTL_MV) ? TFT_HEIGHT : TFT_WIDTH; }

// ISI9341 command opcodes (Section 8.*):
static constexpr u8     // [Name given in datasheet]
    CMD_NOOP    = 0x00, // No-op (NOP)
    CMD_SWRESET = 0x01, // Software Reset
    CMD_WAKE    = 0x11, // Sleep Out
    CMD_INVOFF  = 0x20, // Display Inversion OFF
    CMD_INVON   = 0x21, // Display inversion ON
    CMD_GAMMA   = 0x26, // Gamma Set
    CMD_DISPON  = 0x29, // Display ON
    CMD_CADDR   = 0x2A, // Column Address Set (CASET)
    CMD_PADDR   = 0x2B, // Page Address Set (PASET)
    CMD_RAMWR   = 0x2C, // Memory Write
    CMD_VSCRDEF = 0x33, // Vertical Scrolling Definition
    CMD_MADCTL  = 0x36, // Memory Access Control
    CMD_VSCRSET = 0x37, // Vertical Scrolling Address
    CMD_PIXFMT  = 0x3A, // COLMOD: Pixel Format Set
    CMD_FRMCTR1 = 0xB1, // Frame Rate Control (In Normal Mode/Full Colors)
    CMD_DFUNCTR = 0xB6, // Display Function Control
    CMD_PWRCTR1 = 0xC0, // Power Control 1
    CMD_PWRCTR2 = 0xC1, // Power Control 2
    CMD_VCMCTR1 = 0xC5, // VCOM Control 1
    CMD_VCMCTR2 = 0xC7, // VCOM Control 2
    CMD_PWRCTRA = 0xCB, // Power Control A
    CMD_PWRCTRB = 0xCF, // Power Control B
    CMD_GMCTRP1 = 0xE0, // Positive Gamma Correction
    CMD_GMCTRN1 = 0xE1, // Negative Gamma Correction
    CMD_DRVTIMA = 0xE8, // Driver Timing Control A
    CMD_DRVTIMB = 0xEA, // Driver Timing Control B
    CMD_PWRSEQ  = 0xED, // Power On Sequence Control
    CMD_UNKNOWN = 0xEF, // (Undocumented command from Adafruit driver)
    CMD_GAMMA3  = 0xF2, // Enable 3-gamma control
    CMD_PUMPCTR = 0xF7; // Pump Ratio Control

// Startup sequence, encoded as a series of length/data pairs.
// Note: Length = 0 indicates a wait command, next argument is delay in msec.
static constexpr u8 STARTUP[] = {
    1,  CMD_SWRESET, 0, 5,   // Command + Wait
    4,  CMD_UNKNOWN, 0x03, 0x80, 0x02,
    4,  CMD_PWRCTRB, 0x00, 0xC1, 0x30,
    5,  CMD_PWRSEQ,  0x64, 0x03, 0x12, 0x81,
    4,  CMD_DRVTIMA, 0x85, 0x00, 0x78,
    6,  CMD_PWRCTRA, 0x39, 0x2C, 0x00, 0x34, 0x02,
    2,  CMD_PUMPCTR, 0x20,
    3,  CMD_DRVTIMB, 0x00, 0x00,
    2,  CMD_PWRCTR1, 0x23,
    2,  CMD_PWRCTR2, 0x10,
    3,  CMD_VCMCTR1, 0x3E, 0x28,
    2,  CMD_VCMCTR2, 0x86,
    2,  CMD_VSCRSET, 0x00,
    2,  CMD_PIXFMT,  0x55,
    3,  CMD_FRMCTR1, 0x00, 0x18,
    4,  CMD_DFUNCTR, 0x08, 0x82, 0x27,
    2,  CMD_GAMMA3,  0x00,
    2,  CMD_GAMMA,   0x01,
    16, CMD_GMCTRP1, 0x0F, 0x31, 0x2B, 0x0C, 0x0E, 0x08, 0x4E, 0xF1, 0x37, 0x07, 0x10, 0x03, 0x0E, 0x09, 0x00,
    16, CMD_GMCTRN1, 0x00, 0x0E, 0x14, 0x03, 0x11, 0x07, 0x31, 0xC1, 0x48, 0x08, 0x0F, 0x0C, 0x31, 0x36, 0x0F,
    1,  CMD_WAKE,    0, 150,   // Command + Wait
    1,  CMD_DISPON,  0, 150};  // Command + Wait

static constexpr unsigned INIT_DONE = sizeof(STARTUP) + 1;

Ili9341::Ili9341(SpiGeneric* spi, u8 devidx, u8 madctl)
    : Display(effective_height(madctl), effective_width(madctl))
    , m_spi(spi)            // Pointer to SPI interface
    , m_cursor{}            // Current draw position & colors
    , m_draw_cmd()          // Active draw command
    , m_devidx(devidx)      // SPI device-index (may be shared)
    , m_madctl(madctl)      // Display config & rotation
    , m_init_step(0)        // Initialization state
    , m_scroll(0)           // Current scroll position
    , m_viewtop(0)          // Scrolling viewport configuration
    , m_viewsize(0)
    , m_draw_step(0)        // Burst index (one burst per tile)
    , m_draw_done(0)        // Number of bursts in this DrawCmd
    , m_tile_col(0)         // Current tile position
    , m_tile_row(0)
    , m_tile_width(0)       // Nominal tile size
    , m_tile_height(0)
{
    // Wait for power-on-reset before initialization.
    timer_once(150);
}

bool Ili9341::busy() const {
    return (m_init_step < INIT_DONE) || (m_draw_step < m_draw_done) || m_spi->busy();
}

bool Ili9341::invert(bool inv) {
    // Attempt to send the invert-on or invert-off command.
    u8 cmd = inv ? CMD_INVON : CMD_INVOFF;
    return spi_cmd(1, &cmd, 0); // No callback
}

void Ili9341::reset() {
    // Issue a software reset and reinitialize.
    m_init_step = 0;
    init_next();
}

bool Ili9341::viewport(u16 top, u16 size) {
    // Vertical scrolling isn't supported if X and Y are swapped.
    // (Scrolling applies only to 320-pixel axis, ignoring the MV bit.)
    if (m_madctl & MADCTL_MV) return false;
    // Reset viewport parameters. If initialization is still running,
    // send command at the end of that process. Otherwise, send it now.
    m_scroll    = 0;
    m_viewtop   = top;
    m_viewsize  = size;
    return (m_init_step < INIT_DONE) || spi_vscrdef();
}

bool Ili9341::draw(const Cursor& cursor, const DrawCmd& cmd) {
    // Are we ready to start a new draw command?
    if (busy()) return false;   // False = Try again later

    // Skip planning if new size matches the previous command.
    bool size_match = (cmd.height() == m_draw_cmd.height())
                   && (cmd.width()  == m_draw_cmd.width());

    // Accept the new command parameters.
    m_cursor    = cursor;
    m_draw_cmd  = cmd;
    m_draw_step = 0;
    m_tile_col  = 0;
    m_tile_row  = 0;

    // Planning phase: Split the draw area into equal-size rectangular tiles,
    // where each tile is a single burst (i.e., area <= BURST_PIXELS).  To
    // minimize overhead, we want to minimize the required number of tiles.
    if (!size_match) {
        // Try every viable tile width to determine optimal size.
        // (This sets m_draw_done, m_tile_width, and m_tile_height.)
        m_draw_done = UINT16_MAX;
        try_twidth(BURST_PIXELS);   // Try 1 x N
        for (u16 w = 1 ; w < BURST_PIXELS/2 ; ++w)
            try_twidth(w);          // Try 2 x N/2, 3 x N/3, ...
    }

    // Start sending the first tile/burst.
    draw_next();
    return true;
}

bool Ili9341::scroll(s16 rows) {
    // Discard scroll commands if the viewport isn't configured.
    if (!m_viewsize) return true;
    // Update the scrolling offset, modulo viewport size.
    u16 tmp = m_scroll + u16(rows);
    if (rows < 0 && tmp >= m_viewsize) tmp += m_viewsize;
    if (rows > 0 && tmp >= m_viewsize) tmp -= m_viewsize;
    // Attempt to send "Vertical Scrolling Start Address" command.
    u8 cmd[3] = {CMD_VSCRSET};
    write_be_u16(cmd + 1, m_viewtop + tmp);
    bool ok = spi_cmd(sizeof(cmd), cmd, 0); // No callback
    // If successful, update scroll position.
    if (ok) m_scroll = tmp;
    return ok;
}

void Ili9341::spi_done(unsigned nread, const u8* rbytes) {
    if (m_init_step < INIT_DONE) init_next();
    else if (m_draw_step < m_draw_done) draw_next();
}

void Ili9341::timer_event() {
    if (m_init_step < INIT_DONE) init_next();
    else if (m_draw_step < m_draw_done) draw_next();
}

bool Ili9341::in_viewport(u16 row) const {
    return (m_viewtop <= row) && (row < m_viewtop + m_viewsize);
}

// Each tile/burst transfers a contiguous burst of pixels:
//  * CMD_CADDR = 5 bytes, set column(s) to be written
//  * CMD_PADDR = 5 bytes, set row(s) to be written
//  * CMD_RAMWR = 1 + 2N bytes, pixel data in raster order
void Ili9341::draw_next() {
    u8 cmd[BURST_BYTES];
    // Are we sending a partial tile?
    u16 tile_width  = min_u16(m_tile_width,  m_draw_cmd.width()  - m_tile_col);
    u16 tile_height = min_u16(m_tile_height, m_draw_cmd.height() - m_tile_row);
    // Construct the CADDR command (first 5 bytes).
    cmd[0] = CMD_CADDR;
    write_be_u16(cmd + 1, m_cursor.c + m_tile_col);
    write_be_u16(cmd + 3, m_cursor.c + m_tile_col + tile_width - 1);
    // Construct the PADDR command (next 5 bytes).
    cmd[5] = CMD_PADDR;
    write_be_u16(cmd + 6, m_cursor.r + m_tile_row);
    write_be_u16(cmd + 8, m_cursor.r + m_tile_row + tile_height - 1);
    // Construct and send the RAMWR command.
    cmd[10] = CMD_RAMWR;
    unsigned wrpos = 11;
    for (u16 r = 0 ; r < tile_height ; ++r) {
        for (u16 c = 0 ; c < tile_width ; ++c) {
            u32 color = m_draw_cmd.rc(m_tile_row + r, m_tile_col + c)
                ? m_cursor.fg : m_cursor.bg;
            write_be_u16(cmd + wrpos, u16(color));
            wrpos += 2;
        }
    }
    // Attempt to send all three SPI commands.
    // (Last includes callback to trigger next burst.)
    bool ok = spi_cmd(5, cmd+0, 0)              // CADDR
           && spi_cmd(5, cmd+5, 0)              // PADDR
           && spi_cmd(wrpos-10, cmd+10, this);  // RAMWR
    // If commands were accepted, update tile position for next burst.
    if (ok) {
        // Next tile in raster order, left to right until end of row.
        ++m_draw_step;
        m_tile_col += tile_width;
        if (m_tile_col >= m_draw_cmd.width()) {
            // Row completed, start the next row of tiles.
            bool vp_old = in_viewport(m_cursor.r + m_tile_row);
            m_tile_col = 0;
            m_tile_row += tile_height;
            bool vp_new = in_viewport(m_cursor.r + m_tile_row);
            // Wrap cursor position as needed to stay within viewport.
            if (vp_old && !vp_new) m_cursor.r -= m_viewsize;
        }
    } else {
        timer_once(1);  // SPI busy, try again later.
    }
}

void Ili9341::init_next() {
    if (m_init_step < sizeof(STARTUP)) {
        // Read the next command...
        u8 len = STARTUP[m_init_step++];
        if (!len) {
            // Null command = Wait for specified interval.
            u8 wait = STARTUP[m_init_step++];
            timer_once(wait);
        } else if (spi_cmd(len, STARTUP + m_init_step, this)) {
            // SPI command accepted, advance to next position.
            m_init_step += len;
        } else {
            // SPI busy, try again later.
            --m_init_step;
            timer_once(1);
        }
    } else {
        // Load dynamic parameters.
        if (spi_madctl() && spi_vscrdef()) {
            // Initialization completed.
            m_init_step = INIT_DONE;
        } else {
            // SPI busy, try again later.
            timer_once(1);
        }
    }
}

bool Ili9341::spi_cmd(u8 len, const u8* cmd, Ili9341* callback) {
    return m_spi->query(m_devidx, cmd, len, 0, callback);
}

bool Ili9341::spi_madctl() {
    // Memory access control (i.e., panel configuration and rotation).
    u8 cmd[2] = {CMD_MADCTL, m_madctl};
    return spi_cmd(sizeof(cmd), cmd, 0); // No callback
}

bool Ili9341::spi_vscrdef() {
    // Vertical scrolling definition.
    u8 cmd[7] = {CMD_VSCRDEF};
    write_be_u16(cmd + 1, m_viewtop);
    write_be_u16(cmd + 3, m_viewsize);
    write_be_u16(cmd + 5, TFT_HEIGHT - m_viewtop - m_viewsize);
    return spi_cmd(sizeof(cmd), cmd, this);
}

void Ili9341::try_twidth(u16 w) {
    // Given tile width and max area, find maximum tile height.
    u16 h = BURST_PIXELS / w;
    // Calculate number of required tiles on each axis.
    u16 r = div_ceil<u16>(m_draw_cmd.height(), h);
    u16 c = div_ceil<u16>(m_draw_cmd.width(),  w);
    // If this beats the minimum, update stored parameters.
    if (r * c < m_draw_done) {
        m_draw_done   = r * c;
        m_tile_width  = w;
        m_tile_height = h;
    }
}
