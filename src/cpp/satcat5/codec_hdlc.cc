//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/codec_hdlc.h>

using satcat5::io::HdlcDecoder;
using satcat5::io::HdlcEncoder;
using satcat5::io::Writeable;
using satcat5::io::WriteableRedirect;

// Set default encoding parameters.
// Note: Set ACTRL=1 if control characters 0x00 - 0x1F may be mangled.
// (This is required for RFC1662 but increases byte-stuffing overhead.)
#ifndef SATCAT5_HDLC_DEFAULT_ACTRL
#define SATCAT5_HDLC_DEFAULT_ACTRL 0
#endif

#ifndef SATCAT5_HDLC_DEFAULT_CRC32
#define SATCAT5_HDLC_DEFAULT_CRC32 1
#endif

static constexpr u8 HDLC_END        = 0x7E;
static constexpr u8 HDLC_ESC        = 0x7D;
static constexpr u8 HDLC_MASK       = 0x20;
static constexpr u16 HDLC_ABORT     = 256*HDLC_ESC + HDLC_END;

HdlcEncoder::HdlcEncoder(Writeable* dst)
    : WriteableRedirect(0)
    , m_bstuff(dst)
    , m_crc32(&m_bstuff)
    , m_crc16(&m_bstuff, 0xFFFF)
{
    set_mode_crc32(SATCAT5_HDLC_DEFAULT_CRC32);
}

void HdlcEncoder::set_mode_crc32(bool mode32)
{
    // Redirect incoming API calls to the designated CRC calculation.
    // (HDLC framing encodes CRC first, then performs byte-stuffing.)
    Writeable* dst32 = &m_crc32;
    Writeable* dst16 = &m_crc16;
    write_dst(mode32 ? dst32 : dst16);
}

HdlcEncoder::ByteStuff::ByteStuff(satcat5::io::Writeable* dst)
    : m_dst(dst)
    , m_actrl(SATCAT5_HDLC_DEFAULT_ACTRL)
{
    // Nothing else to initialize.
}

unsigned HdlcEncoder::ByteStuff::get_write_space() const
{
    // Worst-case is that every byte is escaped, plus end-of-frame marker.
    unsigned avail = m_dst->get_write_space();
    if (!avail) return 0;
    return (avail-1) / 2;
}

void HdlcEncoder::ByteStuff::write_abort()
{
    // Downstream block may do nothing on write_abort(), so attempt
    // to force an error in the output stream regardless.
    m_dst->write_u16(HDLC_ABORT);
    m_dst->write_abort();
}

bool HdlcEncoder::ByteStuff::write_finalize()
{
    // Finalize the current frame if valid, abort otherwise.
    // Note: A persistent overflow flag is not required here, because the
    //  upstream CRC block will always overflow first, triggering an abort.
    m_dst->write_u8(HDLC_END);
    return m_dst->write_finalize();
}

void HdlcEncoder::ByteStuff::write_next(u8 data)
{
    if (data == HDLC_END || data == HDLC_ESC) {
        // Always escale the END and ESC tokens.
        m_dst->write_u8(HDLC_ESC);
        m_dst->write_u8(data ^ HDLC_MASK);
    } else if (m_actrl && data < HDLC_MASK) {
        // If ACTRL flag is set, escape anything below 0x20.
        m_dst->write_u8(HDLC_ESC);
        m_dst->write_u8(data ^ HDLC_MASK);
    } else {
        // Normal passthrough.
        m_dst->write_u8(data);
    }
}

HdlcDecoder::HdlcDecoder(satcat5::io::Writeable* dst)
    : m_crc32(dst)
    , m_crc16(dst, 0xFFFF)
    , m_state(State::HDLC_EOF)
    , m_actrl(SATCAT5_HDLC_DEFAULT_ACTRL)
    , m_crc(0)
{
    set_mode_crc32(SATCAT5_HDLC_DEFAULT_CRC32);
}

unsigned HdlcDecoder::get_write_space() const
{
    // Worst case is one-to-one, no special tokens in input.
    return m_crc->get_write_space();
}

void HdlcDecoder::set_mode_crc32(bool mode32)
{
    // Write framed output to the selected CRC.
    Writeable* dst32 = &m_crc32;
    Writeable* dst16 = &m_crc16;
    m_crc = mode32 ? dst32 : dst16;
}

void HdlcDecoder::write_next(u8 data)
{
    // Byte-stuffing state machine (RFC1662 Section 4.2)
    if (data == HDLC_END) {
        // Finalize complete frame, or abort on incomplete data.
        // (This includes back-to-back END tokens, which are harmless.)
        if (m_state == State::HDLC_RDY) {
            m_crc->write_finalize();
        } else if (m_state != State::HDLC_EOF) {
            m_crc->write_abort();
        }
        m_state = State::HDLC_EOF;
    } else if (m_state == State::HDLC_ERR) {
        // After overflow, discard data until next END.
    } else if (m_actrl && data < HDLC_MASK) {
        // If ACTRL is set, discard unescaped control characters.
    } else if (data == HDLC_ESC) {
        m_state = State::HDLC_ESC;          // Escape next byte
    } else if (m_state == State::HDLC_ESC) {
        m_crc->write_u8(data ^ HDLC_MASK);  // Escaped byte
        m_state = State::HDLC_RDY;
    } else {
        m_crc->write_u8(data);              // Normal byte
        m_state = State::HDLC_RDY;
    }
}

void HdlcDecoder::write_overflow()
{
    // Discard any further data until next end-of-frame.
    m_state = State::HDLC_ERR;
    // Purging the destination buffer ensures we can continue parsing.
    m_crc->write_abort();
}
