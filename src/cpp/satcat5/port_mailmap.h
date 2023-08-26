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
// Internal "MailMap" Ethernet port
//
// This class interfaces with "port_axi_mailmap" through ConfigBus.
// It can be used to send and receive Ethernet frames.
//
// Unlike the byte-at-a-time MailBox interface, the MailMap makes the
// entire transmit/receive buffer available for direct access, as if they
// were a regular array.  For now, this remains accessible through the
// Writeable and Readable interfaces.
//

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/io_buffer.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ethernet.h>
#include <satcat5/ip_core.h>
#include <satcat5/udp_core.h>

// Size of the memory-map defined in port_mailmap.vhd
#define SATCAT5_MAILMAP_BYTES   1600
#define SATCAT5_MAILMAP_PAD     106
#define SATCAT5_TIMESTAMP_WORDS 4
#define SATCAT5_CLK_CTRL_WORDS  6

namespace satcat5 {
    namespace port {
        class Mailmap
            : public    satcat5::io::Readable
            , public    satcat5::io::Writeable
            , protected satcat5::cfg::Interrupt
        {
        public:
            // Constructor
            Mailmap(satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr);

            // Used for marking whether a message is a PTP message transported on Layer2, a PTP message on Layer3 (UDP), or not a PTP message.
            enum class PtpType {nonPTP, PTPL2, PTPL3};

            // Writeable / Readable API
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
            void write_abort() override;
            bool write_finalize() override;
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            void read_finalize() override;

            // PTP
            satcat5::ptp::Time ptp_tx_start();
            satcat5::ptp::Time ptp_tx_timestamp();
            PtpType ptp_rx_peek();
            satcat5::ptp::Time ptp_rx_timestamp();
            satcat5::ptp::Time get_timestamp(u32* addr);

        protected:
            // Internal event-handlers.
            void write_next(u8 data) override;
            void write_overflow() override;
            void read_underflow() override;
            u8 read_next() override;
            void irq_event() override;

            // Hardware register map:
            struct ctrl_reg {
                u8 rx_buff[SATCAT5_MAILMAP_BYTES];          // Reg 0-399
                u32 rx_rsvd[SATCAT5_MAILMAP_PAD];           // Reg 400-505
                u32 rx_ptp_time[SATCAT5_TIMESTAMP_WORDS];   // Reg 506-509
                volatile u32 rx_irq;                        // Reg 510
                volatile u32 rx_ctrl;                       // Reg 511
                u8 tx_buff[SATCAT5_MAILMAP_BYTES];          // Reg 512-911
                u32 tx_rsvd[SATCAT5_MAILMAP_PAD-6];         // Reg 912-1011
                u32 rt_clk_ctrl[SATCAT5_CLK_CTRL_WORDS];    // Reg 1012-1017
                u32 tx_ptp_time[SATCAT5_TIMESTAMP_WORDS];   // Reg 1018-1021
                u32 ptp_status;                             // Reg 1022
                volatile u32 tx_ctrl;                       // Reg 1023
            };
            ctrl_reg* const m_ctrl;

            // Internal state.
            unsigned m_wridx;   // Current write-index in transmit buffer
            unsigned m_wrovr;   // Transmit buffer overflow?
            unsigned m_rdidx;   // Current read-index in receive buffer
            unsigned m_rdlen;   // Length of frame in receive buffer
            unsigned m_rdovr;   // Receive buffer underflow?
        };

        inline satcat5::ptp::Time Mailmap::get_timestamp(u32* addr)
        {
            u32 secMSB = addr[0];
            u32 secLSB = addr[1];
            u32 nanoSec = addr[2];
            u16 subNanoSec = addr[3];
            u64 sec = ((u64)secMSB) << 32 | secLSB;

            return satcat5::ptp::Time(sec, nanoSec, subNanoSec);
        }
    }
}
