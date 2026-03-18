//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Throttled I/O adapters
//

#pragma once

#include <satcat5/io_writeable.h>
#include <satcat5/polling.h>
#include <satcat5/timeref.h>

namespace satcat5 {
    namespace io {
        //! A rate-controlled io::WriteableRedirect. Functionally similar, but
        //! artificially limits the rate at which data can be written to the
        //! downstream object.
        class WriteableThrottle
            : public satcat5::io::WriteableRedirect
            , public satcat5::poll::Timer {
        public:
            WriteableThrottle(
                satcat5::io::Writeable* dst,        // Downstream object
                unsigned rate_bps = 1000000);       // Rate limit (bits/sec)

            //! Adjust the rate limit.
            inline void set_rate(unsigned rate_bps)
                { m_rate_bps = rate_bps; }

            // Override required portions of the Writeable API.
            unsigned get_write_space() const override;
            bool write_finalize() override;

        protected:
            unsigned calc_tokens(unsigned usec) const;
            void timer_event() override;            // Timer event handler

            // Internal state.
            unsigned m_rate_bps;                    // Rate limit (bits per second)
            unsigned m_tokens;                      // Accumulated credits (bytes)
            satcat5::util::TimeVal m_tref;          // Time of last update
        };
    }
}
