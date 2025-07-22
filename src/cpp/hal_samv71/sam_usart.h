//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! SAMV71 UART/USART serial interface driver
//!
//! \details Uses the USART and XDMAC drivers of the SAMV71's Advanced Software
//! Framework v3 package to enable serial I/O into and out of the SAMV71.
//!

#pragma once

#include <hal_samv71/interrupt_handler.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>
#ifdef __FREERTOS__
#include <hal_freertos/task.h>
#include <satcat5/utils.h>
#endif

// ASF3 includes
extern "C"{
#include <usart.h>
#include <xdmac.h>
}

// Default buffer size for UsartSamv71Static
#ifndef SATCAT5_SAMV71_UART_BUFFSIZE
#define SATCAT5_SAMV71_UART_BUFFSIZE 1600
#endif

// Enable data cache flushing and invalidation for the DMA controller?
// When disabled (default, safe), SCB_DisableDCache() must be called at init.
#ifndef SATCAT5_SAMV71_UART_DCACHE
#define SATCAT5_SAMV71_UART_DCACHE 0
#endif

namespace satcat5 {
    namespace sam {
        //! io::BufferedIO interface for the SAMV71 USART and UART peripherals.
        //!
        //! UART (not USART) peripherals are also supported by this class due to
        //! a shared register map between the two. Hardware flow control
        //! (RTS/CTS) is not supported for UART peripherals.
        //!
        //! Note that this does NOT establish the SAMV71 I/O mux, this should be
        //! done externally.
        //!
        //! A configurable polling interval is available in the constructor. The
        //! DMA controller only raises interrupts when the buffers are full, so
        //! some periodic checking of buffer occupancy is required. Less
        //! frequent polling is appropriate for low-rate latency-insensitive
        //! tasks, and more frequent polling is appropriate for higher
        //! throughput UARTs. Setting the polling interval to 0 enables
        //! continuous polling via poll::Always to reduce receive latency to the
        //! minimum supported by SatCat5.
        //!
        //! Most users should instantiate sam::UsartSamv71Static instead of
        //! this to perform all stack buffer allocation.
        //!
        //! This class supports but does not require interrupts, which are
        //! triggered if the receive DMA is full (about to overflow) or the
        //! transmit DMA is empty (finished sending a frame). This helps allow
        //! for lower polling intervals, but must be manually set up in an
        //! external file such as main.cc. The single DMA controller interrupt
        //! MUST be named exactly `void XDMAC_Handler()` and service all system
        //! UsartSamv71 instances:
        //!
        //! \code
        //! satcat5::sam::UsartSamv71<...> uart0(...);
        //! satcat5::sam::UsartSamv71<...> uart1(...);
        //!
        //! void XDMAC_Handler() {
        //!     irq_controller.irq_handler(&uart0);
        //!     irq_controller.irq_handler(&uart1);
        //! }
        //!
        //! int main(void) {
        //!     // ...
        //!     NVIC_DisableIRQ(XDMAC_IRQn);
        //!     NVIC_ClearPendingIRQ(XDMAC_IRQn);
        //!     NVIC_SetPriority(XDMAC_IRQn, 4);
        //!     NVIC_EnableIRQ(XDMAC_IRQn);
        //!     // ...
        //!     // Start servicing SatCat5 core loop
        //! }
        //! \endcode
        class UsartSamv71
            : public satcat5::io::BufferedIO
            , public satcat5::poll::Timer
            , public satcat5::poll::Always
            , public satcat5::sam::HandlerSAMV71
        {
        public:
            //! Constructor takes a pointer to the ASF3 USART instance (base
            //! address), configures required DMA channels and USART peripheral,
            //! and starts I/O streaming.
            //!
            //! \param usart Pointer to (baseaddr of) UART/USART peripheral.
            //! \param baud_hz Baud rate for the serial line, in Hz.
            //! \param poll_ms Polling rate for new data in ms, or = 0 for
            //!     continuous polling via poll::Always.
            //! \param fc_on Use hardware flow control (RTS/CTS), default off.
            UsartSamv71(Usart* usart, unsigned baud_hz, unsigned poll_ms,
                u8* txbuff, unsigned txbytes, u8* rxbuff, unsigned rxbytes,
                u8* rxdma0, u8* rxdma1, unsigned rxdmabytes,
                bool fc_on=false);

            //! Set baud rate and RTS/CTS enable.
            //! Always set to 8 bit length, no parity, 1 stop bit.
            void configure(unsigned baud_hz, bool fc_on=false);

        protected:
            //! Immediately transfer incoming TX data to the DMA engine.
            void data_rcvd(satcat5::io::Readable* src) override
                { poll_tx_dma(); }

            //! The user may configure either continuous polling or timer-based
            //! polling; either should perform the same task of servicing both
            //! the RX and TX DMAs.
            //! @{
            void timer_event() override { poll_rx_dma(); poll_tx_dma(); }
            void poll_always() override { poll_rx_dma(); poll_tx_dma(); }
            //! @}

            //! IRQ indicates the RX DMA is full or the TX DMA is empty.
            void irq_event() override;

            //! Get the RX buffer the DMA is currently writing to.
            u8* get_rxdma_buff()
                { return m_rxdma_buffidx == 0 ? m_rxdma0 : m_rxdma1; }

            //! Poll the RX DMA engine for new data received.
            void poll_tx_dma();

            //! Poll the TX DMA engine for unsent data to transmit.
            void poll_rx_dma();

            //! Initial setup of the TX/RX DMA controllers.
            void configure_xdmac(u32 tx_dma_ch, u32 rx_dma_ch);

            //! Drive the RTS signal high/low if flow-control is on.
            //! @{
            void rts_high();
            void rts_low();
            //! @}

        private:
            // Member variables.
            Usart*          m_usart;
            unsigned        m_txdma_nbytes;
            u8* const       m_rxdma0;
            u8* const       m_rxdma1;
            const unsigned  m_rxdma_nbytes;
            unsigned        m_rxdma_buffidx;
            bool            m_fc_on;
            u8              m_tx_dma_ch;
            u8              m_rx_dma_ch;
        };

        //! UsartSamv71 variant with statically-allocated TX and RX buffers;
        //! most users should instantiate this instead of UsartSamv71.
        //!
        //! Optional template parameter specifies buffer sizes.
        //!
        //! TODO: Benefit of disjoint BufferedIO and DMA buffer sizes?
        //!
        //! \copydoc satcat5::sam::UsartSamv71
        template <unsigned SIZE = SATCAT5_SAMV71_UART_BUFFSIZE>
        class UsartSamv71Static : public UsartSamv71 {
        public:
            //! \copydoc satcat5::sam::UsartSamv71::UsartSamv71
            UsartSamv71Static(Usart* usart, unsigned baud_hz, unsigned poll_ms,
                bool fc_on=false)
            : UsartSamv71(usart, baud_hz, poll_ms,
                m_txbuff, SIZE, m_rxbuff, SIZE, m_rxdma0, m_rxdma1, SIZE,
                fc_on) {}

        private:
            u8 m_txbuff[SIZE];
            u8 m_rxbuff[SIZE];
            u8 m_rxdma0[SIZE];
            u8 m_rxdma1[SIZE];
        };

#ifdef __FREERTOS__
        //! UsartSamv71Static variant with a  FreeRTOS task that periodically
        //! polls for updates from the driver. This should be run at a higher
        //! priority than the SatCat5 task to provide a pre-emption capability
        //! that helps guarantee the DMA FIFO does not overflow.
        //!
        //! \copydoc satcat5::sam::UsartSamv71Static
        template <
            unsigned TASK_PRIORITY,
            unsigned SIZE = SATCAT5_SAMV71_UART_BUFFSIZE,
            configSTACK_DEPTH_TYPE TASK_SIZE = 1024>
        class UsartSamv71Preempt
            : public satcat5::freertos::StaticTask<TASK_SIZE, TASK_PRIORITY>
            , public UsartSamv71Static<SIZE> {
        public:
            //! \copydoc satcat5::sam::UsartSamv71Static::UsartSamv71Static
            //! \param poll_ms Polling time for the preempting loop, must be
            //!     at least 1ms.
            //! \param poll_always Keeps the poll::Always call to minimize
            //!     latency of received byte processing under light load.
            UsartSamv71Preempt(Usart* usart, unsigned baud_hz, unsigned poll_ms,
                bool poll_always=false, bool fc_on=false)
            : satcat5::freertos::StaticTask<TASK_SIZE, TASK_PRIORITY>(
                "UsartSamv71Preempt", task, this)
            , UsartSamv71Static<SIZE>(usart, baud_hz, 0, fc_on) // poll_ms = 0
            , m_poll_ms(satcat5::util::max_unsigned(1, poll_ms)) // Must be > 0
            {
                // Unregister the poll_always() call if requested.
                if (!poll_always) { this->poll_unregister(); }
            }

            //! FreeRTOS Task polls the driver at the rate provided in the
            //! constructor.
            static void task(void* pvParams) {
                UsartSamv71Preempt* arg = (UsartSamv71Preempt*) pvParams;
                const TickType_t poll_rate = pdMS_TO_TICKS(arg->m_poll_ms);
                TickType_t last_wake_time = xTaskGetTickCount();
                for (;;) {
                    vTaskDelayUntil(&last_wake_time, poll_rate);
                    arg->poll_rx_dma();
                    arg->poll_tx_dma();
                }
            }

        protected:
            // Member variables
            const unsigned m_poll_ms;
        };
#endif

    } // namespace sam
} // namespace satcat5
