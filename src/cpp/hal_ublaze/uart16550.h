//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface wrapper for the Xilinx "XUart16550" block

#pragma once

#include <satcat5/interrupts.h>
#include <satcat5/io_buffer.h>
#include <xparameters.h>

// Check if BSP will include the XUartNs550 driver before proceeding.
#if XPAR_XUARTNS550_NUM_INSTANCES > 0

#include <xuartns550.h>

// Default size parameters
// For reference: 256 bytes = 2.7 msec buffer @ 921 kbaud
#ifndef SATCAT5_UART_BUFFSIZE
#define SATCAT5_UART_BUFFSIZE   256
#endif

namespace satcat5 {
    namespace ublaze {
        class Uart16550 final
            : public    satcat5::io::BufferedIO
            , protected satcat5::irq::Handler
            , protected satcat5::poll::Timer
        {
        public:
            // Initialize this UART and link to a specific hardware instance.
            Uart16550(
                const char* lbl, int irq, u16 dev_id,
                u32 baud_rate = 921600, u32 clk_ref_hz = 100000000);
            ~Uart16550() {}

            inline bool ok() const {return (m_status == XST_SUCCESS);}

        private:
            // Event handlers.
            void data_rcvd() override;
            void irq_event() override;
            void timer_event() override;

            // Raw Tx/Rx working buffers for BufferedIO.
            u8 m_txbuff[SATCAT5_UART_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_UART_BUFFSIZE];

            // Underlying Xilinx object.
            XUartNs550 m_uart;

            // Status flag.
            int m_status;
        };
    }
}

#endif  // XPAR_XUARTNS550_NUM_INSTANCES > 0
