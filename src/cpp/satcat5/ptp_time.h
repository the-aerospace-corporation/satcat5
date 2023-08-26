//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
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
// High-precision "Time" object for use with PTP / IEEE1588
//
// This file defines a "Time" object that can be used to represent a
// time-difference or an absolute time in the TAI epoch, with enough
// resolution for the finest resolution supported by IEEE1588-2019.
//
// The internal representation is based on increments of 1/65536
// nanoseconds, which is referred to as a "subnanosecond" or "subns".

#pragma once

#include <satcat5/types.h>
#include <satcat5/utils.h>

namespace satcat5 {
    namespace ptp {
        // Define commonly used scaling factors:
        constexpr s64 NSEC_PER_SEC      = 1000000000LL;
        constexpr s64 NSEC_PER_MSEC     = 1000000LL;
        constexpr s64 NSEC_PER_USEC     = 1000LL;
        constexpr s64 USEC_PER_SEC      = 1000000LL;
        constexpr s64 MSEC_PER_SEC      = 1000LL;
        constexpr s64 SUBNS_PER_NSEC    = 65536LL;
        constexpr s64 SUBNS_PER_USEC    = SUBNS_PER_NSEC * NSEC_PER_USEC;
        constexpr s64 SUBNS_PER_MSEC    = SUBNS_PER_NSEC * NSEC_PER_MSEC;
        constexpr s64 SUBNS_PER_SEC     = SUBNS_PER_NSEC * NSEC_PER_SEC;

        // Object holding a PTP-compatible timestamp.
        class Time {
        public:
            // Single argument constructor is scaled in subnanoseconds.
            // (This matches the format used for the PTP "correction" field.)
            constexpr explicit Time(s64 subnanoseconds = 0)
                : m_secs (satcat5::util::divide(subnanoseconds, SUBNS_PER_SEC))
                , m_subns(satcat5::util::modulo(subnanoseconds, SUBNS_PER_SEC)) {}

            // Copy constructor.
            constexpr Time(const Time& other)
                : m_secs(other.m_secs), m_subns(other.m_subns) {}

            // Multi-argument constructor accepts seconds, nanoseconds, and subnanosecods.
            // (This matches the format used for the PTP "timestamp" field.)
            Time(u64 seconds, u32 nanoseconds, u16 subnanoseconds = 0);

            // Read-only accessors for individual fields.
            inline s64 secs() const     {return m_secs;}
            inline u32 nsec() const     {return (u32)satcat5::util::div_round(m_subns, SUBNS_PER_NSEC);}
            inline u64 subns() const    {return (u64)m_subns;}

            // Conversion for "small" time-differences.  Times beyond the safe
            // range (at least +/- 24 hours) will return INT64_MIN or INT64_MAX.
            s64 delta_subns() const;
            s64 delta_nsec() const;
            s64 delta_usec() const;
            s64 delta_msec() const;

            // Read or write the standard 10-byte PTP timestamp.
            // (e.g., originTimestamp: u48 seconds + u32 nanoseconds)
            bool read_from(satcat5::io::Readable* src);
            void write_to(satcat5::io::Writeable* dst) const;

            // Convert to SatCat5 date/time (see "datetime.h")
            s64 to_datetime() const;

            // Arithmetic operations:
            satcat5::ptp::Time abs() const;
            void operator+=(const satcat5::ptp::Time& other);
            void operator-=(const satcat5::ptp::Time& other);
            satcat5::ptp::Time operator=(const satcat5::ptp::Time& other);
            satcat5::ptp::Time operator+(const satcat5::ptp::Time& other) const;
            satcat5::ptp::Time operator-(const satcat5::ptp::Time& other) const;
            satcat5::ptp::Time operator-() const;

            // Scalar multiply and divide are used for weighted averaging.
            // Do not use scaling factors larger than ~10000 or it may overflow.
            void operator*=(unsigned scale);
            void operator/=(unsigned scale);
            satcat5::ptp::Time operator*(unsigned scale) const;
            satcat5::ptp::Time operator/(unsigned scale) const;

            // Comparison operations:
            bool operator==(const satcat5::ptp::Time& other) const;
            bool operator<(const satcat5::ptp::Time& other) const;
            bool operator>(const satcat5::ptp::Time& other) const;
            inline bool operator!=(const satcat5::ptp::Time& other) const {return !operator==(other);}
            inline bool operator<=(const satcat5::ptp::Time& other) const {return !operator>(other);}
            inline bool operator>=(const satcat5::ptp::Time& other) const {return !operator<(other);}

        protected:
            void normalize();       // Reduce to canonical form
            s64 m_secs;             // Seconds since epoch (may be negative)
            s64 m_subns;            // Subnanoseconds, range [0 .. SUBNS_PER_SEC)
        };

        // Convert from SatCat5 date/time to precision timestamp.
        satcat5::ptp::Time from_datetime(s64 gps_msec);

        // Common time-related constants.
        constexpr satcat5::ptp::Time ONE_NANOSECOND(SUBNS_PER_NSEC);
        constexpr satcat5::ptp::Time ONE_MICROSECOND(SUBNS_PER_USEC);
        constexpr satcat5::ptp::Time ONE_MILLISECOND(SUBNS_PER_MSEC);
        constexpr satcat5::ptp::Time ONE_SECOND(SUBNS_PER_SEC);
        constexpr satcat5::ptp::Time ONE_MINUTE(SUBNS_PER_SEC * 60);
        constexpr satcat5::ptp::Time ONE_HOUR(SUBNS_PER_SEC * 3600);
        constexpr satcat5::ptp::Time ONE_DAY(SUBNS_PER_SEC * 3600 * 24);
    }
}
