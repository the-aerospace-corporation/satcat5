//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_buffer.h>
#include <satcat5/utils.h>

using satcat5::io::BufferedCopy;
using satcat5::io::BufferedIO;
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
        satcat5::io::Writeable* dst)
    : m_src(src)
    , m_dst(dst)
{
    m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
BufferedCopy::~BufferedCopy()
{
    if (m_src) m_src->set_callback(0);
}
#endif

void BufferedCopy::data_rcvd(satcat5::io::Readable* src)
{
    src->copy_and_finalize(m_dst);
}

void BufferedCopy::data_unlink(satcat5::io::Readable* src) {m_src = 0;} // GCOVR_EXCL_LINE

satcat5::io::BufferedWriter::BufferedWriter(
        satcat5::io::Writeable* dst,
        u8* txbuff, unsigned txbytes, unsigned txpkt)
    : io::WriteableRedirect(&m_buff)    // Upstream writes to buffer
    , m_buff(txbuff, txbytes, txpkt)    // Initialize working buffer
    , m_copy(&m_buff, dst)              // Auto-copy buffer contents
{
    // Nothing else to initialize.
}
