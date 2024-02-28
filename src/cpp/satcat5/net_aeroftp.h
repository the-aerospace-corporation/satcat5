//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// AeroCube File Transfer Protocol (AeroFTP) transmitter
//
// This file implements the transmit portion of a lightweight file-transfer
// protocol that can operate over unidirectional links. Transport is over
// raw-Ethernet or UDP.
//
// For a matching receiver, see "hal_posix/file_aeroftp.h".
//
// Since data transmission is unidirectional, reliable file transfer requires
// an asynchronous side-channel that can request retransmission of missing
// blocks. This may be real-time, or it may occur hours or days later. If no
// such side-channel exists, sending the file multiple times may provide
// an acceptable chance of receiving the complete file.
//
// Incoming and outgoing files are divided into non-overlapping "blocks".
// Blocks are numbered from zero, starting on 1,024-byte boundaries.
// (i.e., All except the final block are exactly 1,024 bytes long.)
// Files whose length is not a multiple of four bytes will be zero-padded.
// In theory the protocol supports files up to 16 GiB; this implementation
// has not been tested beyond 2 GiB.
//
// By default, the client sends one block every millisecond (~8.1 Mbps).
// To reduce this rate, call throttle(N) to wait N msec before sending
// each subsequent packet, yielding 8192000/N bps.
//
// Note: Unidirectional UDP requires some care because of ARP prerequisites.
// In some cases, proxy-ARP or manual routing tables may be required.
//

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/net_address.h>
#include <satcat5/net_protocol.h>
#include <satcat5/polling.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace net {
        // Transmit file(s) using AeroFtp.
        class AeroFtpClient : satcat5::poll::Timer {
        public:
            // Is there already a transfer in progress?
            inline bool busy() const {return m_file_pos < m_file_len;}
            inline bool done() const {return m_file_pos >= m_file_len;}

            // Begin transmission of the designated file.
            // The "src" stream contains the file data.
            // The optional "aux" stream indicates whether to transmit each
            // 1,024-byte block (0 = no, 1+ = yes). If no aux source is
            // provided, then the client transmits the entire file.
            bool send(u32 file_id,
                satcat5::io::Readable* src,
                satcat5::io::Readable* aux = 0);

            // Close connection and abort transfer in progress.
            void close();

            // Set throttle (one packet every N msec).
            void throttle(unsigned msec_per_pkt);

        protected:
            // Constructor is only available to child classes, such as
            // satcat5::eth::AeroFtpClient and satcat5::udp::AeroFtpClient.
            explicit AeroFtpClient(satcat5::net::Address* dst);

            void end_of_file();             // End-of-file cleanup
            void skip_ahead();              // Skip to next requested block
            void timer_event() override;    // Callback for timer events

            // Internal state.
            satcat5::net::Address* const m_dst;
            satcat5::io::Readable* m_src;
            satcat5::io::Readable* m_aux;
            u32 m_file_id;                  // ID for this file
            u32 m_file_len;                 // Length (bytes)
            u32 m_file_pos;                 // Current read index (bytes)
            u32 m_bytes_sent;               // Count transmission length
            unsigned m_throttle;            // Delay per packet (msec)
        };
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        constexpr satcat5::eth::MacType ETYPE_AEROFTP = {0x4346};

        class AeroFtpClient final
            : public satcat5::eth::AddressContainer
            , public satcat5::net::AeroFtpClient
        {
        public:
            // Constructor links to the Ethernet interface.
            explicit AeroFtpClient(satcat5::eth::Dispatch* eth);

            // Set the destination address before calling send().
            inline void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type = satcat5::eth::ETYPE_AEROFTP)
                { m_addr.connect(addr, type); }
            inline bool ready() const
                { return m_addr.ready(); }
        };
    }

    namespace udp {
        constexpr satcat5::udp::Port PORT_AEROFTP = {0x4346};

        class AeroFtpClient final
            : public satcat5::udp::AddressContainer
            , public satcat5::net::AeroFtpClient
        {
        public:
            // Constructor links to the UDP stack.
            explicit AeroFtpClient(satcat5::udp::Dispatch* udp);

            // Set the destination address before calling send().
            inline void connect(
                const satcat5::udp::Addr& addr,
                const satcat5::udp::Port& port = satcat5::udp::PORT_AEROFTP)
                { m_addr.connect(addr, port, 0); }
            inline bool ready() const
                { return m_addr.ready(); }
        };
    }
}
