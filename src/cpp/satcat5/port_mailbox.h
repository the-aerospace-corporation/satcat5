//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
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
// Internal "MailBox" Ethernet port
//
// This class interfaces with "port_axi_mailbox" through ConfigBus.
// It can be used to send and receive Ethernet frames.
//

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/io_buffer.h>

// Default size parameters:
// (Must be large enough for one full-size Ethernet frame + metadata,
//  larger sizes are fine if you have the memory for it.)
#ifndef SATCAT5_MAILBOX_BUFFSIZE
#define SATCAT5_MAILBOX_BUFFSIZE    1600    // Buffer size in bytes
#endif

#ifndef SATCAT5_MAILBOX_BUFFPKT
#define SATCAT5_MAILBOX_BUFFPKT     32      // Maximum packets per buffer
#endif

namespace satcat5 {
    namespace port {
        // Define the interface driver object.
        class Mailbox
            : public    satcat5::io::BufferedIO
            , protected satcat5::cfg::Interrupt
        {
        public:
            // Constructor
            Mailbox(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr);

        private:
            // Event handlers.
            void data_rcvd() override;
            void irq_event() override;

            // Copy of contiguous segment of transmit data from the Tx buffer.
            // Returns the number of bytes copied.
            u32 copy_tx_segment();

            // Copy a contiguous segment of received data to Rx buffer.
            // Returns last reading from hardware status register.
            u32 copy_rx_segment();

            // Pointer to the hardware control register.
            satcat5::cfg::Register m_hw_reg;

            // Raw Tx/Rx working buffers for BufferedIO.
            u8 m_txbuff[SATCAT5_MAILBOX_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_MAILBOX_BUFFSIZE];
        };
    }
}
