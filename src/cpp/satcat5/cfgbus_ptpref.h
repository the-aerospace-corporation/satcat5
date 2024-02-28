//////////////////////////////////////////////////////////////////////////
// Copyright 2022-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus-controlled PTP reference counter (ptp_counter_gen.vhd)
//
// Various PTP reference counters can operate in free-running mode, or as a
// software-adjustable NCO.  Several HDL blocks share the same interface:
//  * ptp_counter_free (rate only)
//  * ptp_counter_gen (rate only)
//  * ptp_realtime (rate + shift)
// This file implements the TrackingClock interface (see ptp_tracking.h)
// for closed-loop software control of these NCOs.
//

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/ptp_tracking.h>

namespace satcat5 {
    namespace cfg {
        // Reference scale for use with TrackingCoeff class.
        // Scale parameter must match the TFINE_SCALE generic on the HDL block
        // (usually "ptp_counter_free" or "ptp_realtime"). It indicates that
        // the per-cycle rate-accumulator scaling is 2^N LSBs per nanosecond.
        constexpr double ptpref_scale(double ref_clk_hz, unsigned scale=40) {
            return ref_clk_hz / double(satcat5::ptp::NSEC_PER_SEC) / double(1ull << scale);
        }

        // Rate-control only.
        class PtpReference : public satcat5::ptp::TrackingClock {
        public:
            // PtpReference is a thin-wrapper for a single control register.
            PtpReference(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr = satcat5::cfg::REGADDR_ANY);

            // Implement rate-control only for the TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;

        protected:
            satcat5::cfg::Register m_reg;   // Control register
        };

        // Rate-control plus coarse-adjust command.
        class PtpRealtime : public satcat5::ptp::TrackingClock {
        public:
            // PtpRealtime uses a block of six control registers.
            PtpRealtime(satcat5::cfg::ConfigBus* cfg,
                unsigned devaddr, unsigned regaddr_base);

            // Implement the full TrackingClock API.
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;

            // Get or set the current time.
            satcat5::ptp::Time clock_ext();     // External timestamp
            satcat5::ptp::Time clock_now();     // Read current time
            void clock_set(const satcat5::ptp::Time& new_time);

        protected:
            void load(const satcat5::ptp::Time& time);
            satcat5::cfg::Register m_reg;   // Base control register
        };
    }
}
