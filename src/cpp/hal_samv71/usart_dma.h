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
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>

// SatCat HAL
#include <hal_samv71/interrupt_handler.h>

//////////////////////////////////////////////////////////////////////////
// Constants
//////////////////////////////////////////////////////////////////////////

// Default size parameters
#ifndef SATCAT5_SAMV71_USART_DMA_BUFFSIZE
#define SATCAT5_SAMV71_USART_DMA_BUFFSIZE   16000
#endif

//////////////////////////////////////////////////////////////////////////
// Class
//////////////////////////////////////////////////////////////////////////

namespace satcat5 {
    namespace sam {
        class UsartDmaSAMV71
        : public    satcat5::io::BufferedIO
        , protected satcat5::poll::Timer
        , public satcat5::sam::HandlerSAMV71 {
        public:
            // Constructor
            explicit UsartDmaSAMV71(
                const char* lbl,
                Usart* usart,
                const u32 baud_rate,
                const u8 tx_dma_channel,
                const u8 rx_dma_channel,
                const ioport_pin_t flow_ctrl_pin,
                const u32 poll_ticks);

            // Configuration
            void config_seq(const u32 baud_rate);

        private:
            // Event Handlers.
            void data_rcvd(satcat5::io::Readable* src);
            void irq_event();
            void poll();
            void timer_event();

            // TX/RX Buffers
            u8 m_txbuff[SATCAT5_SAMV71_USART_DMA_BUFFSIZE];
            u8 m_rxbuff[SATCAT5_SAMV71_USART_DMA_BUFFSIZE];
            u8 m_tmp_rx_buff_idx = 0;
            u8 m_tmp_rxbuff_0[SATCAT5_SAMV71_USART_DMA_BUFFSIZE];
            u8 m_tmp_rxbuff_1[SATCAT5_SAMV71_USART_DMA_BUFFSIZE];

            // Status
            u32 m_status;

            // USART
            const Usart* m_usart;
            u8 m_tx_dma_channel;
            u8 m_rx_dma_channel;
            ioport_pin_t m_flow_ctrl_pin;
        };
    }  // namespace sam
}  // namespace satcat5

//////////////////////////////////////////////////////////////////////////
