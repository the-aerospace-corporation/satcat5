//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Shared message header for the Precision Time Protocol (PTP / IEEE-1588)
//
// This file defines an object representing the 34-byte header that is
// common to all PTP messages, defined in IEEE 1588-2019 Section 13.3.
// Most PTP messages append additional data after this header.
//

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace ptp {
        // Struct used for sourcePortIdentity and requestingPortIdentity.
        struct PortId {
            // portIdentity is defined in Section 7.5.2.1
            u64 clock_id;
            u16 port_num;

            // Equality check.
            inline bool operator==(const PortId& other) const {
                return (clock_id == other.clock_id)
                    && (port_num == other.port_num);
            }

            // I/O functions.
            bool read_from(satcat5::io::Readable* rd);
            void write_to(satcat5::io::Writeable* wr) const;
        };

        // Struct representing the PTP header used for all message types.
        struct Header {
            // Message header fields (Section 13.3)
            u8  type;                       // messageType (0-15)
            u8  version;                    // versionPTP only
            u16 length;                     // messageLength
            u8  domain;                     // domainNumber
            u16 sdo_id;                     // majorSdoId + minorSdoId
            u16 flags;                      // flagField
            u64 correction;                 // correctionField
            u32 subtype;                    // messageTypeSpecific
            satcat5::ptp::PortId src_port;  // sourcePortIdentity
            u16 seq_id;                     // sequenceId
            u8  control;                    // controlField
            s8  log_interval;               // logMessageInterval

            // Header itself is exactly 34 bytes.
            static constexpr unsigned HEADER_LEN = 34;

            // Message types (Section 13.3.2.3 / Table 36)
            static constexpr u8
                TYPE_SYNC           = 0x0,
                TYPE_DELAY_REQ      = 0x1,
                TYPE_PDELAY_REQ     = 0x2,
                TYPE_PDELAY_RESP    = 0x3,
                TYPE_FOLLOW_UP      = 0x8,
                TYPE_DELAY_RESP     = 0x9,
                TYPE_PDELAY_RFU     = 0xA,
                TYPE_ANNOUNCE       = 0xB,
                TYPE_SIGNALING      = 0xC,
                TYPE_MANAGEMENT     = 0xD;

            // Flag definitions (Section 13.3.2.8 / Table 37)
            static constexpr u16
                FLAG_LEAP61         = (1u << 0),
                FLAG_LEAP59         = (1u << 1),
                FLAG_UTC_VALID      = (1u << 2),
                FLAG_PTP_TIMESCALE  = (1u << 3),
                FLAG_TIME_TRACEABLE = (1u << 4),
                FLAG_FREQ_TRACEABLE = (1u << 5),
                FLAG_UNCERTAIN      = (1u << 6),
                FLAG_ALT_MASTER     = (1u << 8),
                FLAG_TWO_STEP       = (1u << 9),
                FLAG_UNICAST        = (1u << 10),
                FLAG_PROFILE1       = (1u << 13),
                FLAG_PROFILE2       = (1u << 14);

            // I/O functions
            bool read_from(satcat5::io::Readable* rd);
            void write_to(satcat5::io::Writeable* wr) const;
        };

        // Clock configuration metadata for the ANNOUNCE message.
        struct ClockInfo {
            // Fields defined in Section 13.5.1, Table 43.
            // (ClockQuality subfields defined in Section 5.3.7)
            u8  grandmasterPriority1;   // Note: Lower takes priority
            u8  grandmasterClass;       // Traceability to reference?
            u8  grandmasterAccuracy;    // Approximate accuracy
            u16 grandmasterVariance;    // Fixed-point variance
            u8  grandmasterPriority2;   // Note: Lower takes priority
            u64 grandmasterIdentity;    // Unique identifier
            u16 stepsRemoved;           // Number of hops to grandmaster
            u8  timeSource;             // Reference type

            // Priority index: Lower values take priority.
            static constexpr u8
                PRIORITY_MIN    = 255,
                PRIORITY_MID    = 128,
                PRIORITY_MAX    = 0;

            // ClockClass values from Section 7.6.2.5, Table 4.
            // (Indicates whether a clock is traceable to NIST or similar.)
            static constexpr u8
                CLASS_PRIMARY   = 6,        // Primary reference
                CLASS_APP_SPEC  = 13,       // Application-specific reference
                CLASS_DEFAULT   = 248,      // Any other clock
                CLASS_SLAVE     = 255;      // Any slave-only clock

            // Accuracy enumeration from Section 7.6.2.6, Table 5.
            static constexpr u8
                ACCURACY_1PSEC      = 0x17,
                ACCURACY_2PSEC      = 0x18,
                ACCURACY_10PSEC     = 0x19,
                ACCURACY_25PSEC     = 0x1A,
                ACCURACY_100PSEC    = 0x1B,
                ACCURACY_250PSEC    = 0x1C,
                ACCURACY_1NSEC      = 0x1D,
                ACCURACY_2NSEC      = 0x1E,
                ACCURACY_10NSEC     = 0x1F,
                ACCURACY_25NSEC     = 0x20,
                ACCURACY_100NSEC    = 0x21,
                ACCURACY_250NSEC    = 0x22,
                ACCURACY_1USEC      = 0x23,
                ACCURACY_2USEC      = 0x24,
                ACCURACY_10USEC     = 0x25,
                ACCURACY_25USEC     = 0x26,
                ACCURACY_100USEC    = 0x27,
                ACCURACY_250USEC    = 0x28,
                ACCURACY_1MSEC      = 0x29,
                ACCURACY_2MSEC      = 0x2A,
                ACCURACY_10MSEC     = 0x2B,
                ACCURACY_25MSEC     = 0x2C,
                ACCURACY_100MSEC    = 0x2D,
                ACCURACY_250MSEC    = 0x2E,
                ACCURACY_1SEC       = 0x2F,
                ACCURACY_10SEC      = 0x30,
                ACCURACY_LOW        = 0x31,
                ACCURACY_UNK        = 0xFE;

            // The "offsetScaledLogVariance" metric defined in Section 7.6.3.3
            // is a fixed-point representation of the Allan deviation:
            //      round(512 * log2(adev_sec) + 32768)
            // The constants defined below are precalculated examples.
            static constexpr u16
                VARIANCE_1PSEC      = 0x3046,
                VARIANCE_10PSEC     = 0x36EB,
                VARIANCE_100PSEC    = 0x3D90,
                VARIANCE_1NSEC      = 0x4435,
                VARIANCE_10NSEC     = 0x4AD9,
                VARIANCE_100NSEC    = 0x517E,
                VARIANCE_1USEC      = 0x5823,
                VARIANCE_10USEC     = 0x5EC8,
                VARIANCE_100USEC    = 0x656D,
                VARIANCE_1MSEC      = 0x6C12,
                VARIANCE_10MSEC     = 0x72B6,
                VARIANCE_100MSEC    = 0x795B,
                VARIANCE_1SEC       = 0x8000,
                VARIANCE_MAX        = 0xFFFF;

            // TimeSource values from Section 7.6.2.8, Table 6.
            static constexpr u8
                SRC_ATOMIC      = 0x10,     // Local atomic clock
                SRC_GNSS        = 0x20,     // GPS, Galileo, etc.
                SRC_RADIO       = 0x30,     // Terrestrial radio
                SRC_SERIAL      = 0x39,     // IRIG-B or similar
                SRC_PTP         = 0x40,     // Another PTP domain
                SRC_NTP         = 0x50,     // Network time protocol
                SRC_MANUAL      = 0x60,     // Human-provided
                SRC_OTHER       = 0x90,     // Any other source
                SRC_INTERNAL    = 0xA0;     // Internal oscillator

            // I/O functions
            bool read_from(satcat5::io::Readable* rd);
            void write_to(satcat5::io::Writeable* wr) const;
        };

        // Default clock with extremely low priority on all metrics.
        constexpr satcat5::ptp::ClockInfo DEFAULT_CLOCK = {
            ClockInfo::PRIORITY_MIN,    // Lowest possible priority
            ClockInfo::CLASS_DEFAULT,   // Unspecified traceability
            ClockInfo::ACCURACY_UNK,
            ClockInfo::VARIANCE_MAX,
            ClockInfo::PRIORITY_MIN,
            0,                          // User should replace source-ID
            0,                          // Grandmaster = self
            ClockInfo::SRC_INTERNAL,
        };

        // Example of a high-quality GPS-disciplined clock.
        constexpr satcat5::ptp::ClockInfo VERY_GOOD_CLOCK = {
            ClockInfo::PRIORITY_MID,    // Mid-priority
            ClockInfo::CLASS_PRIMARY,   // Directly traceable to GPS
            ClockInfo::ACCURACY_25NSEC,
            ClockInfo::VARIANCE_10NSEC,
            ClockInfo::PRIORITY_MID,
            0,                          // User should replace source-ID
            0,                          // Grandmaster = self
            ClockInfo::SRC_INTERNAL,
        };
    }
}
