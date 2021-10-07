//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// File I/O wrappers

#pragma once

#include <cstdio>
#include <string>
#include <satcat5/io_core.h>

namespace satcat5 {
    namespace io {
        class FileWriter : public satcat5::io::Writeable {
        public:
            explicit FileWriter(
                const char* filename = 0,
                bool close_on_finalize = false);
            virtual ~FileWriter();

            // Open the specified file to write the next frame.
            // User must call open() after each call to write_finalize().
            void open(const char* filename);
            void close();

            // Required function overrides.
            unsigned get_write_space() const override;
            bool write_finalize() override;
            void write_abort() override;
        protected:
            void write_next(u8 data) override;
            const bool m_close_on_finalize;
            FILE* m_file;       // Current file object
            std::string m_name; // Filename of m_file
            
        };

        class FileReader : public satcat5::io::Readable {
        public:
            explicit FileReader(
                const char* filename = 0,
                bool close_on_finalize = false);
            virtual ~FileReader();

            // Open the specified file to read the next frame.
            // Specify maximum read length, or zero to auto-detect file length.
            void open(const char* filename, unsigned len = 0);
            void close();

            // Required function overrides.
            unsigned get_read_ready() const override;
            void read_finalize() override;
        protected:
            u8 read_next() override;
            const bool m_close_on_finalize;
            FILE* m_file;       // Current file object
            unsigned m_rem;     // Remaining readable bytes
        };
    }
}
