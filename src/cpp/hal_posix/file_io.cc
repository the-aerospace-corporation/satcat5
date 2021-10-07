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

#include "file_io.h"

using satcat5::io::FileReader;
using satcat5::io::FileWriter;

FileWriter::FileWriter(const char* filename, bool close_on_finalize)
    : m_close_on_finalize(close_on_finalize)
    , m_file(0)
{
    // Open file if specified, otherwise remain idle.
    if (filename) open(filename);
}

FileWriter::~FileWriter()
{
    close();
}

void FileWriter::open(const char* filename)
{
    // Cleanup before attempting to open the new file.
    close();
    m_name = filename;
    m_file = fopen(filename, "wb");
}

void FileWriter::close()
{
    // Close file object and revert to idle state.
    if (m_file) fclose(m_file);
    m_file = 0;
}

unsigned FileWriter::get_write_space() const
{
    // If a file is open, max write length is effectively unlimited.
    return m_file ? UINT32_MAX : 0;
}

bool FileWriter::write_finalize()
{
    // Close current file or just keep writing?
    if (m_close_on_finalize) close();
    return true;
}

void FileWriter::write_abort()
{
    // Reopening the file clears saved contents, ready for new data.
    if (m_file) {
        fclose(m_file);
        m_file = fopen(m_name.c_str(), "wb");
    }
}

void FileWriter::write_next(u8 data)
{
    fputc(data, m_file);
}

FileReader::FileReader(const char* filename, bool close_on_finalize)
    : m_close_on_finalize(close_on_finalize)
    , m_file(0)
    , m_rem(0)
{
    // Open filename if specified, otherwise remain idle.
    if (filename) open(filename);
}

FileReader::~FileReader()
{
    close();
}

void FileReader::open(const char* filename, unsigned len)
{
    // Close current input file before attempting to open the new one.
    close();
    m_file = fopen(filename, "rb");

    // Specified length, or auto-sense from file size?
    if (len) {
        m_rem = len;
    } else if (m_file) {
        fseek(m_file, 0, SEEK_END);
        m_rem = (unsigned)ftell(m_file);
        fseek(m_file, 0, SEEK_SET);
    }
}

void FileReader::close()
{
    // Close file object and revert to idle state.
    if (m_file) fclose(m_file);
    m_file = 0;
    m_rem  = 0;
}

unsigned FileReader::get_read_ready() const
{
    return m_file ? m_rem : 0;
}

void FileReader::read_finalize()
{
    // Close current file or just keep reading?
    if (m_close_on_finalize) close();
}

u8 FileReader::read_next()
{
    return (u8)fgetc(m_file);
}
