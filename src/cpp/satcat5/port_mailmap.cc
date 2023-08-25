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
#include <satcat5/cfgbus_ptpref.h>

using satcat5::irq::AtomicLock;
using satcat5::port::Mailmap;
using satcat5::ptp::Time;

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
    m_rdlen = m_ctrl->rx_ctrl;              // Refresh Rx-buffer state
    if (m_rdlen) request_poll();            // Schedule follow-up?
}

Time Mailmap::ptp_tx_start()
{
    // Initiate an outgoing PTP message
    m_ctrl->ptp_status = 0x01;                  // Freeze the RTC
    return get_timestamp(m_ctrl->rt_clk_ctrl);  // Read the current time
}

Time Mailmap::ptp_tx_timestamp()
{
    // Returns the timestamp for the previous outgoing message as ptp::Time
    return get_timestamp(m_ctrl->tx_ptp_time);
}

Mailmap::PtpType Mailmap::ptp_rx_peek()
{
    // Peek at the contents of an incoming message and determine if it is a PTP message.
    // Returns an enum that indicates whether it is non - PTP, PTP - L2(raw), or PTP - L3(UDP)

    satcat5::eth::MacType ether_type = {util::extract_be_u16(m_ctrl->rx_buff + 12)};

    if (ether_type == satcat5::eth::ETYPE_PTP)        // PTP - L2 if etherType is 0x88F7
    {
        return PtpType::PTPL2;
    }

    if (ether_type == satcat5::eth::ETYPE_IPV4)        // might be PTP - L3 if ether_type is 0x0800
    {
        // Get protocol type, check if it's UDP i.e. protocol = 17 = 0x11.
        u8 protocol = m_ctrl->rx_buff[23];

        if (protocol == satcat5::ip::PROTO_UDP)
        {
            // Get the header length
            u16 version_and_length = util::extract_be_u16(&(m_ctrl->rx_buff[14]));
            u16 header_length = (version_and_length >> (8)) & 0x000f;

            // Find the source and destination ports (their position depends on the header length)
            u16 src_port_index = 14 + header_length * 4;
            u16 dst_port_index = 16 + header_length * 4;
            satcat5::ip::Port src_port = util::extract_be_u16(m_ctrl->rx_buff + src_port_index);
            satcat5::ip::Port dst_port = util::extract_be_u16(m_ctrl->rx_buff + dst_port_index);

            // If source or destination port is 319 or 320, message is PTP - L3
            if (src_port == satcat5::udp::PORT_PTP_EVENT || src_port == satcat5::udp::PORT_PTP_GENERAL ||
                dst_port == satcat5::udp::PORT_PTP_EVENT || dst_port == satcat5::udp::PORT_PTP_GENERAL)
            {
                return PtpType::PTPL3;
            }
        }
    }

    // Message is not PTP
    return PtpType::nonPTP;
}

Time Mailmap::ptp_rx_timestamp()
{
    // Returns the timestamp for the current received message as ptp::Time
    return get_timestamp(m_ctrl->rx_ptp_time);
}
