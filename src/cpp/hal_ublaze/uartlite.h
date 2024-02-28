//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface wrapper for the Xilinx "XUartLite" block
//
// This block provides a SatCat5 API for the Xilinx XUartLite functions.
//

#pragma once

#include <satcat5/interrupts.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>
#include <xparameters.h>

// Check if BSP will include the XUartLite driver before proceeding.
#if XPAR_XUARTLITE_NUM_INSTANCES > 0

#include <xuartlite.h>

// Default size parameters
// For reference: 256 bytes = 2.7 msec buffer @ 921 kbaud
#ifndef SATCAT5_UART_BUFFSIZE
#define SATCAT5_UART_BUFFSIZE   256
#endif

namespace satcat5 {
    namespace ublaze {
        class UartLite
            : public    satcat5::io::BufferedIO
            , protected satcat5::irq::Handler
            , protected satcat5::poll::Timer
        {
        public:
            // Initialize this UART and link to a specific hardware instance.
            UartLite(const char* lbl, int irq, u16 dev_id);

        private:
            // Event handlers.
            void data_rcvd();
            void irq_event();
            void poll();
            void timer_event();

            // Raw Tx/Rx working buffers for BufferedIO.
            u8 m_txbuff[SATCAT5_UART_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_UART_BUFFSIZE];

            // Status flags
            u32 m_status;

            // Underlying Xilinx object.
            XUartLite m_uart;
        };
    }
}

#endif  // XPAR_XUARTLITE_NUM_INSTANCES > 0
