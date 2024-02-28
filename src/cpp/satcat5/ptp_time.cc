//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ptp_time.h>
#include <satcat5/datetime.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>

using satcat5::ptp::MSEC_PER_SEC;
using satcat5::ptp::USEC_PER_SEC;
using satcat5::ptp::NSEC_PER_SEC;
using satcat5::ptp::SUBNS_PER_SEC;
using satcat5::ptp::SUBNS_PER_MSEC;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::Time;
using satcat5::util::abs_s64;
using satcat5::util::div_round;

Time::Time(u64 seconds, u32 nanoseconds, u16 subnanoseconds)
    : m_secs((s64)seconds)
    , m_subns(nanoseconds * SUBNS_PER_NSEC + subnanoseconds)
{
    normalize();
}

void Time::normalize() {
    while (m_subns < 0) {
        m_secs  -= 1;     // Underflow
        m_subns += SUBNS_PER_SEC;
    }
    while (m_subns >= SUBNS_PER_SEC) {
        m_secs  += 1;     // Wraparound
        m_subns -= SUBNS_PER_SEC;
    }
}

// All "delta_*" unit-conversion methods follow the same template:
template<s64 UNITS_PER_SEC>
inline s64 delta_convert(s64 sec, s64 subns) {
    constexpr s64 MAX_SAFE = INT64_MAX / UNITS_PER_SEC - 1;
    constexpr s64 SUBNS_PER_UNIT = SUBNS_PER_SEC / UNITS_PER_SEC;
    if (sec < -MAX_SAFE) {
        return INT64_MIN;
    } else if (sec > MAX_SAFE) {
        return INT64_MAX;
    } else if (SUBNS_PER_UNIT > 1) {
        return UNITS_PER_SEC * sec + div_round(subns, SUBNS_PER_UNIT);
    } else {
        return UNITS_PER_SEC * sec + subns;
    }
}

s64 Time::delta_subns() const
    { return delta_convert<SUBNS_PER_SEC>(m_secs, m_subns); }
s64 Time::delta_nsec() const
    { return delta_convert<NSEC_PER_SEC>(m_secs, m_subns); }
s64 Time::delta_usec() const
    { return delta_convert<USEC_PER_SEC>(m_secs, m_subns); }
s64 Time::delta_msec() const
    { return delta_convert<MSEC_PER_SEC>(m_secs, m_subns); }

bool Time::read_from(satcat5::io::Readable* src) {
    if (src->get_read_ready() >= 10) {
        s64 sec_msb = (s64)src->read_u16();     // MSBs of seconds
        s64 sec_lsb = (s64)src->read_u32();     // LSBs of seconds
        s64 nsec    = (s64)src->read_u32();     // Nanoseconds
        m_secs  = (sec_msb << 32) + sec_lsb;    // Set internal variables
        m_subns = (nsec * SUBNS_PER_NSEC);
        normalize(); return true;               // Success!
    } else {
        return false;                           // Read error.
    }
}

void Time::write_to(satcat5::io::Writeable* dst) const {
    dst->write_u16((u16)(m_secs >> 32));        // MSBs of seconds
    dst->write_u32((u32)(m_secs >> 0));         // LSBs of seconds
    dst->write_u32(field_nsec());               // Nanoseconds (floor)
}

void Time::log_to(satcat5::log::LogBuffer& wr) const {
    wr.wr_str(" = 0x");
    wr.wr_hex((u32)(m_secs >> 32), 4);          // MSBs of seconds
    wr.wr_hex((u32)(m_secs >>  0), 8);          // LSBs of seconds
    wr.wr_str(".");
    wr.wr_hex((u32)(m_subns >> 32), 4);         // MSBs of subns
    wr.wr_hex((u32)(m_subns >>  0), 8);         // LSBs of subns
}

// Offset (in milliseconds) from the PTP epoch (TAI @ 1970 Jan 1)
// to the GPS epoch (1980 Jan 6 + 19 leap seconds).
constexpr s64 GPS_EPOCH = satcat5::datetime::ONE_DAY * 3652LL
                        + satcat5::datetime::ONE_SECOND * 19LL;

s64 Time::to_datetime() const {
    // Calculate milliseconds since PTP epoch.
    s64 tai_msec = MSEC_PER_SEC * m_secs + div_round(m_subns, SUBNS_PER_MSEC);
    // Add the offset from PTP/TAI to GPS (see above).
    return tai_msec - GPS_EPOCH;
}

Time satcat5::ptp::from_datetime(s64 gps_msec) {
    // Add the offset GPS to PTP/TAI (see above).
    s64 tai_msec = gps_msec + GPS_EPOCH;
    // Convert that to PTP format (seconds + nanoseconds)
    u64 ptp_secs = (u64)satcat5::util::divide(tai_msec, MSEC_PER_SEC);
    u32 ptp_msec = (u32)satcat5::util::modulo(tai_msec, MSEC_PER_SEC);
    return Time(ptp_secs, ptp_msec * 1000000u);
}

Time Time::abs() const {
    Time temp(0);
    temp.m_secs  = (s64)abs_s64(m_secs);
    if (m_secs >= 0) {
        // Simple positive case (no change).
        temp.m_subns = m_subns;
    } else if (m_subns > 0) {
        // Negative rollover (-4 + 0.6 --> -3.4)
        temp.m_secs -= 1;
        temp.m_subns = SUBNS_PER_SEC - m_subns;
    } else {
        // Negative boundary (-4 + 0.0 --> -4.0)
        temp.m_subns = 0;
    }
    return temp;
}

bool Time::operator==(const Time& other) const {
    return (m_secs == other.m_secs) && (m_subns == other.m_subns);
}

bool Time::operator<(const Time& other) const {
    if (m_secs < other.m_secs) return true;
    if (m_secs > other.m_secs) return false;
    return m_subns < other.m_subns;
}

bool Time::operator>(const Time& other) const {
    if (m_secs > other.m_secs) return true;
    if (m_secs < other.m_secs) return false;
    return m_subns > other.m_subns;
}

void Time::operator+=(const Time& other) {
    m_secs  += other.m_secs;
    m_subns += other.m_subns;
    normalize();
}

void Time::operator-=(const Time& other) {
    m_secs  -= other.m_secs;
    m_subns -= other.m_subns;
    normalize();
}

void Time::operator*=(unsigned scale) {
    s64 tmp = m_subns * scale;
    m_secs  = tmp / SUBNS_PER_SEC + m_secs * scale;
    m_subns = tmp % SUBNS_PER_SEC;
    normalize();
}

void Time::operator/=(unsigned scale) {
    s64 tmp = (m_secs % scale) * SUBNS_PER_SEC;
    m_secs  = m_secs / scale;
    m_subns = (m_subns + tmp) / scale;
    normalize();
}

Time Time::operator=(const Time& other) {
    m_secs  = other.m_secs;
    m_subns = other.m_subns;
    return *this;
}

Time Time::operator+(const Time& other) const {
    Time tmp(*this);
    tmp += other;
    return tmp;
}

Time Time::operator-(const Time& other) const {
    Time tmp(*this);
    tmp -= other;
    return tmp;
}

Time Time::operator-() const {
    Time tmp(0);
    tmp -= *this;
    return tmp;
}

Time Time::operator*(unsigned scale) const {
    Time tmp(*this);
    tmp *= scale;
    return tmp;
}

Time Time::operator/(unsigned scale) const {
    Time tmp(*this);
    tmp /= scale;
    return tmp;
}
