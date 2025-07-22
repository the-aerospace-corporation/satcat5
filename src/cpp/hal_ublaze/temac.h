//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Interface wrappers for the Xilinx "Tri Mode Ethernet MAC" block (TEMAC)

#pragma once

#include <satcat5/interrupts.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tracking.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace ublaze {
        //! Timestamp format used by the AVB core. \see TemacAvb
        struct TemacTime {
            s64 sec;    // Positive or negative
            u32 nsec;   // Always 0 - 999,999,999
        };

        //! Basic Xilinx TEMAC functionality.
        //! This block puts the Tri-Mode Ethernet MAC core in a mode that's
        //! compatible with typical use-cases for SatCat5.  (For example, the
        //! use case for the "vc707_managed" example design.)
        class Temac {
        public:
            //! Initialize the core and link to specified instance.
            explicit Temac(uintptr_t baseaddr);

        protected:
            volatile u32* const m_regs;
        };

        //! Defines callback methods for timestamped egress times.
        //! Child classes should override one or more of these functions.
        class TemacAvbTxCallback {
        public:
            //! Callback for PTP "Sync" messages.
            virtual void tx_sync(const satcat5::ptp::Time& sync_egress) {}
            //! Callback for PTP "Delay request" messages.
            virtual void tx_delay_req(const satcat5::ptp::Time& delay_req_egress) {}
        };

        //! Xilinx TEMAC with Audio-Video-Bridge (AVB) functionality.
        //! This class is a child of ublaze::Temac that provides additional
        //! hooks used for the IEEE1588 Precision Time Protocol (PTP).
        class TemacAvb
            : public satcat5::ublaze::Temac
            , public satcat5::io::ReadableRedirect
            , public satcat5::irq::Handler
            , public satcat5::poll::Always
            , public satcat5::ptp::TrackingClock
        {
        public:
            //! Initialize the core and link to specified instance.
            TemacAvb(uintptr_t baseaddr, int irq_idx);

            //! Register callbacks for transmitted timestamps for PTP packets
            void set_tx_callback(TemacAvbTxCallback* tx_callback);

            //! Read current time from the AVB internal timer.
            satcat5::ublaze::TemacTime avb_get_time();

            //! Update AVB rate register.
            //! Rate is a fixed-point integer with a resolution of 2^-20 nsec.
            //! (i.e., Set counter increment to N / 2^20 nanoseconds per clock.)
            //! TODO: This may be deprecated in favor of clock_rate(...)
            void avb_set_rate(u32 incr);

            //! One-time increment of the AVB internal timer.
            //! TODO: This may be deprecated in favor of clock_adjust(...)
            void avb_jump_by(const satcat5::ublaze::TemacTime& delta);

            //! Send an arbitrary PTP frame with Ethernet header.
            void send_frame(const u8* buf, unsigned buflen);

            //! Clock-adjustment API for ptp::TrackingClock.
            //! Note: Recommend use of ptp::TrackingDither, due to the limited
            //!  resolution of the rate register.
            //!@{
            satcat5::ptp::Time clock_adjust(
                const satcat5::ptp::Time& amount) override;
            void clock_rate(s64 offset) override;
            satcat5::ptp::Time clock_now() override;
            //!@}

            //! Scaling factor for use with `avb_set_rate`.
            static constexpr double CLOCK_SCALE = 0.125 / (1u << 20);

        private:
            void irq_event() override;
            void poll_always() override;
            void check_frames_waiting();

            satcat5::io::PacketBuffer m_txbuff; // TODO: Unused, but corrupts RX when removed. WHY?
            satcat5::io::PacketBuffer m_rxbuff;
            TemacAvbTxCallback* m_tx_callback;
            u32 m_prev_buf_idx;
            u8 m_frames_waiting;
            u8 m_txrawbuff[2048]; // TODO: see above
            u8 m_rxrawbuff[2048];
        };
    }
}
