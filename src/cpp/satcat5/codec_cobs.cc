//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/codec_cobs.h>
#include <satcat5/log.h>

using satcat5::io::CobsEncoder;
using satcat5::io::CobsDecoder;
using satcat5::io::CobsCodec;
using satcat5::io::CobsCodecInverse;
using satcat5::io::Readable;
using satcat5::io::Writeable;

// By default, log all COBS errors.
#ifndef SATCAT5_COBS_LOG_ERROR
#define SATCAT5_COBS_LOG_ERROR  1
#endif

static constexpr u8 COBS_END    = 0x00;     // Inter-frame token
static constexpr u8 COBS_MAX    = 0xFE;     // Maximum segment = 254 bytes
static constexpr u8 BLK_EMPTY   = 0x00;     // First block / empty packet
static constexpr u8 BLK_DATA    = 0x01;     // Data block, no termination
static constexpr u8 BLK_TERM    = 0x02;     // Data block, zero-terminated

CobsEncoder::CobsEncoder(Writeable* dst)
    : m_dst(dst)
    , m_ctr(0)
    , m_ovr(0)
    , m_buf{}
{
    // Nothing else to initialize.
}

unsigned CobsEncoder::get_write_space() const {
    // Worst-case: One overhead byte per 254 output bytes (including
    // those in the working buffer), plus one for the COBS_END token.
    unsigned dst = m_dst->get_write_space();
    unsigned rem = 3 + unsigned(m_ctr) + dst / 254;
    if (m_ovr || dst <= rem)
        return 0;
    else
        return dst - rem;
}

bool CobsEncoder::write_finalize() {
    if (m_ovr) {
        // Overflow: Terminate then abort, to gracefully handle
        // output interfaces where write_abort() may be a no-op.
        m_ctr = 0;
        m_ovr = 0;
        m_dst->write_u8(COBS_END);
        m_dst->write_abort();
        return false;
    } else {
        // Normal case: Flush the last segment, then terminate.
        flush_segment();
        m_dst->write_u8(COBS_END);
        return m_dst->write_finalize();
    }
}

void CobsEncoder::write_overflow() {
    m_ovr = 1;  // Set persistent error flag
}

void CobsEncoder::write_next(u8 data) {
    // Max segment? Flush and start a new one.
    if (m_ctr == COBS_MAX) {
        flush_segment();
    }
    // Append new data to the current segment.
    if (data == COBS_END) {
        flush_segment();
    } else {
        m_buf[m_ctr++] = data;
    }
}

void CobsEncoder::flush_segment() {
    m_dst->write_u8(m_ctr + 1);
    if (m_ctr) {
        m_dst->write_bytes(m_ctr, m_buf);
        m_ctr = 0;
    }
}

CobsDecoder::CobsDecoder(Writeable* dst)
    : m_dst(dst)
    , m_blk(BLK_EMPTY)
    , m_ctr(0)
    , m_ovr(0)
{
    // Nothing else to initialize.
}

unsigned CobsDecoder::get_write_space() const {
    // Decoded output will always be smaller than encoded input.
    return m_dst->get_write_space();
}

void CobsDecoder::write_next(u8 data) {
    if (data == COBS_END && m_ctr) {
        // Unexpected end-of-frame token, reset parsing.
        if (SATCAT5_COBS_LOG_ERROR)
            satcat5::log::Log(satcat5::log::WARNING, "COBS decode error");
        m_dst->write_abort();
        m_blk = BLK_EMPTY;
        m_ctr = 0;
        m_ovr = 0;
    } else if (data == COBS_END) {
        // Normal end-of-frame token.
        if (m_blk != BLK_EMPTY) m_dst->write_finalize();
        m_blk = BLK_EMPTY;
        m_ctr = 0;
        m_ovr = 0;
    } else if (m_ovr) {
        // Ignore incoming data after an overflow event.
    } else if (m_ctr) {
        // Unmodified data.
        m_dst->write_u8(data);
        --m_ctr;
    } else {
        // Start of new segment.
        if (m_blk == BLK_TERM) m_dst->write_u8(COBS_END);
        m_blk = (data == 0xFF) ? BLK_DATA : BLK_TERM;
        m_ctr = data - 1;
    }
}

void CobsDecoder::write_overflow() {
    // Discard any further data until next end-of-frame.
    m_ctr = COBS_MAX;
    m_ovr = 1;
}

CobsCodec::CobsCodec(Writeable* dst, Readable* src)
    : CobsEncoder(dst)              // Upstream writes are encoded enroute
    , ReadableRedirect(&m_buff)     // Upstream reads pull from buffer
    , m_buff(m_rawbuff, SATCAT5_COBS_BUFFSIZE, SATCAT5_COBS_PACKETS)
    , m_decode(&m_buff)             // Decoder writes to buffer
    , m_copy(src, &m_decode)        // Auto-copy from source to decoder
{
    // Nothing else to initialize.
}

CobsCodecInverse::CobsCodecInverse(Writeable* dst, Readable* src)
    : CobsDecoder(dst)              // Upstream writes are decoded enroute
    , ReadableRedirect(&m_buff)     // Upstream reads pull from buffer
    , m_buff(m_rawbuff, SATCAT5_COBS_BUFFSIZE, 0)
    , m_encode(&m_buff)             // Decoder writes to buffer
    , m_copy(src, &m_encode)        // Auto-copy from source to encoder
{
    // Nothing else to initialize.
}
