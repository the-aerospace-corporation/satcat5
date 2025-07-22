//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/file_display.h>

using satcat5::gui::FileDisplay;

// Workaround to ensure C++11 allocates static constants.
// See also: https://stackoverflow.com/questions/8452952/
constexpr satcat5::gui::LogColors FileDisplay::LOG_COLORS;

// Other useful constants.
static constexpr u8 DATA_BLANK[]    = {' '};
static constexpr u8 DATA_NEWLINE[]  = {'\r', '\n'};

// Create a "display" using the specified file.
FileDisplay::FileDisplay(const char* filename, u16 rows, u16 cols)
    : satcat5::gui::Display(rows, cols)
    , m_file(0)
{
    // Open the file in binary mode to avoid \n vs \r\n confusion.
    m_file = fopen(filename, "wb");
    if (!m_file) return;

    // Fill the "display" with blank lines.
    for (u16 r = 0 ; r < rows ; ++r) {
        for (u16 c = 0 ; c < cols ; ++c) {
            fwrite(DATA_BLANK, sizeof(DATA_BLANK), 1, m_file);
        }
        fwrite(DATA_NEWLINE, sizeof(DATA_NEWLINE), 1, m_file);
    }
}

FileDisplay::~FileDisplay() {
    if (m_file) fclose(m_file);
    m_file = 0;
}

bool FileDisplay::draw(const Cursor& cursor, const DrawCmd& cmd) {
    // Abort immediately if I/O is impossible.
    if (!m_file) return false;

    // Discard commands that go out of bounds.
    if (cursor.c + cmd.width() > width()) return true;

    // Calculate the number of bytes per row.
    u32 row_len = u32(width()) + sizeof(DATA_NEWLINE);

    // Draw/overwrite each "pixel" affected by this command.
    for (u16 r = 0 ; r < cmd.height() ; ++r) {
        // At the start of each row, seek to the write position.
        u32 rr = (r + cursor.r) % u32(height());
        u32 posn = row_len * rr + u32(cursor.c);
        fseek(m_file, posn, SEEK_SET);
        // Write one character for each column.
        for (u16 c = 0 ; c < cmd.width() ; ++c) {
            u8 pixel = cmd.rc(r, c) ? u8(cursor.fg) : u8(cursor.bg);
            fwrite(&pixel, 1, 1, m_file);
        }
    }

    // The operation always succeeds.
    return true;
}
