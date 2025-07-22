//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Type definitions for manipulating TCP segments
//!
//!\details
//! SatCat5 does not yet support TCP/IP, but sometimes needs to manipulate
//! TCP headers (e.g., `router::BasicNat`). This file defines a minimal
//! skeleton for simple operations. It may be expanded in future versions.

#pragma once

#include <satcat5/ip_core.h>

namespace satcat5 {
    namespace tcp {
        // Alias for address and port types in the "tcp" namespace.
        typedef satcat5::ip::Addr Addr;
        typedef satcat5::ip::Port Port;

        //! Minimum and maximum TCP header length parameters.
        //!@{
        constexpr unsigned HDR_MIN_WORDS        = 5;
        constexpr unsigned HDR_MIN_SHORTS       = 2 * HDR_MIN_WORDS;
        constexpr unsigned HDR_MIN_BYTES        = 4 * HDR_MIN_WORDS;
        constexpr unsigned HDR_MAX_WORDS        = 15;
        constexpr unsigned HDR_MAX_SHORTS       = 2 * HDR_MAX_WORDS;
        constexpr unsigned HDR_MAX_BYTES        = 4 * HDR_MAX_WORDS;
        //!@}

        //! TCP header contents. \see tcp_core.h.
        struct Header {
            //! Raw access to the underlying header contents.
            u16 data[HDR_MAX_SHORTS];

            // Accessors for specific sub-fields.
            // https://en.wikipedia.org/wiki/Transmission_Control_Protocol#TCP_segment_structure
            constexpr satcat5::tcp::Port src() const    //!< Source port
                { return satcat5::tcp::Port{data[0]}; }
            constexpr satcat5::tcp::Port dst() const    //!< Destination port
                { return satcat5::tcp::Port{data[1]}; }
            constexpr unsigned ihl() const              //!< Header length (4-byte words)
                { return (data[6] >> 12) & 0x0F; }
            constexpr u16 chk() const                   //!< Checksum (incoming only)
                { return data[8]; }

            //! Incremental update to checksum by replacing a given field.
            //! The before/after values can any location in the TCP psuedo-header
            //! Uses the ~m + m' method of RFC1624 Section 3.
            void chk_incr16(u16 prev, u16 next);
            void chk_incr32(u32 prev, u32 next);

            //! Write TCP header to the designated stream.
            void write_to(satcat5::io::Writeable* wr) const;

            //! Read a partial TCP header from the designated stream.
            //! This method reads the first 20 bytes of a TCP header, which
            //! contains basic header fields but not variable-length options
            //! (i.e., OFFSET > 5).  This is used in cases where the full header
            //! is unavailable or unnecessary (e.g., due to "peek" limits). To
            //! read the entire TCP checksum, \see read_from.
            //! \returns True if the partial header is valid, false otherwise.
            bool read_core(satcat5::io::Readable* rd);

            //! Read TCP header from the designated stream.
            //! This method calls `read_core`, then reads variable-length
            //! header options up to the start of user data.  It does not
            //! validate the TCP checksum.
            //! \returns True if header is valid, false otherwise.
            bool read_from(satcat5::io::Readable* rd);
        };
    }
}
