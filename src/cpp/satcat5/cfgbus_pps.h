//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Pulse-per-second (PPS) input and output
//!
//! This file defines software drivers for the pulse-per-second (PPS)
//! input block (ptp_pps_in.vhd) and output block (ptp_pps_out.vhd).

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/polling.h>
#include <satcat5/ptp_source.h>

namespace satcat5 {
    namespace cfg {
        //! Driver for the PPS input block (ptp_pps_in.vhd).
        //! The VHDL input block accepts an incoming PPS signal and a PTP time
        //! reference, timestamps each PPS rising or falling edge, and writes
        //! those timestamps to a FIFO.  This software driver configures that
        //! block and polls the FIFO, reading the stored hardware timestamps.
        //! The result can be fed to a ptp::TrackingController for closed-loop
        //! discipline of the original PTP time reference.
        //! \see satcat5::ptp::PpsOutput
        class PpsInput : protected satcat5::poll::Timer {
        public:
            //! Link this driver to the hardware control register.
            //! \param reg Sets ConfigBus control register.
            //! \param rising Sets the default input polarity.
            explicit PpsInput(satcat5::cfg::Register reg, bool rising=true);

            //! Set recipient for phase-offset information.
            inline void set_callback(satcat5::ptp::TrackingController* cb)
                { m_callback = cb; }

            //! Get the current phase offset setting.
            //! \returns Offset in subnanoseconds, \see set_offset.
            inline s64 get_offset() const       { return m_offset; }

            //! Set phase offset for calculating clock discipline.
            //! Units are subnanoseconds, \see satcat5::ptp::Time.
            //! The maximum supported offset is +/- 500 msec.
            //! Positive values indicate the PPS input lags the GPS epoch.
            inline void set_offset(s64 offset)  { m_offset = offset; }

            //! Clear FIFO and set the active edge (rising or falling).
            void reset(bool rising=true);

        protected:
            // Internal methods.
            bool read_pulse();              // Attempt to read one pulse
            void timer_event() override;    // Timer event handler

            // Internal state.
            satcat5::cfg::Register m_reg;
            satcat5::ptp::TrackingController* m_callback;
            s64 m_offset;
        };

        //! Driver for the PPS output block (ptp_pps_out.vhd).
        //! The VHDL output block accepts a PTP time reference and synthesizes
        //! a PPS signal. This software driver allows configuration of that
        //! block, setting its phase offset and polarity.
        //! \see satcat5::ptp::PpsInput
        class PpsOutput {
        public:
            //! Link this driver to the hardware control register.
            //! \param reg Sets ConfigBus control register.
            //! \param rising Sets the default output polarity.
            explicit PpsOutput(satcat5::cfg::Register reg, bool rising=true);

            //! Adjust the phase-offset for this output.
            //! Units are subnanoseconds, \see satcat5::ptp::Time.
            //! Positive offsets increase delay of the synthesized output.
            void set_offset(s64 offset);

            //! Set the rising- or falling-edge polarity of this output.
            void set_polarity(bool rising);

        protected:
            // Internal methods.
            void configure();               // Reload all parameters

            // Internal state.
            satcat5::cfg::Register m_reg;
            s64 m_offset;
            bool m_rising;
        };
    }
}
