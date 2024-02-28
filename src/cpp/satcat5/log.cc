//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ethernet.h>
#include <satcat5/io_core.h>
#include <satcat5/ip_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

namespace io    = satcat5::io;
namespace log   = satcat5::log;
using log::Log;
using log::LogBuffer;

// Enable emoji for log priority indicators?
#ifndef SATCAT5_LOG_EMOJI
#define SATCAT5_LOG_EMOJI 1
#endif

// Global pointer to a linked list of active destination objects, if any.
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

// Helper function for writing a single decimal digit.
template <typename T>
inline void next_digit(char* out, unsigned& wridx, T& val, T place) {
    // Find value of leading digit (i.e., '0' through '9').
    // Use while loop in case CPU doesn't have a divide instruction.
    char digit = '0';
    while (val >= place) {++digit; val -= place;}

    // Write the next digit if it is nonzero or trails an earlier digit.
    if ((digit > '0') || (wridx > 0))
        out[wridx++] = digit;
}

// Helper function writes a decimal number to buffer, returns sting length.
// Working buffer MUST contain the designated minimum size:
//  u32 max = ~4 billion = 10 digits + terminator = 11 bytes
//  u64 max = ~18 pentillion = 20 digits + terminator = 21 bytes
static constexpr unsigned LOG_ITOA_BUFF32 = 11;
static unsigned log_itoa32(char* out, u32 val) {
    unsigned wridx = 0;
    next_digit<u32>(out, wridx, val, 1000000000u);
    next_digit<u32>(out, wridx, val, 100000000u);
    next_digit<u32>(out, wridx, val, 10000000u);
    next_digit<u32>(out, wridx, val, 1000000u);
    next_digit<u32>(out, wridx, val, 100000u);
    next_digit<u32>(out, wridx, val, 10000u);
    next_digit<u32>(out, wridx, val, 1000u);
    next_digit<u32>(out, wridx, val, 100u);
    next_digit<u32>(out, wridx, val, 10u);
    out[wridx++] = val + '0';   // Always write final digit
    out[wridx] = 0;             // Null termination
    return wridx;               // String length excludes terminator
}

static constexpr unsigned LOG_ITOA_BUFF64 = 21;
static unsigned log_itoa64(char* out, u64 val) {
    unsigned wridx = 0;
    next_digit<u64>(out, wridx, val, 10000000000000000000ull);
    next_digit<u64>(out, wridx, val, 1000000000000000000ull);
    next_digit<u64>(out, wridx, val, 100000000000000000ull);
    next_digit<u64>(out, wridx, val, 10000000000000000ull);
    next_digit<u64>(out, wridx, val, 1000000000000000ull);
    next_digit<u64>(out, wridx, val, 100000000000000ull);
    next_digit<u64>(out, wridx, val, 10000000000000ull);
    next_digit<u64>(out, wridx, val, 1000000000000ull);
    next_digit<u64>(out, wridx, val, 100000000000ull);
    next_digit<u64>(out, wridx, val, 10000000000ull);
    next_digit<u64>(out, wridx, val, 1000000000ull);
    next_digit<u64>(out, wridx, val, 100000000ull);
    next_digit<u64>(out, wridx, val, 10000000ull);
    next_digit<u64>(out, wridx, val, 1000000ull);
    next_digit<u64>(out, wridx, val, 100000ull);
    next_digit<u64>(out, wridx, val, 10000ull);
    next_digit<u64>(out, wridx, val, 1000ull);
    next_digit<u64>(out, wridx, val, 100ull);
    next_digit<u64>(out, wridx, val, 10ull);
    out[wridx++] = val + '0';   // Always write final digit
    out[wridx] = 0;             // Null termination
    return wridx;               // String length excludes terminator
}

// Translate priority code (+/-20) to a suitable UTF8 emoji.
const char* log::priority_label(s8 val) {
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

log::EventHandler::EventHandler()
    : m_next(0)
{
    satcat5::util::ListCore::add(g_log_dst, this);
}

#if SATCAT5_ALLOW_DELETION
log::EventHandler::~EventHandler()
{
    satcat5::util::ListCore::remove(g_log_dst, this);
}
#endif

log::ToWriteable::ToWriteable(io::Writeable* dst)
    : m_dst(dst)
{
    // Write a few newlines to flush Tx buffer.
    dst->write_str("\r\n\n");
    dst->write_finalize();
}

void log::ToWriteable::log_event(
    s8 priority, unsigned nbytes, const char* msg)
{
    // Prefix message with a priority emoji.
    m_dst->write_str(log::priority_label(priority));
    m_dst->write_str("\t");
    m_dst->write_bytes(nbytes, msg);
    m_dst->write_str("\r\n");
    m_dst->write_finalize();
}

// Suppress static-analysis warnings for uninitialized members.
// (Large array "m_buff" is always written before use.)
// cppcheck-suppress uninitMemberVar

Log::Log(s8 priority)
    : m_priority(priority)
{
    // Nothing else to do at this time.
}

Log::Log(s8 priority, const char* str)
    : m_priority(priority)
{
    m_buff.wr_str(str);
}

Log::Log(s8 priority, const char* str1, const char* str2)
    : m_priority(priority)
{
    m_buff.wr_str(str1);
    m_buff.wr_str(": ");
    m_buff.wr_str(str2);
}

Log::Log(s8 priority, const void* str, unsigned nbytes)
    : m_priority(priority)
{
    m_buff.wr_fix((const char*)str, nbytes);
}

log::Log::~Log()
{
    // Null-terminate the final message string.
    m_buff.terminate();

    // Deliver it to each handler on the global list.
    log::EventHandler* dst = g_log_dst;
    while (dst) {
        dst->log_event(m_priority, m_buff.len(), m_buff.m_buff);
        dst = satcat5::util::ListCore::next(dst);
    }
}

Log& Log::write(const char* str) {
    m_buff.wr_str(str);
    return *this;
}

Log& Log::write(bool val) {
    m_buff.wr_str(" = ");
    m_buff.wr_hex(val ? 1:0, 1);
    return *this;
}

Log& Log::write(u8 val) {
    m_buff.wr_str(" = 0x");
    m_buff.wr_hex(val, 2);
    return *this;
}

Log& Log::write(u16 val) {
    m_buff.wr_str(" = 0x");
    m_buff.wr_hex(val, 4);
    return *this;
}

Log& Log::write(u32 val) {
    m_buff.wr_str(" = 0x");
    m_buff.wr_hex(val, 8);
    return *this;
}

Log& Log::write(u64 val) {
    u32 msb = (u32)(val >> 32);
    u32 lsb = (u32)(val >> 0);
    m_buff.wr_str(" = 0x");
    m_buff.wr_hex(msb, 8);
    m_buff.wr_hex(lsb, 8);
    return *this;
}

Log& Log::write(io::Readable* rd)
{
    m_buff.wr_str(" = 0x");
    while (rd->get_read_ready())
        m_buff.wr_hex(rd->read_u8(), 2);
    return *this;
}

Log& Log::write(const u8* val, unsigned nbytes) {
    m_buff.wr_str(" = 0x");
    for (unsigned a = 0 ; a < nbytes ; ++a)
        m_buff.wr_hex(val[a], 2);
    return *this;
}

Log& Log::write(const satcat5::eth::MacAddr& mac)
{
    // Convention is six hex bytes with ":" delimeter.
    // e.g., "DE:AD:BE:EF:CA:FE"
    m_buff.wr_str(" = ");
    for (unsigned a = 0 ; a < 6 ; ++a) {
        if (a) m_buff.wr_str(":");
        m_buff.wr_hex(mac.addr[a], 2);
    }
    return *this;
}

Log& Log::write(const satcat5::ip::Addr& ip)
{
    // Extract individual bytes from the 32-bit IP-address.
    u32 ip_bytes[] = {
        (ip.value >> 24) & 0xFF,    // MSB-first
        (ip.value >> 16) & 0xFF,
        (ip.value >>  8) & 0xFF,
        (ip.value >>  0) & 0xFF,
    };

    // Convention is 4 decimal numbers with "." delimiter.
    // e.g., "192.168.1.42"
    m_buff.wr_str(" = ");
    for (unsigned a = 0 ; a < 4 ; ++a) {
        if (a) m_buff.wr_str(".");
        m_buff.wr_dec(ip_bytes[a]);
    }
    return *this;
}

Log& Log::write10(s32 val) {
    // Decimal string with sign prefix.
    m_buff.wr_str(val < 0 ? " = -" : " = +");
    m_buff.wr_dec(satcat5::util::abs_s32(val));
    return *this;
}

Log& Log::write10(s64 val) {
    // Decimal string with sign prefix.
    m_buff.wr_str(val < 0 ? " = -" : " = +");
    m_buff.wr_d64(satcat5::util::abs_s64(val));
    return *this;
}

Log& Log::write10(u32 val) {
    m_buff.wr_str(" = ");
    m_buff.wr_dec(val);
    return *this;
}

Log& Log::write10(u64 val) {
    m_buff.wr_str(" = ");
    m_buff.wr_d64(val);
    return *this;
}

void LogBuffer::wr_fix(const char* str, unsigned len)
{
    if (!str) return;  // Ignore null pointers
    const char* end = str + len;
    while (str != end && m_wridx < SATCAT5_LOG_MAXLEN)
        m_buff[m_wridx++] = *(str++);
}

void LogBuffer::wr_str(const char* str)
{
    if (!str) return;  // Ignore null pointers
    while (*str && m_wridx < SATCAT5_LOG_MAXLEN)
        m_buff[m_wridx++] = *(str++);
}

void LogBuffer::wr_hex(u32 val, unsigned nhex)
{
    for (unsigned a = 0 ; m_wridx < SATCAT5_LOG_MAXLEN && a < nhex ; ++a) {
        unsigned shift = 4 * (nhex-a-1);    // Most significant nybble first
        m_buff[m_wridx++] = hex_lookup(val >> shift);
    }
}

void LogBuffer::wr_dec(u32 val)
{
    char temp[LOG_ITOA_BUFF32];
    log_itoa32(temp, val);
    wr_str(temp);
}

void LogBuffer::wr_d64(u64 val)
{
    char temp[LOG_ITOA_BUFF64];
    log_itoa64(temp, val);
    wr_str(temp);
}
