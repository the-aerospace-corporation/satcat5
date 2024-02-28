//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/net_aeroftp.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

// Define the protocol-specific wrappers first.
satcat5::eth::AeroFtpClient::AeroFtpClient(satcat5::eth::Dispatch* eth)
    : satcat5::eth::AddressContainer(eth)
    , satcat5::net::AeroFtpClient(&m_addr)
{
    // Nothing else to initialize.
}

satcat5::udp::AeroFtpClient::AeroFtpClient(satcat5::udp::Dispatch* udp)
    : satcat5::udp::AddressContainer(udp)
    , satcat5::net::AeroFtpClient(&m_addr)
{
    // Nothing else to initialize.
}

// From this point on, "AeroFtpClient" refers to the generic version.
using satcat5::io::Readable;
using satcat5::log::Log;
using satcat5::net::AeroFtpClient;
using satcat5::util::div_ceil;
using satcat5::util::max_unsigned;
using satcat5::util::min_unsigned;

static constexpr unsigned BLOCK_BYTES = 1024;

static constexpr unsigned bytes2words(unsigned bytes)
    { return div_ceil(bytes, 4u); }
static constexpr unsigned bytes2blocks(unsigned bytes)
    { return div_ceil(bytes, BLOCK_BYTES); }

AeroFtpClient::AeroFtpClient(satcat5::net::Address* dst)
    : m_dst(dst)
    , m_src(0)
    , m_aux(0)
    , m_file_id(0)
    , m_file_len(0)
    , m_file_pos(0)
    , m_bytes_sent(0)
    , m_throttle(1)
{
    // Nothing else to initialize.
}

void AeroFtpClient::close()
{
    m_dst->close();
    end_of_file();
}

void AeroFtpClient::end_of_file()
{
    if (m_src) m_src->read_finalize();
    if (m_aux) m_aux->read_finalize();
    m_src = 0;
    m_aux = 0;
    m_file_id = 0;
    m_file_len = 0;
    m_file_pos = 0;
    timer_stop();
}

bool AeroFtpClient::send(u32 file_id, Readable* src, Readable* aux)
{
    // Sanity check: Must be idle before starting a new file.
    if (busy()) return false;

    // Sanity check: The primary input must be non-empty.
    if (!(src && src->get_read_ready())) return false;

    // Sanity check: If auxiliary source is provided, the lengths must match.
    if (aux) {
        unsigned src_blocks = bytes2blocks(src->get_read_ready());
        unsigned aux_blocks = aux->get_read_ready();
        if (src_blocks != aux_blocks) return false;
    }

    // Reset transmit state.
    m_src = src;
    m_aux = aux;
    m_file_id = file_id;
    m_file_len = src->get_read_ready();
    m_file_pos = 0;
    m_bytes_sent = 0;
    if (m_aux) skip_ahead();

    // If there's any data left, send the first packet.
    if (!done()) timer_event();
    return true;
}

void AeroFtpClient::skip_ahead()
{
    // For each "0" in the aux stream, discard an input block.
    while (m_aux->get_read_ready() && !m_aux->read_u8()) {
        m_src->read_consume(BLOCK_BYTES);
        m_file_pos += BLOCK_BYTES;
    }
}

void AeroFtpClient::throttle(unsigned msec_per_pkt)
{
    // Note: Leave timer state as-is; new setting applies after next packet.
    m_throttle = max_unsigned(1, msec_per_pkt);
}

void AeroFtpClient::timer_event()
{
    // Ignore stray timer events that occur after close().
    if (!m_src) return;

    // Calculate length for the next packet.
    unsigned next_bytes = min_unsigned(BLOCK_BYTES, m_file_len - m_file_pos);
    unsigned next_words = bytes2words(next_bytes);

    // Are we able to send data right now?
    satcat5::io::Writeable* wr = m_dst->open_write(16 + 4*next_words);
    if (wr) {
        // Write the transfer header.
        wr->write_u32(m_file_id);
        wr->write_u32(bytes2words(m_file_len));
        wr->write_u32(bytes2words(m_file_pos));
        wr->write_u32(next_words);

        // Copy the next block of data.
        u8 temp[BLOCK_BYTES];
        m_src->read_bytes(next_bytes, temp);
        wr->write_bytes(next_bytes, temp);

        // Zero-pad to word boundary if needed.
        unsigned pad = 4*next_words - next_bytes;
        while (pad--) {wr->write_u8(0);}
        bool ok = wr->write_finalize();

        // Get ready for the next packet.
        if (!ok) Log(satcat5::log::WARNING, "AeroFTP: Tx drop at offset").write(m_file_pos);
        m_file_pos += BLOCK_BYTES;
        m_bytes_sent += 4*next_words;
        if (m_aux) skip_ahead();
    }

    // Continue transmission?
    if (done()) {
        Log(satcat5::log::INFO, "AeroFTP: Transmission complete, ID")
            .write10(m_file_id).write(", sent").write10(m_bytes_sent);
        end_of_file();
    } else {
        timer_once(m_throttle);
    }
}
