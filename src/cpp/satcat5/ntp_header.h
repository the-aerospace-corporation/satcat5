//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Message headers for the Network Time Protocol (NTP / IETF RFC-5905)

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>

namespace satcat5 {
    namespace ntp {
        //! Message headers for the Network Time Protocol (NTP / IETF RFC-5905).
        //!
        //! This struct represents the NTP message header, as defined in
        //! RFC-5905 Section 7.3 and Figure 8.  It includes all basic
        //! information, but not the extension fields or message digest.
        //! Support for MD5 authentication may be added in future versions.
        struct Header {
            // Message header fields (Section 7.3)
            u8  lvm;                        //!< Combined LI + VN + Mode
            u8  stratum;                    //!< Hops to grandmaster (1-15)
            s8  poll;                       //!< Interval = 2^N seconds
            s8  precision;                  //!< Precision = 2^N seconds
            u32 rootdelay;                  //!< Round trip delay to grandmaster
            u32 rootdisp;                   //!< Total dispersion to grandmaster
            u32 refid;                      //!< Server-ID or KoD code
            u64 ref;                        //!< Time of last sync to parent
            u64 org;                        //!< T1 (Client transmit time)
            u64 rec;                        //!< T2 (Server receive time)
            u64 xmt;                        //!< T3 (Server transmit time)

            //! The basic header is exactly 12 words = 48 bytes long.
            static constexpr unsigned HEADER_LEN = 34;

            //! Leap second indictor (LI) for last minute of current day.
            static constexpr u8
                LI_MASK     = (3 << 6),     // LI = Bits 7:6
                LEAP_NONE   = (0 << 6),     // No leap second expected
                LEAP_61     = (1 << 6),     // Insert leap-second (Append 23:59:60)
                LEAP_59     = (2 << 6),     // Remove leap-second (Skip 23:59:59)
                LEAP_UNK    = (3 << 6);     // Unknown / clock unsynchronized

            //! Version number is always 4.
            static constexpr u8
                VN_MASK     = (7 << 3),     // VN = Bits 5:3
                VERSION_3   = (3 << 3),     // Version 3 (RFC-958, published 1992)
                VERSION_4   = (4 << 3);     // Version 4 (RFC-5905, published 2010)

            //! Mode number indicates client or server role.
            static constexpr u8
                MODE_MASK   = 0x7,          // Mode = Bits 2:0
                MODE_RSVD   = 0,            // Reserved
                MODE_SYMM1  = 1,            // Symmetric active
                MODE_SYMM0  = 2,            // Symmetric passive
                MODE_CLIENT = 3,            // Client (issues request)
                MODE_SERVER = 4,            // Server (issues reply)
                MODE_BCAST  = 5,            // Broadcast
                MODE_CTRL   = 6,            // NTP control message
                MODE_PRIVAT = 7;            // Reserved for private use

            //! Reserved RefIDs, aka "kiss codes" (Section 7.4)
            static constexpr u32
                KISS_ACST   = 0x41435354u,
                KISS_AUTH   = 0x41555448u,
                KISS_AUTO   = 0x4155544Fu,
                KISS_BCST   = 0x42435354u,
                KISS_CRYP   = 0x43525950u,
                KISS_DENY   = 0x44454E59u,
                KISS_DROP   = 0x44524F50u,
                KISS_RSTR   = 0x52535452u,
                KISS_INIT   = 0x494E4954u,
                KISS_MCST   = 0x4D435354u,
                KISS_NKEY   = 0x4E4B4559u,
                KISS_RATE   = 0x52415445u,
                KISS_RMOT   = 0x524D4F54u,
                KISS_STEP   = 0x53544550u;

            //! Named constants for polling intervals and dispersion.
            static constexpr s8
                TIME_1HOUR      = 12,
                TIME_32MIN      = 11,
                TIME_16MIN      = 10,
                TIME_8MIN       = 9,
                TIME_4MIN       = 8,
                TIME_2MIN       = 7,
                TIME_1MIN       = 6,
                TIME_32SEC      = 5,
                TIME_16SEC      = 4,
                TIME_8SEC       = 3,
                TIME_4SEC       = 2,
                TIME_2SEC       = 1,
                TIME_1SEC       = 0,
                TIME_500MSEC    = -1,
                TIME_250MSEC    = -2,
                TIME_125MSEC    = -3,
                TIME_64MSEC     = -4,
                TIME_32MSEC     = -5,
                TIME_16MSEC     = -6,
                TIME_8MSEC      = -7,
                TIME_4MSEC      = -8,
                TIME_2MSEC      = -9,
                TIME_1MSEC      = -10,
                TIME_500USEC    = -11,
                TIME_250USEC    = -12,
                TIME_125USEC    = -13,
                TIME_64USEC     = -14,
                TIME_32USEC     = -15,
                TIME_16USEC     = -16,
                TIME_8USEC      = -17,
                TIME_4USEC      = -18,
                TIME_2USEC      = -19,
                TIME_1USEC      = -20,
                TIME_500NSEC    = -21,
                TIME_250NSEC    = -22,
                TIME_125NSEC    = -23,
                TIME_64NSEC     = -24,
                TIME_32NSEC     = -25,
                TIME_16NSEC     = -26,
                TIME_8NSEC      = -27,
                TIME_4NSEC      = -28,
                TIME_2NSEC      = -29,
                TIME_1NSEC      = -30;

            //! Accessors for splitting LI, VN, and Mode fields.
            //!@{
            inline u8 li() const    { return lvm & LI_MASK; }
            inline u8 vn() const    { return lvm & VN_MASK; }
            inline u8 mode() const  { return lvm & MODE_MASK; }
            //!@}

            //! Human-readable formatting of the header contents.
            void log_to(satcat5::log::LogBuffer& wr) const;
            //! Read this header from a data source.
            bool read_from(satcat5::io::Readable* rd);
            //! Write this header to a data sink.
            void write_to(satcat5::io::Writeable* wr) const;
        };
    }
}
