//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
