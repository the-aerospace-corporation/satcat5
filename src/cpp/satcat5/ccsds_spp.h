//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! CCSDS Space Packet Protocol
//!
//!\details
//! This file defines SatCat5 networking primitives (i.e., net::Address,
//! net::Dispatch, and net::Protocol), and other utility functions for
//! the [CCSDS Space Packet Protocol, Blue Book 133.0-B-2]
//! (https://public.ccsds.org/Pubs/133x0b2e2.pdf).
//!
//! Space Packet Protocol (SPP) is intended for point-to-point links, so
//! there is no "address" per-se.  Instead, the SatCat5 address/protocol
//! binding is based entirely on the APID field.

#pragma once

#include <satcat5/io_buffer.h>
#include <satcat5/net_core.h>
#include <satcat5/pkt_buffer.h>

namespace satcat5 {
    namespace ccsds_spp {
        // Constants and conversion functions for specific fields.
        // (Refer to 133.0-B-2 Section 4.1 for details.)
        constexpr u32 VERSION_MASK  = 0xE0000000u;  // Packet version number
        constexpr u32 TYPE_MASK     = 0x10000000u;  // Packet type (cmd/tlm)
        constexpr u32 SEC_HDR_FLAG  = 0x08000000u;  // Secondary header flag
        constexpr u32 APID_MASK     = 0x07FF0000u;  // APID field
        constexpr u32 SEQF_MASK     = 0x0000C000u;  // Sequence flags
        constexpr u32 SEQC_MASK     = 0x00003FFFu;  // Sequence count
        constexpr u32 VERSION_1     = (0 << 29);
        constexpr u32 TYPE_CMD      = (1 << 28);
        constexpr u32 TYPE_TLM      = (0 << 28);
        constexpr u32 SEQF_CONTINUE = (0 << 14);
        constexpr u32 SEQF_FIRST    = (1 << 14);
        constexpr u32 SEQF_LAST     = (2 << 14);
        constexpr u32 SEQF_UNSEG    = (3 << 14);

        // Reserved APID values:
        constexpr u16 APID_IDLE     = 0x7FF;        // Idle Packets

        //! Helper object for the CCSDS-SPP primary packet header.
        //! (Length field and secondary headers are handled separately.)
        struct Header {
            u32 value;              // All fields concatenated.

            //! Convert raw APID to the packed internal format.
            static constexpr u32 pack_apid(u16 apid)
                { return (u32(apid) << 16) & APID_MASK; }
            //! Convert raw SEQC to the packed internal format.
            static constexpr u32 pack_seqc(u16 seqc)
                { return u32(seqc) & SEQC_MASK; }

            // Convenience accessors.
            u32 version() const     //!< Version field
                { return value & VERSION_MASK; }
            bool type_cmd() const   //!< Type field is command?
                { return (value & TYPE_MASK) == TYPE_CMD; }
            bool type_tlm() const   //!< Type field is telemetry?
                { return (value & TYPE_MASK) == TYPE_TLM; }
            bool sec_hdr() const    //!< Secondary header present?
                { return !!(value & SEC_HDR_FLAG); }
            u16 apid() const        //!< Application process identifier (APID)
                { return u16((value & APID_MASK) >> 16); }
            u32 seqf() const        //!< Sequence flags
                { return value & SEQF_MASK; }
            u16 seqc() const        //!< Sequence counter
                { return u16(value & SEQC_MASK); }

            //! Construct a basic single-part SPP header.
            void set(bool cmd, u16 apid, u16 seq);

            //! Increment the sequence-count field.
            Header& operator++();
        };

        //! Find packet boundaries in a raw CCSDS-SPP byte-stream.
        //! \see ccsds_spp.h, ccsds_spp::PacketizerStatic, ccsds_spp::Dispatch.
        //!
        //! This helper object finds CCSDS-SPP packet boundaries in an
        //! incoming byte-stream.  The byte-stream can be written directly
        //! to this object, or passively pulled from any Readable source.
        //! In either case, delimited SPP frames are available by reading
        //! from this object. Reads are backed by an internal buffer.
        //!
        //! Note that SPP provides few mechanisms for detecting errors.
        //! Packet desynchronization is resolved using a timeout (default
        //! one second) that discards any trailing data.  If more robust
        //! error-detection is required, please consider using the CCSDS
        //! AOS space data-link protocol \see ccsds_aos.h.
        class Packetizer
            : public satcat5::io::ReadableRedirect
            , public satcat5::io::Writeable
            , public satcat5::poll::Timer {
        public:
            //! Direct write-access to the internal buffer.
            inline satcat5::io::Writeable* bypass()
                { return &m_buff; }

            //! Write-access with CCSDS-SPP packetization.
            inline satcat5::io::Writeable* packet()
                { return this; }

            //! Access the event-listener used for read/pull mode.
            inline satcat5::io::EventListener* listen()
                { return &m_copy; }

            //! Reset partial packets and synchronization state.
            //! Discards incomplete partials, but retains complete packets.
            void flush();

            //! Full reset of buffer and synchronization state.
            //! Discards ALL buffer contents, including complete packets.
            void reset();

            //! If sync is lost, rely on idle periods to resync.
            void set_timeout(unsigned timeout_msec)
                { m_timeout = timeout_msec; }

            // Required methods from the Writeable API.
            unsigned get_write_space() const override;

        protected:
            //! Child class must provide a working buffer.
            //! Child class may provide a Readable source or null.
            Packetizer(
                u8* buff, unsigned rxbytes, unsigned rxpkt,
                satcat5::io::Readable* src = nullptr);

            // Required event handlers.
            void timer_event() override;
            void write_next(u8 data) override;

            // Internal state:
            satcat5::io::BufferedCopy m_copy;   //!< Push-pull adapter.
            satcat5::io::PacketBuffer m_buff;   //!< Output buffer.
            unsigned m_rem;         //!< Bytes remaining in current packet.
            unsigned m_timeout;     //!< User-configurable resync timeout.
            u8 m_wridx;             //!< Packet header write pointer.
            u16 m_sreg;             //!< Packet header working buffer.
        };

        //! Packetizer variant with a statically-allocated buffer.
        //! (Optional template parameter specifies buffer size.)
        template<unsigned SIZE=1600>
        class PacketizerStatic : public satcat5::ccsds_spp::Packetizer {
        public:
            //! Optionally link this object to a source byte-stream.
            explicit PacketizerStatic(satcat5::io::Readable* src = nullptr)
                : Packetizer(m_raw, SIZE, 32, src), m_raw{} {}
        private:
            u8 m_raw[SIZE];
        };

        //! Implemention of "net::Address" API for CCSDS-SPP packets.
        //! \see ccsds_spp.h, ccsds_spp::Dispatch.
        //! This object automatically tracks required per-APID sequence counters.
        class Address : public satcat5::net::Address {
        public:
            //! Attach this address to a specified interface.
            explicit constexpr Address(satcat5::ccsds_spp::Dispatch* iface)
                : m_iface(iface), m_dst{0} {}

            //! Set the packet type and APID.
            //! TODO: Do we need access to the full feature-set?
            inline void connect(bool cmd, u16 apid)
                { m_dst.set(cmd, apid, 0); }

            // Implement the required net::Address API.
            satcat5::net::Dispatch* iface() const override;
            satcat5::io::Writeable* open_write(unsigned len) override;
            void close() override;
            bool ready() const override;
            bool is_multicast() const override {return false;}
            bool matches_reply_address() const override;
            bool reply_is_multicast() const override {return false;}
            void save_reply_address() override;

        protected:
            satcat5::ccsds_spp::Dispatch* const m_iface;
            satcat5::ccsds_spp::Header m_dst;
        };

        //! Implemention of "net::Dispatch" API for CCSDS-SPP packets.
        //! \see ccsds_spp.h, ccsds_spp::Address, ccsds_spp::Packetizer.
        class Dispatch final
            : public satcat5::io::EventListener
            , public satcat5::net::Dispatch {
        public:
            //! Connect to any valid packetized I/O source and sink.
            //! (e.g., satcat5::io::PacketBuffer or satcat5::port::MailMap.)
            //! For connection to a raw UART, use ccsds_spp::Packetizer, above.
            //! For unidirectional links, `src` or `dst` may be a null pointer.
            Dispatch(
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            //! Write CCSDS-SPP frame header and get Writeable object.
            //! This variant replies with the last received APID.
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;

            //! Write CCSDS-SPP frame header and get Writeable object.
            //! This variant sets all destination parameters.
            satcat5::io::Writeable* open_write(
                const satcat5::ccsds_spp::Header& hdr, unsigned len);

            //! Fetch the last received CCSDS-SPP header.
            inline const satcat5::ccsds_spp::Header& rcvd_hdr() const
                { return m_rcvd_hdr; }

        protected:
            // Required event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Sink and source objects for the parent interface.
            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* const m_dst;

            // Store most recent received header parameters.
            satcat5::ccsds_spp::Header m_rcvd_hdr;
        };

        //! Implemention of "net::Protocol" API for CCSDS-SPP packets.
        //! Child class must define the frame_rcvd() method.
        class Protocol : public satcat5::net::Protocol {
        protected:
            //! Constructor and destructor access restricted to children.
            //! APID is bound permanently when the object is created.
            Protocol(satcat5::ccsds_spp::Dispatch* iface, u16 apid);
            ~Protocol() SATCAT5_OPTIONAL_DTOR;

            // Child class must define the frame_rcvd() method.
            // void frame_rcvd(satcat5::io::LimitedRead& src) override;

            //! Pointer to the parent interface.
            satcat5::ccsds_spp::Dispatch* const m_iface;
        };

        //! Convert a raw byte-stream by inserting CCSDS-SPP headers.
        //! This class reads a raw unformatted byte-stream, breaks it into
        //! chunks up to a maximum size (default 256 bytes), and inserts a
        //! CCSDS-SPP header at the start of each chunk.  The modified SPP
        //! packet stream is then written to a designated destination.
        class BytesToSpp {
        public:
            //! Set source, destination, APID, and chunk-size.
            BytesToSpp(
                satcat5::io::Readable* src,
                satcat5::ccsds_spp::Dispatch* dst,
                u16 apid, unsigned max_chunk = 256);

            //! Access the inner io::BufferedStream.
            inline satcat5::io::BufferedStream* strm()
                { return &m_strm; }

        protected:
            satcat5::ccsds_spp::Address m_dst;
            satcat5::io::BufferedStream m_strm;
        };

        //! Convert a CCSDS-SPP packet stream by removing CCSDS-SPP headers.
        //! This class implements the ccsds_spp::Protocol API, accepting SPP
        //! packets with a specified APID.  For each such packet, it removes
        //! the SPP header and copies user data to the specified destination.
        //! \see ccsds_spp::Dispatch, ccsds_spp::Packetizer.
        class SppToBytes : public satcat5::ccsds_spp::Protocol {
        public:
            //! Set source, destination, and APID.
            SppToBytes(
                satcat5::ccsds_spp::Dispatch* src,
                satcat5::io::Writeable* dst, u16 apid);

            //! For each SPP frame, remove header and forward data.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

        protected:
            satcat5::io::Writeable* const m_dst;
        };
    }
}
