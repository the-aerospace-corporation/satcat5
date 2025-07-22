//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// File I/O wrappers

#pragma once

#include <cstdio>
#include <string>
#include <satcat5/io_core.h>

namespace satcat5 {
    namespace io {
        //! Write bytes or packets to a file.
        class FileWriter : public satcat5::io::Writeable {
        public:
            //! Create the FileWriter object.
            //! \param filename Optionally open a file immediately.
            //! \param close_on_finalize If true, calling `write_finalize`
            //!     closes the current file. If false, keep writing.
            explicit FileWriter(
                const char* filename = 0,
                bool close_on_finalize = false);
            virtual ~FileWriter();

            //! Open the specified file. If "close_on_finalize" is set, then
            //! user must call open() after each call to write_finalize().
            void open(const char* filename);
            void close();

            //! Move write cursor to the specified absolute offset.
            void seek(unsigned offset);

            // Required and optional function overrides.
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src);
            bool write_finalize() override;
            void write_abort() override;
        protected:
            void write_next(u8 data) override;
            const bool m_close_on_finalize;
            FILE* m_file;           // Current file object
            unsigned m_last_commit; // Position of last commit
        };

        //! Read bytes or packets from a file.
        class FileReader : public satcat5::io::Readable {
        public:
            //! Create the FileWriter object.
            //! \param filename Optionally open a file immediately.
            //! \param close_on_finalize If true, calling `read_finalize`
            //!     closes the current file. If false, keep reading.
            explicit FileReader(
                const char* filename = 0,
                bool close_on_finalize = false);
            virtual ~FileReader();

            //! Open the specified file to read the next frame.
            //! \param filename Filename to be opened (required).
            //! \param len Optionally specify maximum read length.
            //!     A length of zero (default) auto-detects file length.
            void open(const char* filename, unsigned len = 0);
            void close();

            // Required and optional function overrides.
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst);
            bool read_consume(unsigned nbytes);
            void read_finalize() override;
        protected:
            u8 read_next() override;
            const bool m_close_on_finalize;
            FILE* m_file;       // Current file object
            unsigned m_rem;     // Remaining readable bytes
        };
    }
}
