//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface driver for the cfgbus_uart block

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/io_buffer.h>

// Default size parameters
// For reference: 256 bytes = 2.7 msec buffer @ 921 kbaud
#ifndef SATCAT5_UART_BUFFSIZE
#define SATCAT5_UART_BUFFSIZE   256
#endif

namespace satcat5 {
    namespace cfg {
        class Uart
            : public    satcat5::io::BufferedIO
            , protected satcat5::cfg::Interrupt
        {
        public:
            // Initialize this UART and link to a specific register bank.
            Uart(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            // Set baud rate.
            void configure(
                unsigned clkref_hz,     // ConfigBus clock rate
                unsigned baud_hz);      // Desired UART baud rate

        private:
            // Event handlers.
            void data_rcvd();
            void irq_event();

            // Control registers
            satcat5::cfg::Register m_ctrl;

            // Raw Tx/Rx working buffers are NOT publicly accessible.
            u8 m_txbuff[SATCAT5_UART_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_UART_BUFFSIZE];
        };
    }
}
