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

#include <satcat5/io_buffer.h>
#include <satcat5/utils.h>

using satcat5::util::min_unsigned;

// Set batch size for BufferedCopy
#ifndef SATCAT5_BUFFCOPY_BATCH
#define SATCAT5_BUFFCOPY_BATCH  32
#endif

satcat5::io::BufferedIO::BufferedIO(
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

satcat5::io::BufferedCopy::BufferedCopy(
        satcat5::io::Readable* src,
        satcat5::io::Writeable* dst)
    : m_src(src)
    , m_dst(dst)
{
    m_src->set_callback(this);
}

#if SATCAT5_ALLOW_DELETION
satcat5::io::BufferedCopy::~BufferedCopy()
{
    m_src->set_callback(0);
}
#endif

void satcat5::io::BufferedCopy::data_rcvd()
{
    // Temporary buffer sets our maximum batch size.
    u8 buff[SATCAT5_BUFFCOPY_BATCH];
    while (1) {
        // How much data could we copy from source to sink?
        unsigned max_rd = m_src->get_read_ready();
        unsigned max_wr = m_dst->get_write_space();
        unsigned max_rw = min_unsigned(max_rd, max_wr);
        if (max_rw) {
            // Copy up to that limit or batch size, whichever is smaller.
            unsigned batch = min_unsigned(max_rw, SATCAT5_BUFFCOPY_BATCH);
            m_src->read_bytes(batch, buff);
            m_dst->write_bytes(batch, buff);
            // Did we just finish a frame?
            if (batch == max_rd) {
                m_src->read_finalize();
                m_dst->write_finalize();
            }
        } else {
            // Source empty or sink full; stop for now.
            break;
        }
    }
}

satcat5::io::BufferedWriter::BufferedWriter(
        satcat5::io::Writeable* dst,
        u8* txbuff, unsigned txbytes, unsigned txpkt)
    : io::WriteableRedirect(&m_buff)    // Upstream writes to buffer
    , m_buff(txbuff, txbytes, txpkt)    // Initialize working buffer
    , m_copy(&m_buff, dst)              // Auto-copy buffer contents
{
    // Nothing else to initialize.
}
