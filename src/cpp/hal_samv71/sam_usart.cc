//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "sam_usart.h"

// ASF3 includes
extern "C"{
#include <core_cm7.h>
#include <ioport.h>
#include <pmc.h>
}

using satcat5::io::BufferedIO;
using satcat5::irq::AtomicLock;
using satcat5::poll::Always;
using satcat5::sam::HandlerSAMV71;
using satcat5::sam::UsartSamv71;

// SAMV71 cache is 32-bytes per line, invalidate on the appropriate boundary.
static const u32 CACHE_LINESIZE = 32;
static const u32 CACHE_ADDRMASK = 0xFFFFFFE0;

// Struct holding relevant parameters for each peripheral.
struct usart_conf {
    u8              clk_id;
    IRQn            irq;
    bool            supports_fc;
    u8              tx_dma_ch;
    u8              rx_dma_ch;
    u8              tx_perid;
    u8              rx_perid;
};

// XDMAC needs to be reset exactly once before configuration. This flag will be
// set true when the first called constructor resets the peripheral.
static bool XDMAC_RESET_DONE = false;

// Lookup relevant peripheral information from USART instance.
// DMA channel assignments are static since this is assumed to be the only
// active DMA controller on the device. Datasheet and ASF3 disagree on number of
// available channels (7 vs. 24), seems to be 24 in hardware.
static usart_conf get_conf(const Usart* usart) {
    if (usart == USART0) {
        return { ID_USART0, USART0_IRQn, true, 0, 1,
            XDMAC_CHANNEL_HWID_USART0_TX, XDMAC_CHANNEL_HWID_USART0_RX };
    } else if (usart == USART1) {
        return { ID_USART1, USART1_IRQn, true, 2, 3,
            XDMAC_CHANNEL_HWID_USART1_TX, XDMAC_CHANNEL_HWID_USART1_RX };
    } else if (usart == USART2) {
        return { ID_USART2, USART2_IRQn, true, 4, 5,
            XDMAC_CHANNEL_HWID_USART2_TX, XDMAC_CHANNEL_HWID_USART2_RX };
    } else if (usart == (Usart*) UART0) {
        return { ID_UART0, UART0_IRQn, false, 6, 7,
            XDMAC_CHANNEL_HWID_UART0_TX, XDMAC_CHANNEL_HWID_UART0_RX };
    } else if (usart == (Usart*) UART1) {
        return { ID_UART1, UART1_IRQn, false, 8, 9,
            XDMAC_CHANNEL_HWID_UART1_TX, XDMAC_CHANNEL_HWID_UART1_RX };
    } else if (usart == (Usart*) UART2) {
        return { ID_UART2, UART2_IRQn, false, 10, 11,
            XDMAC_CHANNEL_HWID_UART2_TX, XDMAC_CHANNEL_HWID_UART2_RX };
    } else if (usart == (Usart*) UART3) {
        return { ID_UART3, UART3_IRQn, false, 12, 13,
            XDMAC_CHANNEL_HWID_UART3_TX, XDMAC_CHANNEL_HWID_UART3_RX };
    } else if (usart == (Usart*) UART4) {
        return { ID_UART4, UART4_IRQn, false, 14, 15,
            XDMAC_CHANNEL_HWID_UART4_TX, XDMAC_CHANNEL_HWID_UART4_RX };
    } else {
        return { ID_PERIPH_COUNT, PERIPH_COUNT_IRQn, false, 0, 0, 0, 0 };
    }
}

// Constructor calls out to setup functions.
UsartSamv71::UsartSamv71(Usart* usart, unsigned baud_hz, unsigned poll_ms,
    u8* txbuff, unsigned tx_nbytes, u8* rxbuff, unsigned rx_nbytes,
    u8* rxdma0, u8* rxdma1, unsigned rxdma_nbytes, bool fc_on)
    : BufferedIO(txbuff, tx_nbytes, 0, rxbuff, rx_nbytes, 0)
    , Always(false) // Do not auto-register.
    , HandlerSAMV71("UsartSamv71", XDMAC_IRQn)
    , m_usart(usart)
    , m_txdma_nbytes(0)
    , m_rxdma0(rxdma0)
    , m_rxdma1(rxdma1)
    , m_rxdma_nbytes(rxdma_nbytes)
    , m_rxdma_buffidx(0)
{
    // Lookup the passed in USART and set self in a dead state on failure.
    usart_conf ids = get_conf(m_usart);
    if (ids.clk_id == ID_PERIPH_COUNT) {
        m_usart = nullptr;
        return;
    }
    m_fc_on = ids.supports_fc && fc_on;
    m_tx_dma_ch = ids.tx_dma_ch;
    m_rx_dma_ch = ids.rx_dma_ch;

    // If the XDMAC needs a reset, execute exactly once.
    if (!XDMAC_RESET_DONE) {
        XDMAC->XDMAC_GD = 0xFFFFFFFF;   // Disable all channels
        XDMAC->XDMAC_GID = 0xFFFFFFFF;  // Disable all interrupts
        XDMAC->XDMAC_GSWR = 1;          // Software reset
        XDMAC_RESET_DONE = true;
    }

    // Set up clocking, DMA controller, and USART peripheral.
    sysclk_enable_peripheral_clock(ids.clk_id);
    pmc_enable_periph_clk(ID_XDMAC);
    configure_xdmac(ids.tx_perid, ids.rx_perid);
    configure(baud_hz, fc_on);

    // Start polling at the specified rate, 0 = use poll::Always instead.
    if (poll_ms == 0) {
        poll_register();
    } else {
        timer_every(poll_ms);
    }
}

// Configures the USART peripheral for a specific baud rate.
void UsartSamv71::configure(unsigned baud_hz, bool fc_on) {

    // Sanity check: driver is correctly configured.
    if (!m_usart) { return; }

    // Always set to 8 bit length, no parity, 1 stop bit.
    sam_usart_opt_t opt =
    {
        .baudrate       = baud_hz,
        .char_length    = US_MR_CHRL_8_BIT,
        .parity_type    = US_MR_PAR_NO,
        .stop_bits      = US_MR_NBSTOP_1_BIT,
        .channel_mode   = US_MR_USART_MODE_NORMAL
    };

    // Separate init functions with RTS/CTS ("handshaking") and without.
    if (m_fc_on) {
        usart_init_hw_handshaking(m_usart, &opt, sysclk_get_peripheral_hz());
        rts_high(); // Block sender until DMA on.
    } else {
        usart_init_rs232(m_usart, &opt, sysclk_get_peripheral_hz());
        m_usart->US_CR = US_CR_RTSEN; // Leave RTS idling low.
    }
    usart_enable_tx(m_usart);
    usart_enable_rx(m_usart);
}

// Check for end-of-block (BIS) IRQs from RX/TX DMAs and service, clears IRQs.
void UsartSamv71::irq_event() {
    if (XDMAC->XDMAC_CHID[m_rx_dma_ch].XDMAC_CIS & XDMAC_CIS_BIS) {
        rts_high(); // RX full: block sender and service immediately.
        poll_rx_dma();
    }
    if (XDMAC->XDMAC_CHID[m_tx_dma_ch].XDMAC_CIS & XDMAC_CIS_BIS) {
        poll_tx_dma(); // TX empty: check for unsent bytes.
    }
}

// If the TX DMA engine has free buffer space, copy any bytes from the
// transmit-side PacketBuffer to its address space.
void UsartSamv71::poll_tx_dma() {

    // Sanity check: driver is correctly configured.
    if (!m_usart) { return; }

    // Return immediately if the DMA channel is busy.
    if ((XDMAC->XDMAC_GS >> m_tx_dma_ch) & 0x1) { return; }

    // If we just finished a transaction, consume the PacketBuffer bytes.
    if (m_txdma_nbytes > 0) { m_tx.read_consume(m_txdma_nbytes); }

    // Check if we have any data waiting to send.
    m_txdma_nbytes = m_tx.get_peek_ready();
    if (!m_txdma_nbytes) { return; }

#if SATCAT5_SAMV71_UART_DCACHE
    // Flush the data cache for any 32-byte lines the DMA will read from.
    u32* cache_addr = (u32*) ((u32) m_tx.peek(m_txdma_nbytes) & CACHE_ADDRMASK);
    SCB_CleanDCache_by_Addr(cache_addr, m_txdma_nbytes + CACHE_LINESIZE-1);
#endif

    // Configure DMA address and length and start the transfer.
    XDMAC->XDMAC_CHID[m_tx_dma_ch].XDMAC_CSA = (u32) m_tx.peek(m_txdma_nbytes);
    XDMAC->XDMAC_CHID[m_tx_dma_ch].XDMAC_CUBC = (u32) m_txdma_nbytes;
    XDMAC->XDMAC_GE = (1 << m_tx_dma_ch);
}

// If the RX DMA engine has bytes available, copy them into the receive-side
// PacketBuffer. Maintain a pair of ping-pong buffers in the DMA to ensure bytes
// are not lost while copying.
void UsartSamv71::poll_rx_dma() {

    // Sanity check: driver is correctly configured.
    if (!m_usart) { return; }

    // Skip if the DMA engine is enabled but has received no bytes.
    // NOTE: If moving to multiple microblocks, ensure to follow the procedure
    // outlined in Section 35.8 of the datasheet.
    if (((XDMAC->XDMAC_GS >> m_rx_dma_ch) & 0x1) &&
        XDMAC->XDMAC_CHID[m_rx_dma_ch].XDMAC_CUBC == m_rxdma_nbytes) { return; }

    // Data available - disable DMA, swap buffers, re-enable DMA.
    // TODO: Unclear if this disables peripheral linkage and has the potential
    // to drop data. Consider moving to flush+suspend and/or hardware
    // linked-list support. See xdmac_example.c for more.
    AtomicLock lock("UsartSamv71::poll_rx_dma()");
    const u8* read_buff = get_rxdma_buff(); // Save used buffer
    m_rxdma_buffidx = 1 - m_rxdma_buffidx; // Swap read/write buffers
    rts_high(); // Drive RTS high while servicing DMA
    XDMAC->XDMAC_GD = (1 << m_rx_dma_ch); // Disable channel
    while ((XDMAC->XDMAC_GS >> m_rx_dma_ch) & 0x1) {} // Wait for flush, ~1us
    unsigned nbytes_wr = m_rxdma_nbytes -
        XDMAC->XDMAC_CHID[m_rx_dma_ch].XDMAC_CUBC;
    XDMAC->XDMAC_CHID[m_rx_dma_ch].XDMAC_CDA = (u32) get_rxdma_buff();
    XDMAC->XDMAC_CHID[m_rx_dma_ch].XDMAC_CUBC = m_rxdma_nbytes;
    XDMAC->XDMAC_GE = (1 << m_rx_dma_ch); // Re-enable channel
    rts_low(); // Enabled, drive RTS low
    lock.release();

    // Invalidate cache for any relevant lines then copy to the PacketBuffer.
    if (!nbytes_wr) { return; }
#if SATCAT5_SAMV71_UART_DCACHE
    u32* cache_addr = (u32*) ((u32) read_buff & CACHE_ADDRMASK);
    SCB_InvalidateDCache_by_Addr(cache_addr, nbytes_wr + CACHE_LINESIZE-1);
#endif
    m_rx.write_bytes(nbytes_wr, read_buff);
    m_rx.write_finalize();
}

// Configure TX/RX DMA controllers.
void UsartSamv71::configure_xdmac(u32 tx_perid, u32 rx_perid) {

    // TX DMA-to-USART transfer is configured as a single block+microblock.
    // Source: Memory, address and length are set via poll_tx_dma().
    // Destination: Peripheral, ID is passed in as an argument.
    xdmac_channel_config_t tx_dma_conf =
    {
        .mbr_ubc        =   0,
        .mbr_sa         =   0,
        .mbr_da         =   (u32)&(m_usart->US_THR),
        .mbr_cfg        =   XDMAC_CC_TYPE_PER_TRAN      |
                            XDMAC_CC_MBSIZE_SINGLE      |
                            XDMAC_CC_DSYNC_MEM2PER      |
                            XDMAC_CC_CSIZE_CHK_1        |
                            XDMAC_CC_DWIDTH_BYTE        |
                            XDMAC_CC_SIF_AHB_IF0        |
                            XDMAC_CC_DIF_AHB_IF1        |
                            XDMAC_CC_SAM_INCREMENTED_AM |
                            XDMAC_CC_DAM_FIXED_AM       |
                            XDMAC_CC_PERID(tx_perid),
        .mbr_bc         = 0,
        .mbr_ds         = 0,
        .mbr_sus        = 0,
        .mbr_dus        = 0
    };

    // RX USART-to-DMA transfer is configured as a single block+microblock.
    // Source: Peripheral, ID is passed in as an argument.
    // Destination: Memory, double-buffered with fixed length.
    xdmac_channel_config_t rx_dma_conf =
    {
        .mbr_ubc        =   m_rxdma_nbytes,
        .mbr_sa         =   (u32) &(m_usart->US_RHR),
        .mbr_da         =   (u32) get_rxdma_buff(),
        .mbr_cfg        =   XDMAC_CC_TYPE_PER_TRAN      |
                            XDMAC_CC_MBSIZE_SINGLE      |
                            XDMAC_CC_DSYNC_PER2MEM      |
                            XDMAC_CC_CSIZE_CHK_1        |
                            XDMAC_CC_DWIDTH_BYTE        |
                            XDMAC_CC_SIF_AHB_IF1        |
                            XDMAC_CC_DIF_AHB_IF0        |
                            XDMAC_CC_SAM_FIXED_AM       |
                            XDMAC_CC_DAM_INCREMENTED_AM |
                            XDMAC_CC_PERID(rx_perid),
        .mbr_bc         = 0,
        .mbr_ds         = 0,
        .mbr_sus        = 0,
        .mbr_dus        = 0
    };

    // Disable channels if necessary then (re-)configure with interrupts.
    xdmac_channel_disable(XDMAC, m_tx_dma_ch);
    xdmac_channel_disable(XDMAC, m_rx_dma_ch);
    xdmac_configure_transfer(XDMAC, m_tx_dma_ch, &tx_dma_conf);
    xdmac_configure_transfer(XDMAC, m_rx_dma_ch, &rx_dma_conf);
    xdmac_enable_interrupt(XDMAC, m_rx_dma_ch);
    xdmac_channel_enable_interrupt(XDMAC, m_rx_dma_ch, XDMAC_CIE_BIE);
    xdmac_enable_interrupt(XDMAC, m_tx_dma_ch);
    xdmac_channel_enable_interrupt(XDMAC, m_tx_dma_ch, XDMAC_CIE_BIE);
    // DMA engine enable is performed on first poll_rx_dma() call.
}

// In handshaking mode (RTS/CTS), the RTS pin is driven High when RTSEN is set.
void UsartSamv71::rts_high() {
    if (m_fc_on) { m_usart->US_CR = US_CR_RTSEN; }
}

// In handshaking mode (RTS/CTS), the RTS pin is driven Low when RTSDIS is set.
void UsartSamv71::rts_low() {
    if (m_fc_on) { m_usart->US_CR = US_CR_RTSDIS; }
}
