//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Simulated point-to-point network interface with PTP compatibility

#pragma once

#include <hal_posix/posix_utils.h>
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/ptp_interface.h>
#include <satcat5/ptp_time.h>

namespace satcat5 {
    namespace test {
        //! Simulation of a PTP-compatible Ethernet interface controller.
        //! This class simulates a PTP-compatible endpoint in a back-to-back
        //! Ethernet network of two nodes. \see test::Crosslink
        class EthernetInterface
            : public satcat5::ptp::Interface
            , public satcat5::io::ArrayWrite
            , public satcat5::io::EventListener
            , public satcat5::io::ReadableRedirect
        {
        public:
            //! Create a simulated interface, with optional packet-capture.
            explicit EthernetInterface(satcat5::io::Writeable* pcap);

            //! Crosslink to specified destination object.
            void connect(satcat5::test::EthernetInterface* dst);

            //! Enable or disable support for one-step timestamps.
            inline void support_one_step(bool en)
                { m_support_one_step = en; }

            // Required API for Precision Time Protocol (ptp::Interface)
            satcat5::ptp::Time ptp_time_now() override;
            satcat5::ptp::Time ptp_tx_start() override;
            satcat5::ptp::Time ptp_tx_timestamp() override;
            satcat5::ptp::Time ptp_rx_timestamp() override;
            satcat5::io::Writeable* ptp_tx_write() override;
            satcat5::io::Readable* ptp_rx_read() override;

            // Override specific new-packet and end-of-packet notifications
            // so we can add timestamp metadata as needed.
            void set_callback(satcat5::io::EventListener* callback) override;
            void read_finalize() override;
            bool write_finalize() override;

            //! Set rate for randomized drops of outgoing packets.
            void set_loss_rate(float rate);

            //! Set minimum frame length. Runt frames are zero-padded.
            inline void set_zero_pad(unsigned len) {m_zero_pad = len;}

            //! Count packets sent.
            inline unsigned tx_count() const { return m_tx_count; }
            //! Count packets received.
            inline unsigned rx_count() const { return m_rx_count; }

        protected:
            // Event handler for new-packet notifications.
            void data_rcvd(satcat5::io::Readable* src) override;

            // Update internal state at start of each packet.
            void read_begin_packet();

            // Internal state.
            satcat5::io::Writeable* m_txpcap;
            satcat5::io::Writeable* m_txbuff_data;
            satcat5::io::Writeable* m_txbuff_time;
            satcat5::io::PacketBufferHeap m_rxbuff_data;
            satcat5::io::PacketBufferHeap m_rxbuff_time;
            satcat5::ptp::Time m_time_rx;
            satcat5::ptp::Time m_time_tx0;
            satcat5::ptp::Time m_time_tx1;
            unsigned m_tx_count;
            unsigned m_rx_count;
            unsigned m_zero_pad;
            bool m_support_one_step;
            u32 m_loss_threshold;

            // Working buffer for cloning incoming data.
            // (Large enough for a full-size Ethernet packet.)
            u8 m_txbuff[1600];
        };
    }
}
