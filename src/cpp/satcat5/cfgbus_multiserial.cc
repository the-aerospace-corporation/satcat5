//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_multiserial.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

namespace log   = satcat5::log;
namespace util  = satcat5::util;

// Define the ConfigBus register map.
const unsigned satcat5::cfg::MultiSerial::REGADDR_IRQ       = 0;
const unsigned satcat5::cfg::MultiSerial::REGADDR_CFG       = 1;
const unsigned satcat5::cfg::MultiSerial::REGADDR_STATUS    = 2;
const unsigned satcat5::cfg::MultiSerial::REGADDR_DATA      = 3;

// Status and command codes for the multiserial control registers.
static const u32 MS_DVALID      = (1u << 8);
static const u32 MS_RD_READY    = (1u << 0);
static const u32 MS_CMD_FULL    = (1u << 1);
static const u32 MS_BUSY        = (1u << 2);
static const u32 MS_ERROR       = (1u << 3);

satcat5::cfg::MultiSerial::MultiSerial(
        ConfigBus* cfg, unsigned devaddr,
        unsigned maxpkt,
        u8* txbuff, unsigned txsize,
        u8* rxbuff, unsigned rxsize)
    : cfg::Interrupt(cfg, devaddr, REGADDR_IRQ)
    , m_ctrl(cfg->get_register(devaddr))
    , m_tx(txbuff, txsize, maxpkt)
    , m_rx(rxbuff, rxsize, maxpkt)
    , m_cmd_max(maxpkt)
    , m_cmd_cbidx(0)
    , m_cmd_queued(0)
    , m_new_wralloc(0)
    , m_new_rdalloc(0)
    , m_rdalloc(0)
    , m_irq_wrrem(0)
    , m_irq_rdrem(0)
{
    m_rdalloc = m_rx.get_write_space();
    m_rx.set_callback(this);
}

bool satcat5::cfg::MultiSerial::write_check(unsigned ncmd, unsigned nread)
{
    // Sanity check: Can we accept this command at all?
    if (ncmd == 0) return false;                    // Invalid command
    if (m_cmd_queued >= m_cmd_max) return false;    // No room in Rx-buffer

    // Check free-space in command buffer:
    // (Each command includes u8 read-length, then u16 each opcode.)
    m_new_wralloc = 1 + 2*ncmd;
    if (m_new_wralloc > m_tx.get_write_space()) return false;

    // Check preallocated space in reply buffer:
    // (Each command includes u8 each reply byte, then u8 error flag.)
    m_new_rdalloc = nread + 1;
    if (m_new_rdalloc > m_rdalloc) return false;

    // Safe to proceed.
    m_tx.write_u8(m_new_rdalloc);
    return true;
}

unsigned satcat5::cfg::MultiSerial::write_finish()
{
    // Calculate index of the new command.
    unsigned idx = util::modulo_add_uns(m_cmd_cbidx + m_cmd_queued, m_cmd_max);

    // Sanity-check: Predicted length should match actual.
    unsigned actual = m_tx.get_write_partial();
    if (m_new_wralloc != actual) {
        log::Log(log::ERROR, "MST: Write-length mismatch")
            .write((u16)actual).write((u16)m_new_wralloc);
        m_tx.write_abort();     // Discard this command
    } else {
        m_tx.write_finalize();  // Retain this command
        ++m_cmd_queued;
        m_rdalloc -= m_new_rdalloc;
        request_poll();         // Start writing if possible
    }

    return idx;
}

void satcat5::cfg::MultiSerial::data_rcvd()
{
    // Handle any pending notifications...
    unsigned nread;
    while (nread = m_rx.get_read_ready(), nread) {
        // Ask child to handle callback.
        read_done(m_cmd_cbidx);
        m_rx.read_finalize();
        // Mark this item as completed.
        --m_cmd_queued;
        m_rdalloc += nread;
        m_cmd_cbidx = util::modulo_add_uns(m_cmd_cbidx + 1, m_cmd_max);
    }
}

void satcat5::cfg::MultiSerial::irq_event()
{
    // Schedule follow-up, but no urgent action required.
    request_poll();
}

void satcat5::cfg::MultiSerial::poll_demand()
{
    // Read each reply byte from the hardware FIFO.
    while (m_irq_rdrem > 1) {
        u32 tmp = m_ctrl[REGADDR_DATA];
        if (tmp & MS_DVALID) {
            m_rx.write_u8((u8)(tmp & 0xFF));
            --m_irq_rdrem;
        } else {
            break;
        }
    }

    // Did we just finish a command?
    if (m_irq_wrrem == 0 && m_irq_rdrem == 1) {
        // Check the hardware BUSY flag...
        u32 status = m_ctrl[REGADDR_STATUS];
        if (status & MS_BUSY) {
            // Still busy? Try again later.
            request_poll();
            return;
        } else {
            // Done with command, note error flag.
            m_irq_rdrem = 0;
            m_rx.write_u8((status & MS_ERROR) ? 1 : 0);
            m_rx.write_finalize();
            m_tx.read_finalize();
        }
    }

    // Should we open a new command?
    if (m_irq_wrrem == 0 && m_irq_rdrem == 0) {
        if (m_tx.get_read_ready()) {
            m_irq_rdrem = m_tx.read_u8();
            m_irq_wrrem = m_tx.get_read_ready() / 2;
        } else {
            return;                     // Idle.
        }
    }

    // Write each opcode to the hardware FIFO.
    while (m_irq_wrrem) {
        u32 status = m_ctrl[REGADDR_STATUS];
        if (status & MS_CMD_FULL) break;
        m_ctrl[REGADDR_DATA] = (u32)m_tx.read_u16();
        --m_irq_wrrem;
    }
}
