//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Diagnostic logging system for the Ethernet switch
//!
//! \details
//! The classes defined in this file read or write diagnostic logs of packets
//! that reach the switch or router,  providing basic information about packet
//! source/destination/type, and where it was directed or why it was dropped.
//!
//! In low-rate debugging (i.e., only a few packets per second), the log
//! will record every single packet.  At higher rates, it will attempt to
//! record packet information on a best-effort basis, with placeholders
//! indicating how many packets were skipped between complete records.
//!
//! The message format uses the same 24-byte format as "mac_log_core":
//!  * Timestamp in microseconds (24-bit)
//!    Counts up from switch reset, wraparound every 16.7 seconds.
//!  * Type indicator (3-bit)
//!      * 0 = Delivered packet
//!      * 1 = Dropped packet
//!      * 2 = Skipped packet(s)
//!      * (3-7 reserved)
//!  * Source port number (5-bit, all-ones if unknown)
//!  * Destination MAC address (48-bit, zero if unknown)
//!  * Source MAC address (48-bit, zero if unknown)
//!  * EtherType (16-bit, zero if unknown)
//!  * VLAN tag (16-bit)
//!  * Metadata for this packet
//!    Interpretation depends on the "Type indicator", see above.
//!      * Type = 0: Destination bit-mask
//!        Bit 31-00: Packet delivered to each port with a '1' bit.
//!      * Type = 1: Reason for packet drop
//!        Bit 31-08: Reserved
//!        Bit 07-00: Reason code, see "eth_frame_common.vhd"
//!      * Type = 2: Number of skipped packets
//!        Bit 31-16: Packets dropped
//!        Bit 15-00: Packets delivered
//!
//! The `eth::SwitchLogMessage` struct represents one such message.
//!
//! For some errors, frame information may not be available.  In such cases,
//! the header information is filled in with zeros, marking it as invalid.
//!
//! The `eth::SwitchLogWriter` is notified for each individual packet, then
//! writes the stream of log data. At low rates, every packet is logged
//! individually. If the output buffer is nearly full, it instead generates
//! a summary of skipped packets to provide rate-limiting of the log data.
//!
//! The `eth::SwitchLogReader` class reads a stream of log data and notifies
//! a callback for each received message. The `eth::SwitchLogFormatter` class
//! is a child that generates human-readable `log::Log` messages.
//!
//! The `eth::SwitchLogStats` class is an alternative to SwitchLogWriter that
//! counts sent and received packets, rather than reporting the details of each
//! one. Its API is similar to the one provided by cfg::NetworkStats.
//!

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/eth_header.h>
#include <satcat5/eth_switch.h>
#include <satcat5/io_writeable.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace eth {
        //! A single 24-byte packet-log message.
        struct SwitchLogMessage {
            // Define "reason codes" used when dropping a packet.
            // These match the codes defined in "eth_frame_common.vhd".
            static constexpr u8
                REASON_KEEP     = 0x00, //!< Packet accepted / not dropped
                DROP_OVERFLOW   = 0x01, //!< FIFO overflow (Rx or Tx)
                DROP_BADFCS     = 0x02, //!< Invalid frame check sequence
                DROP_BADFRM     = 0x03, //!< Frame length, source MAC, etc.
                DROP_MCTRL      = 0x04, //!< Link-local control packet
                DROP_VLAN       = 0x05, //!< Virtual-LAN policy
                DROP_VRATE      = 0x06, //!< Virtual-LAN rate limits
                DROP_PTPERR     = 0x07, //!< PTP error (no timestamp)
                DROP_NO_ROUTE   = 0x08, //!< No destination or null route
                DROP_DISABLED   = 0x09, //!< Ingress or egress port disabled
                DROP_UNKNOWN    = 0xFF; //!< Other unspecified error

            // Other constants:
            static constexpr u8
                SRC_MASK    = 0x1F,     //!< Mask for source index
                TYPE_MASK   = 0xE0,     //!< Mask for message type
                TYPE_KEEP   = (0 << 5), //!< Message type: KEEP (delivered)
                TYPE_DROP   = (1 << 5), //!< Message type: DROP (dropped)
                TYPE_SKIP   = (2 << 5); //!< Message type: SKIP (summary)
            static constexpr u32
                TIME_MASK   = 0xFFFFFF; //!< Timestamp wraparound at 2^24
            static constexpr unsigned
                LEN_BYTES   = 24;       //!< Message length, in bytes

            // Raw packet fields
            u32 tstamp;                 //!< Timestamp in microseconds
            u8  type_src;               //!< Type and source port
            satcat5::eth::Header hdr;   //!< Ethernet packet header
            u32 meta;                   //!< Additional metadata

            //! Coded reason for a dropped packet, if applicable.
            //! \see DROP_OVERFLOW, DROP_BADFCS, DROP_BADFRM, DROP_MCTRL, etc.
            u8 reason() const;

            //! Human-readable reason for a dropped packet, if applicable.
            const char* reason_str() const;

            //! Destination mask (KEEP messages only).
            //! This bit-mask sets a '1' for each destination port.
            inline SATCAT5_PMASK_TYPE dstmask() const
                { return SATCAT5_PMASK_TYPE(meta); }

            // Other accessors
            u16 count_drop() const;         //!< Count dropped packets.
            u16 count_keep() const;         //!< Count delivered packets.
            inline u8 srcport() const       //!< Source port index.
                { return type_src & SRC_MASK; }
            inline u8 type() const          //!< Message type.
                { return type_src & TYPE_MASK; }

            //! Initialize a KEEP message.
            void init_keep(const satcat5::eth::Header& hdr, u8 src, u32 dst);

            //! Initialize a DROP message.
            void init_drop(const satcat5::eth::Header& hdr, u8 src, u8 why);

            //! Initialize a SKIP message.
            void init_skip(u16 drop, u16 keep);

            //! Format this field as a human-readable string.
            void log_to(satcat5::log::LogBuffer& wr) const;
            //! Write descriptor to the designated stream.
            void write_to(satcat5::io::Writeable* wr) const;
            //! Read descriptor from the designated stream.
            //! (Returns true on success, false otherwise.)
            bool read_from(satcat5::io::Readable* rd);
        };

        //! Poll a hardware switch or router for log data.
        class SwitchLogHardware : public satcat5::poll::Timer {
        public:
            //! Link this object to a log-writer and a data source.
            //! The writer object may be shared with other log sources.
            //! Sources: \see eth::SwitchCore, router2::Offload.
            SwitchLogHardware(
                satcat5::eth::SwitchLogHandler* dst,
                satcat5::cfg::Register src);

        protected:
            // Event handlers.
            void timer_event() override;

            // Member variables.
            satcat5::eth::SwitchLogHandler* const m_dst;
            satcat5::cfg::Register m_src;
            satcat5::io::ArrayWriteStatic<SwitchLogMessage::LEN_BYTES> m_buff;
        };

        //! Record packet statistics based on switch log events.
        //! This API is simplified from the one provided by cfg::NetworkStats.
        class SwitchLogStats : public satcat5::eth::SwitchLogHandler {
        public:
            //! Data structure for reporting per-port traffic statistics.
            struct TrafficStats {
                u32 bcast_frames;   //!< Broadcast frames received from device
                u32 rcvd_frames;    //!< Total frames received from device
                u32 sent_frames;    //!< Total frames sent from switch to device
                u32 errct_ovr;      //!< Frames dropped due to FIFO overflow
                u32 errct_pkt;      //!< Invalid packets (bad checksum, etc.)
                u32 errct_total;    //!< Total packet errors, all types
            };

            //! Read most recent statistics for the Nth port.
            //! Calling this method resets all counters for the requested port.
            TrafficStats get_port(unsigned idx);

            //! Process each packet event.
            void log_packet(const satcat5::eth::SwitchLogMessage& msg) override;

        protected:
            //! Constructor accepts a pointer to the working buffer.
            SwitchLogStats(TrafficStats* buff, unsigned size);

            // Working buffers are provided by the parent class.
            TrafficStats* const m_stats;    //!< Working counters.
            const unsigned m_size;          //!< Buffer size
        };

        //! Static allocation wrapper for eth::SwitchLogStats.
        template <unsigned SIZE = satcat5::eth::PMASK_SIZE>
        class SwitchLogStatsStatic : public satcat5::eth::SwitchLogStats {
        public:
            SwitchLogStatsStatic() : SwitchLogStats(m_stats_buffer, SIZE) {}

        protected:
            satcat5::eth::SwitchLogStats::TrafficStats m_stats_buffer[SIZE];
        };

        //! Record rate-limited packet-logs for a switch or router.
        //! This SwitchLogHandler writes packet descriptors to a byte-stream.
        //! The resulting byte-stream can be parsed by eth::SwitchLogReader.
        class SwitchLogWriter
            : public satcat5::eth::SwitchLogHandler
            , protected satcat5::poll::Timer {
        public:
            //! Link this object to a Writeable destination.
            explicit SwitchLogWriter(satcat5::io::Writeable* dst)
                : m_dst(dst), m_skip_drop(0), m_skip_keep(0) {}

            //! Process each packet event.
            void log_packet(const satcat5::eth::SwitchLogMessage& msg) override;

        protected:
            // Event handlers.
            void timer_event() override;

            // Member variables.
            satcat5::io::Writeable* const m_dst;
            u16 m_skip_drop;
            u16 m_skip_keep;
        };

        //! Read packet-logs from an input byte-stream.
        class SwitchLogReader : protected satcat5::io::EventListener {
        protected:
            //! Only children should create or destroy the base class.
            explicit SwitchLogReader(satcat5::io::Readable* src);
            ~SwitchLogReader() SATCAT5_OPTIONAL_DTOR;

            //! The child class MUST override this method.
            //! This callback is notified for each parsed log message.
            virtual void log_event(const satcat5::eth::SwitchLogMessage& msg) = 0;

            // Event handlers.
            void data_rcvd(satcat5::io::Readable* src) override;
            void data_unlink(satcat5::io::Readable* src) override;

            // Member variables.
            satcat5::io::Readable* m_src;
        };

        //! Read binary packet logs to produce human-readable log messages.
        class SwitchLogFormatter : protected SwitchLogReader {
        public:
            //! Bind this object to a stream of packet-logging data.
            explicit SwitchLogFormatter(
                satcat5::io::Readable* src,
                const char* lbl = "PktLog");
            void log_event(const satcat5::eth::SwitchLogMessage& msg) override;

        protected:
            const char* const m_label;
        };
    }
}
