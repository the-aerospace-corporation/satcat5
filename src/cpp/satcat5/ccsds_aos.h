//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// CCSDS "Advanced Orbiting Systems" (AOS) Space Data Link Protocol
//
// This file defines SatCat5 networking primitives (i.e., net::Address,
// net::Dispatch, and net::Protocol), and other utility functions for
// the CCSDS AOS Space Data Link Protocol (Blue Book 732.0-B-4).
//  https://public.ccsds.org/Pubs/732x0b4.pdf
//
// For simplicity, SatCat5 lumps the Spacecraft ID and the Virtual
// Channel ID into a single address/protocol binding.  The fixed
// size of the Transfer Frame Data Field is specified on creation.
//
// For now, only the following configuration is supported:
//  * Space Data Link Security (SDLS) is disabled.
//  * Frame Header Error Control Field is disabled.
//  * Transfer Frame Insert Zone is disabled.
//  * Operational Control Field is disabled.
//  * Frame Error Control Field (FECF) is required.
//
// The I/O format can be configured for frame or stream mode.  In "frame"
// mode, the underlying physical medium provides framing information and
// no further encoding is required.  In "stream" mode, the byte-stream is
// further encoded using CCSDS "TM Synchronization and Channel Coding"
// (Blue Book 131.0-B-5) in uncoded mode. This simply inserts (or expects)
// a fixed 32-bit sync-word (0x1ACFFC1D) before each AOS transfer frame.
//

#pragma once

#include <satcat5/crc16_checksum.h>
#include <satcat5/net_core.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace ccsds_aos {
        // Constants and conversion functions for specific fields.
        // (Refer to 732.0-B-4 Section 4.1 for details.)
        constexpr u16 VERSION_MASK  = 0xC000;   // Transfer Frame Version Number
        constexpr u16 SVID_MASK     = 0x3FC0;   // Spacecraft ID
        constexpr u16 VCID_MASK     = 0x003F;   // Virtual Channel ID
        constexpr u8 REPLAY_MASK    = 0x80;     // Replay flag
        constexpr u8 FRCT_EXT_MASK  = 0x40;     // Extended frame-count enable?
        constexpr u8 RSVD_MASK      = 0x30;     // Reserved (zeros)
        constexpr u8 FRCT_VAL_MASK  = 0x0F;     // Extended frame-count value
        constexpr u16 VERSION_2     = (1 << 14);

        // Sync-word for CCSDS "TM Synchronization and Channel Coding".
        constexpr u32 TM_SYNC_WORD  = 0x1ACFFC1D;
        constexpr u8 TM_SYNC_BYTES[] = {0x1A, 0xCF, 0xFC, 0x1D};

        // Special IDs for virtual channels:
        constexpr u16 VCID_DEFAULT  = 0x0000;   // Default channel
        constexpr u16 VCID_IDLE     = 0x003F;   // Only idle data (OID)

        // Helper object for the CCSDS-AOS transfer frame header.
        // TODO: Add support for frame header error control field?
        struct Header {
            u16 id;                 // Spaceraft ID + Virtual Channel ID
            u8  signal;             // Signaling field
            u32 count;              // Virtual Channel Frame Count

            // Constructor sets frame count to zero.
            constexpr Header()
                : id(0), signal(0), count(0) {}
            constexpr Header(u8 svid, u8 vcid)
                : id(VERSION_2 | pack_svid(svid) | pack_vcid(vcid))
                , signal(FRCT_EXT_MASK), count(0) {}

            // Convert raw values to the preferred internal format.
            static constexpr u32 pack_svid(u8 svid)
                { return (u16(svid) << 6) & SVID_MASK; }
            static constexpr u32 pack_vcid(u8 vcid)
                { return u16(vcid) & VCID_MASK; }

            // Convenience accessors.
            u16 version() const     // Transfer frame version number
                { return id & VERSION_MASK; }
            u8 svid() const         // Spacecraft ID
                { return u8((id & SVID_MASK) >> 6); }
            u8 vcid() const         // Virtual Channel ID
                { return u8(id & VCID_MASK); }
            bool replay() const     // Replay flag?
                { return !!(signal & REPLAY_MASK); }

            // I/O functions.
            void write_to(satcat5::io::Writeable* wr) const;
            bool read_from(satcat5::io::Readable* rd);
            Header& operator++();
        };

        // A "channel" object represents a single virtual channel, bound
        // to a unique Satellite ID and Virtual Channel ID.  It may be
        // configured M_PDU (SPP packets) or B_PDU (byte-stream) mode.
        class Channel final
            : public satcat5::io::EventListener
            , public satcat5::net::Protocol {
        public:
            // Create a virtual channel, bound to an AOS interface.
            // Unidirectional channels may use null "src" or "dst".
            Channel(
                satcat5::ccsds_aos::Dispatch* iface,    // Parent interface
                satcat5::io::Readable* src,             // Outgoing data
                satcat5::io::Writeable* dst,            // Incoming data
                u8 svid, u8 vcid, bool pkt);            // ID and mode-select
            ~Channel() SATCAT5_OPTIONAL_DTOR;

            // Force resynchronization after an error.
            void desync();

            // Process each received AOS frame.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

        protected:
            // Required event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;
            u8 idle_filler(satcat5::io::Writeable* dst, unsigned req);
            bool read_header(satcat5::io::Readable* src);

            // Internal state.
            enum class State {RAW, RESYNC, HEADER, DATA, SKIP};
            satcat5::ccsds_aos::Dispatch* const m_iface;
            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* const m_dst;
            satcat5::io::ArrayWrite m_rx_spp;
            satcat5::ccsds_aos::Header m_rx_next;
            satcat5::ccsds_aos::Header m_tx_next;
            satcat5::ccsds_aos::Channel::State m_rx_state;
            unsigned m_rx_rem;
            u8  m_tx_busy;
            u8  m_tx_irem;
            u16 m_tx_iseq;
            u8  m_rx_tmp[6];
        };

        // Implemention of "net::Dispatch" API for CCSDS-AOS protocol.
        class Dispatch
            : public satcat5::io::EventListener
            , public satcat5::net::Dispatch {
        public:
            // Connect source, sink, and a working buffer.
            // For a fixed-size Transfer Frame Data Field of "dsize" bytes,
            // the required working buffer size is (dsize + 6).
            // Set insert_sync to false if the input is already packetized
            // by the physical layer, or true to insert CCSDS-TM sync words.
            // Unidirectional interfaces may set src or dst to null as needed.
            Dispatch(
                satcat5::io::Readable* src,     // Input interface
                satcat5::io::Writeable* dst,    // Output interface
                u8* buff, unsigned dsize,       // Rx working buffer
                bool insert_sync = false);      // Insert TM sync word?
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Write CCSDS-AOS frame header and get Writeable object.
            satcat5::io::Writeable* open_write(
                const satcat5::ccsds_aos::Header& hdr);

            // Other accessors.
            inline unsigned dsize() const
                { return m_dsize; }     // Data field size
            inline unsigned tsize() const
                { return m_dsize + 6;}  // Buffer = Header + Data
            inline const satcat5::ccsds_aos::Header& rcvd_hdr() const
                { return m_rcvd_hdr; }  // Most recent header

        protected:
            // Required event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;
            bool read_sync(satcat5::io::Readable* src);
            bool read_data(satcat5::io::Readable* src);

            // Stub required for the Dispatch API (not supported).
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;

            // Synchronization and parser state.
            const unsigned m_dsize;
            const bool m_insert;
            u8 m_sync_state;

            // Sink and source objects for the parent interface.
            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* const m_dst;
            satcat5::io::ArrayWrite m_work;
            satcat5::crc16::XmodemRx m_crc_rx;
            satcat5::crc16::XmodemTx m_crc_tx;

            // Store most recent received header parameters.
            satcat5::ccsds_aos::Header m_rcvd_hdr;
        };

        // Dispatch with a statically-allocated working buffer.
        // (Optional template parameter specifies data-field size.)
        template<unsigned DSIZE=251>
        class DispatchStatic : public satcat5::ccsds_aos::Dispatch {
        public:
            DispatchStatic(
                satcat5::io::Readable* src,     // Input interface
                satcat5::io::Writeable* dst,    // Output interface
                bool insert_sync = false)       // Already packetized?
                : Dispatch(src, dst, m_raw, DSIZE, insert_sync), m_raw{} {}
        private:
            u8 m_raw[DSIZE+6];                  // Working buffer
        };

    }
}
