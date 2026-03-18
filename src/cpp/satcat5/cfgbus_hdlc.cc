//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_hdlc.h>
#include <satcat5/polling.h>
#include <satcat5/utils.h>

using satcat5::cfg::Hdlc;
using satcat5::util::div_round_u32;

// Define hardware register map.
static const unsigned REGADDR_IRQ       = 0;
static const unsigned REGADDR_CFG       = 1;
static const unsigned REGADDR_STATUS    = 2;
static const unsigned REGADDR_DATA      = 3;

// Define control-register commands:
static const u32 CMD_EOF = 0x0100u;

// Status and command codes for the multiserial control registers.
static const u32 MS_DVALID      = (1u << 8);
static const u32 MS_RD_READY    = (1u << 0);
static const u32 MS_CMD_FULL    = (1u << 1);

Hdlc::Hdlc(satcat5::cfg::ConfigBus* cfg, unsigned devaddr)
    : BufferedIO(m_txbuff, SATCAT5_HDLC_BUFFSIZE, SATCAT5_HDLC_MAXPKT,
                 m_rxbuff, SATCAT5_HDLC_BUFFSIZE, 0)
    , Interrupt(cfg, devaddr, REGADDR_IRQ)
    , m_ctrl(cfg->get_register(devaddr))
    , m_tx_eof(false)
{
    // No other initialization at this time.
}

void Hdlc::configure(
    unsigned clkref_hz,
    unsigned baud_hz,
    unsigned frame_bytes)
{
    // Note: Writing to Config register also resets hardware FIFOs.
    u32 clkdiv = div_round_u32(clkref_hz, baud_hz);
    m_ctrl[REGADDR_CFG] = (frame_bytes << 16) | (clkdiv);
}

void Hdlc::data_rcvd(satcat5::io::Readable* src) {
    // Forward data from Tx-FIFO to hardware.
    unsigned rdy = src->get_read_ready();
    while (m_tx_eof || rdy) {
        // Any space in the command FIFO?  If so, issue command (data or EOF).
        u32 status = m_ctrl[REGADDR_STATUS];
        if (status & MS_CMD_FULL) break;
        if (m_tx_eof) {
            m_ctrl[REGADDR_DATA] = CMD_EOF;
            m_tx_eof = false;
        } else {
            m_ctrl[REGADDR_DATA] = src->read_u8();
            if (--rdy == 0) { m_tx_eof = true; }
        }
    }
    // End of data? Always finalize to avoid getting stuck in limbo.
    if (!rdy) src->read_finalize();
    // Do we need to schedule follow-up for trailing EOF?
    // (The command FIFO may fill before we can write CMD_EOF.)
    if (m_tx_eof) { timer_every(1); } else { timer_stop(); }
}

void Hdlc::irq_event() {
    // Read any data waiting in the hardware FIFO.
    // (Let PacketBuffer object handle overflow, if it occurs.)
    unsigned nwrite = 0;
    while (1) {
        u32 data = m_ctrl[REGADDR_DATA];
        if (data & MS_DVALID) {
            u8 byte = (u8)(data & 0xFF);
            m_rx.write_u8(byte);
            ++nwrite;
        } else {
            break;
        }
    }

    // Finalize new data to ensure downstream notifications.
    if (nwrite) m_rx.write_finalize();
}

void Hdlc::timer_event() {
    // Trailing EOF: Write the command as soon as the FIFO has space.
    // (We may not get another data_rcvd() notification.)
    data_rcvd(&satcat5::io::null_read);
}
