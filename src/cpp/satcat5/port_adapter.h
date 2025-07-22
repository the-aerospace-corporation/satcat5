//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Adapter definitions for using generic I/O objects with eth::SwitchCore.
//!
//!\details
//! The software-defined Ethernet switch (i.e., `eth::SwitchCore`) defines
//! a specific port interface (i.e., `eth::SwitchPort`).  This file defines
//! adapters that apply egress conversions required for VLAN support and
//! convert that data to/from various streaming formats.
//!
//! This includes:
//!  * `port::MailAdapter`
//!    Use this adapter with packetized Ethernet streams that have already
//!    had the FCS field verified and removed, such as "port::MailMap".
//!    This adapter accepts data from a Readable interface and copies it
//!    to the switch, and it copies data from the switch to a Writeable
//!    interface after applying required modifications to the VLAN tag.
//!  * `port::SlipAdapter`
//!    Use this adapter with byte-streams containing SLIP-encoded Ethernet
//!    frames with an FCS, such as "cfg:Spi" or "cfg::Uart".  The adapter
//!    decodes SLIP data from a Readable interface, verifies the FCS, and
//!    copies to the switch. Egress data updates VLAN tags before appending
//!    an FCS, applying SLIP encoding, and relaying to a Writeable interface.
//!  * `port::NullAdapter`
//!    Use this adapter with SatCat5 network interfaces such as "ip::Stack"
//!    or "eth::Dispatch". It presents the virtual switch port as a direct
//!    Readable and Writeable interface with no inline modifications.
//!  * `port::SwitchAdapter`
//!    Use this adapter as a crossover port to connect two networking devices
//!    together. e.g., switch <-> switch or switch <-> router.

#pragma once

#include <satcat5/codec_slip.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_vlan.h>
#include <satcat5/io_core.h>

namespace satcat5 {
    namespace port {
        //! Parent class for handling switch egress and VLAN functions.
        //! This partial implementation of eth::SwitchPort accepts egress
        //! data, reformats VLAN tags, and writes to a designated device.
        //! This class cannot be used on its own.
        //! \see port_adapter.h, port::MailAdapter, port::SlipAdapter.
        class VlanAdapter : public satcat5::eth::SwitchPort {
        public:
            //! Constructor sets source and destination.
            VlanAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Writeable* vdst);

        protected:
            //! VLAN plugin for this port.
            satcat5::eth::SwitchVlanEgress m_vport;
        };

        //! Port adapter for MailBox, MailMap, etc.
        //! Implementation of SwitchPort for packetized byte streams that have
        //! already had their FCS checked and removed, such as `port::MailMap`.
        //! \see port_adapter.h, port::MailBox, port::MailMap.
        class MailAdapter final : public satcat5::port::VlanAdapter {
        public:
            //! Attach port to the Ethernet switch and its data source/sink.
            MailAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);

        protected:
            satcat5::io::BufferedCopy m_rx_copy;    // Push/pull adapter
        };

        //! Port adapter for SLIP-encoded serial ports.
        //! Implementation of SwitchPort for SLIP-encoded byte streams, such as
        //! `cfg::Spi` or `cfg::Uart`.  Includes SLIP codec and FCS calculation.
        //! \see port_adapter.h, cfg::Spi, cfg::Uart.
        class SlipAdapter final : public satcat5::port::VlanAdapter {
        public:
            //! Attach port to the Ethernet switch and its data source/sink.
            SlipAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);

            //! Count frame errors since previous query.
            inline unsigned error_count()
                { return m_rx_fcs.error_count(); }

            //! Count valid frames since previous query.
            inline unsigned frame_count()
                { return m_rx_fcs.frame_count(); }

            //! Access the event-listener used for read/pull mode.
            inline satcat5::io::EventListener* listen()
                { return &m_rx_copy; }

        protected:
            satcat5::io::BufferedCopy m_rx_copy;    // Push/pull adapter
            satcat5::io::SlipDecoder m_rx_slip;     // SLIP decoder
            satcat5::eth::ChecksumRx m_rx_fcs;      // Checksum verification
            satcat5::eth::ChecksumTx m_tx_fcs;      // Checksum calculation
            satcat5::io::SlipEncoder m_tx_slip;     // SLIP encoder
        };

        //! Minimalist port adapter with no VLAN conversion.
        //! Implementation of eth::SwitchPort without VLAN tag formatting or
        //! other interface conversions. Suitable for use with "ip::Stack".
        class NullAdapter
            : public satcat5::eth::SwitchPort
            , public satcat5::io::ReadableRedirect
        {
        public:
            explicit NullAdapter(satcat5::eth::SwitchCore* sw);
        };

        //! Back-to-back connection of one SwitchCore to another SwitchCore.
        //! Suitable for crosslinking a switch to a router, since both are
        //! compatible with the eth::SwitchCore parent class.
        class SwitchAdapter {
        public:
            SwitchAdapter(
                satcat5::eth::SwitchCore* swa,
                satcat5::eth::SwitchCore* swb);

        protected:
            satcat5::port::VlanAdapter m_a2b, m_b2a;
        };
    }
}
