//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface driver for the cfgbus_hdlc block

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/io_buffer.h>

// Default size parameters
#ifndef SATCAT5_HDLC_BUFFSIZE
#define SATCAT5_HDLC_BUFFSIZE   256
#endif

#ifndef SATCAT5_HDLC_MAXPKT
#define SATCAT5_HDLC_MAXPKT  16      // Each queue up to N packets
#endif

namespace satcat5 {
    namespace cfg {
        //! Interface driver for the cfgbus_hdlc block.
        //! Note: This driver preserves packet boundaries in outgoing data,
        //! but discards packet boundaries in incoming received data.
        class Hdlc
            : public    satcat5::io::BufferedIO
            , protected satcat5::cfg::Interrupt
            , protected satcat5::poll::Timer
        {
        public:
            //! Initialize this HDLC and link to a specific register bank.
            Hdlc(ConfigBus* cfg, unsigned devaddr);

            //! Configure the HDLC driver.
            //!
            //! Sets the baud-rate, and frame size. This method should only be
            //! called when the bus is idle.
            //!
            //! \param clkref_hz ConfigBus clock rate.
            //! \param baud_hz Desired HDLC baud rate.
            //! \param frame_bytes Size of HDLC frame.
            //!     Set to 0 for variable length frames.
            void configure(unsigned clkref_hz,
                           unsigned baud_hz,
                           unsigned frame_bytes = 0);

        private:
            // Event handlers.
            void data_rcvd(satcat5::io::Readable* src);
            void irq_event();
            void timer_event();

            // Control registers
            satcat5::cfg::Register m_ctrl;

            // Pending end-of-packet marker?
            bool m_tx_eof;

            // Raw Tx/Rx working buffers are NOT publicly accessible.
            u8 m_txbuff[SATCAT5_HDLC_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_HDLC_BUFFSIZE];
        };
    }
}
