//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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

#include <satcat5/datetime.h>
#include <satcat5/timer.h>

namespace date = satcat5::datetime;
namespace ptp = satcat5::ptp;
using satcat5::datetime::Clock;
using satcat5::datetime::GpsTime;
using satcat5::datetime::RtcTime;

// The offset from GPS to PTP is fixed by the IEEE1588 standard.
constexpr s64 PTP_EPOCH = 1000LL * 315964819;

// Convert a millisecond timestamp to or from PTP format.
s64 date::from_ptp(const ptp::Time& time)
{
    return time.delta_msec() - PTP_EPOCH;
}

ptp::Time date::to_ptp(s64 time)
{
    s64 secs = s64((time + PTP_EPOCH) / 1000);
    u32 msec = u32((time + PTP_EPOCH) % 1000);
    return ptp::Time(secs, msec * ptp::NSEC_PER_MSEC);
}

// The core "Clock" functions don't require any fancy conversions.
Clock::Clock(satcat5::util::GenericTimer* timer)
    : satcat5::poll::Timer()
    , m_timer(timer)
    , m_frac(0)
    , m_tref(0)
    , m_tcount(0)
    , m_gps(0)
{
    // Update about once per millisecond if possible.
    // (Slower is fine; we just don't want to hog the CPU.)
    timer_every(1);
}

void Clock::set(s64 gps)
{
    // Reset the current time reference.
    m_frac  = 0;
    m_tref  = m_timer->now();
    m_gps   = gps;
}

void Clock::timer_event()
{
    // Elapsed time since the last update?
    unsigned elapsed = m_timer->elapsed_incr(m_tref) + m_frac;
    u32 incr = elapsed / 1000;  // Increment millisecond counter.
    m_frac   = elapsed % 1000;  // Save leftovers to prevent drift.

    // Increment both time counters.
    m_tcount += incr;           // Always increment uptime
    if (m_gps) m_gps += incr;   // Keep counting once set
}

// Offset from GPS epoch (1980 Jan 6) to the RtcTime epoch (2000 Jan 1).
// Note: 2000 Jan 1 is a Saturday (DOW = 6)
static constexpr s64 RTC_EPOCH =
    1042 * (s64)date::ONE_WEEK + 6 * (s64)date::ONE_DAY;

// Convert BCD value to ordinary value and vice-versa.
static inline u8 bcd2int(u8 bcd)
{
    return 10 * (bcd >> 4) + (bcd & 0x0F);
}
static inline u8 int2bcd(u8 x) {
    return 16 * (x / 10) + (x % 10);
}

// Lookup table converts BCD 12-hour time to 24-hour format.
// (Assume AM/PM flags follow the ISL12082 convention.)
u8 bcd_convert_24hr(u8 val)
{
    // If MIL flag is already set, simply convert from BCD.
    if (val & date::RTC_MIL_BIT)
        return bcd2int(val & 0x7F);

    // Otherwise, use the following lookup table:
    switch (val) {
    case 0x12:  return 0;   // 12 AM = 00:00 (midnight)
    case 0x01:  return 1;   //  1 AM = 01:00
    case 0x02:  return 2;   //  2 AM = 02:00
    case 0x03:  return 3;   //  3 AM = 03:00
    case 0x04:  return 4;   //  4 AM = 04:00
    case 0x05:  return 5;   //  5 AM = 05:00
    case 0x06:  return 6;   //  6 AM = 06:00
    case 0x07:  return 7;   //  7 AM = 07:00
    case 0x08:  return 8;   //  8 AM = 08:00
    case 0x09:  return 9;   //  9 AM = 09:00
    case 0x10:  return 10;  // 10 AM = 10:00
    case 0x11:  return 11;  // 11 AM = 11:00
    case 0x32:  return 12;  // 12 PM = 12:00 (noon)
    case 0x21:  return 13;  //  1 PM = 13:00
    case 0x22:  return 14;  //  2 PM = 14:00
    case 0x23:  return 15;  //  3 PM = 15:00
    case 0x24:  return 16;  //  4 PM = 16:00
    case 0x25:  return 17;  //  5 PM = 17:00
    case 0x26:  return 18;  //  6 PM = 18:00
    case 0x27:  return 19;  //  7 PM = 19:00
    case 0x28:  return 20;  //  8 PM = 20:00
    case 0x29:  return 21;  //  9 PM = 21:00
    case 0x30:  return 22;  // 10 PM = 22:00
    case 0x31:  return 23;  // 11 PM = 23:00
    }

    // Anything else is invalid.
    return 0xFF;
}

// Given year, return days in that year.
static inline unsigned days_per_year(u8 yy)
{
    // Assume year "00" is 2000, which is a leap year.
    return (yy % 4) ? 365 : 366;
}

// Given year and month, return days in that month.
static unsigned days_per_month(u8 yy, u8 mm)
{
    // Special-case for leap years:
    if ((mm == 2) && (yy % 4 == 0))
        return 29;

    // All other months by lookup table:
    switch (mm) {
    case 2:
        return 28;
    case 4: case 6: case 9: case 11:
        return 30;
    default:
        return 31;
    }
}

unsigned RtcTime::days_since_epoch() const
{
    if (!validate()) return UINT32_MAX;

    // Count days for each full year.
    unsigned total = 0;
    for (unsigned y = 0 ; y < yr ; ++y)
        total += days_per_year(y);

    // Count days for each full month.
    for (u32 m = 1 ; m < mo ; ++m)
        total += days_per_month(yr, m);

    // Count days in the current month.
    return total + dt - 1;
}

unsigned RtcTime::msec_since_midnight() const
{
    // Calculate total offset in milliseconds.
    if (validate())
        return 10*ss + 1000*sc + 60000*mn + 3600000*hr;
    else
        return UINT32_MAX;  // Error
}

GpsTime date::to_gps(s64 time)
{
    return GpsTime {
        (s32)(time / date::ONE_WEEK),   // Week number
        (u32)(time % date::ONE_WEEK)    // Time of week
    };
}

s64 date::from_gps(const GpsTime& time)
{
    return (s64)date::ONE_WEEK * time.wkn + time.tow;
}

RtcTime date::to_rtc(s64 time)
{
    // Convert to the RTC epoch (2000 Jan 1 @ 00:00:00).
    time -= RTC_EPOCH;

    // Split time into days-since-epoch and msec-since-midnight.
    u32 days = (u32)(time / date::ONE_DAY);
    u32 msec = (u32)(time % date::ONE_DAY);

    // This format can't represent anything outside 2000 - 2099.
    if ((time < 0) || (days >= 36525))
        return date::RTC_ERROR;

    // Calculate day of week (epoch is a Saturday = 6).
    u8 dw = (u8)((days + 6) % 7);

    // Deduct days for each full year.
    u8 yr = 0;
    while (days >= days_per_year(yr))
        days -= days_per_year(yr++);

    // Deduct days for each full month.
    u8 mo = 1;
    while (days >= days_per_month(yr, mo))
        days -= days_per_month(yr, mo++);

    // Whatever's leftover = Day-of-month.
    u8 dt = (u8)(days + 1);

    // Calculate hours, minutes, seconds...
    u32 rem = msec / 10;                    // Each tick = 10 msec
    u8 ss = (u8)(rem % 100);    rem /= 100; // Ticks
    u8 sc = (u8)(rem % 60);     rem /= 60;  // Seconds
    u8 mn = (u8)(rem % 60);     rem /= 60;  // Minutes
    u8 hr = (u8)(rem);

    // Construct the new RTC object.
    return RtcTime {dw, yr, mo, dt, hr, mn, sc, ss};
}

s64 date::from_rtc(const RtcTime& time)
{
    u32 days = time.days_since_epoch();
    u32 msec = time.msec_since_midnight();
    if ((days < UINT32_MAX) && (msec < UINT32_MAX))
        return RTC_EPOCH + (s64)date::ONE_DAY * days + msec;
    else
        return date::TIME_ERROR;
}

// Comparison and I/O helper functions
bool GpsTime::read_from(io::Readable* rd)
{
    if (rd->get_read_ready() < 8)
        return false;

    wkn = (s32)rd->read_u32();
    tow = rd->read_u32();
    return true;
}

bool GpsTime::operator<(const GpsTime& other) const
{
    if (wkn < other.wkn) return true;
    if (wkn > other.wkn) return false;
    return tow < other.tow;
}

bool GpsTime::operator==(const GpsTime& other) const
{
    return (wkn == other.wkn) && (tow == other.tow);
}

bool RtcTime::validate() const
{
    return (ss < 100) && (sc < 60) && (mn < 60) && (hr < 24)
        && (dt > 0) && (dt <= days_per_month(yr, mo))
        && (mo > 0) && (mo <= 12) && (yr < 100) && (dw < 7);
}

void RtcTime::write_to(satcat5::io::Writeable* wr) const
{
    // Convert each field to BCD format, then write.
    u8 temp[8];
    temp[0] = int2bcd(ss);      // Sub-seconds (0-99)
    temp[1] = int2bcd(sc);      // Seconds (0-59)
    temp[2] = int2bcd(mn);      // Minutes (0-59)
    temp[3] = int2bcd(hr) | date::RTC_MIL_BIT;  // Hours (0-23) + MIL bit
    temp[4] = int2bcd(dt);      // Day of month (1-31)
    temp[5] = int2bcd(mo);      // Month (1-12)
    temp[6] = int2bcd(yr);      // Year (00-99)
    temp[7] = int2bcd(dw);      // Day of week (0-6)
    wr->write_bytes(8, temp);
}

bool RtcTime::read_from(satcat5::io::Readable* rd)
{
    // Read raw bytes
    u8 temp[8];
    bool rdok = rd->read_bytes(8, temp);

    // Convert each field, ignoring most status flags.
    if (rdok) {
        ss = bcd2int(temp[0] & 0xFF);       // Sub-seconds (0-99)
        sc = bcd2int(temp[1] & 0x7F);       // Seconds (0-59)
        mn = bcd2int(temp[2] & 0x7F);       // Minutes (0-59)
        hr = bcd_convert_24hr(temp[3]);     // Hours (0-23)
        dt = bcd2int(temp[4] & 0x3F);       // Day of month (1-31)
        mo = bcd2int(temp[5] & 0x1F);       // Month (1-12)
        yr = bcd2int(temp[6] & 0xFF);       // Year (00-99)
        dw = bcd2int(temp[7] & 0x07);       // Day of week (0-6)
    }

    // Validate before returning.
    bool ok = rdok && validate();
    if (!ok) {ss = sc = mn = hr = dt = mo = yr = dw = 0;}
    return ok;
}

bool RtcTime::operator<(const RtcTime& other) const
{
    // Note: Ignore day-of-week field.
    if (yr < other.yr) return true;
    if (yr > other.yr) return false;
    if (mo < other.mo) return true;
    if (mo > other.mo) return false;
    if (dt < other.dt) return true;
    if (dt > other.dt) return false;
    if (hr < other.hr) return true;
    if (hr > other.hr) return false;
    if (mn < other.mn) return true;
    if (mn > other.mn) return false;
    if (sc < other.sc) return true;
    if (sc > other.sc) return false;
    return ss < other.ss;
}

bool RtcTime::operator==(const RtcTime& other) const
{
    // Note: Ignore day-of-week field.
    return (yr == other.yr)
        && (mo == other.mo)
        && (dt == other.dt)
        && (hr == other.hr)
        && (mn == other.mn)
        && (sc == other.sc)
        && (ss == other.ss);
}
