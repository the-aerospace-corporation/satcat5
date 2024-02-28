//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
            // Default constructor.
            constexpr Time()
                : m_secs(0), m_subns(0) {}

            // Single argument constructor is scaled in subnanoseconds.
            // (This matches the format used for the PTP "correction" field.)
            constexpr explicit Time(s64 subnanoseconds)
                : m_secs (satcat5::util::divide(subnanoseconds, SUBNS_PER_SEC))
                , m_subns(satcat5::util::modulo(subnanoseconds, SUBNS_PER_SEC)) {}

            // Copy constructor.
            constexpr Time(const Time& other)
                : m_secs(other.m_secs), m_subns(other.m_subns) {}

            // Multi-argument constructor accepts seconds, nanoseconds, and subnanosecods.
            // (This matches the format used for the PTP "timestamp" field.)
            Time(u64 seconds, u32 nanoseconds, u16 subnanoseconds = 0);

            // Read-only accessors for individual fields.
            // Use "field_xx()" in combination with "correction()", below.
            // Use "round_xx()" for safe rounding to nearest nanosecond.
            inline s64 field_secs() const
                {return m_secs;}
            inline u32 field_nsec() const
                {return (u32)satcat5::util::div_floor(m_subns, SUBNS_PER_NSEC);}
            inline u64 field_subns() const
                {return (u64)m_subns;}
            inline s64 round_secs() const
                {return (*this + Time(SUBNS_PER_NSEC / 2)).field_secs();}
            inline u32 round_nsec() const
                {return (*this + Time(SUBNS_PER_NSEC / 2)).field_nsec();}

            // Conversion for "small" time-differences.  Times beyond the safe
            // range (at least +/- 24 hours) will return INT64_MIN or INT64_MAX.
            s64 delta_subns() const;
            s64 delta_nsec() const;
            s64 delta_usec() const;
            s64 delta_msec() const;

            // Read or write the standard 10-byte PTP timestamp.
            // (e.g., originTimestamp: u48 seconds + u32 nanoseconds)
            // Note: This does not preserve subnanosecond precision.
            bool read_from(satcat5::io::Readable* src);
            void write_to(satcat5::io::Writeable* dst) const;

            // User-readable format for logging.
            void log_to(satcat5::log::LogBuffer& wr) const;

            // To preserve full precision (see above), sender should set the
            // initial value of "correctionField" using this accessor.
            inline u64 correction() const
                {return (u64)satcat5::util::modulo(m_subns, SUBNS_PER_NSEC);}

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
        constexpr satcat5::ptp::Time TIME_ZERO(0LL);
        constexpr satcat5::ptp::Time ONE_NANOSECOND(SUBNS_PER_NSEC);
        constexpr satcat5::ptp::Time ONE_MICROSECOND(SUBNS_PER_USEC);
        constexpr satcat5::ptp::Time ONE_MILLISECOND(SUBNS_PER_MSEC);
        constexpr satcat5::ptp::Time ONE_SECOND(SUBNS_PER_SEC);
        constexpr satcat5::ptp::Time ONE_MINUTE(SUBNS_PER_SEC * 60);
        constexpr satcat5::ptp::Time ONE_HOUR(SUBNS_PER_SEC * 3600);
        constexpr satcat5::ptp::Time ONE_DAY(SUBNS_PER_SEC * 3600 * 24);
    }
}
