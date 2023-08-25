//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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
// Real-time clock conversion functions
//
// The preferred representation for SatCat5 real-time functions is the number
// of milliseconds since the GPS epoch (i.e., midnight between 1980 Jan 5 and
// Jan 6).  This file defines various conversions to and from this format.
//
// GPS time has the advantage that it has no time-zones, no leap-seconds, etc.
// By definition, GPS time is always behind TAI by exactly 19 seconds.  Because
// UTC inserts leap seconds every few years, the offset from GPS to UTC varies.
// From 2017-2021, GPS has lead UTC by 18 seconds.
//
// Conversion functions to human-readable calendar formats are effectively in a
// GPS "time-zone" that is more-or-less equivalent to TAI/UTC as noted above.
//
// For more information, including the current GPS/TAI/UTC time:
//  http://www.leapsecond.com/java/gpsclock.htm
// For an online conversion tool:
//  https://www.labsat.co.uk/index.php/en/gps-time-calculator
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_time.h>

namespace satcat5 {
    namespace datetime {
        // One week = 604,800,000 milliseconds.
        static constexpr u32 ONE_SECOND = 1000;
        static constexpr u32 ONE_MINUTE = 60 * ONE_SECOND;
        static constexpr u32 ONE_HOUR   = 60 * ONE_MINUTE;
        static constexpr u32 ONE_DAY    = 24 * ONE_HOUR;
        static constexpr u32 ONE_WEEK   = 7 * ONE_DAY;

        // A time of zero indicates an error.
        static constexpr s64 TIME_ERROR = 0;

        // Convert an internal timestamp into other formats:
        satcat5::datetime::GpsTime to_gps(s64 time);
        satcat5::ptp::Time to_ptp(s64 time);
        satcat5::datetime::RtcTime to_rtc(s64 time);

        // Convert other formats to an internal timestamp:
        s64 from_gps(const satcat5::datetime::GpsTime& time);
        s64 from_ptp(const satcat5::ptp::Time& time);
        s64 from_rtc(const satcat5::datetime::RtcTime& time);

        // GPS week-number and time-of-week:
        //  * Week number
        //    Number of 7-day weeks since the GPS epoch.  Each week begins and
        //    ends at midnight boundary between Saturday and Sunday.
        //  * Time of week
        //    Number of milliseconds since the start of the current GPS week.
        //    Each week = 604,800,000 milliseconds.
        struct GpsTime {
            s32 wkn;    // Week number
            u32 tow;    // Time of week

            bool operator==(const satcat5::datetime::GpsTime& other) const;
            bool operator<(const satcat5::datetime::GpsTime& other) const;
            inline bool operator!=(const satcat5::datetime::GpsTime& other) const
                {return !operator==(other);}

            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u32((u32)wkn); wr->write_u32(tow);}
            bool read_from(satcat5::io::Readable* rd);
        };

        // Hardware RTC (e.g., Renesas ISL12082)
        // This format mimics the eight-byte timestamp used by many real-time
        // clock ASICs, such as the Renesas ISL12082.
        // Note: Over-the-wire format is BCD-coded.
        //       In-memory format is normal binary values.
        // Note: Converted output will always be in 24-hour "military" format.
        // Note: Resolution is limited to 10-millisecond steps.
        struct RtcTime {
            u8 dw;      // Day of week (0-6, 0 = Sunday)
            u8 yr;      // Year (00-99)
            u8 mo;      // Month (1-12)
            u8 dt;      // Day-of-month (1-31)
            u8 hr;      // Hour (0-23) + MIL bit (see below)
            u8 mn;      // Minutes (0-59)
            u8 sc;      // Seconds (0-59)
            u8 ss;      // Sub-seconds (0-99)

            // Days since 2000 Jan 1 (a Saturday).
            unsigned days_since_epoch() const;
            // Milliseconds since midnight (0 - 86.4M).
            unsigned msec_since_midnight() const;
            // Are current contents valid?
            bool validate() const;

            bool operator==(const satcat5::datetime::RtcTime& other) const;
            bool operator<(const satcat5::datetime::RtcTime& other) const;

            void write_to(satcat5::io::Writeable* wr) const;
            bool read_from(satcat5::io::Readable* rd);
        };

        static const datetime::RtcTime RTC_ERROR = {0, 0, 0, 0, 0, 0, 0, 0};
        static const u8 RTC_MIL_BIT = 0x80; // Indicates 24-HOUR clock format

        // Real-time clock tracking.  Defaults to T = 0 (unknown).  To use:
        //  * Instantiate this object and provide a reference timer.
        //    (The timer is used to self-correct for irregular updates.)
        //  * Obtain the current clock time from an external source.
        //  * Convert to GPS time (see functions below) and call set(...).
        //  * Call now(), gps(), or ptp() at any point to obtain the current
        //    time in the designated format.
        class Clock : protected satcat5::poll::Timer {
        public:
            // Constructor requires a reference timer to prevent drift.
            explicit Clock(satcat5::util::GenericTimer* timer);

            // Get elapsed time since startup (e.g., for ICMP timestamps)
            inline u32 uptime() const {return m_tcount;}

            // Set/get current GPS time. (0 = Unknown)
            //  now() = Milliseconds since GPS epoch.
            //  gps() = GPS week number and time-of-week.
            //  ptp() = Precision Time Protocol timestamp.
            //  rtc() = ISL12082 real-time clock.
            void set(s64 gps);
            inline s64 now() const {return m_gps;}
            inline satcat5::datetime::GpsTime gps() const
                { return satcat5::datetime::to_gps(m_gps); }
            inline satcat5::ptp::Time ptp() const
                { return satcat5::datetime::to_ptp(m_gps); }
            inline satcat5::datetime::RtcTime rtc() const
                { return satcat5::datetime::to_rtc(m_gps); }

        protected:
            void timer_event() override;

            satcat5::util::GenericTimer* const m_timer;
            unsigned m_frac;
            u32 m_tref, m_tcount;
            s64 m_gps;
        };
    }
}
