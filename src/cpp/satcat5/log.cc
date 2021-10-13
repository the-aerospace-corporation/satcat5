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

#include <satcat5/io_core.h>
#include <satcat5/log.h>

namespace io    = satcat5::io;
namespace log   = satcat5::log;
using log::Log;

// Enable emoji for log priority indicators?
#ifndef SATCAT5_LOG_EMOJI
#define SATCAT5_LOG_EMOJI 1
#endif

// Global pointer to the active destination object, if any.
log::EventHandler* g_log_dst = 0;

// Helper function for looking up hex values.
inline char hex_lookup(unsigned val) {
    switch (val & 0xF) {
    case 0x0:   return '0';
    case 0x1:   return '1';
    case 0x2:   return '2';
    case 0x3:   return '3';
    case 0x4:   return '4';
    case 0x5:   return '5';
    case 0x6:   return '6';
    case 0x7:   return '7';
    case 0x8:   return '8';
    case 0x9:   return '9';
    case 0xA:   return 'A';
    case 0xB:   return 'B';
    case 0xC:   return 'C';
    case 0xD:   return 'D';
    case 0xE:   return 'E';
    default:    return 'F';
    }
}

// Translate priority code (+/-20) to a suitable UTF8 emoji.
inline const char* priority_lookup(s8 val) {
    if (val >= log::CRITICAL)       // Critical = Skull and crossbones
        return SATCAT5_LOG_EMOJI ? "\xE2\x98\xA0\xEF\xB8\x8F" : "Crit";
    else if (val >= log::ERROR)     // Error = Red 'X'
        return SATCAT5_LOG_EMOJI ? "\xE2\x9D\x8C" : "Error";
    else if (val >= log::WARNING)   // Warning = Caution sign
        return SATCAT5_LOG_EMOJI ? "\xE2\x9A\xA0\xEF\xB8\x8F" : "Warn";
    else if (val >= log::INFO)      // Info = Speech bubble
        return SATCAT5_LOG_EMOJI ? "\xF0\x9F\x92\xAC" : "Info";
    else                            // Debug = Gear
        return SATCAT5_LOG_EMOJI ? "\xE2\x9A\x99\xEF\xB8\x8F" : "Debug";
}

log::ToWriteable::ToWriteable(io::Writeable* dst, log::EventHandler* cc)
    : m_dst(dst)
    , m_cc(cc)
{
    // Write a few newlines to flush Tx buffer.
    dst->write_str("\r\n\n");
    dst->write_finalize();
    // Automatically set ourselves as the log destination.
    log::start(this);
}

#if SATCAT5_ALLOW_DELETION
log::ToWriteable::~ToWriteable()
{
    // Object deleted, point to next hop in chain.
    // (If this is NULL, this shuts down the logging system.)
    log::start(m_cc);
}
#endif

void log::ToWriteable::log_event(
    s8 priority, unsigned nbytes, const char* msg)
{
    // Prefix message with a priority emoji.
    m_dst->write_str(priority_lookup(priority));
    m_dst->write_str("\t");
    m_dst->write_bytes(nbytes, msg);
    m_dst->write_str("\r\n");
    m_dst->write_finalize();

    // Optionally daisy-chain to a second handler.
    if (m_cc) m_cc->log_event(priority, nbytes, msg);
}

void log::start(log::EventHandler* dst)
{
    g_log_dst = dst;
}

// Suppress static-analysis warnings for uninitialized members.
// (Large array "m_buff" is always written before use.)
// cppcheck-suppress uninitMemberVar

Log::Log(s8 priority)
    : m_priority(priority)
    , m_wridx(0)
{
    // Nothing else to do at this time.
}

Log::Log(s8 priority, const char* str)
    : m_priority(priority)
    , m_wridx(0)
{
    wr_str(str);
}

Log::Log(s8 priority, const char* str1, const char* str2)
    : m_priority(priority)
    , m_wridx(0)
{
    wr_str(str1);
    wr_str(": ");
    wr_str(str2);
}

log::Log::~Log()
{
    if (g_log_dst) {
        // Null-terminate the message string before we deliver it.
        m_buff[m_wridx] = 0;
        g_log_dst->log_event(m_priority, m_wridx, m_buff);
    }
}

Log& Log::write(const char* str) {
    wr_str(str);
    return *this;
}

Log& Log::write(u8 val) {
    wr_str(" = 0x");
    wr_hex(val, 2);
    return *this;
}

Log& Log::write(u16 val) {
    wr_str(" = 0x");
    wr_hex(val, 4);
    return *this;
}

Log& Log::write(u32 val) {
    wr_str(" = 0x");
    wr_hex(val, 8);
    return *this;
}

Log& Log::write(u64 val) {
    u32 msb = (u32)(val >> 32);
    u32 lsb = (u32)(val >> 0);
    wr_str(" = 0x");
    wr_hex(msb, 8);
    wr_hex(lsb, 8);
    return *this;
}

Log& Log::write(const u8* val, unsigned nbytes) {
    wr_str(" = 0x");
    for (unsigned a = 0 ; a < nbytes ; ++a)
        wr_hex(val[a], 2);
    return *this;
}

void Log::wr_str(const char* str)
{
    if (!str) return;  // Ignore null pointers
    while (*str && m_wridx < SATCAT5_LOG_MAXLEN)
        m_buff[m_wridx++] = *(str++);
}

void Log::wr_hex(uint32_t val, unsigned nhex)
{
    for (unsigned a = 0 ; m_wridx < SATCAT5_LOG_MAXLEN && a < nhex ; ++a) {
        unsigned shift = 4 * (nhex-a-1);    // Most significant nybble first
        m_buff[m_wridx++] = hex_lookup(val >> shift);
    }
}
