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

#include <cstring>
#include <satcat5/port_mailmap.h>

using satcat5::irq::AtomicLock;
using satcat5::port::Mailmap;

static const char* LBL_MAP = "MAP";
static const unsigned REGADDR_IRQ = 510;    // Matches position in ctrl_reg

Mailmap::Mailmap(satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr)
    : satcat5::cfg::Interrupt(cfg, devaddr, REGADDR_IRQ)
    , m_ctrl((ctrl_reg*)cfg->get_device_mmap(devaddr))
    , m_wridx(0)
    , m_wrovr(0)
    , m_rdidx(0)
    , m_rdlen(0)
    , m_rdovr(0)
{
    // No other initialization required.
}

unsigned Mailmap::get_write_space() const
{
    AtomicLock lock(LBL_MAP);
    if (m_ctrl->tx_ctrl)    // Busy?
        return 0;
    else if (m_wrovr)       // Overflow?
        return 0;
    else                    // Ready to write
        return SATCAT5_MAILMAP_BYTES - m_wridx;
}

void Mailmap::write_bytes(unsigned nbytes, const void* src)
{
    // For performance, use memcpy rather than repeated write_next().
    AtomicLock lock(LBL_MAP);
    if (nbytes <= get_write_space()) {
        memcpy(m_ctrl->tx_buff + m_wridx, src, nbytes);
        m_wridx += nbytes;
    } else write_overflow();
}

void Mailmap::write_overflow()
{
    // Set overflow flag to prevent further writes.
    m_wrovr = 1;
}

void Mailmap::write_abort()
{
    // Discard partially-written packet and revert to idle.
    m_wrovr = 0;
    m_wridx = 0;
}

bool Mailmap::write_finalize()
{
    AtomicLock lock(LBL_MAP);
    if (m_wrovr) {                  // Buffer overflow
        m_wrovr = 0;                // Reset for next frame
        m_wridx = 0;
        return false;
    } else if (m_wridx) {           // Valid packet
        m_ctrl->tx_ctrl = m_wridx;  // Begin transmission
        m_wridx = 0;                // Reset for next frame
        return true;
    } else {                        // Empty packet
        return false;
    }
}

void Mailmap::read_underflow()
{
    m_rdovr = 1;                    // Set underflow flag
}

unsigned Mailmap::get_read_ready() const
{
    AtomicLock lock(LBL_MAP);
    if (m_rdovr)
        return 0;                   // Read underflow
    else if (m_rdlen)
        return m_rdlen - m_rdidx;   // Ready to read
    else
        return 0;                   // Waiting for new packet...
}

bool Mailmap::read_bytes(unsigned nbytes, void* dst)
{
    // For performance, use memcpy rather than repeated read_next().
    AtomicLock lock(LBL_MAP);
    if (nbytes <= get_read_ready()) {
        memcpy(dst, m_ctrl->rx_buff + m_rdidx, nbytes);
        m_rdidx += nbytes;
        return true;
    } else {
        read_underflow();
        return false;
    }
}

void Mailmap::read_finalize()
{
    AtomicLock lock(LBL_MAP);
    if (m_rdlen) {
        m_ctrl->rx_ctrl = 0;        // Flush hardware buffer
        m_rdidx = 0;                // Reset for next frame
        m_rdlen = 0;
        m_rdovr = 0;
    }
}

void Mailmap::write_next(u8 data)
{
    m_ctrl->tx_buff[m_wridx++] = data;      // Write next byte to hardware
}

u8 Mailmap::read_next()
{
    return m_ctrl->rx_buff[m_rdidx++];      // Read next byte from hardware
}

void Mailmap::irq_event()
{
    m_rdlen = m_ctrl->rx_ctrl;              // Refresh Rx-buffer state
    if (m_rdlen) request_poll();            // Schedule follow-up?
}
