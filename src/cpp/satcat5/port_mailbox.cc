//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/port_mailbox.h>

using satcat5::port::Mailbox;

// Maximum I/O segment-length.
// (Very long contiguous reads can exceed safe lock time.)
static const unsigned MAX_SEGMENT = 256;

// Opcodes and bit-masks for the control register:
static const u32 ETHCMD_NOOP    = (0x00u << 24);
static const u32 ETHCMD_WRNEXT  = (0x02u << 24);
static const u32 ETHCMD_WRFINAL = (0x03u << 24);
static const u32 ETHCMD_RESET   = (0xFFu << 24);

static const u32 ETHREG_DVALID  = (1u << 31);
static const u32 ETHREG_DFINAL  = (1u << 30);
static const u32 ETHREG_ERROR   = (1u << 29);
static const u32 ETHREG_DMASK   = (0xFFu);

Mailbox::Mailbox(satcat5::cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : satcat5::io::BufferedIO(
            m_txbuff, SATCAT5_MAILBOX_BUFFSIZE, SATCAT5_MAILBOX_BUFFPKT,
            m_rxbuff, SATCAT5_MAILBOX_BUFFSIZE, SATCAT5_MAILBOX_BUFFPKT)
    , satcat5::cfg::Interrupt(cfg)
    , m_hw_reg(cfg->get_register(devaddr, regaddr))
{
    // Send reset command to hardware.
    *m_hw_reg = ETHCMD_RESET;
}

void Mailbox::data_rcvd()
{
    // Copy segments of data to the hardware buffer.
    while (copy_tx_segment()) {}
}

u32 Mailbox::copy_tx_segment()
{
    satcat5::irq::AtomicLock lock("ETH-Tx");

    // How much data is available in the next segment?
    // (Use peek/consume for better throughput.)
    u32 pkt = m_tx.get_read_ready();    // Bytes to EOF
    u32 seg = m_tx.get_peek_ready();    // Bytes to EOF or wraparound

    // Special case if empty.
    if (!seg) return 0;                 // No data available

    // Cap segment length to avoid hogging lock time.
    if (seg > MAX_SEGMENT) seg = MAX_SEGMENT;

    // Fetch pointer to start of next contiguous segment:
    const u8* src = m_tx.peek(seg);

    // Is this a complete packet?
    if (pkt == seg) {
        // Complete packet, set FINAL flag.
        for (unsigned a = 0 ; a < seg-1 ; ++a)
            *m_hw_reg = ETHCMD_WRNEXT | src[a];
        // cppcheck-suppress redundantAssignment
        *m_hw_reg = ETHCMD_WRFINAL | src[seg-1];
        m_tx.read_finalize();
    } else {
        // Partial packet.
        for (unsigned a = 0 ; a < seg ; ++a)
            *m_hw_reg = ETHCMD_WRNEXT | src[a];
        m_tx.read_consume(seg);
    }
    return seg;
}

u32 Mailbox::copy_rx_segment()
{
    satcat5::irq::AtomicLock lock("ETH-Rx");

    // Get the next contiguous buffer segment.
    u32 rem = m_rx.zcw_maxlen();
    u8* dst = m_rx.zcw_start();

    // Abort if the FIFO is full.
    if (!rem) return ETHREG_ERROR;

    // Cap segment length to avoid hogging lock time.
    if (rem > MAX_SEGMENT) rem = MAX_SEGMENT;

    // Copy any received data to the software FIFO.
    u32 reg = *m_hw_reg;
    while ((rem) && (reg & ETHREG_DVALID)) {
        // Copy the next byte...
        *dst = (u8)(reg & ETHREG_DMASK);
        ++dst; --rem;
        // Was this the end of a frame?
        if (reg & ETHREG_DFINAL) break;
        // Poll hardware for the next byte...
        if (rem) reg = *m_hw_reg;
    }

    // Complete the write process.
    u32 ncopy = dst - m_rx.zcw_start();
    m_rx.zcw_write(ncopy);
    if (reg & ETHREG_DFINAL)
        m_rx.write_finalize();  // End of frame

    return reg;
}

// Interrupt context copies received data ONLY.
// Data MUST be read immediately; any overflow is discarded.
void Mailbox::irq_event()
{
    // Copy one segment of received data.
    // (Keep interrupts short to avoid priority inversion.)
    u32 reg = copy_rx_segment();

    // If we encountered an error, flush any partial data.
    if (reg & ETHREG_ERROR) {
        while (reg & (ETHREG_DVALID | ETHREG_ERROR))
            reg = *m_hw_reg;    // Read and discard until empty
        m_rx.write_abort();     // Discard any work in progress
    }
}
