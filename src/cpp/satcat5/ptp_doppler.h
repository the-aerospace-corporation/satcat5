//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Doppler Precision Time Protocol (Doppler-PTP)
//
// Ordinary PTP assumes all nodes are stationary, the path length is
// fixed, and delays in each direction are symmetric.  Violating these
// assumptions results in biased or inaccurate time transfer.  This
// file defines experimental extensions that relax these assumptions,
// allowing motion to be measured and mitigated for better accuracy.
//
// The largest change is the creation of a new TLV for Doppler metadata.
// This file implements the software that initializes and read such tags
// at each endpoint.  Transparent clocks that support Doppler-TLV require
// gateware or hardware that increments the tag's contents at each hop.
//

#pragma once

#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_tlv.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace ptp {
        // TlvHandler for the Doppler-TLV tags.
        class DopplerTlv : public satcat5::ptp::TlvHandler {
        public:
            // Link this instance to a specific PTP client.
            explicit DopplerTlv(satcat5::ptp::Client* client);

            // Add to the chain of processing filters.
            // Filters are applied in the order added.
            inline void add_filter(satcat5::ptp::Filter* filter)
                { m_predict.add_filter(filter); }

            // Enable or disable timestamp compensation.
            // (The default setting is given by SATCAT5_DOPPLER_TCOMP.)
            inline bool get_tcomp_en() const
                { return m_tcomp; }
            inline void set_tcomp_en(bool enable)
                { m_tcomp = enable; }

            // Measured velocity (subns/sec) or acceleration (subns/sec^2).
            inline s64 get_velocity() const
                { return m_predict.predict(0); }
            inline s64 get_acceleration() const
                { return m_predict.predict(1000000) - m_predict.predict(0); }

            // Required TlvHandler API.
            bool tlv_rcvd(
                const satcat5::ptp::Header& hdr,
                const satcat5::ptp::TlvHeader& tlv,
                satcat5::io::LimitedRead& rd) override;
            unsigned tlv_send(
                const satcat5::ptp::Header& hdr,
                satcat5::io::Writeable* wr) override;
            void tlv_meas(satcat5::ptp::Measurement& meas) override;

        protected:
            satcat5::ptp::LinearPrediction m_predict;
            s64 m_dstamp;
            satcat5::util::TimeVal m_tref;
            bool m_tcomp;
        };

        // Streamlined variant of ptp::DopplerTlv, with a built-in
        // filter chain that is adequate for most PTP applications.
        class DopplerSimple : public satcat5::ptp::DopplerTlv {
        public:
            explicit DopplerSimple(satcat5::ptp::Client* client);

        protected:
            satcat5::ptp::AmplitudeReject m_ampl;
            satcat5::ptp::ControllerPI m_ctrl;
        };
    }
}
