//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Implement the gui::Display API using a temporary file.
//
// The FileDisplay class writes "pixels" as an 80x40 grid of characters
// in a plaintext file.  The foreground and background "color" are the
// ASCII character to be filled, usualy '*' and ' '.
//
// The scroll() method is not supported.  Buffering is not required.
//
// This class is not particularly useful, except for unit testing and
// for serving as a simple working example.
//

#pragma once

#include <cstdio>
#include <satcat5/gui_display.h>

namespace satcat5 {
    namespace gui {
        class FileDisplay : public satcat5::gui::Display {
        public:
            // Create a "display" using the specified file.
            FileDisplay(const char* filename,
                u16 rows = 40, u16 cols = 80);
            ~FileDisplay();

            // "Color" parameters for this display are actually characters.
            // Recommended set for use with the LogToDisplay class:
            static constexpr LogColors LOG_COLORS =
                {' ', '*', ' ', 'E', ' ', 'W', ' ', 'I', ' ', 'D'};

        protected:
            // Implement the required draw() method.
            bool draw(
                const satcat5::gui::Cursor& cursor,
                const satcat5::gui::DrawCmd& cmd) override;

            // Current file object
            FILE* m_file;
        };
    }
}
