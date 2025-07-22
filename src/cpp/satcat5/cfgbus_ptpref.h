//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! ConfigBus-controlled PTP reference counter (ptp_counter_gen.vhd).
//!
//!\details
//! Various PTP reference counters can operate in free-running mode, or as a
//! software-adjustable NCO.  Several HDL blocks share the same interface:
//!  * ptp_counter_free (rate only)
//!  * ptp_counter_gen (rate only)
//!  * ptp_realtime (rate + shift)
//! This file implements the TrackingClock interface for closed-loop software
//! control of compatible NCOs. \see ptp_tracking.h.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/ptp_filters.h>
#include <satcat5/ptp_tracking.h>

namespace satcat5 {
    namespace cfg {
        //! PTP reference counter with rate-control only.
        //! \see cfgbus_ptpref.h, cfg::PtpRealtime.
        class PtpReference : public satcat5::ptp::TrackingClock {
        public:
            //! PtpReference is a thin-wrapper for a single control register.
            //! Clock rate is required to renormalize frequency adjustments.
            //! Default scale parameter matches "ptp_counter_free.vhd".
            constexpr PtpReference(
                const satcat5::cfg::Register& reg,
                double ref_clk_hz, unsigned scale=40)
                : m_reg(reg), m_rate(ref_clk_hz, scale) {}

            // Implement rate-control only for the TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;
            satcat5::ptp::Time clock_now() override;

            //! Legacy API for rate-control without additional scaling.
            void clock_rate_raw(s64 rate);

        protected:
            satcat5::cfg::Register m_reg;   // Control register
            const satcat5::ptp::RateConversion m_rate;
        };

        //! PTP reference with rate-control and coarse-adjust command.
        //! \see cfgbus_ptpref.h, cfg::PtpReference.
        class PtpRealtime : public satcat5::ptp::TrackingClock {
        public:
            //! PtpRealtime uses a block of six control registers.
            //! Clock rate is required to renormalize frequency adjustments.
            //! Default scale parameter matches "ptp_realtime.vhd".
            constexpr PtpRealtime(
                const satcat5::cfg::Register& reg,
                double ref_clk_hz, unsigned scale=40)
                : m_reg(reg), m_rate(ref_clk_hz, scale) {}

            // Implement the full TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;
            satcat5::ptp::Time clock_now() override;

            //! Legacy API for rate-control without additional scaling.
            void clock_rate_raw(s64 rate);

            //! Read timestamp of external rising-edge signal.
            satcat5::ptp::Time clock_ext();

            //! Coarse adjustment of the current time.
            void clock_set(const satcat5::ptp::Time& new_time);

        protected:
            void load(const satcat5::ptp::Time& time);
            satcat5::cfg::Register m_reg;   // Base control register
            const satcat5::ptp::RateConversion m_rate;
        };
    }
}
