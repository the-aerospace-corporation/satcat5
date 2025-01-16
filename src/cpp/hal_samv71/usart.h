//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
#pragma once

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SAMV71 Drivers
extern "C"{
    // Advanced Software Framework
    #include <asf.h>
};

// SatCat
#include <satcat5/interrupts.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>

// SatCat HAL
#include <hal_samv71/interrupt_handler.h>

//////////////////////////////////////////////////////////////////////////
// Constants
//////////////////////////////////////////////////////////////////////////

// Default size parameters
#ifndef SATCAT5_SAMV71_UART_BUFFSIZE
#define SATCAT5_SAMV71_UART_BUFFSIZE   1024
#endif

//////////////////////////////////////////////////////////////////////////
// Class
//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace sam {
        class UsartSAMV71
        : public    satcat5::io::BufferedIO
        , protected satcat5::sam::HandlerSAMV71
        , protected satcat5::poll::Timer {
        public:
            // Constructor.
            explicit UsartSAMV71(
                const char* lbl, int irq, Usart* usart, const u32 baud_rate);

            // Configuration
            void config_seq(const u32 baud_rate);

        private:
            // Event Handlers.
            void data_rcvd(satcat5::io::Readable* src);
            void irq_event();
            void poll();
            void timer_event();

            // TX/RX Buffers
            u8 m_txbuff[SATCAT5_SAMV71_UART_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_SAMV71_UART_BUFFSIZE];

            // Status
            u32 m_status;

            // Underlying SAMV71 Object
            const Usart* m_usart;
        };
    }  // namespace sam
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
