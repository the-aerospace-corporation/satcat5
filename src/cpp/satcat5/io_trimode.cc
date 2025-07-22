//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/io_trimode.h>

using satcat5::eth::SwitchCore;
using satcat5::io::EventListener;
using satcat5::io::null_write;
using satcat5::io::Readable;
using satcat5::io::TriMode;
using satcat5::io::Writeable;

// Note: For complete datapath details, see comments in configure(...).
TriMode::TriMode(SwitchCore* sw, Readable* src, Writeable* dst, u16 apid_raw)
    : ReadableRedirect(&m_rx_buff)                  // Rx: Always read buffer
    , WriteableRedirect(&null_write)                // Tx: Disabled for now
    , m_src(src)                                    // Original source pointer
    , m_rx_buff(src)                                // Rx buffer (push/pull)
    , m_tx_buff(nullptr)                            // Tx buffer (push only)
    , m_rx_bpdu()                                   // AOS buffer (stream mode)
    , m_rx_mpdu(nullptr)                            // AOS buffer (packet mode)
    , m_aos_core(src, dst, true)                    // Connect AOS to UART
    , m_aos_bpdu(&m_aos_core, &m_tx_buff, &m_rx_bpdu, 0, 1, false)
    , m_aos_mpdu(&m_aos_core, &m_tx_buff, &m_rx_mpdu, 0, 0, true)
    , m_copy_rx(nullptr, m_rx_buff.bypass())        // Raw copy (Rx path)
    , m_copy_tx(nullptr, dst)                       // Raw copy (Tx path)
    , m_eth_slip(sw, src, dst)                      // SLIP-mode connection
    , m_spp_rx(&m_rx_mpdu, m_rx_buff.bypass())      // SPP dispatch (Rx path)
    // SPP header insert (Rx)
    , m_spp_rxi(src, &m_spp_rx, apid_raw, SATCAT5_TRIMODE_SPPMAXSIZE)
    , m_spp_rxr(&m_spp_rx, m_rx_buff.bypass(), apid_raw) // SPP header remove
    , m_spp_tx(&m_tx_buff, dst)                          // SPP dispatch (Tx path)
    // SPP header insert (Tx)
    , m_spp_txi(&m_tx_buff, &m_spp_tx, apid_raw, SATCAT5_TRIMODE_SPPMAXSIZE)
    , m_spp_txr(&m_spp_tx, dst, apid_raw)           // SPP header remove (Tx)
{
    // Initial state is disabled.
    configure(Port::OFF, Stream::OFF, Stream::OFF);
}

// The constructor creates all encoder and decoder paths simultaneously.
// In practice, they are dormant until triggered by `data_rcvd` callback
// events.  This method activates exactly one Tx path and one Rx path
// by reconfiguring those callbacks.
void TriMode::configure(Port port, Stream tx, Stream rx) {
    // Flush all working buffers.
    m_rx_buff.reset();
    m_tx_buff.reset();
    m_rx_bpdu.clear();
    m_rx_mpdu.reset();
    m_aos_bpdu.desync();
    m_aos_mpdu.desync();
    m_eth_slip.port_flush();

    // Flush frame and error counters.
    m_aos_core.error_count();
    m_aos_core.frame_count();
    m_eth_slip.error_count();
    m_eth_slip.frame_count();

    // Enable or disable the Ethernet port.
    // (Logic below will connect the callback if requested.)
    m_eth_slip.port_enable(port == Port::SLIP);

    // Select the transmit path. Stream data is written to the TriMode object,
    // which redirects to the transmit buffer (m_tx_buff) in raw or SPP mode.
    // Select which object reads from this buffer and relays to final output.
    Writeable* dst = &null_write;
    EventListener* txc = nullptr;
    if (tx == Stream::RAW && port == Port::RAW) {
        // Transmit buffer in bypass mode, then direct copy to output.
        // * User writes to m_tx_buff (bypass)
        // * Buffer notifies m_copy_tx, which copies raw data to the output.
        dst = m_tx_buff.bypass();
        txc = &m_copy_tx;
    } else if (tx == Stream::RAW && port == Port::AOS) {
        // Transmit buffer in bypass mode, then use AOS/BPDU channel.
        // * User writes to m_tx_buff (bypass)
        // * Buffer notifies m_aos_bpdu, which generates AOS/B_PDU headers.
        // * The m_aos_core writes fixed-size transfer frames to the output.
        dst = m_tx_buff.bypass();
        txc = &m_aos_bpdu;
    } else if (tx == Stream::RAW && port == Port::SPP) {
        // Transmit buffer in bypass mode, then SPP header insertion.
        // * User writes to m_tx_buff (bypass)
        // * Buffer notifies m_spp_txi, which streams to a specific APID.
        // * Use m_spp_tx to write SPP headers + data to the output.
        dst = m_tx_buff.bypass();
        txc = m_spp_txi.strm();
    } else if (tx == Stream::SPP && port == Port::RAW) {
        // SPP packetization, then SPP dispatch for header removal.
        // * User writes to m_tx_buff (SPP mode)
        // * Buffer notifies m_spp_tx, which reads SPP headers.
        // * On APID match (apid_raw), forward packets to m_spp_txr.
        //   (TODO: Should we match *all* APIDs in this mode?)
        // * Ignoring SPP headers, write contained data to the output.
        dst = m_tx_buff.packet();
        txc = &m_spp_tx;
    } else if (tx == Stream::SPP && port == Port::AOS) {
        // SPP packetization, then use AOS/MPDU channel.
        // * User writes to m_tx_buff (SPP mode)
        // * Buffer notifies m_aos_mpdu, which generates AOS/M_PDU headers.
        // * The m_aos_core writes fixed-size transfer frames to the output.
        dst = m_tx_buff.packet();
        txc = &m_aos_mpdu;
    } else if (tx == Stream::SPP && port == Port::SPP) {
        // SPP packetization, then direct copy.
        // * User writes to m_tx_buff (SPP mode)
        // * Buffer notifies m_copy_tx, which copies valid packets to output.
        dst = m_tx_buff.packet();
        txc = &m_copy_tx;
    }
    write_dst(dst);
    m_tx_buff.set_callback(txc);

    // Select the receive path by configuring callbacks.
    // Notifications from the source are forwarded to various objects, which
    // eventually write bytes or packets to the receive buffer (m_buff_rx).
    // The user stream is always read directly from m_buff_rx.
    EventListener *rxc = nullptr, *rxb = nullptr, *rxm = nullptr;
    if (port == Port::RAW && rx == Stream::RAW) {
        // Direct copy from source to receive buffer.
        // * Source notifies m_copy_rx, which copies to m_buff_rx.
        rxc = &m_copy_rx;
    } else if (port == Port::RAW && rx == Stream::SPP) {
        // Streaming copy with SPP header insertion.
        // * Source notifies m_spp_rxi, which streams to a specific APID.
        // * Use m_spp_rx to insert SPP headers and copy data to m_buff_rx.
        rxc = m_spp_rxi.strm();
    } else if (port == Port::AOS && rx == Stream::RAW) {
        // AOS decoder separates Raw (B_PDU) vs SPP (M_PDU) data.
        // * Source notifies m_aos_core, which parses AOS transfer frames.
        // * Virtual channel 1 (byte stream) is forwarded to m_aos_bpdu.
        //   * Parsed B_PDU contents are written to an internal buffer.
        //   * Internal buffer notifies m_copy_rx, which copies to m_buff_rx.
        // * Virtual channel 0 (SPP packets) are forwarded to m_aos_mpdu.
        //   * Parsed SPP contents are written to an internal buffer.
        //   * Internal buffer notifies m_spp_rx, which strips SPP headers.
        //   * Matching APID forwards to m_spp_rxr, which writes to m_buff_rx.
        rxc = &m_aos_core;
        rxb = &m_copy_rx;
        rxm = &m_spp_rx;
    } else if (port == Port::AOS && rx == Stream::SPP) {
        // AOS decoder separates Raw (B_PDU) vs SPP (M_PDU) data.
        // * Source notifies m_aos_core, which parses AOS transfer frames.
        // * Virtual channel 1 (byte stream) is forwarded to m_aos_bpdu.
        //   * Parsed B_PDU contents are written to an internal buffer.
        //   * Internal buffer notifies m_spp_rxi, which streams to m_spp_rx.
        //   * Use m_spp_rx to insert SPP headers and copy data to m_buff_rx.
        // * Virtual channel 0 (SPP packets) are forwarded to m_aos_mpdu.
        //   * Parsed SPP contents are written to an internal buffer.
        //   * Internal buffer notifies m_copy_rx, which copies to m_buff_rx.
        rxc = &m_aos_core;
        rxb = m_spp_rxi.strm();
        rxm = &m_copy_rx;
    } else if (port == Port::SPP && rx == Stream::RAW) {
        // Packetize SPP data, then remove headers (m_spp_rxr).
        // * Source notifies m_rx_mpdu (bypass mode / buffer only)
        // * Working buffer notifies m_spp_rx, which strips SPP headers.
        // * Matching APID forwards to m_spp_rxr, which writes to m_buff_rx.
        rxc = m_rx_mpdu.listen();
        rxm = &m_spp_rx;
    } else if (port == Port::SPP && rx == Stream::SPP) {
        // Validated copy from source to receive buffer.
        // * Source notifies m_rx_buff directly in SPP parsing / pull mode.
        rxc = m_rx_buff.listen();
    } else if (port == Port::SLIP) {
        // Incoming data directed to the Ethernet/SLIP port.
        // * Source notifies m_eth_slip for Ethernet packet processing.
        rxc = m_eth_slip.listen();
    }
    m_src->set_callback(rxc);
    m_rx_bpdu.set_callback(rxb);
    m_rx_mpdu.set_callback(rxm);
}

unsigned TriMode::error_count() {
    return m_aos_core.error_count()
         + m_eth_slip.error_count();
}

unsigned TriMode::frame_count() {
    return m_aos_core.frame_count()
         + m_eth_slip.frame_count();
}
