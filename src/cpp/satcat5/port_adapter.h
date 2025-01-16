//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Adapter definitions for using generic I/O objects with eth::SwitchCore.
//
// The software-defined Ethernet switch (i.e., eth::SwitchCore) defines
// a specific port interface.  This file defines adapters that convert
// from generic I/O in various formats to match this API.
//
// This includes:
//  * port::MailAdapter
//    Use this adapter with packetized Ethernet streams that have already
//    had the FCS field verified and removed, such as "port::MailMap".
//    This adapter accepts data from a Readable interface and copies it
//    to the switch, and it copies data from the switch to a Writeable
//    interface after applying required modifications to the VLAN tag.
//  * port::SlipAdapter
//    Use this adapter with byte-streams containing SLIP-encoded Ethernet
//    frames with an FCS, such as "cfg:Spi" or "cfg::Uart".  The adapter
//    decodes SLIP data from a Readable interface, verifies the FCS, and
//    copies to the switch. Egress data updates VLAN tags before appending
//    an FCS, applying SLIP encoding, and relaying to a Writeable interface.
//  * port::NullAdapter
//    Use this adapter with SatCat5 network interfaces such as "ip::Stack"
//    or "eth::Dispatch". It presents the virtual switch port as a direct
//    Readable and Writeable interface with no inline modifications.
//

#pragma once

#include <satcat5/codec_slip.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/eth_switch.h>
#include <satcat5/io_core.h>

namespace satcat5 {
    namespace port {
        // Partial implementation of eth::SwitchPort that accepts egress
        // data, reformats VLAN tags, and writes to a designated device.
        class VlanAdapter
            : public satcat5::eth::SwitchPort
            , public satcat5::io::EventListener
        {
        public:
            VlanAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Writeable* vdst);

        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            satcat5::io::Writeable* m_vdst;         // Intermediate output
            bool m_vhdr;                            // Read VLAN header?
        };

        // Implementation of SwitchPort for packetized byte streams that have
        // already had their FCS checked and removed, such as "port::MailMap".
        class MailAdapter final : public satcat5::port::VlanAdapter {
        public:
            MailAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);

        protected:
            satcat5::io::BufferedCopy m_rx_copy;    // Push/pull adapter
        };

        // Implementation of SwitchPort for SLIP-encoded byte streams, such as
        // "cfg::Spi" or "cfg::Uart".  Includes SLIP codec and FCS calculation.
        class SlipAdapter final : public satcat5::port::VlanAdapter {
        public:
            SlipAdapter(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);

        protected:
            satcat5::io::BufferedCopy m_rx_copy;    // Push/pull adapter
            satcat5::io::SlipDecoder m_rx_slip;     // SLIP decoder
            satcat5::eth::ChecksumRx m_rx_fcs;      // Checksum verification
            satcat5::eth::ChecksumTx m_tx_fcs;      // Checksum calculation
            satcat5::io::SlipEncoder m_tx_slip;     // SLIP encoder
        };

        // Implementation of eth::SwitchPort without VLAN tag formatting or
        // other interface conversions. Suitable for use with "ip::Stack".
        class NullAdapter
            : public satcat5::eth::SwitchPort
            , public satcat5::io::ReadableRedirect
        {
        public:
            explicit NullAdapter(satcat5::eth::SwitchCore* sw);
        };
    }
}
