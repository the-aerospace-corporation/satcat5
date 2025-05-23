//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Define the data structure for a two-way time transfer handshake

#pragma once

#include <satcat5/ptp_header.h>
#include <satcat5/ptp_time.h>

// Cache-size parameter sets the maximum number of two-way
// PTP handshakes that can be in-flight at a given time.
#ifndef SATCAT5_PTP_CACHE_SIZE
#define SATCAT5_PTP_CACHE_SIZE 4
#endif

namespace satcat5 {
    namespace ptp {
        //! Timestamps and metadata for a two-way time-transfer handshake.
        //!
        //! The Precision Time Protocol (PTP / IEEE-1588-2019) defines several
        //! variations on the two-way time-transfer handshake.  The process
        //! is illustrated in Section 11.3 Figure 41 (leader-follower) and in
        //! Section 11.4 Figure 42 (peer-to-peer).  In both cases, each complete
        //! measurement requires four timestamps:
        //!  * t1 = Tx time of 1st message (A to B, measured in A's clock)
        //!  * t2 = Rx time of 1st message (A to B, measured in B's clock)
        //!  * t3 = Tx time of 2nd message (B to A, measured in B's clock)
        //!  * t4 = Rx time of 2nd message (B to A, measured in A's clock)
        //!
        //! The `Measurement` class holds the four timestamps of a given
        //! measurement, plus additional metadata such as sequence-ID used to
        //! match packets to a given exchange.
        //! \see MeasurementCache
        struct Measurement {
            //! Reference header is copied from the initiating PTP message
            //! (i.e., SYNC or PDELAY_REQ) and used to match later messages.
            satcat5::ptp::Header ref;
            satcat5::ptp::Time t1;      //!< Timestamp T1 (A to B / Tx)
            satcat5::ptp::Time t2;      //!< Timestamp T2 (A to B / Rx)
            satcat5::ptp::Time t3;      //!< Timestamp T3 (B to A / Tx)
            satcat5::ptp::Time t4;      //!< Timestamp T4 (B to A / Rx)

            //! Is this measurement completed? (i.e., T1/T2/T3/T4 all known)
            bool done() const;

            //! Write all four timestamps to the log.
            void log_to(satcat5::log::LogBuffer& wr) const;

            //! Check if an incoming message matches this exchange.
            //! (i.e., Matching sequence-ID, sdo_id, etc.)
            bool match(
                const satcat5::ptp::Header& hdr,
                const satcat5::ptp::PortId& port) const;

            //! Calculate PTP "meanPathDelay".
            //! Calculate derived clock parameters using the recommended methods
            //! defined in IEEE 1588-2019 Section 11.
            satcat5::ptp::Time mean_path_delay() const;
            //! Calculate PTP "meanLinkDelay". \copydetails mean_path_delay
            satcat5::ptp::Time mean_link_delay() const;
            //! Calculate PTP "offsetFromMaster". \copydetails mean_path_delay
            satcat5::ptp::Time offset_from_master() const;

            //! Reset this data structure for immediate reuse.
            //! Reset (overwrite) the current measurement state, saving
            //! the header of the initiating SYNC or PDELAY_REQ message.
            void reset(const satcat5::ptp::Header& hdr);
        };

        //! Placeholder for an empty Measurement.
        constexpr satcat5::ptp::Measurement MEASUREMENT_NULL = {};

        //! Searchable cache of recent Measurement objects.
        //! The `MeasurementCache` class defines a searchable cache of recent
        //! in-progress Measurement objects.  Each ptp::Client uses the cache
        //! to match incoming messages against previous received messages.
        class MeasurementCache {
        public:
            //! Create an empty cache.
            constexpr MeasurementCache()
                : m_next_wr(0), m_buff{} {}

            //! Find the first matching measurement in the cache.
            //! (If no match is found, return NULL.)
            satcat5::ptp::Measurement* find(
                const satcat5::ptp::Header& hdr,
                const satcat5::ptp::PortId& port);

            //! Shortcut for searches where port = hdr.src_port.
            inline satcat5::ptp::Measurement* find(
                const satcat5::ptp::Header& hdr)
                { return find(hdr, hdr.src_port); }

            //! Create a new measurement, overwriting the oldest.
            //! \returns A pointer to the newly-created Measurement object.
            satcat5::ptp::Measurement* push(
                const satcat5::ptp::Header& hdr);

        protected:
            unsigned m_next_wr;
            satcat5::ptp::Measurement m_buff[SATCAT5_PTP_CACHE_SIZE];
        };
    }
}
