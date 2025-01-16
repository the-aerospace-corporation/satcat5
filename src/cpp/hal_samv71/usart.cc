//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

//////////////////////////////////////////////////////////////////////////
// Includes
//////////////////////////////////////////////////////////////////////////

// SAMV71 Drivers
extern "C" {
    // Advanced Software Framework
    #include <asf.h>
};

// SatCat
#include <satcat5/log.h>

// SatCat HAL
#include <hal_samv71/usart.h>
#include <hal_samv71/interrupt_handler.h>

//////////////////////////////////////////////////////////////////////////
// Namespace
//////////////////////////////////////////////////////////////////////////

namespace log = satcat5::log;
using satcat5::sam::UsartSAMV71;

//////////////////////////////////////////////////////////////////////////

UsartSAMV71::UsartSAMV71(
    const char* lbl, int irq, Usart* usart, const u32 baud_rate)
    : satcat5::io::BufferedIO(
        m_txbuff, SATCAT5_SAMV71_UART_BUFFSIZE, 0,
        m_rxbuff, SATCAT5_SAMV71_UART_BUFFSIZE, 0)
    , satcat5::sam::HandlerSAMV71(lbl, irq)
    , m_status(0)
    , m_usart(usart)
{
    // Configuration Sequence
    this->config_seq(baud_rate);

    // Read UART Every 1ms
    timer_every(1);
}

void UsartSAMV71::config_seq(const u32 baud_rate)
{
    // USART Options
    usart_serial_options_t uart_options = {
        .baudrate = baud_rate,
        .charlength = US_MR_CHRL_8_BIT,
        .paritytype = US_MR_PAR_NO,
        .stopbits = US_MR_NBSTOP_1_BIT
    };

    // Initialize USART
    usart_serial_init((usart_if)m_usart, &uart_options);
}

void UsartSAMV71::poll()
{
    // Log Overflow
    if (m_status & UART_SR_OVRE)
    {
        log::Log(log::ERROR, m_label).write(": Rx-overflow");
    }

    // Log Framing Error
    if (m_status & UART_SR_FRAME)
    {
        log::Log(log::ERROR, m_label).write(": Rx-framing");
    }

    // Log Parity Error
    if (m_status & UART_SR_PARE)
    {
        log::Log(log::ERROR, m_label).write(": Rx-parity");
    }
}

void UsartSAMV71::timer_event()
{
    irq_event();
}

void UsartSAMV71::data_rcvd(satcat5::io::Readable* src)
{
    u32 txbytes = m_tx.get_peek_ready();
    if (txbytes)
    {
        const u8* ptr = m_tx.peek(txbytes);
        usart_serial_write_packet((usart_if)m_usart, (u8*)ptr, txbytes);
        m_tx.read_consume(txbytes);
    }
}

void UsartSAMV71::irq_event()
{
    // Critical Section Lock
    satcat5::irq::AtomicLock lock(m_label);

    // Read Status
    m_status = m_usart->US_CSR;

    // Check for Data
    if (m_status & US_CSR_RXRDY)
    {
        // Get Safe-to-Read Length
        u32 rxmax = m_rx.zcw_maxlen();
        if (rxmax)
        {
            // Get Pointer to Buffer
            u8* rxtmp = m_rx.zcw_start();

            // Read Data
            *rxtmp = m_usart->US_RHR;

            // Commit Data
            m_rx.zcw_write(1);
            m_rx.write_finalize();
        }
    }
}

//////////////////////////////////////////////////////////////////////////
