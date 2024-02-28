//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_ublaze/uart16550.h>
#include <satcat5/utils.h>

// Enable built-in-self-test?
#ifndef SATCAT5_UART16550_BIST
#define SATCAT5_UART16550_BIST 0
#endif

// Define interrupt status-codes:
static const u8 UART_IRQ_MODEM  = 0;    // Flow-control changes
static const u8 UART_IRQ_NONE   = 1;    // No service required
static const u8 UART_IRQ_TXDATA = 2;    // Transmit FIFO empty
static const u8 UART_IRQ_RXDATA = 4;    // Receive FIFO near-full
static const u8 UART_IRQ_STATUS = 6;    // Receive error or "break" event
static const u8 UART_IRQ_RXTIME = 12;   // Receive timeout (idle)

// Check if BSP will include the XUartNs550 driver before proceeding.
#if XPAR_XUARTNS550_NUM_INSTANCES > 0

#include <xuartns550_l.h>   // Low-level to set baud rate

using satcat5::ublaze::Uart16550;

Uart16550::Uart16550(
    const char* lbl, int irq, u16 dev_id, u32 baud_rate, u32 clk_ref_hz)
    : satcat5::io::BufferedIO(
            m_txbuff, SATCAT5_UART_BUFFSIZE, 0,
            m_rxbuff, SATCAT5_UART_BUFFSIZE, 0)
    , satcat5::irq::Handler(lbl, irq)
{
    // Initialize the underlying Xilinx driver.
    m_status = XUartNs550_Initialize(&m_uart, dev_id);
    if (m_status != XST_SUCCESS) return;

    // Run self-test, if enabled.
    if (SATCAT5_UART16550_BIST) {
        m_status = XUartNs550_SelfTest(&m_uart);
        if (m_status != XST_SUCCESS) return;
    }

    // Set baud rate.
    XUartNs550_Config* cfg = XUartNs550_LookupConfig(dev_id);
    XUartNs550_SetBaud(cfg->BaseAddress, clk_ref_hz, baud_rate);

    // Always reset and enable both FIFOs.
    u16 options = XUN_OPTION_FIFOS_ENABLE
                | XUN_OPTION_RESET_TX_FIFO
                | XUN_OPTION_RESET_RX_FIFO;
    // Enable Rx-Data interrupt?
    if (m_irq_idx >= 0) options |= XUN_OPTION_DATA_INTR;
    // Set hardware option flags:
    m_status = XUartNs550_SetOptions(&m_uart, options);
    if (m_status != XST_SUCCESS) return;

    // If interrupts are disabled, poll frequently instead.
    if (m_irq_idx < 0) timer_every(1);
}

void Uart16550::timer_event()
{
    // Poll as if an interrupt has been received.
    // (This allows minimal function even if interrupt isn't connected.)
    satcat5::irq::AtomicLock lock(m_label);
    irq_event();
}

void Uart16550::data_rcvd()
{
    // Just got new data in our transmit buffer.
    // If the UART is idle, start a new transmission.
    satcat5::irq::AtomicLock lock(m_label);
    irq_event();
}

void Uart16550::irq_event()
{
    // Read and clear interrupt status register.
    u8 isr_type = (u8)XUartNs550_ReadReg(m_uart.BaseAddress, XUN_IIR_OFFSET) & XUN_INT_ID_MASK;
    u32 linereg = XUartNs550_GetLineStatusReg(m_uart.BaseAddress);

    // Outgoing data ready to send?
    u32 txbytes = m_tx.get_peek_ready();
    if (txbytes) {
        // Copy from software buffer to the hardware FIFO.
        // Note: Return value from XUartNs550_Send is the number transferred
        //       to hardware immediately; it does hang onto the rest of the
        //       buffer, but we override that built-in polling.
        const u8* ptr = m_tx.peek(txbytes);
        u32 nsent = XUartNs550_Send(&m_uart, (u8*)ptr, txbytes);
        m_tx.read_consume(nsent);
        if (nsent == txbytes) m_tx.read_finalize();
    } else if ((isr_type == UART_IRQ_TXDATA) && (m_irq_idx >= 0)) {
        // Disable "Tx FIFO empty" interrupt (done sending for now).
        u32 en_mask = XUartNs550_ReadReg(m_uart.BaseAddress, XUN_IER_OFFSET);
        satcat5::util::clr_mask_u32(en_mask, XUN_IER_TX_EMPTY);
        XUartNs550_WriteReg(m_uart.BaseAddress, XUN_IER_OFFSET, en_mask);
    }

    // Copy any new incoming data to the software buffer.
    // Use the three-step zero-copy-write (ZCW) method.
    constexpr u32 LSR_READ_ANY = XUN_LSR_BREAK_INT | XUN_LSR_DATA_READY;
    u32 rxmax = m_rx.zcw_maxlen();      // Max safe to read?
    if ((rxmax > 0) && (linereg & LSR_READ_ANY)) {
        u8* rxtmp = m_rx.zcw_start();   // Get pointer to buffer
        u32 rcvd = XUartNs550_Recv(&m_uart, rxtmp, rxmax);
        if (rcvd) {
            m_rx.zcw_write(rcvd);       // Commit any new data
            m_rx.write_finalize();      // Data is ready to be read
        }
    }
}

#endif  // XPAR_XUARTNS550_NUM_INSTANCES > 0
