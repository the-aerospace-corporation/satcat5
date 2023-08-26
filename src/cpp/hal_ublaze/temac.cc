//////////////////////////////////////////////////////////////////////////
// Copyright 2022, 2023 The Aerospace Corporation
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

#include <satcat5/utils.h>
#include <satcat5/log.h>
#include <hal_ublaze/temac.h>

using satcat5::ptp::Time;
using satcat5::ublaze::Temac;
using satcat5::ublaze::TemacAvb;
using satcat5::ublaze::TemacTime;

// Define address offsets for specific control registers:
// (Refer to Xilinx PG051 "Tri-Mode Ethernet MAC v9.0")
static constexpr unsigned REG_RXCONFIG      = 0x404 / 4;
static constexpr unsigned REG_TXCONFIG      = 0x408 / 4;
static constexpr unsigned REG_FILTER        = 0x708 / 4;
static constexpr unsigned REG_AVB_RX_BASE   = 0x10000 / 4;
static constexpr unsigned REG_AVB_TX_BASE   = 0x11000 / 4;
static constexpr unsigned REG_AVB_TX_CTRL   = 0x12000 / 4;
static constexpr unsigned REG_AVB_RX_CTRL   = 0x12004 / 4;
static constexpr unsigned REG_AVB_OFFS_NSEC = 0x12800 / 4;
static constexpr unsigned REG_AVB_OFFS_SECL = 0x12808 / 4;
static constexpr unsigned REG_AVB_OFFS_SECH = 0x1280C / 4;
static constexpr unsigned REG_AVB_RATE      = 0x12810 / 4;
static constexpr unsigned REG_AVB_NOW_NSEC  = 0x12814 / 4;
static constexpr unsigned REG_AVB_NOW_SECL  = 0x12818 / 4;
static constexpr unsigned REG_AVB_NOW_SECH  = 0x1281C / 4;

// Max for AVB rate register is 63.99 nanoseconds per clock.
static constexpr u32 AVB_RATE_MAX           = 0x3FFFFFFu;

// Parametes for the AVB receive buffers:
static constexpr unsigned AVB_RXBUF_DATA    = 0;    // Offset to Rx frame data
static constexpr unsigned AVB_RXBUF_TIME    = 252;  // Offset to Rx timestamp
static constexpr unsigned AVB_RXBUF_SIZE    = 256;  // Size of each buffer
static constexpr unsigned AVB_RXBUF_DLEN    = AVB_RXBUF_TIME - AVB_RXBUF_DATA;
static constexpr unsigned AVB_TXBUF_LEN     = 0;    // Offset to Tx frame length
static constexpr unsigned AVB_TXBUF_DATA    = 8;    // Offset to Tx frame data
static constexpr unsigned AVB_TXBUF_TIME    = 252;  // Offset to Tx timestamp
static constexpr unsigned AVB_TXBUF_SIZE    = 256;  // Size of each buffer
static constexpr unsigned AVB_TXBUF_DLEN    = AVB_TXBUF_TIME - AVB_TXBUF_DATA;

// AVB mapping of PTP types to AVB transmit buffer index
static constexpr unsigned AVB_TX_SYNC       = 0;
static constexpr unsigned AVB_TX_FOLLOW_UP  = 1;
static constexpr unsigned AVB_TX_DLY_REQ    = 2;
static constexpr unsigned AVB_TX_DLY_RESP   = 3;
static constexpr unsigned AVB_TX_ANNOUNCE   = 4;

// From IEEE1588 spec
static constexpr u8 PTP_TYPE_MASK           = 0x0F;
static constexpr u8 PTP_TYPE_SYNC           = 0x0;
static constexpr u8 PTP_TYPE_DLY_REQ        = 0x1;
static constexpr u8 PTP_TYPE_PATH_DLY_REQ   = 0x2;
static constexpr u8 PTP_TYPE_FOLLOW_UP      = 0x8;
static constexpr u8 PTP_TYPE_DLY_RESP       = 0x9;
static constexpr u8 PTP_TYPE_ANNOUNCE       = 0xB;

Temac::Temac(uintptr_t baseaddr)
    : m_regs((volatile u32*) baseaddr)
{
    m_regs[REG_RXCONFIG]    = 0x90000000u;  // Reset + Disable FCS passing (RX)
    m_regs[REG_TXCONFIG]    = 0x90000000u;  // Reset + Disable FCS passing (TX)
    m_regs[REG_FILTER]      = 0x80000100u;  // Promiscuous mode + AVB filter
}

TemacAvb::TemacAvb(uintptr_t baseaddr, int irq_idx)
    : Temac(baseaddr)
    , satcat5::io::ReadableRedirect(&m_rxbuff)
    , satcat5::irq::Handler("TemacAVB", irq_idx)
    , m_txbuff(m_txrawbuff, sizeof(m_txrawbuff), 16)
    , m_rxbuff(m_rxrawbuff, sizeof(m_rxrawbuff), 16)
    , m_tx_callback(nullptr)
    , m_prev_buf_idx(0)
    , m_frames_waiting(0x00)
{
    // Additional setup for AVB system
    m_regs[REG_AVB_TX_CTRL] = 0;    // Tx reset
    m_regs[REG_AVB_RX_CTRL] = 1;    // Rx reset
    // Read and discard status register to clear interrupt flag.
    (void) m_regs[REG_AVB_RX_CTRL];

    // TEMAC AVB requires a GMII or RGMII interface - both have 125MHz clocks
    // Format is fixed point 6.20, period is 8ns.
    avb_set_rate(8 << 20);
    avb_jump_by({ 0, 0 });
}

void TemacAvb::set_tx_callback(TemacAvbTxCallback* tx_callback) {
    m_tx_callback = tx_callback;
}

TemacTime TemacAvb::avb_get_time()
{
    // A read from the nanoseconds register samples the entire counter.
    u32 time_n = m_regs[REG_AVB_NOW_NSEC];
    u64 time_s = m_regs[REG_AVB_NOW_SECL];
    u64 time_e = m_regs[REG_AVB_NOW_SECH];
    time_s += (time_e << 32);
    return TemacTime{(s64)time_s, time_n};
}

void TemacAvb::avb_set_rate(u32 incr)
{
    // Sanity check on rate before updating the register.
    if (incr > AVB_RATE_MAX) incr = AVB_RATE_MAX;
    m_regs[REG_AVB_RATE] = incr;
}

void TemacAvb::avb_jump_by(const TemacTime& delta)
{
    // New timestamp is committed once the nanoseconds register is written
    m_regs[REG_AVB_OFFS_SECH] = (u32)(delta.sec >> 32);
    m_regs[REG_AVB_OFFS_SECL] = (u32)(delta.sec >> 0);
    m_regs[REG_AVB_OFFS_NSEC] = delta.nsec;
}

Time TemacAvb::clock_adjust(const Time& amount)
{
    // Testing indicates that shifts smaller than one second have no effect.
    // This appears to be a bug in the Xilinx IP, so we need a workaround.
    if (amount.abs() < satcat5::ptp::ONE_SECOND)
        return amount;  // Skip adjustment if it would have no effect.
    TemacTime tmp = {amount.secs(), amount.nsec()};
    avb_jump_by(tmp);   // Apply adjustment
    return Time(0);     // Report success (zero residue)
}

void TemacAvb::clock_rate(s64 offset)
{
    // Limit maximum offset from nominal rate.
    constexpr s32 NOMINAL    = (8 << 20);   // 8.0 nsec per clock
    constexpr s32 MAX_OFFSET = (1 << 20);   // 1.0 nsec per clock
    if (offset < -MAX_OFFSET) offset = -MAX_OFFSET;
    if (offset > MAX_OFFSET) offset = MAX_OFFSET;
    s32 rate = NOMINAL + (s32)offset;
    avb_set_rate((u32)rate);
}

void TemacAvb::irq_event()
{
    // Read the current buffer pointer to see if there are new packets.
    // (Reading this register also clears the interrupt flag, if set.)
    u32 rx_status = m_regs[REG_AVB_RX_CTRL];

    // Status reg contains index of last element in ringbuffer
    u32 ringbuf_end = ((rx_status >> 8) + 1) & 0xF;

    // Copy each received packet for later processing:
    while (m_prev_buf_idx != ringbuf_end) {
        // Get pointer to the next buffer:
        const u8* rx_ptp_buf = (const u8*)(m_regs + REG_AVB_RX_BASE);
        rx_ptp_buf += AVB_RXBUF_SIZE * m_prev_buf_idx;

        // Extract useful fields from that buffer:
        // Note: No length indicator, always copy full contents.
        const u8*   pdata   = (const u8*)(rx_ptp_buf + AVB_RXBUF_DATA);
        const u32*  ptime   = (const u32*)(rx_ptp_buf + AVB_RXBUF_TIME);

        // Copy received data and metadata to the working buffer.
        // (Write timestamp first for easier packet processing.)
        m_rxbuff.write_u32(*ptime);
        m_rxbuff.write_bytes(AVB_RXBUF_DLEN, pdata);
        m_rxbuff.write_finalize();
        // Increment buffer index with wraparound.
        m_prev_buf_idx = (m_prev_buf_idx + 1) & 0xF;
    }
}

void TemacAvb::poll_always()
{
    // Polling loop added due to issues with TEMAC interrupt reliability.
    satcat5::irq::AtomicLock lock(m_label);
    irq_event();
    check_frames_waiting();
}

void TemacAvb::check_frames_waiting()
{
    // Frame waiting indicators are bits 15:8. Check for updates
    u8 new_frames_waiting = (u8) (m_regs[REG_AVB_TX_CTRL] >> 8);
    u8 frame_updates = new_frames_waiting ^ m_frames_waiting;
    if (frame_updates == 0) {
        return;
    }

    // Some frame updates, capture timestamps and send updates if the frame was sent (1 -> 0)
    for (u32 i = 0; i < 8; i++) {
        if (((frame_updates >> i) & 0x1) == 0) { // No updates for this frame
            continue;
        }
        if (((new_frames_waiting >> i) & 0x1) == 0) { // Frame was sent

            // Log(LOG_DEBUG, "Frame was sent from buffer #").write10(i);

            // Get TX time nsec field, taken at end of trame TX
            const u8* tx_ptp_buf = (const u8*)(m_regs + REG_AVB_TX_BASE);
            tx_ptp_buf += AVB_TXBUF_SIZE * i;
            const u32* ptime = (const u32*)(tx_ptp_buf + AVB_TXBUF_TIME);
            // Build full TX time with sec field
            auto now = avb_get_time(); // Convert to PTPTime?
            s64 tx_time_sec = now.sec;
            u32 tx_time_nsec = *ptime;
            if (now.nsec < tx_time_nsec && now.sec > 0) { // Second rollover since packet was sent
                tx_time_sec--;
            }
            Time tx_time(tx_time_sec, tx_time_nsec);

            // Save state before callback to avoid recusive loop
            m_frames_waiting = new_frames_waiting;

            // Send egress time to higher layer state machines
            if (m_tx_callback) {
                switch(i) {
                    case AVB_TX_SYNC:
                        m_tx_callback->tx_sync(tx_time);
                        break;
                    case AVB_TX_DLY_REQ:
                        m_tx_callback->tx_delay_req(tx_time);
                        break;
                    default: {}
                }
            }

        } else { // send_frame() sets m_frames_waiting, so something else queued a packet
            Log(LOG_DEBUG, "Frame was silently queued to buffer #").write10(i);
            m_frames_waiting = new_frames_waiting;
        }
    }
}

void TemacAvb::send_frame(const u8* buf, unsigned buf_len)
{

    // Sanity check
    if (buf_len < 14+34) { // min size for eth+PTP headers
        Log(LOG_WARNING, "Runt frame passed to TemacAvb::send_frame(), ignoring...");
        return;
    }

    // Look up which PTP frame this is by peeking the buffer
    // Log(LOG_DEBUG, "Sending PTP eth frame").write(buf, 32);
    u8 ptp_type = buf[14] & 0x0F; // Skip eth header, second nibble of PTP header
    u8 avb_tx_buf_idx = 0;
    switch(ptp_type) {
        // Below defs from TEMAC docs: PG051 v9.0 Table 2-57
        case PTP_TYPE_SYNC:
            avb_tx_buf_idx = AVB_TX_SYNC;
            break;
        case PTP_TYPE_FOLLOW_UP:
            avb_tx_buf_idx = AVB_TX_FOLLOW_UP;
            break;
        case PTP_TYPE_DLY_REQ:
        case PTP_TYPE_PATH_DLY_REQ:
            // There is no Delay_Req buffer? Reusing Pdelay_Req buffer.
            avb_tx_buf_idx = AVB_TX_DLY_REQ;
            break;
        case PTP_TYPE_DLY_RESP:
            avb_tx_buf_idx = AVB_TX_DLY_RESP;
            break;
        case PTP_TYPE_ANNOUNCE:
            avb_tx_buf_idx = AVB_TX_ANNOUNCE;
            break;
        default:
            Log(LOG_WARNING, "TemacAvb::send_frame() was passed a PTP ethernet frame "
                    "with unsupported PTP type").write10((u32) ptp_type);
            return;
    }

    // Ensure the frame we want to send is not waiting
    check_frames_waiting();
    if (m_frames_waiting & (1 << avb_tx_buf_idx)) {
        // Already pending a frame for this buffer, don't overwrite
        Log(LOG_INFO, "A new PTP frame was requested in a pending buffer and "
                "will not be overwritten.");
        return;
    }

    // Get pointer to destination buffer
    // Write the packet length in the first byte, 7 reserved bytes, data starts on 8th byte
    const u8* tx_ptp_buf = (const u8*)(m_regs + REG_AVB_TX_BASE);
    tx_ptp_buf += AVB_TXBUF_SIZE * avb_tx_buf_idx;
    u8* plen  = (u8*)(tx_ptp_buf + AVB_TXBUF_LEN);
    *plen = (u8) buf_len;
    u32* pdata = (u32*)(tx_ptp_buf + AVB_TXBUF_DATA);
    memcpy(pdata, buf, buf_len);

    // Notify the AVB core intent to send this packet using 8 LSBs of TX CTRL reg
    m_regs[REG_AVB_TX_CTRL] = (1 << avb_tx_buf_idx);
    // The frame could be sent before the call to check_frames_waiting(), so go ahead and
    // register the queued transmission in the member var
    m_frames_waiting |= (1 << avb_tx_buf_idx); // See above note
    check_frames_waiting();
}
