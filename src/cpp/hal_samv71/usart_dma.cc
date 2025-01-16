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
#include <satcat5/utils.h>
#include <satcat5/interrupts.h>

// SatCat HAL
#include <hal_samv71/usart_dma.h>

//////////////////////////////////////////////////////////////////////////
// Namespace
//////////////////////////////////////////////////////////////////////////

using satcat5::sam::UsartDmaSAMV71;

//////////////////////////////////////////////////////////////////////////

UsartDmaSAMV71::UsartDmaSAMV71(
    const char* lbl,
    Usart* usart,
    const u32 baud_rate,
    const u8 tx_dma_channel,
    const u8 rx_dma_channel,
    const ioport_pin_t flow_ctrl_pin,
    const u32 poll_ticks)
    : satcat5::io::BufferedIO(
    m_txbuff, SATCAT5_SAMV71_USART_DMA_BUFFSIZE, 0,
    m_rxbuff, SATCAT5_SAMV71_USART_DMA_BUFFSIZE, 0)
    , satcat5::sam::HandlerSAMV71(lbl, XDMAC_IRQn)
    , m_status(0)
    , m_usart(usart)
    , m_tx_dma_channel(tx_dma_channel)
    , m_rx_dma_channel(rx_dma_channel)
    , m_flow_ctrl_pin(flow_ctrl_pin)
{
    // Configuration Sequence
    this->config_seq(baud_rate);

    // Read UART Every X Ticks
    timer_every(poll_ticks);
}

void UsartDmaSAMV71::config_seq(const u32 baud_rate)
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

    // RX DMA Config
    xdmac_channel_config_t rx_dma_config =
    {
        .mbr_ubc        =   SATCAT5_SAMV71_USART_DMA_BUFFSIZE,
        .mbr_sa         =   (uint32_t)&m_usart->US_RHR,
        .mbr_da         =   0,
        .mbr_cfg        =   XDMAC_CC_TYPE_PER_TRAN      |
        XDMAC_CC_MBSIZE_SINGLE      |
        XDMAC_CC_DSYNC_PER2MEM      |
        XDMAC_CC_CSIZE_CHK_1        |
        XDMAC_CC_DWIDTH_BYTE        |
        XDMAC_CC_SIF_AHB_IF1        |
        XDMAC_CC_DIF_AHB_IF0        |
        XDMAC_CC_SAM_FIXED_AM       |
        XDMAC_CC_DAM_INCREMENTED_AM |
        XDMAC_CC_PERID(m_rx_dma_channel),
        .mbr_bc         = 0,
        .mbr_ds         = 0,
        .mbr_sus        = 0,
        .mbr_dus        = 0
    };

    // TX DMA Config
    xdmac_channel_config_t tx_dma_config =
    {
        .mbr_ubc        =   0,
        .mbr_sa         =   0,
        .mbr_da         =   (uint32_t)&m_usart->US_THR,
        .mbr_cfg        =   XDMAC_CC_TYPE_PER_TRAN      |
        XDMAC_CC_MBSIZE_SINGLE      |
        XDMAC_CC_DSYNC_MEM2PER      |
        XDMAC_CC_CSIZE_CHK_1        |
        XDMAC_CC_DWIDTH_BYTE        |
        XDMAC_CC_SIF_AHB_IF0        |
        XDMAC_CC_DIF_AHB_IF1        |
        XDMAC_CC_SAM_INCREMENTED_AM |
        XDMAC_CC_DAM_FIXED_AM       |
        XDMAC_CC_PERID(m_tx_dma_channel),
        .mbr_bc         = 0,
        .mbr_ds         = 0,
        .mbr_sus        = 0,
        .mbr_dus        = 0
    };

    // Configure DMA Controller
    xdmac_channel_disable(XDMAC, m_tx_dma_channel);
    xdmac_channel_disable(XDMAC, m_rx_dma_channel);
    xdmac_configure_transfer(XDMAC, m_tx_dma_channel, &tx_dma_config);
    xdmac_configure_transfer(XDMAC, m_rx_dma_channel, &rx_dma_config);
}

void UsartDmaSAMV71::poll()
{
    // Nothing for Now
}

void UsartDmaSAMV71::timer_event()
{
    irq_event();
}

void UsartDmaSAMV71::data_rcvd(satcat5::io::Readable* src)
{
    // Atomic Lock
    satcat5::irq::AtomicLock lock(m_label);

    // Check TX Ready Bytes & Transfer
    u32 txbytes = m_tx.get_peek_ready();
    if (txbytes)
    {
        // Wait for DMA Channel
        while (XDMAC->XDMAC_CHID[m_tx_dma_channel].XDMAC_CIE != 0) continue;

        // Configure DMA Address & Length
        XDMAC->XDMAC_CHID[m_tx_dma_channel].XDMAC_CSA   =
            (u32)(m_tx.peek(txbytes));
        XDMAC->XDMAC_CHID[m_tx_dma_channel].XDMAC_CUBC  =
            txbytes;

        // Enable DMA Transfer
        XDMAC->XDMAC_GE = (1 << m_tx_dma_channel);

        // Consume Bytes
        m_tx.read_consume(txbytes);
    }
}

void UsartDmaSAMV71::irq_event()
{
    // Atomic Lock
    satcat5::irq::AtomicLock lock(m_label);

    // Assert Flow Control
    ioport_set_pin_level(m_flow_ctrl_pin, IOPORT_PIN_LEVEL_HIGH);

    // Get Buffer Pointer & Update Index
    u8* buf_ptr = (m_tmp_rx_buff_idx == 0) ? m_tmp_rxbuff_0 : m_tmp_rxbuff_1;
    m_tmp_rx_buff_idx = 1 - m_tmp_rx_buff_idx;

    // Disable DMA
    XDMAC->XDMAC_GD = (1 << m_rx_dma_channel);

    // Get Bytes Received
    u32 rx_recv_len = (XDMAC->XDMAC_CHID[m_rx_dma_channel].XDMAC_CUBC);

    // Re-Configure DMA
    XDMAC->XDMAC_CHID[m_rx_dma_channel].XDMAC_CDA   = (u32) buf_ptr;
    XDMAC->XDMAC_CHID[m_rx_dma_channel].XDMAC_CUBC  =
        SATCAT5_SAMV71_USART_DMA_BUFFSIZE;

    // Enable DMA
    XDMAC->XDMAC_GE = (1 << m_rx_dma_channel);

    // Calculate Bytes Received
    rx_recv_len = (SATCAT5_SAMV71_USART_DMA_BUFFSIZE - rx_recv_len);

    // Commit Bytes
    if (rx_recv_len)
    {
        if (m_tmp_rx_buff_idx == 1)
        {
            m_rx.write_bytes(rx_recv_len, m_tmp_rxbuff_1);
            m_rx.write_finalize();
        }
        else
        {
            m_rx.write_bytes(rx_recv_len, m_tmp_rxbuff_0);
            m_rx.write_finalize();
        }
    }

    // De-Assert Flow Control
    ioport_set_pin_level(m_flow_ctrl_pin, IOPORT_PIN_LEVEL_LOW);
}

//////////////////////////////////////////////////////////////////////////
