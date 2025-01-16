//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <ctime>
#include <hal_test/eth_interface.h>
#include <hal_test/sim_utils.h>
#include <satcat5/log.h>

using satcat5::io::ArrayWrite;
using satcat5::io::Readable;
using satcat5::io::ReadableRedirect;
using satcat5::io::Writeable;
using satcat5::log::Log;
using satcat5::log::DEBUG;
using satcat5::ptp::Time;
using satcat5::ptp::TIME_ZERO;
using satcat5::test::EthernetInterface;

// Set debugging verbosity level (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

EthernetInterface::EthernetInterface(Writeable* pcap)
    : satcat5::ptp::Interface()
    , ArrayWrite(m_txbuff, sizeof(m_txbuff))
    , ReadableRedirect(&m_rxbuff_data)
    , m_txpcap(pcap)
    , m_txbuff_data(0)
    , m_txbuff_time(0)
    , m_rxbuff_data()
    , m_rxbuff_time()
    , m_time_rx(TIME_ZERO)
    , m_time_tx0(TIME_ZERO)
    , m_time_tx1(TIME_ZERO)
    , m_tx_count(0)
    , m_rx_count(0)
    , m_support_one_step(true)
    , m_loss_threshold(0)
{
    // Configure callback for incoming packets.
    m_rxbuff_data.set_callback(this);
}

void EthernetInterface::connect(EthernetInterface *dst)
{
    // Forward data to the destination's primary receive buffer.
    // Keep a pointer to the side-channel buffer for timestamps.
    m_txbuff_data = &dst->m_rxbuff_data;
    m_txbuff_time = &dst->m_rxbuff_time;
}

Time EthernetInterface::ptp_tx_start()
{
    // In one step mode, this sets the effective timestamp.
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "EthInterface::ptp_tx_start");
    m_time_tx0 = m_support_one_step ? ptp_time_now() : TIME_ZERO;
    return m_time_tx0;
}

void EthernetInterface::set_callback(satcat5::io::EventListener* callback)
{
    // Normal redirect forwards set_callback(...) directly to the source:
    //  * Source request_poll() -> Destination data_rcvd()
    // This class must override to intercept data_rcvd() callbacks:
    //  * Source request_poll() -> Local data_rcvd()
    //  * Local data_rcvd() -> Destination data_rcvd()
    Readable::set_callback(callback);
}

void EthernetInterface::read_finalize()
{
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "EthInterface::read_finalize");

    // Forward the event to both sources simultaneously.
    m_rxbuff_data.read_finalize();
    m_rxbuff_time.read_finalize();

    // Clear receive timestamp, and read the next one if possible.
    m_time_rx = TIME_ZERO;
    read_begin_packet();
}

bool EthernetInterface::write_finalize()
{
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "EthInterface::write_finalize");

    // Enable randomized packet loss?
    bool drop = false;
    if (m_loss_threshold == UINT32_MAX) {
        // Special case for 100% loss rate.
        drop = true;
    } else if (m_loss_threshold > 0) {
        // Randomly drop packet if die-roll is under threshold.
        drop = (satcat5::test::rand_u32() < m_loss_threshold);
    }

    if (drop) {
        // Drop this packet.  Since we're simulating an event where it's
        // sent, but dropped in transit, the result is still "success".
        if (DEBUG_VERBOSE > 0) Log(DEBUG, "EthInterface: Dropped packet.");
        ArrayWrite::write_abort();
        return true;
    }

    // Intercepted end-of-packet event.
    // Attempt to finalize the data queue first...
    if (ArrayWrite::write_finalize()) {
        // Update packet statistics.
        ++m_tx_count;
        // Use one-step pre-timestamp if it exists, otherwise current time.
        // In either case, clear the pre-timestamp for next time around.
        m_time_tx1 = (m_time_tx0 == TIME_ZERO) ? ptp_time_now() : m_time_tx0;
        m_time_tx0 = TIME_ZERO;
        // Copy data and/or timestamps to each enabled destination.
        // TODO: Is it possible to gracefully handle desync errors?
        bool desync = false;
        if (m_txpcap) {
            m_txpcap->write_bytes(written_len(), m_txbuff);
            if (!m_txpcap->write_finalize()) desync = true;
        }
        if (m_txbuff_data) {
            m_txbuff_data->write_bytes(written_len(), m_txbuff);
            if (!m_txbuff_data->write_finalize()) desync = true;
        }
        if (m_txbuff_time) {
            m_txbuff_time->write_obj(m_time_tx1);
            m_txbuff_time->write_finalize();
        }
        if (desync) Log(satcat5::log::CRITICAL, "EthInterface: Desync");
        return true;
    } else {
        if (DEBUG_VERBOSE > 0) Log(DEBUG, "EthInterface: Write overflow.");
        return false;
    }
}

void EthernetInterface::set_loss_rate(float rate)
{
    // PRNG generates integers in the range [0..2**32)
    // Set threshold to achieve the desired probability.
    if (rate <= 0.0f) {
        m_loss_threshold = 0;
    } else if (rate < 1.0f) {
        m_loss_threshold = (u32)(rate * (float)UINT32_MAX);
    } else {
        m_loss_threshold = UINT32_MAX;
    }
}

void EthernetInterface::data_rcvd(satcat5::io::Readable* src)
{
    if (DEBUG_VERBOSE > 1) Log(DEBUG, "EthInterface::data_rcvd");

    // Update packet statistics if applicable.
    // (In rare cases, "data_rcvd" may be called twice for the same packet.)
    read_begin_packet();

    // Forward the new-data notification to the appropriate callback.
    unsigned peek_len = m_rxbuff_data.get_peek_ready();
    if (ptp_dispatch(m_rxbuff_data.peek(peek_len), peek_len)) {
        // Forward PTP notification in immediate mode.
        if (DEBUG_VERBOSE > 0) Log(DEBUG, "EthInterface: Received PTP.");
        ptp_notify_now();
    } else {
        // Forward notification to the ReadableRedirect callback.
        // See discussion under EthernetInterface::set_callback().
        if (DEBUG_VERBOSE > 0) Log(DEBUG, "EthInterface: Received Non-PTP.");
        ReadableRedirect::read_notify();
    }
}

void EthernetInterface::read_begin_packet()
{
    // Have we already read the timestamp for the current packet?
    // (Don't double-count packets if data_rcvd is called twice.)
    if (m_time_rx != TIME_ZERO) return;

    // Is there a new packet waiting in the primary receive buffer?
    if (m_rxbuff_data.get_read_ready() == 0) return;
    ++m_rx_count;

    // Read Rx timestamp if available, otherwise fallback to "now".
    if (m_rxbuff_time.get_read_ready() > 0) {
        m_rxbuff_time.read_obj(m_time_rx);
    } else {
        m_time_rx = ptp_time_now();
    }
}

// Read the current system time.
Time EthernetInterface::ptp_time_now()
{
    struct timespec tv;
    int errcode = clock_gettime(CLOCK_MONOTONIC, &tv);
    if (errcode) {
        // Fallback to clock() function, usually millisecond resolution.
        const u64 SCALE = 1000000000ull / CLOCKS_PER_SEC;
        return Time(SCALE * clock());
    } else {
        // Higher resolution using clock_gettime(), if available.
        return Time(tv.tv_sec, tv.tv_nsec);
    }
}

// One-liners for most recent Tx/Rx timestamps.
Time EthernetInterface::ptp_tx_timestamp()
    { return m_time_tx1; }
Time EthernetInterface::ptp_rx_timestamp()
    { return m_time_rx; }
Writeable* EthernetInterface::ptp_tx_write()
    { return this; }
Readable* EthernetInterface::ptp_rx_read()
    { return this; }
