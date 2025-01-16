//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

using satcat5::io::ArrayWrite;
using satcat5::io::LimitedWrite;
using satcat5::io::NullWrite;
using satcat5::io::Writeable;
using satcat5::io::WriteableRedirect;
using satcat5::util::reinterpret;

// Global instance of the basic NullWrite object.
NullWrite satcat5::io::null_write(65535);

void Writeable::write_u8(u8 data) {
    if (get_write_space() >= 1) {
        write_next(data);
    } else {write_overflow();}
}

// Make sure Doxygen ignores all write_ functions for scalars except write_u8().
//! \cond int_io_render
void Writeable::write_u16(u16 data) {
    if (get_write_space() >= 2) {
        write_next((u8)(data >> 8));   // Big-endian
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void Writeable::write_u24(u32 data) {
    if (get_write_space() >= 3) {
        write_next((u8)(data >> 16));  // Big-endian
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void Writeable::write_u32(u32 data) {
    if (get_write_space() >= 4) {
        write_next((u8)(data >> 24));  // Big-endian
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void Writeable::write_u48(u64 data) {
    if (get_write_space() >= 6) {
        write_next((u8)(data >> 40));   // Big-endian
        write_next((u8)(data >> 32));
        write_next((u8)(data >> 24));
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 0));
    } else {write_overflow();}
}

void Writeable::write_u64(u64 data) {
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

void Writeable::write_u16l(u16 data) {
    if (get_write_space() >= 2) {
        write_next((u8)(data >> 0));    // Little-endian
        write_next((u8)(data >> 8));
    } else {write_overflow();}
}

void Writeable::write_u24l(u32 data) {
    if (get_write_space() >= 3) {
        write_next((u8)(data >> 0));    // Little-endian
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 16));
    } else {write_overflow();}
}

void Writeable::write_u32l(u32 data) {
    if (get_write_space() >= 4) {
        write_next((u8)(data >> 0));    // Little-endian
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 24));
    } else {write_overflow();}
}

void Writeable::write_u48l(u64 data) {
    if (get_write_space() >= 6) {
        write_next((u8)(data >> 0));    // Little-endian
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 24));
        write_next((u8)(data >> 32));
        write_next((u8)(data >> 40));
    } else {write_overflow();}
}

void Writeable::write_u64l(u64 data) {
    if (get_write_space() >= 8) {
        write_next((u8)(data >> 0));    // Little-endian
        write_next((u8)(data >> 8));
        write_next((u8)(data >> 16));
        write_next((u8)(data >> 24));
        write_next((u8)(data >> 32));
        write_next((u8)(data >> 40));
        write_next((u8)(data >> 48));
        write_next((u8)(data >> 56));
    } else {write_overflow();}
}

void Writeable::write_s8(s8 data)
    { write_u8(reinterpret<s8,u8>(data)); }

void Writeable::write_s16(s16 data)
    { write_u16(reinterpret<s16,u16>(data)); }

void Writeable::write_s24(s32 data)
    { write_u24(reinterpret<s32,u32>(data)); }

void Writeable::write_s32(s32 data)
    { write_u32(reinterpret<s32,u32>(data)); }

void Writeable::write_s48(s64 data)
    { write_u48(reinterpret<s64,u64>(data)); }

void Writeable::write_s64(s64 data)
    { write_u64(reinterpret<s64,u64>(data)); }

void Writeable::write_f32(float data)
    { write_u32(reinterpret<float,u32>(data)); }

void Writeable::write_f64(double data)
    { write_u64(reinterpret<double,u64>(data)); }

void Writeable::write_s16l(s16 data)
    { write_u16l(reinterpret<s16,u16>(data)); }

void Writeable::write_s24l(s32 data)
    { write_u24l(reinterpret<s32,u32>(data)); }

void Writeable::write_s32l(s32 data)
    { write_u32l(reinterpret<s32,u32>(data)); }

void Writeable::write_s48l(s64 data)
    { write_u48l(reinterpret<s64,u64>(data)); }

void Writeable::write_s64l(s64 data)
    { write_u64l(reinterpret<s64,u64>(data)); }

void Writeable::write_f32l(float data)
    { write_u32l(reinterpret<float,u32>(data)); }

void Writeable::write_f64l(double data)
    { write_u64l(reinterpret<double,u64>(data)); }
//! \endcond

void Writeable::write_bytes(unsigned nbytes, const void* src) {
    const u8* src8 = reinterpret_cast<const u8*>(src);
    if (get_write_space() >= nbytes) {
        while (nbytes) {
            write_next(*src8);
            src8++; nbytes--;
        }
    } else {write_overflow();}
}

void Writeable::write_str(const char* str) {
    unsigned nbytes = strlen(str);  // Do not include null-termination
    write_bytes(nbytes, str);
}

bool Writeable::write_finalize()   {return true;}
void Writeable::write_abort()      {}
void Writeable::write_overflow()   {}

unsigned ArrayWrite::get_write_space() const {
    return m_len - m_wridx;     // Remaining space in array
}

void ArrayWrite::write_abort() {
    m_ovr   = false;            // Clear overflow flag
    m_wrlen = 0;                // Clear prior contents
    m_wridx = 0;                // Restart at beginning
}

bool ArrayWrite::write_finalize() {
    bool ok = !m_ovr;           // Fail on overflow
    m_ovr   = false;            // Clear overflow flag
    m_wrlen = ok ? m_wridx : 0; // Note current length
    m_wridx = 0;                // Next write wraps to start
    return ok;
}

void ArrayWrite::write_overflow() {
    m_ovr = true;
}

void ArrayWrite::write_next(u8 data) {
    m_wrlen = 0;                // Clear prior contents
    m_dst[m_wridx++] = data;    // Write the new byte
}

unsigned LimitedWrite::get_write_space() const {
    return satcat5::util::min_unsigned(m_rem, m_dst->get_write_space());
}

void LimitedWrite::write_bytes(unsigned nbytes, const void* src) {
    if (get_write_space() >= nbytes) {
        m_dst->write_bytes(nbytes, src);
        m_rem -= nbytes;
    } else {write_overflow();}
}

void LimitedWrite::write_next(u8 data) {
    m_dst->write_next(data);
    --m_rem;
}

// The WriteableRedirect class is all one-liners that could all be defined
// in the .h file.  However, this leads to duplication of the underlying
// function (inline, direct, and virtual methods) that complicate testing.
// Defining these micro-functions here prevents such undesired changes.
unsigned WriteableRedirect::get_write_space() const
    { return m_dst ? m_dst->get_write_space() : 0; }

void WriteableRedirect::write_abort()
    { if (m_dst) m_dst->write_abort(); }

void WriteableRedirect::write_bytes(unsigned nbytes, const void* src)
    { if (m_dst) m_dst->write_bytes(nbytes, src); }

bool WriteableRedirect::write_finalize()
    { return m_dst && m_dst->write_finalize(); }

void WriteableRedirect::write_next(u8 data)
    { m_dst->write_next(data); }  // Unreachable if m_dst is null.

void WriteableRedirect::write_overflow()
    { if (m_dst) m_dst->write_overflow(); }

unsigned NullWrite::get_write_space() const
    { return m_write_space; }

void NullWrite::write_bytes(unsigned nbytes, const void* src)
    {}  // Do nothing, all incoming data is discarded.

void NullWrite::write_next(u8 data)
    {}  // Do nothing, all incoming data is discarded.
