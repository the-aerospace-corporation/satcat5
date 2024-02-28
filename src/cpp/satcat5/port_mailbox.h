//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
