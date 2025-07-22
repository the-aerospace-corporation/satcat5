//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_buffer.h>
#include <satcat5/net_address.h>
#include <satcat5/utils.h>

using satcat5::io::BufferedCopy;
using satcat5::io::BufferedIO;
using satcat5::io::BufferedStream;
using satcat5::util::min_unsigned;

BufferedIO::BufferedIO(
        u8* txbuff, unsigned txbytes, unsigned txpkt,
        u8* rxbuff, unsigned rxbytes, unsigned rxpkt)
    : satcat5::io::ReadableRedirect(&m_rx)
    , satcat5::io::WriteableRedirect(&m_tx)
    , m_tx(txbuff, txbytes, txpkt)
    , m_rx(rxbuff, rxbytes, rxpkt)
{
    m_tx.set_callback(this);    // Tx notifies local callback
    m_rx.set_callback(0);       // Rx notifies user callback
}

BufferedCopy::BufferedCopy(
        satcat5::io::Readable* src,
        satcat5::io::Writeable* dst,
        satcat5::io::CopyMode mode)
    : m_src(src)
    , m_dst(dst)
    , m_mode(mode)
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
BufferedCopy::~BufferedCopy() {
    if (m_src) m_src->set_callback(0);
}
#endif

void BufferedCopy::data_rcvd(satcat5::io::Readable* src) {
    src->copy_and_finalize(m_dst, m_mode);
}

void BufferedCopy::data_unlink(satcat5::io::Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

BufferedStream::BufferedStream(
        satcat5::io::Readable* src,
        satcat5::net::Address* dst,
        unsigned max_chunk,
        unsigned min_txnow)
    : m_src(src)
    , m_dst(dst)
    , m_max_chunk(max_chunk)
    , m_min_txnow(min_unsigned(max_chunk, min_txnow))
    , m_timeout_msec(10)
    , m_tref{nullptr, 0}
{
    if (m_src) m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
BufferedStream::~BufferedStream() {
    if (m_src) m_src->set_callback(0);
}
#endif

void BufferedStream::data_rcvd(satcat5::io::Readable* src) {
    // Are we ready to read a chunk of data?
    unsigned nread = src->get_read_ready(), ncopy = 0;
    if (nread >= m_min_txnow) {
        // Enough data to justify immediate transmission.
        ncopy = min_unsigned(nread, m_max_chunk);
    } else if (m_tref.clk) {
        // Wait for partial-chunk timeout.
        if (m_tref.checkpoint_elapsed()) ncopy = nread;
    } else if (m_timeout_msec) {
        // Start new partial-chunk timeout.
        m_tref = SATCAT5_CLOCK->checkpoint_msec(m_timeout_msec);
    }

    // Attempt to send a packet?
    satcat5::io::Writeable* wr = nullptr;
    if (ncopy) wr = m_dst->open_write(ncopy);
    if (wr) {
        // Copy the next chunk of data.
        satcat5::io::LimitedRead chunk(src, ncopy);
        chunk.copy_and_finalize(wr);
        // Reset state for next time around.
        m_tref = {nullptr, 0};
        if (ncopy == nread) src->read_finalize();
    }
}

void BufferedStream::data_unlink(satcat5::io::Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

satcat5::io::BufferedWriter::BufferedWriter(
        satcat5::io::Writeable* dst,
        u8* txbuff, unsigned txbytes, unsigned txpkt)
    : io::WriteableRedirect(&m_buff)    // Upstream writes to buffer
    , m_buff(txbuff, txbytes, txpkt)    // Initialize working buffer
    , m_copy(&m_buff, dst)              // Auto-copy buffer contents
{
    // Nothing else to initialize.
}
