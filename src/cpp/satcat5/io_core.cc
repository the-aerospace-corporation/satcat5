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

#include <cstring>
#include <satcat5/io_core.h>
#include <satcat5/utils.h>

// Set batch size for copy_to()
#ifndef SATCAT5_BUFFCOPY_BATCH
#define SATCAT5_BUFFCOPY_BATCH  32
#endif

using satcat5::util::min_unsigned;
using satcat5::util::reinterpret;

void satcat5::io::Writeable::write_u8(u8 data)
{
    if (get_write_space() >= 1) {
        write_next(data);
    } else write_overflow();
}

void satcat5::io::Writeable::write_u16(u16 data)
{
    if (get_write_space() >= 2) {
        write_next((u8)(data >> 8));   // Big-endian
        write_next((u8)(data >> 0));
    } else write_overflow();
}

void satcat5::io::Writeable::write_u32(u32 data)
{
    if (get_write_space() >= 4) {
        write_next((u8)(data >> 24));  // Big-endian
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else write_overflow();
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
    } else write_overflow();
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
    } else write_overflow();
}

void satcat5::io::Writeable::write_str(const char* str)
{
    unsigned nbytes = strlen(str);  // Do not include null-termination
    write_bytes(nbytes, str);
}

bool satcat5::io::Writeable::write_finalize()   {return true;}
void satcat5::io::Writeable::write_abort()      {}
void satcat5::io::Writeable::write_overflow()   {}

satcat5::io::Readable::Readable(io::EventListener* callback)
    : m_callback(callback)
{
    // No other initialization required.
}

void satcat5::io::Readable::set_callback(io::EventListener* callback)
{
    m_callback = callback;
    if (get_read_ready()) request_poll();
}

u8 satcat5::io::Readable::read_u8()
{
    if (get_read_ready() >= 1) {
        return read_next();
    } else {
        read_underflow();
        return 0;
    }
}

u16 satcat5::io::Readable::read_u16()
{
    if (get_read_ready() >= 2) {
        u16 temp = read_next();    // Big-endian
        return (temp << 8) | read_next();
    } else {
        read_underflow();
        return 0;
    }
}

u32 satcat5::io::Readable::read_u32()
{
    if (get_read_ready() >= 4) {
        u32 temp = read_next();    // Big-endian
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        return (temp << 8) | read_next();
    } else {
        read_underflow();
        return 0;
    }
}

u64 satcat5::io::Readable::read_u64()
{
    if (get_read_ready() >= 8) {
        u64 temp = read_next();    // Big-endian
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        temp = (temp << 8) | read_next();
        return (temp << 8) | read_next();
    } else {
        read_underflow();
        return 0;
    }
}

s8 satcat5::io::Readable::read_s8()
{
    return reinterpret<u8, s8>(read_u8());
}

s16 satcat5::io::Readable::read_s16()
{
    return reinterpret<u16, s16>(read_u16());
}

s32 satcat5::io::Readable::read_s32()
{
    return reinterpret<u32, s32>(read_u32());
}

s64 satcat5::io::Readable::read_s64()
{
    return reinterpret<u64, s64>(read_u64());
}

float satcat5::io::Readable::read_f32()
{
    return reinterpret<u32, float>(read_u32());
}

double satcat5::io::Readable::read_f64()
{
    return reinterpret<u64, double>(read_u64());
}

bool satcat5::io::Readable::read_bytes(unsigned nbytes, void* dst)
{
    u8* dst_u8 = (u8*)dst;

    if (get_read_ready() >= nbytes) {
        while (nbytes) {
            *dst_u8 = read_next();
            ++dst_u8; --nbytes;
        }
        return true;
    } else {
        read_underflow();
        return false;
    }
}

bool satcat5::io::Readable::read_consume(unsigned nbytes)
{
    if (get_read_ready() >= nbytes) {
        while (nbytes--) read_next();
        return true;
    } else {
        read_underflow();
        return false;
    }
}

bool satcat5::io::Readable::copy_to(satcat5::io::Writeable* dst)
{
    // Temporary buffer sets our maximum batch size.
    u8 buff[SATCAT5_BUFFCOPY_BATCH];
    while (1) {
        // How much data could we copy from source to sink?
        unsigned max_rd = get_read_ready();
        unsigned max_wr = min_unsigned(max_rd, dst->get_write_space());
        if (max_wr == 0) return false;
        // Copy up to that limit or batch size, whichever is smaller.
        unsigned batch = min_unsigned(max_wr, SATCAT5_BUFFCOPY_BATCH);
        read_bytes(batch, buff);
        dst->write_bytes(batch, buff);
        // Did we just finish a frame?
        if (batch == max_rd) return true;
    }
}

void satcat5::io::Readable::poll_demand()
{
    // If we have any data waiting, deliver it.
    // If we STILL have data afterward, try again later.
    if (m_callback && get_read_ready() > 0) {
        m_callback->data_rcvd();
        if (get_read_ready()) request_poll();
    }
}

void satcat5::io::Readable::read_finalize()    {}
void satcat5::io::Readable::read_underflow()   {}

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

satcat5::io::ArrayRead::ArrayRead(const void* src, unsigned len)
    : m_src((const u8*)src)
    , m_len(len)
    , m_rdidx(0)
{
    // Nothing else to do at this time.
}

unsigned satcat5::io::ArrayRead::get_read_ready() const
{
    return m_len - m_rdidx;
}

u8 satcat5::io::ArrayRead::read_next()
{
    return m_src[m_rdidx++];
}

void satcat5::io::ArrayRead::read_finalize()
{
    m_rdidx = 0;
}

satcat5::io::LimitedRead::LimitedRead(satcat5::io::Readable* src, unsigned maxrd)
    : m_src(src), m_rem(maxrd) {}

unsigned satcat5::io::LimitedRead::get_read_ready() const
    {return m_rem;}

bool satcat5::io::LimitedRead::read_bytes(unsigned nbytes, void* dst)
{
    if (nbytes <= m_rem) {
        m_rem -= nbytes;
        return m_src->read_bytes(nbytes, dst);
    } else {
        m_rem = 0;
        return false;
    }

}

bool satcat5::io::LimitedRead::read_consume(unsigned nbytes)
{
    if (nbytes <= m_rem) {
        m_rem -= nbytes;
        return m_src->read_consume(nbytes);
    } else {
        m_rem = 0;
        return false;
    }
}

u8 satcat5::io::LimitedRead::read_next()
{
    // Internal method, parent has already checked get_read_ready()
    --m_rem;
    return m_src->read_next();
}

// The WriteableRedirect class is all one-liners that could all be defined
// in the .h file.  However, this leads to duplication of the underlying
// function (inline, direct, and virtual methods) that complicate testing.
// Defining these micro-functions here prevents such undesired changes.
satcat5::io::WriteableRedirect::WriteableRedirect(io::Writeable* dst)
    : m_dst(dst) {}

unsigned satcat5::io::WriteableRedirect::get_write_space() const
    {return m_dst->get_write_space();}

void satcat5::io::WriteableRedirect::write_bytes(unsigned nbytes, const void* src)
    {m_dst->write_bytes(nbytes, src);}

bool satcat5::io::WriteableRedirect::write_finalize()
    {return m_dst->write_finalize();}

void satcat5::io::WriteableRedirect::write_next(u8 data)
    {m_dst->write_next(data);}

void satcat5::io::WriteableRedirect::write_overflow()
    {m_dst->write_overflow();}

// Same goes for ReadableRedirect.
satcat5::io::ReadableRedirect::ReadableRedirect(io::Readable* src)
    : m_src(src) {}

void satcat5::io::ReadableRedirect::set_callback(io::EventListener* callback)
    {m_src->set_callback(callback);}

unsigned satcat5::io::ReadableRedirect::get_read_ready() const
    {return m_src->get_read_ready();}

bool satcat5::io::ReadableRedirect::read_bytes(unsigned nbytes, void* dst)
    {return m_src->read_bytes(nbytes, dst);}

bool satcat5::io::ReadableRedirect::read_consume(unsigned nbytes)
    {return m_src->read_consume(nbytes);}

void satcat5::io::ReadableRedirect::read_finalize()
    {m_src->read_finalize();}

u8 satcat5::io::ReadableRedirect::read_next()
    {return m_src->read_next();}

void satcat5::io::ReadableRedirect::read_underflow()
    {m_src->read_underflow();}
