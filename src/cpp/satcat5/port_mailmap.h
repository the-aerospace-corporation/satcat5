//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
#include <satcat5/ptp_interface.h>

// Size of the memory-map defined in port_mailmap.vhd
#define SATCAT5_MAILMAP_BYTES   1600

namespace satcat5 {
    namespace port {
        class Mailmap
            : public satcat5::io::Readable
            , public satcat5::io::Writeable
            , public satcat5::ptp::Interface
            , protected satcat5::cfg::Interrupt
        {
        public:
            // Constructor
            Mailmap(satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr);

            // Writeable / Readable API
            unsigned get_write_space() const override;
            void write_bytes(unsigned nbytes, const void* src) override;
            void write_abort() override;
            bool write_finalize() override;
            unsigned get_read_ready() const override;
            bool read_bytes(unsigned nbytes, void* dst) override;
            void read_finalize() override;

            // Implement the ptp::Interface API.
            satcat5::ptp::Time ptp_tx_start() override;
            satcat5::ptp::Time ptp_tx_timestamp() override;
            satcat5::ptp::Time ptp_rx_timestamp() override;
            satcat5::io::Writeable* ptp_tx_write() override;
            satcat5::io::Readable* ptp_rx_read() override;

        protected:
            // Internal event-handlers.
            void write_next(u8 data) override;
            void write_overflow() override;
            void read_underflow() override;
            u8 read_next() override;
            void irq_event() override;

            // Hardware register map:
            struct ctrl_reg {
                u8 rx_buff[SATCAT5_MAILMAP_BYTES];  // Reg 0-399
                u32 rx_rsvd[106];                   // Reg 400-505
                volatile u32 rx_ptp_time[4];        // Reg 506-509
                volatile u32 rx_irq;                // Reg 510
                volatile u32 rx_ctrl;               // Reg 511
                u8 tx_buff[SATCAT5_MAILMAP_BYTES];  // Reg 512-911
                u32 tx_rsvd[100];                   // Reg 912-1011
                volatile u32 rt_clk_ctrl[6];        // Reg 1012-1017
                volatile u32 tx_ptp_time[4];        // Reg 1018-1021
                volatile u32 ptp_status;            // Reg 1022
                volatile u32 tx_ctrl;               // Reg 1023
            };
            ctrl_reg* const m_ctrl;

            // Internal state.
            unsigned m_wridx;   // Current write-index in transmit buffer
            unsigned m_wrovr;   // Transmit buffer overflow?
            unsigned m_rdidx;   // Current read-index in receive buffer
            unsigned m_rdlen;   // Length of frame in receive buffer
            unsigned m_rdovr;   // Receive buffer underflow?
        };
    }
}
