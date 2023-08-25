//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022 The Aerospace Corporation
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

#include <cstring>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

using satcat5::util::reinterpret;

void satcat5::io::Writeable::write_u8(u8 data)
{
    if (get_write_space() >= 1) {
        write_next(data);
    } else {write_overflow();}
}

void satcat5::io::Writeable::write_u16(u16 data)
{
    if (get_write_space() >= 2) {
        write_next((u8)(data >> 8));   // Big-endian
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void satcat5::io::Writeable::write_u32(u32 data)
{
    if (get_write_space() >= 4) {
        write_next((u8)(data >> 24));  // Big-endian
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void satcat5::io::Writeable::write_u64(u64 data)
{
    if (get_write_space() >= 8) {
        write_next((u8)(data >> 56));  // Big-endian
        write_next((u8)(data >> 48));
        write_next((u8)(data >> 40));
        write_next((u8)(data >> 32));
        write_next((u8)(data >> 24));
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void satcat5::io::Writeable::write_s8(s8 data)
{
    write_u8(reinterpret<s8,u8>(data));
}

void satcat5::io::Writeable::write_s16(s16 data)
{
    write_u16(reinterpret<s16,u16>(data));
}

void satcat5::io::Writeable::write_s32(s32 data)
{
    write_u32(reinterpret<s32,u32>(data));
}

void satcat5::io::Writeable::write_s64(s64 data)
{
    write_u64(reinterpret<s64,u64>(data));
}

void satcat5::io::Writeable::write_f32(float data)
{
    write_u32(reinterpret<float,u32>(data));
}

void satcat5::io::Writeable::write_f64(double data)
{
    write_u64(reinterpret<double,u64>(data));
}

void satcat5::io::Writeable::write_bytes(unsigned nbytes, const void* src)
{
    const u8* src8 = reinterpret_cast<const u8*>(src);
    if (get_write_space() >= nbytes) {
        while (nbytes) {
            write_next(*src8);
            src8++; nbytes--;
        }
    } else {write_overflow();}
}

void satcat5::io::Writeable::write_str(const char* str)
{
    unsigned nbytes = strlen(str);  // Do not include null-termination
    write_bytes(nbytes, str);
}

bool satcat5::io::Writeable::write_finalize()   {return true;}
void satcat5::io::Writeable::write_abort()      {}
void satcat5::io::Writeable::write_overflow()   {}

satcat5::io::ArrayWrite::ArrayWrite(void* dst, unsigned len)
    : m_dst((u8*)dst)
    , m_len(len)
    , m_wridx(0)
    , m_wrlen(0)
{
    // Nothing else to do at this time.
}

unsigned satcat5::io::ArrayWrite::get_write_space() const
{
    return m_len - m_wridx;
}

bool satcat5::io::ArrayWrite::write_finalize()
{
    m_wrlen = m_wridx;          // Note current length
    m_wridx = 0;                // Next write wraps to start
    return true;                // Always successful
}

void satcat5::io::ArrayWrite::write_next(u8 data)
{
    m_wrlen = 0;                // Clear prior contents
    m_dst[m_wridx++] = data;    // Write the new byte
}

// The WriteableRedirect class is all one-liners that could all be defined
// in the .h file.  However, this leads to duplication of the underlying
// function (inline, direct, and virtual methods) that complicate testing.
// Defining these micro-functions here prevents such undesired changes.
satcat5::io::WriteableRedirect::WriteableRedirect(io::Writeable* dst)
    : m_dst(dst) {}

unsigned satcat5::io::WriteableRedirect::get_write_space() const
    {return m_dst->get_write_space();}

void satcat5::io::WriteableRedirect::write_abort()
    {m_dst->write_abort();}

void satcat5::io::WriteableRedirect::write_bytes(unsigned nbytes, const void* src)
    {m_dst->write_bytes(nbytes, src);}

bool satcat5::io::WriteableRedirect::write_finalize()
    {return m_dst->write_finalize();}

void satcat5::io::WriteableRedirect::write_next(u8 data)
    {m_dst->write_next(data);}

void satcat5::io::WriteableRedirect::write_overflow()
    {m_dst->write_overflow();}
