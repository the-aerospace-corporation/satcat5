//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Real-time clock conversion functions
//!
//!\details
//! The preferred representation for SatCat5 real-time functions is the number
//! of milliseconds since the GPS epoch (i.e., midnight between 1980 Jan 5 and
//! Jan 6).  This file defines various conversions to and from this format.
//!
//! (This is separate from the more precise satcat5::ptp::Time class used for PTP.)
//!
//! GPS time has the advantage that it has no time-zones, no leap-seconds, etc.
//! By definition, GPS time is always behind TAI by exactly 19 seconds.  Because
//! UTC inserts leap seconds every few years, the offset from GPS to UTC varies.
//! From 2017-2025, GPS has lead UTC by 18 seconds.
//!
//! Conversion functions to human-readable calendar formats are effectively in a
//! GPS "time-zone" that is more-or-less equivalent to TAI/UTC as noted above.
//!
//! For more information, including the current GPS/TAI/UTC time:
//!  http://www.leapsecond.com/java/gpsclock.htm
//! For an online conversion tool:
//!  https://www.labsat.co.uk/index.php/en/gps-time-calculator
//!
//! \see ptp_time.h


#pragma once

#include <satcat5/io_core.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_time.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace datetime {
        //! Common time-related constants, measured in milliseconds.
        //! e.g., One week = 604,800,000 milliseconds.
        //!@{
        static constexpr u32 ONE_SECOND = 1000;
        static constexpr u32 ONE_MINUTE = 60 * ONE_SECOND;
        static constexpr u32 ONE_HOUR   = 60 * ONE_MINUTE;
        static constexpr u32 ONE_DAY    = 24 * ONE_HOUR;
        static constexpr u32 ONE_WEEK   = 7 * ONE_DAY;
        //!@}

        //! A date/time of zero indicates an error.
        static constexpr s64 TIME_ERROR = 0;

        //! Convert an internal timestamp into the designated format.
        //! \link datetime.h Explanation of the SatCat5 datetime format. \endlink
        //!@{
        satcat5::datetime::GpsTime to_gps(s64 time);
        satcat5::ptp::Time to_ptp(s64 time);
        satcat5::datetime::RtcTime to_rtc(s64 time);
        //!@}

        //! Convert the designated format into an internal timestamp.
        //! \link datetime.h Explanation of the SatCat5 datetime format. \endlink
        //!@{
        s64 from_gps(const satcat5::datetime::GpsTime& time);
        s64 from_ptp(const satcat5::ptp::Time& time);
        s64 from_rtc(const satcat5::datetime::RtcTime& time);
        //!@}

        //! GPS week-number and time-of-week.
        //!
        //! The week number is the number of 7-day weeks since the GPS epoch.
        //! Each GPS week begins and ends at midnight boundary between
        //! Saturday and Sunday.
        //!
        //! The time of week (TOW) is the number of milliseconds since the start
        //! of the current GPS week.  Each week is 604,800,000 milliseconds.
        struct GpsTime {
            s32 wkn;    //!< Week number
            u32 tow;    //!< Time of week

            bool operator==(const satcat5::datetime::GpsTime& other) const;
            bool operator<(const satcat5::datetime::GpsTime& other) const;
            inline bool operator!=(const satcat5::datetime::GpsTime& other) const
                {return !operator==(other);}

            inline void write_to(satcat5::io::Writeable* wr) const
                {wr->write_u32((u32)wkn); wr->write_u32(tow);}
            bool read_from(satcat5::io::Readable* rd);
        };

        //! Hardware RTC (e.g., Renesas ISL12082).
        //! This format mimics the eight-byte timestamp used by many real-time
        //! clock ASICs, such as the Renesas ISL12082.  The resolution of this
        //! format is limited to 10-millisecond steps.
        //!
        //! For hardware compatibitilty, the Over-the-wire format used in
        //! `write_to` and `read_from` is BCD-coded.  For local use, the
        //! in-memory format uses normal binary values.
        //!
        //! Note: HR field will always be in 24-hour "military" format.
        struct RtcTime {
            u8 dw;      //!< Day of week (0-6, 0 = Sunday)
            u8 ct;      //!< Century (20 = year 20xx)
            u8 yr;      //!< Year (00-99)
            u8 mo;      //!< Month (1-12)
            u8 dt;      //!< Day-of-month (1-31)
            u8 hr;      //!< Hour (0-23) + MIL bit \see RTC_MIL_BIT
            u8 mn;      //!< Minutes (0-59)
            u8 sc;      //!< Seconds (0-59)
            u8 ss;      //!< Sub-seconds (0-99)

            //! Days since 2000 Jan 1 (a Saturday).
            u32 days_since_epoch() const;
            //! Milliseconds since midnight (0 - 86.4M).
            u32 msec_since_midnight() const;
            //! Are current contents valid?
            bool validate() const;

            bool operator==(const satcat5::datetime::RtcTime& other) const;
            bool operator<(const satcat5::datetime::RtcTime& other) const;

            //! Write legacy binary format (Deprecated).
            //! Note: Legacy format does not support years beyond 2099.
            void write_to(satcat5::io::Writeable* wr) const;

            //! Read legacy binary format (Deprecated).
            //! Note: Legacy format does not support years beyond 2099.
            bool read_from(satcat5::io::Readable* rd);

            //! Format as an ISO8601 / RFC3339 timestamp.
            //! ISO doesn't allow a "GPS" time-zone, so we use UTC instead.
            //! For better accuracy, add the current leap-second offset
            //! before converting the GPS timestamp to the RTC format.
            void log_to(satcat5::log::LogBuffer& wr) const;
        };

        //! Special datetime::RtcTime value indicating an error.
        static const datetime::RtcTime RTC_ERROR = {0, 0, 0, 0, 0, 0, 0, 0, 0};

        //! Bit-flag in HR field indicating 24-HOUR clock format.
        //! When calling RtcTime::write_to, this flag is always set.
        static const u8 RTC_MIL_BIT = 0x80;

        //! Real-time clock for tracking date/time.
        //! The global SATCAT5_CLOCK measures relative time only.  This
        //! object tracks that TimeRef to indicate the current date/time.
        //!
        //! To use this class:
        //!  * Obtain the current date/time from an external source.
        //!  * Convert to the SatCat5 internal format and call `set`.
        //!  * Call `now`, `gps`, or `ptp` at any point to obtain the
        //!    current date/time in the designated format.
        class Clock : protected satcat5::poll::Timer {
        public:
            //! Constructor defaults to T = 0 (unknown).
            Clock();

            //! Get elapsed time since startup, in milliseconds.
            //! \returns Uptime in milliseconds, wraps every ~49 days.
            //! This value is useful for ICMP timestamps, or for elapsed-time
            //! that exceeds the dynamic range of a satcat5::util::TimeVal.
            inline u32 uptime_msec() const {return m_tcount;}

            //! Get elapsed time since startup, in microseconds.
            //! \returns Uptime in microseconds, wraps every ~1.2 hours.
            u32 uptime_usec() const;

            //! Reset internals after changes to SATCAT5_CLOCK.
            //! Optionally reset uptime and GPS time.
            void reset(bool full = false);

            //! Set current GPS time. (0 = Unknown)
            //! For conversion \see `from_gps`, `from_ptp`, or `from_rtc`.
            void set(s64 gps);

            //! Current time as milliseconds since GPS epoch.
            inline s64 now() const {return m_gps;}
            //! Current time as GPS week number and time-of-week.
            inline satcat5::datetime::GpsTime gps() const
                { return satcat5::datetime::to_gps(m_gps); }
            //! Current time as Precision Time Protocol timestamp.
            inline satcat5::ptp::Time ptp() const
                { return satcat5::datetime::to_ptp(m_gps); }
            //! Current time as ISL12082 real-time clock timestamp.
            inline satcat5::datetime::RtcTime rtc() const
                { return satcat5::datetime::to_rtc(m_gps); }

        protected:
            friend satcat5::poll::OnDemandHelper;
            void timer_event() override;

            satcat5::util::TimeVal m_tref;
            u32 m_tcount;
            s64 m_gps;
        };

        //! Global instance of the datetime::Clock class.
        //! This instance is provided for general-use and convenience, but
        //! specialized use-cases may create and manage their own clocks.
        extern satcat5::datetime::Clock clock;
    }
}
