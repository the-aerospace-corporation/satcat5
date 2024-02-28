//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2022 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <cstring>
#include <satcat5/interrupts.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/utils.h>

using satcat5::io::PacketBuffer;
using satcat5::irq::AtomicLock;
using satcat5::util::modulo_add_uns;
using satcat5::util::min_unsigned;

// Safety-check ZCQ calls? Safe but slow.
static const unsigned DEBUG_SAFE_ZCW    = 0;

// For compatibility with previous versions, optionally allow user
// to advance to next packet without calling read_finalize().
#ifndef SATCAT5_PKTBUF_AUTORDF
#define SATCAT5_PKTBUF_AUTORDF  0   // Disabled by default
#endif

// Label for AtomicLock statistics tracking.
static const char* LBL_PKT = "PKT";

PacketBuffer::PacketBuffer(u8* buff, unsigned nbytes, unsigned max_pkt)
    : m_buff(buff + 2*max_pkt)
    , m_buff_size(nbytes - 2*max_pkt)
    , m_buff_rdidx(0)
    , m_buff_rdcount(0)
    , m_pkt_lbuff((u16*)buff)
    , m_pkt_maxct(max_pkt)
    , m_pkt_rdidx(0)
    , m_next_wrpos(0)
    , m_next_wrlen(0)
    , m_shared_rdavail(0)
    , m_shared_pktcount(0)
{
    // No further initialization required
}

void PacketBuffer::clear()
{
    AtomicLock lock(LBL_PKT);
    m_buff_rdidx = 0;
    m_buff_rdcount = 0;
    m_pkt_rdidx = 0;
    m_next_wrpos = 0;
    m_next_wrlen = 0;
    m_shared_rdavail = 0;
    m_shared_pktcount = 0;
}

u8 PacketBuffer::get_percent_full() const
{
    unsigned wralloc = m_buff_size - m_shared_rdavail;
    if (m_next_wrlen >= wralloc)
        return 100;
    unsigned wr_pct = (100 * (m_shared_rdavail + m_next_wrlen)) / m_buff_size;
    unsigned pkt_pct = 0;
    if (m_pkt_maxct)
        pkt_pct = (100 * m_shared_pktcount) / m_pkt_maxct;
    return (u8)satcat5::util::max_unsigned(wr_pct, pkt_pct);
}

unsigned PacketBuffer::get_write_space() const
{
    // No space if we overflow the buffer (wrlen = UINT32_MAX).
    unsigned wralloc = m_buff_size - m_shared_rdavail;
    if (m_next_wrlen > wralloc)
        return 0;
    // In packet mode, also restricted by max packet size UINT16_MAX
    // and by the number of packets, regardless of size.
    if (m_pkt_maxct) {
        if (m_next_wrlen >= UINT16_MAX) return 0;
        if (m_shared_pktcount >= m_pkt_maxct) return 0;
        return min_unsigned(wralloc - m_next_wrlen, UINT16_MAX - m_next_wrlen);
    } else {
        // Otherwise we can simply compute the remaining space
        return wralloc - m_next_wrlen;
    }
}

unsigned PacketBuffer::get_write_partial() const
{
    return m_next_wrlen;
}

void PacketBuffer::write_bytes(unsigned nbytes, const void* src)
{
    // For performance, use memcpy rather than repeated write_next().
    const u8* src_u8 = (const u8*)src;
    if (get_write_space() >= nbytes) {
        unsigned wridx = modulo_add_uns(m_next_wrpos + m_next_wrlen, m_buff_size);
        unsigned wrap = m_buff_size - wridx;
        if (nbytes > wrap) {    // Two segments (wrap)
            memcpy(m_buff + wridx, src_u8, wrap);
            memcpy(m_buff, src_u8 + wrap, nbytes - wrap);
        } else {                // One segment
            memcpy(m_buff + wridx, src_u8, nbytes);
        }
        m_next_wrlen += nbytes;
    } else {write_overflow();}
}

void PacketBuffer::write_abort()
{
    m_next_wrlen = 0; // Operation cancelled
}

void PacketBuffer::write_next(u8 data)
{
    // Write to the appropriate location in the circular buffer.
    unsigned wridx = modulo_add_uns(m_next_wrpos + m_next_wrlen, m_buff_size);
    m_buff[wridx] = data;
    // Increment temporary write pointer location.
    ++m_next_wrlen;
}

void PacketBuffer::write_overflow()
{
    m_next_wrlen = UINT32_MAX;    // Overflow / Error
}

bool PacketBuffer::write_finalize()
{
    AtomicLock lock(LBL_PKT);

    // Whatever happens, clear m_next_wrlen.
    unsigned next_len = m_next_wrlen;
    m_next_wrlen = 0;

    // Handle empty packets or overflow.
    unsigned wrmax = m_buff_size - m_shared_rdavail;
    if ((next_len == 0) || (next_len > wrmax)) {
        return false;
    }

    // Update per-packet state, if applicable.
    if (m_pkt_maxct) {
        if (m_shared_pktcount < m_pkt_maxct) {
            // Packet accepted, update the next stored length.
            unsigned wridx = modulo_add_uns(m_pkt_rdidx + m_shared_pktcount, m_pkt_maxct);
            m_pkt_lbuff[wridx] = next_len;
            ++m_shared_pktcount;
        } else if (m_pkt_maxct) {
            // No room in the length buffer, discard unwritten data.
            return false;
        }
    }

    // Write accepted, update overall buffer state.
    m_shared_rdavail += next_len;
    m_next_wrpos = modulo_add_uns(m_next_wrpos + next_len, m_buff_size);

    // Success! Request follow-up for received-data callback.
    request_poll();
    return true;
}

unsigned PacketBuffer::zcw_maxlen() const
{
    unsigned wralloc = m_buff_size - m_shared_rdavail;
    if (m_next_wrlen < wralloc) {
        unsigned wridx = modulo_add_uns(m_next_wrpos + m_next_wrlen, m_buff_size);
        unsigned max_write = get_write_space();
        unsigned max_wrap  = m_buff_size - wridx;
        return min_unsigned(max_write, max_wrap);
    } else {
        return 0;   // Not an error unless user tries to write.
    }
}

u8* PacketBuffer::zcw_start()
{
    // Safety check: Confirm maxlen > 0.
    if (DEBUG_SAFE_ZCW && !zcw_maxlen())
        return 0;   // Not an error unless user tries to write.

    // Otherwise, calculate write index.
    unsigned wridx = modulo_add_uns(m_next_wrpos + m_next_wrlen, m_buff_size);
    return m_buff + wridx;
}

void PacketBuffer::zcw_write(unsigned nbytes)
{
    // Safety check: Confirm this was a safe write.
    if (DEBUG_SAFE_ZCW) {
        unsigned max_safe = zcw_maxlen();
        if (nbytes > max_safe) {
            m_next_wrlen = UINT32_MAX;
            return;
        }
    }
    // Increment the amount of temporary working data.
    m_next_wrlen += nbytes;
}

unsigned PacketBuffer::get_read_ready() const
{
    if (!m_pkt_maxct) {                 // Non-packet mode
        return m_shared_rdavail - m_buff_rdcount;
    } else if (m_shared_pktcount) {     // Remainder of current packet
        return m_pkt_lbuff[m_pkt_rdidx];
    } else {                            // No packets in buffer
        return 0;
    }
}

bool PacketBuffer::read_bytes(unsigned nbytes, void* dst)
{
    // For performance, use memcpy rather than repeated read_next().
    u8* dst_u8 = (u8*)dst;
    if (can_read_internal(nbytes)) {
        unsigned wrap = m_buff_size - m_buff_rdidx;
        if (nbytes > wrap) {    // Two segments (wraparound)
            memcpy(dst_u8, m_buff + m_buff_rdidx, wrap);
            memcpy(dst_u8 + wrap, m_buff, nbytes - wrap);
        } else {                // One segment
            memcpy(dst_u8, m_buff + m_buff_rdidx, nbytes);
        }
        consume_internal(nbytes);
        return true;        // Success
    } else {
        read_underflow();
        return false;
    }
}

u8 PacketBuffer::read_next()
{
    // Return the next byte.
    u8 temp = m_buff[m_buff_rdidx];
    consume_internal(1);
    return temp;
}

bool PacketBuffer::can_read_internal(unsigned nbytes) const
{
    if (!m_pkt_maxct) {
        return (nbytes <= m_shared_rdavail - m_buff_rdcount);
    } else if (m_shared_pktcount) {
        return (nbytes <= m_pkt_lbuff[m_pkt_rdidx]);
    } else {
        return false;
    }
}

void PacketBuffer::consume_internal(unsigned nbytes)
{
    // Increment read pointer.
    m_buff_rdidx = modulo_add_uns(m_buff_rdidx + nbytes, m_buff_size);

    // Decrement global and per-packet length counters.
    m_buff_rdcount += nbytes;
    if (m_pkt_maxct) {
        m_pkt_lbuff[m_pkt_rdidx] -= nbytes;
    }

    // Is auto-finalize enabled?  Last byte calls read_finalize.
    if (SATCAT5_PKTBUF_AUTORDF && m_pkt_maxct) {
        // Packet mode -> Last byte in frame?
        if (!m_pkt_lbuff[m_pkt_rdidx]) read_finalize();
    } else if (SATCAT5_PKTBUF_AUTORDF) {
        // Non-packet mode -> Last byte in buffer?
        if (m_shared_rdavail == m_buff_rdcount) read_finalize();
    }
}

unsigned PacketBuffer::get_peek_ready() const
{
    unsigned max_read = get_read_ready();
    unsigned max_wrap = m_buff_size - m_buff_rdidx;
    return min_unsigned(max_read, max_wrap);
}

const u8* PacketBuffer::peek(unsigned nbytes) const
{
    if (nbytes <= get_peek_ready()) {
        return m_buff + m_buff_rdidx;
    } else {
        return NULL;
    }
}

bool PacketBuffer::read_consume(unsigned nbytes)
{
    if (can_read_internal(nbytes)) {
        consume_internal(nbytes);
        return true;
    } else {
        read_underflow();
        return false;
    }
}

void PacketBuffer::read_finalize()
{
    AtomicLock lock(LBL_PKT);

    // Move to next packet, if applicable.
    if (m_pkt_maxct && m_shared_pktcount) {
        // Is there anything left in the current packet?
        unsigned nrem = m_pkt_lbuff[m_pkt_rdidx];
        if (nrem) consume_internal(nrem);
        // Move to the next packet.
        m_pkt_rdidx = modulo_add_uns(m_pkt_rdidx + 1, m_pkt_maxct);
        --m_shared_pktcount;
    }

    // Update current read state.
    m_shared_rdavail -= m_buff_rdcount;
    m_buff_rdcount = 0;

    // Special case if that was the very last byte:
    // Reset reduces the cost of handling buffer-wraparound in peek().
    if (m_shared_rdavail == 0 && m_next_wrlen == 0) {
        clear();
    }
}
