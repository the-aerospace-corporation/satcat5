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

#include <satcat5/log.h>
#include <satcat5/slip.h>

namespace io = satcat5::io;
using satcat5::io::SlipEncoder;
using satcat5::io::SlipDecoder;
using satcat5::io::SlipCodec;

// By default, log all SLIP errors.
#ifndef SATCAT5_SLIP_LOG_ERROR
#define SATCAT5_SLIP_LOG_ERROR  1
#endif

// Constants for various SLIP tokens:
static const u8 SLIP_END        = 0xC0;
static const u8 SLIP_ESC        = 0xDB;
static const u8 SLIP_ESC_END    = 0xDC;
static const u8 SLIP_ESC_ESC    = 0xDD;
static const u16 SLIP_ESC_W_END = 0xDBDC;
static const u16 SLIP_ESC_W_ESC = 0xDBDD;

SlipEncoder::SlipEncoder(io::Writeable* dst)
    : m_dst(dst)
    , m_overflow(false)
{
    // Nothing else to initialize.
}

unsigned SlipEncoder::get_write_space() const
{
    // Worst-case: Every input character needs to be escaped,
    // then allow one additional byte for the SLIP_END token.
    unsigned dst = m_dst->get_write_space();
    if (m_overflow)
        return 0;
    else if (dst < 3)
        return 0;
    else
        return (dst - 1) / 2;
}

bool SlipEncoder::write_finalize()
{
    // Always attempt to write the end-of-frame token.  This helps prevent
    // cascading errors for interfaces where write_abort() is a no-op.
    m_dst->write_u8(SLIP_END);

    // Finalize the frame, or attempt to abort if possible.
    if (m_overflow) {
        m_overflow = false;
        m_dst->write_abort();
        return false;
    } else {
        return m_dst->write_finalize();
    }
}

void SlipEncoder::write_overflow()
{
    m_overflow = true;  // Set persistent error flag
}

void SlipEncoder::write_next(u8 data)
{
    if (data == SLIP_END) {
        m_dst->write_u16(SLIP_ESC_W_END);
    } else if (data == SLIP_ESC) {
        m_dst->write_u16(SLIP_ESC_W_ESC);
    } else {
        m_dst->write_u8(data);
    }
}

// Inline SLIP Decoder
SlipDecoder::SlipDecoder(io::Writeable* dst)
    : m_dst(dst)
    , m_state(State::SLIP_RDY)
{
    // Nothing else to initialize.
}

unsigned SlipDecoder::get_write_space() const
{
    // Worst case is one-to-one, no special tokens in input.
    return m_dst->get_write_space();
}

void SlipDecoder::write_next(u8 data)
{
    if (data == SLIP_END) {
        // Finalize complete frame, or abort on incomplete data.
        // (This includes back-to-back END tokens, which are harmless.)
        if (m_state == State::SLIP_RDY) {
            m_dst->write_finalize();
        } else if (m_state != State::SLIP_EOF) {
            if (SATCAT5_SLIP_LOG_ERROR)
                satcat5::log::Log(satcat5::log::WARNING, "SLIP decode error");
            m_dst->write_abort();
        }
        m_state = State::SLIP_EOF;
    } else if (m_state == State::SLIP_ERR) {
        // After error, discard data until next END.
    } else if (data == SLIP_ESC) {
        m_state = State::SLIP_ESC;  // Escape next byte
    } else if (m_state != State::SLIP_ESC) {
        m_dst->write_u8(data);      // Normal passthrough
        m_state = State::SLIP_RDY;
    } else if (data == SLIP_ESC_END) {
        m_dst->write_u8(SLIP_END);  // Escaped END
        m_state = State::SLIP_RDY;
    } else if (data == SLIP_ESC_ESC) {
        m_dst->write_u8(SLIP_ESC);  // Escaped ESC
        m_state = State::SLIP_RDY;
    } else {
        m_state = State::SLIP_ERR;  // Error
    }
}

SlipCodec::SlipCodec(
        io::Writeable* dst,
        io::Readable* src)
    : SlipEncoder(dst)              // Upstream writes are encoded enroute
    , io::ReadableRedirect(&m_rx)   // Upstream reads pull from buffer
    , m_rx(m_rxbuff, SATCAT5_SLIP_BUFFSIZE, SATCAT5_SLIP_PACKETS)
    , m_decode(&m_rx)               // Decoder writes to buffer
    , m_copy(src, &m_decode)        // Auto-copy from source to decoder
{
    // Nothing else to initialize.
}
