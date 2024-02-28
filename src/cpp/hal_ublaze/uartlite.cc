//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_ublaze/uartlite.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

// Check if BSP will include the XUartLite driver before proceeding.
#if XPAR_XUARTLITE_NUM_INSTANCES > 0

namespace log = satcat5::log;
using satcat5::ublaze::UartLite;

// Software status flags:
static const u32 STATUS_RX_OVR1 = (1u << 0);
static const u32 STATUS_RX_OVR2 = (1u << 1);
static const u32 STATUS_RX_OVR  = (STATUS_RX_OVR1 | STATUS_RX_OVR2);

UartLite::UartLite(const char* lbl, int irq, u16 dev_id)
    : satcat5::io::BufferedIO(
        m_txbuff, SATCAT5_UART_BUFFSIZE, 0,
        m_rxbuff, SATCAT5_UART_BUFFSIZE, 0)
    , satcat5::irq::Handler(lbl, irq)
    , m_status(0)
{
    // Initialize the underlying Xilinx driver.
    XUartLite_Initialize(&m_uart, dev_id);
    XUartLite_ResetFifos(&m_uart);

    // Enable interrupts from the device, if applicable.
    // (We don't use the XUartLite driver's built-in interrupt handling.)
    if (m_irq_idx >= 0) {
        XUartLite_EnableInterrupt(&m_uart);
    }

    // Poll frequently, to allow basic functionality even
    // if the hardware interrupt line isn't connected.
    timer_every(1);
}

void UartLite::poll()
{
    // Log any receive errors.
    if (m_status & STATUS_RX_OVR) {
        log::Log(log::ERROR, m_label).write(": Rx-overflow");
        satcat5::util::clr_mask_u32(m_status, STATUS_RX_OVR);
    }
}

void UartLite::timer_event()
{
    irq_event();
}

void UartLite::data_rcvd()
{
    // Just got new data in our transmit buffer.
    // If the UART is idle, start a new transmission.
    irq_event();
}

void UartLite::irq_event()
{
    satcat5::irq::AtomicLock lock(m_label);

    // If there's data and the UART is idle, start a new transmission.
    // Note: Return value from XUartLite_Send is the number transferred
    //       to hardware immediately; it does hang onto the rest of the
    //       buffer, but we aren't using that built-in polling.
    u32 txbytes = m_tx.get_peek_ready();
    if (txbytes) {
        const u8* ptr = m_tx.peek(txbytes);
        u32 nsent = XUartLite_Send(&m_uart, (u8*)ptr, txbytes);
        m_tx.read_consume(nsent);
    }

    // Copy any new received data to the software buffer.
    // Use the three-step zero-copy-write (ZCW) method.
    u32 rxmax = m_rx.zcw_maxlen();      // Max safe to read?
    if (rxmax) {
        u8* rxtmp = m_rx.zcw_start();   // Get pointer to buffer
        u32 rcvd = XUartLite_Recv(&m_uart, rxtmp, rxmax);
        if (rcvd) {
            m_rx.zcw_write(rcvd);       // Commit any new data
            bool ok = m_rx.write_finalize();
            if (!ok) {
                satcat5::util::set_mask_u32(m_status, STATUS_RX_OVR1);
                request_poll();         // Deferred follow-up
            }
        }
    } else {
        satcat5::util::set_mask_u32(m_status, STATUS_RX_OVR2);
        XUartLite_ResetFifos(&m_uart);
        request_poll();                 // Deferred follow-up
    }
}

#endif  // XPAR_XUARTLITE_NUM_INSTANCES > 0
