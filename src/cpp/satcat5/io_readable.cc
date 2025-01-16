//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/utils.h>

// Set batch size for copy_to()
#ifndef SATCAT5_BUFFCOPY_BATCH
#define SATCAT5_BUFFCOPY_BATCH  32
#endif

using satcat5::io::ArrayRead;
using satcat5::io::EventListener;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;
using satcat5::io::ReadableRedirect;
using satcat5::io::NullRead;
using satcat5::io::NullSink;
using satcat5::io::Writeable;
using satcat5::util::min_unsigned;
using satcat5::util::reinterpret;

// Global instance of the basic NullRead and NullSink objects.
NullRead satcat5::io::null_read;
NullSink satcat5::io::null_sink;

#if SATCAT5_ALLOW_DELETION
Readable::~Readable()
{
    if (m_callback) m_callback->data_unlink(this);
}
#endif

void Readable::set_callback(EventListener* callback) {
    m_callback = callback;
    if (get_read_ready()) request_poll();
}

u8 Readable::read_u8() {
    if (get_read_ready() >= 1) {
        return read_next();
    } else {
        read_underflow();
        return 0;
    }
}

// Make sure Doxygen ignores all read_ functions for scalars except read_u8().
//! \cond int_io_render
u16 Readable::read_u16() {
    if (get_read_ready() >= 2) {
        u16 temp = read_next();    // Big-endian
        return (temp << 8) | read_next();
    } else {
        read_underflow();
        return 0;
    }
}

u32 Readable::read_u24() {
    if (get_read_ready() >= 3) {
        u32 temp = read_next();    // Big-endian
        temp = (temp << 8) | read_next();
        return (temp << 8) | read_next();
    } else {
        read_underflow();
        return 0;
    }
}

u32 Readable::read_u32() {
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

u64 Readable::read_u48() {
    if (get_read_ready() >= 6) {
        u64 temp = read_next();    // Big-endian
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

u64 Readable::read_u64() {
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

s8 Readable::read_s8()
    { return reinterpret<u8, s8>(read_u8()); }

s16 Readable::read_s16()
    { return reinterpret<u16, s16>(read_u16()); }

s32 Readable::read_s24()   // Sign extension required
    { return (reinterpret<u32, s32>(read_u24()) << 8) >> 8; }

s32 Readable::read_s32()
    { return reinterpret<u32, s32>(read_u32()); }

s64 Readable::read_s48()   // Sign extension required
    { return (reinterpret<u64, s64>(read_u48()) << 16) >> 16; }

s64 Readable::read_s64()
    { return reinterpret<u64, s64>(read_u64()); }

float Readable::read_f32()
    { return reinterpret<u32, float>(read_u32()); }

double Readable::read_f64()
    { return reinterpret<u64, double>(read_u64()); }

u16 Readable::read_u16l()
    { return __builtin_bswap16(read_u16()); }

u32 Readable::read_u24l()
    { return __builtin_bswap32(read_u24()) >> 8; }

u32 Readable::read_u32l()
    { return __builtin_bswap32(read_u32()); }

u64 Readable::read_u48l()
    { return __builtin_bswap64(read_u48()) >> 16; }

u64 Readable::read_u64l()
    { return __builtin_bswap64(read_u64()); }

s16 Readable::read_s16l()
    { return reinterpret<u16, s16>(read_u16l()); }

s32 Readable::read_s24l()  // Sign extension required
    { return reinterpret<u32, s32>(__builtin_bswap32(read_u24())) >> 8; }

s32 Readable::read_s32l()
    { return reinterpret<u32, s32>(read_u32l()); }

s64 Readable::read_s48l()  // Sign extension required
    { return reinterpret<u64, s64>(__builtin_bswap64(read_u48())) >> 16; }

s64 Readable::read_s64l()
    { return reinterpret<u64, s64>(read_u64l()); }

float Readable::read_f32l()
    { return reinterpret<u32, float>(read_u32l()); }

double Readable::read_f64l()
    { return reinterpret<u64, double>(read_u64l()); }
//! \endcond

unsigned Readable::read_str(unsigned dst_size, char* dst) {
    unsigned nwrite = 0;
    while (get_read_ready() > 0) {  // Stop at end-of-input?
        u8 tmp = read_next();       // Read next byte.
        if (tmp == 0) break;        // Null-termination?
        if (nwrite+1 < dst_size) dst[nwrite++] = (char)tmp;
    }
    dst[nwrite] = 0;                // Always null-terminate
    return nwrite;
}

bool Readable::read_bytes(unsigned nbytes, void* dst) {
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

bool Readable::read_consume(unsigned nbytes) {
    if (get_read_ready() >= nbytes) {
        while (nbytes--) read_next();
        return true;
    } else {
        read_underflow();
        return false;
    }
}

unsigned Readable::copy_to(Writeable* dst) {
    // Temporary buffer sets our maximum batch size.
    u8 buff[SATCAT5_BUFFCOPY_BATCH];
    unsigned total = 0;
    while (1) {
        // How much data could we copy from source to sink?
        unsigned max_rd = get_read_ready();
        unsigned max_wr = min_unsigned(max_rd, dst->get_write_space());
        if (max_wr == 0) break;
        // Copy up to that limit or batch size, whichever is smaller.
        unsigned batch = min_unsigned(max_wr, SATCAT5_BUFFCOPY_BATCH);
        read_bytes(batch, buff);
        dst->write_bytes(batch, buff);
        total += batch;
        // Did we just finish a frame?
        if (batch == max_rd) break;
    }
    return total;
}

bool Readable::copy_and_finalize(Writeable* dst) {
    // End-of-frame if we copy at least one byte and source is now exhausted.
    bool done = copy_to(dst) && !get_read_ready();
    if (done) read_finalize();
    return done && dst->write_finalize();
}

void Readable::read_notify() {
    // If we have any data waiting, deliver it.
    if (m_callback && get_read_ready() > 0) {
        m_callback->data_rcvd(this);
    }
}

void Readable::poll_demand() {
    // If we have any data waiting, deliver it.
    // If we STILL have data afterward, try again later.
    if (m_callback && get_read_ready() > 0) {
        m_callback->data_rcvd(this);
        if (get_read_ready()) request_poll();
    }
}

void Readable::read_finalize()    {}
void Readable::read_underflow()   {}

unsigned ArrayRead::get_read_ready() const {
    return m_len - m_rdidx;
}

void ArrayRead::read_reset(unsigned len) {
    m_len = len;
    m_rdidx = 0;
}

u8 ArrayRead::read_next() {
    return m_src[m_rdidx++];
}

void ArrayRead::read_finalize() {
    m_rdidx = 0;
}

LimitedRead::LimitedRead(Readable* src)
    : m_src(src), m_rem(src->get_read_ready()) {}

unsigned LimitedRead::get_read_ready() const
    {return min_unsigned(m_rem, m_src->get_read_ready());}

bool LimitedRead::read_bytes(unsigned nbytes, void* dst) {
    if (nbytes <= m_rem) {
        m_rem -= nbytes;
        return m_src->read_bytes(nbytes, dst);
    } else {
        m_rem = 0;
        return false;
    }

}

bool LimitedRead::read_consume(unsigned nbytes) {
    if (nbytes <= m_rem) {
        m_rem -= nbytes;
        return m_src->read_consume(nbytes);
    } else {
        m_rem = 0;
        return false;
    }
}

void LimitedRead::read_finalize() {
    read_consume(m_rem);
}

u8 LimitedRead::read_next() {
    // Internal method, parent has already checked get_read_ready()
    --m_rem;
    return m_src->read_next();
}

// The ReadableRedirect class is all one-liners that could all be defined
// in the .h file.  However, this leads to duplication of the underlying
// function (inline, direct, and virtual methods) that complicate testing.
// Defining these micro-functions here prevents such undesired changes.
void ReadableRedirect::set_callback(EventListener* callback) {
    Readable::set_callback(callback);
    if (m_src) m_src->set_callback(callback);
}

unsigned ReadableRedirect::get_read_ready() const
    { return m_src ? m_src->get_read_ready() : 0; }

bool ReadableRedirect::read_bytes(unsigned nbytes, void* dst)
    { return m_src && m_src->read_bytes(nbytes, dst); }

bool ReadableRedirect::read_consume(unsigned nbytes)
    { return m_src && m_src->read_consume(nbytes); }

void ReadableRedirect::read_finalize()
    { if (m_src) m_src->read_finalize(); }

u8 ReadableRedirect::read_next()    // Unreachable if get_read_ready() is zero.
    { return m_src->read_next(); }  // Therefore m_src cannot be null.

void ReadableRedirect::read_underflow()
    { if (m_src) m_src->read_underflow(); }

unsigned NullRead::get_read_ready() const
    { return 0; }                   // The null source never generates data.

// Unreachable because get_read_ready() is always zero.
u8 NullRead::read_next()            // GCOVR_EXCL_LINE
    { return 0; }                   // GCOVR_EXCL_LINE

void NullSink::data_rcvd(Readable* src) {
    src->read_consume(src->get_read_ready());
    src->read_finalize();
}
