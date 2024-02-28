//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/file_io.h>
#include <hal_posix/posix_utils.h>

#if SATCAT5_WIN32
    #include <io.h>             // Windows file I/O
    #undef ERROR                // Deconflict Windows "ERROR" macro
#else
    #include <unistd.h>         // For "ftruncate"
#endif

using satcat5::io::FileReader;
using satcat5::io::FileWriter;

FileWriter::FileWriter(const char* filename, bool close_on_finalize)
    : m_close_on_finalize(close_on_finalize)
    , m_file(0)
    , m_last_commit(0)
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
    if (filename) m_file = fopen(filename, "wb");
}

void FileWriter::close()
{
    // Close file object and revert to idle state.
    if (m_file) fclose(m_file);
    m_file = 0;
    m_last_commit = 0;
}

void FileWriter::seek(unsigned offset)
{
    if (m_file) fseek(m_file, m_last_commit + offset, SEEK_SET);
}

unsigned FileWriter::get_write_space() const
{
    // If a file is open, max write length is effectively unlimited.
    return m_file ? UINT32_MAX : 0;
}

void FileWriter::write_bytes(unsigned nbytes, const void* src)
{
    if (m_file) fwrite(src, 1, nbytes, m_file);
}

bool FileWriter::write_finalize()
{
    // Close current file or just keep writing?
    if (m_file) m_last_commit = (unsigned)ftell(m_file);
    if (m_close_on_finalize) close();
    return true;
}

void FileWriter::write_abort()
{
    if (!m_file) return;
    fflush(m_file);
#if SATCAT5_WIN32
    _chsize(fileno(m_file), m_last_commit);
#else
    ftruncate(fileno(m_file), m_last_commit);
#endif
    fseek(m_file, m_last_commit, SEEK_SET);
}

void FileWriter::write_next(u8 data)
{
    if (m_file) fputc(data, m_file);
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
    if (filename) m_file = fopen(filename, "rb");

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

bool FileReader::read_bytes(unsigned nbytes, void* dst)
{
    size_t result = 0;
    if (m_file && m_rem >= nbytes) {
        result = fread(dst, 1, nbytes, m_file);
        m_rem -= result;
    }
    return (result == nbytes);
}

bool FileReader::read_consume(unsigned nbytes)
{
    if (m_file && m_rem >= nbytes) {
        fseek(m_file, (int)nbytes, SEEK_CUR);
        m_rem -= nbytes;
        return true;
    } else {
        return false;
    }
}

void FileReader::read_finalize()
{
    // Close current file or just keep reading?
    if (m_close_on_finalize) close();
}

u8 FileReader::read_next()
{
    if (m_file && m_rem) {
        --m_rem;
        return (u8)fgetc(m_file);
    } else {
        return 0;
    }
}
