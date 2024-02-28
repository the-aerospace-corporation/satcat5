//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/port_mailmap.h>
#include <satcat5/ptp_time.h>
#include <satcat5/cfgbus_ptpref.h>

using satcat5::irq::AtomicLock;
using satcat5::log::DEBUG;
using satcat5::log::Log;
using satcat5::port::Mailmap;
using satcat5::ptp::Time;

// Enable additional diagnostics? (0/1/2)
// Note: Sending log messages may overwrite Tx timestamps before they are read.
static constexpr unsigned DEBUG_VERBOSE = 0;

static const char* LBL_MAP = "MAP";
static const unsigned REGADDR_IRQ = 510;    // Matches position in ctrl_reg

// Read standard 4-word timestamp, starting from designated register.
inline Time get_timestamp(volatile u32* addr)
{
    u32 secMSB = addr[0];
    u32 secLSB = addr[1];
    u32 nanoSec = addr[2];
    u16 subNanoSec = addr[3];
    u64 sec = ((u64)secMSB) << 32 | secLSB;
    return Time(sec, nanoSec, subNanoSec);
}

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
    } else {write_overflow();}
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
    // Interrupts indicate a new received packet. Update state.
    m_rdlen = m_ctrl->rx_ctrl;
    if (!m_rdlen) return;                   // Ignore empty packets
    // PTP packet? Deferred notification to selected event-handler.
    if (ptp_dispatch(m_ctrl->rx_buff, m_rdlen)) {
        ptp_notify_req();
    } else {
        request_poll();
    }
}

Time Mailmap::ptp_tx_start()
{
    // Initiate an outgoing PTP message
    m_ctrl->ptp_status = 0x01;                      // Freeze the RTC
    Time tmp = get_timestamp(m_ctrl->rt_clk_ctrl);  // Read the RTC
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "ptp_tx_start").write_obj(tmp);
    return tmp;
}

Time Mailmap::ptp_tx_timestamp()
{
    // Returns the timestamp for the previous outgoing message as ptp::Time
    Time tmp = get_timestamp(m_ctrl->tx_ptp_time);  // Read packet timestamp
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "ptp_tx_timestamp").write_obj(tmp);
    return tmp;
}

Time Mailmap::ptp_rx_timestamp()
{
    // Returns the timestamp for the current received message as ptp::Time
    Time tmp = get_timestamp(m_ctrl->rx_ptp_time);  // Read packet timestamp
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "ptp_rx_timestamp").write_obj(tmp);
    return tmp;
}

satcat5::io::Writeable* Mailmap::ptp_tx_write()
{
    return this;    // PTP and normal data use the same interface.
}

satcat5::io::Readable* Mailmap::ptp_rx_read()
{
    return this;    // PTP and normal data use the same interface.
}
