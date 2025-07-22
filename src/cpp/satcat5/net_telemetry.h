//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! State-of-health telemetry using QCBOR
//!
//!\details
//! This file implements a multipurpose system for reporting state-of-health
//! telemetry, typically over a network interface.  All messages in this
//! system are CBOR-encoded as a key-value dictionary.  Users can choose to
//! use integer keys (more compact) or string keys (more readable).  Classes
//! are provided to send and receive telemetry.
//!
//! The transmit API can be operated in raw-Ethernet mode (eth::Telemetry) or
//! UDP mode (udp::Telemetry).  In both cases, the user must call connect(...)
//! to set the destination address.  To begin sending telemetry:
//!   * Instantiate either eth::Telemetry or net::Telemetry.
//!   * Create a user-defined net::TelemetrySource object that overrides
//!     telem_event(...) to send key/value data of interest.
//!   * Instantiate net::TelemetryTier, passing the previous objects
//!     and the desired reporting interval.  (Optionally, this object may
//!     be included as part of the user-defined net::TelemetrySource.)
//!   * Call the Telemetry object's connect(...) method.
//!
//! The transmit API uses the following classes:
//!  * net::TelemetryAggregator
//!      This is the parent class that handles encoded data delivery, creation
//!      of the CBOR encoder, timer polling, etc.  Each TelemetryAggregator
//!      object operates a linked list of associated TelemetryTier object(s).
//!      Encoded CBOR data is passed to one or more TelemetrySink object(s).
//!  * net::TelemetryTier
//!      This class sets the reporting interval for a specific "tier" of data
//!      for a given TelemetrySource.  Each TelemetrySource may have multiple
//!      tiers operating at different rates, identified by an ID number.
//!      ID-codes are optional parameters used by sources and sinks to indicate
//!      the content and priority of data, for filtering or other purposes.
//!      (i.e., Sources with only one tier can simply set the ID to zero.)
//!  * net::TelemetrySink
//!      This class accepts encoded telemetry data and sends it to the network,
//!      using a user-selected transport protocol.  Implementations are provided
//!      for raw-Ethernet (eth::Telemetry) and UDP (udp::Telemetry).
//!      To add headers or use other protocols, users should inherit from this
//!      class and override the telem_ready(...) method.
//!  * net::TelemetrySource
//!      This class is a user-defined data source.  Users MUST define a class
//!      that inherits from the net::TelemetrySource class and overrides the
//!      telem_event(...) method.  Sources MAY instantiate any number of
//!      TelemetryTier member variables as part of their class definition.
//!  * net::TelemetryCbor
//!      An ephemeral wrapper passed to the TelemetrySource::telem_event(...)
//!      method.  Use the provided helper methods (add_*) or call QCBOR
//!      functions directly using the provided "EncodeContext" pointer.
//!  * eth::Telemetry
//!      Send CBOR telemetry using raw-Ethernet frames.
//!      (Combined net::TelemetryAggregator + net::TelemetrySink.)
//!  * udp::Telemetry
//!      Send CBOR telemetry using UDP datagrams.
//!      (Combined net::TelemetryAggregator + net::TelemetrySink.)
//!
//! The receive API uses the following classes:
//!  * net::TelemetryWatcher
//!      This class receives a callback for each received key/value pair.
//!      It should identify information of interest and discard other items.
//!  * net::TelemetryKey
//!      Store a pointer to a statically-allocated global string (const char*)
//!      and calculate the CRC32 hash for that string.
//!  * net::TelemetryLogger
//!      An example implementation of net::TelemetryWatcher.
//!      This class logs received key/value pairs, with an optional filter.
//!  * net::TelemetryLoopback
//!      This TelemetrySink attaches to an existing interface for outgoing
//!      telemetry messages, and echoes their contents to a designated
//!      net::TelemetryRx object.  This is useful for message-passing
//!      systems that may accept messages from internal or external sources.
//!  * net::TelemetryRx
//!      Helper-class and parent of eth::TelemetryRx and udp::TelemetryRx.
//!      This class parses the incoming CBOR message and notifies registered
//!      callbacks (net::TelemetryWatcher).  Create a child class to define
//!      a custom transport protocol.
//!  * eth::TelemetryRx
//!      Receive CBOR telemetry using raw-Ethernet frames.
//!  * udp::TelemetryRx
//!      Receive CBOR telemetry using UDP datagrams.

#pragma once

#include <satcat5/eth_socket.h>
#include <satcat5/io_cbor.h>
#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/types.h>
#include <satcat5/udp_socket.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE

namespace satcat5 {
    namespace net {
        //! Legacy ephemeral wrapper class for the CBOR encoder.
        //! Wraps io::CborMapWriter which replaces this functionality for more
        //! generic usage.  This version is specialized for use with the
        //! net::TelemetrySource and net::TelemetryAggregator classes.
        //! \see net_telemetry.h, io::CborMapWriter.
        class TelemetryCbor final
            : public satcat5::cbor::MapWriter<s64>
            , public satcat5::cbor::MapWriter<const char*>
        {
        public:
            // Import specific functions to resolve ambiguous name issues.
            // (Explicitly include both variants, unless they're equivalent.)
            using satcat5::cbor::MapWriter<s64>::add_bool;
            using satcat5::cbor::MapWriter<s64>::add_item;
            using satcat5::cbor::MapWriter<s64>::add_array;
            using satcat5::cbor::MapWriter<s64>::add_bytes;
            using satcat5::cbor::MapWriter<s64>::add_string;
            using satcat5::cbor::MapWriter<s64>::add_null;
            using satcat5::cbor::MapWriter<s64>::close_list;
            using satcat5::cbor::MapWriter<s64>::close_map;
            using satcat5::cbor::MapWriter<s64>::open_list;
            using satcat5::cbor::MapWriter<s64>::open_map;
            using satcat5::cbor::MapWriter<const char*>::add_bool;
            using satcat5::cbor::MapWriter<const char*>::add_item;
            using satcat5::cbor::MapWriter<const char*>::add_array;
            using satcat5::cbor::MapWriter<const char*>::add_bytes;
            using satcat5::cbor::MapWriter<const char*>::add_string;
            using satcat5::cbor::MapWriter<const char*>::add_null;
            using satcat5::cbor::MapWriter<const char*>::open_list;
            using satcat5::cbor::MapWriter<const char*>::open_map;

            //! Default constructor initializes both variants.
            TelemetryCbor()
                : CborWriter(nullptr, &m_cbor, m_raw, SATCAT5_QCBOR_BUFFER, true) {}

        private:
            QCBOREncodeContext m_cbor;
            u8 m_raw[SATCAT5_QCBOR_BUFFER];
        };

        //! User data sinks must inherit from the TelemetrySink class.
        //! This class sends the encoded data to its destination(s).
        //! \see net_telemetry.h, net::TelemetrySource.
        class TelemetrySink {
        public:
            //! This method is called for each outgoing telemetry message.
            //!  * If the aggregator is in concatenate mode (default), all tiers
            //!    are added to a single dictionary and the method is called once.
            //!    (Placeholder tier_id = 0.)
            //!  * If the aggregator is in per-tier mode, the method is called
            //!    for each telemetry tier and sets the appropriate tier_id.
            //! Child class MUST override this method.
            virtual void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) = 0;

        protected:
            //! Only children can safely access constructor/destructor.
            explicit TelemetrySink(satcat5::net::TelemetryAggregator* tlm);
            ~TelemetrySink() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the parent object.
            satcat5::net::TelemetryAggregator* const m_tlm;

        private:
            // Linked list of other TelemetrySink objects.
            friend satcat5::util::ListCore;
            satcat5::net::TelemetrySink* m_next;
        };

        //! User data sources must inherit from the TelemetrySource class.
        //! \see net_telemetry.h, net::TelemetrySink.
        class TelemetrySource {
        public:
            //! User method for writing each telemetry message.
            //! Child class MUST override this method.
            virtual void telem_event(
                u32 tier_id, satcat5::net::TelemetryCbor& cbor) = 0;
        };

        //! Rate control for a particular telemetry "tier".
        //! A given TelemetrySource has at least one tier, sometimes many.
        //! \see net_telemetry.h, net::TelemetrySource.
        class TelemetryTier final {
        public:
            //! Constructor is typically called by the TelemetrySource.
            TelemetryTier(
                satcat5::net::TelemetryAggregator* tlm,
                satcat5::net::TelemetrySource* src,
                u32 tier_id, unsigned interval_msec = 0);
            ~TelemetryTier() SATCAT5_OPTIONAL_DTOR;

            //! Immediately send a message at this tier.
            void send_now();

            //! Set the reporting interval for this tier, or zero to disable.
            void set_interval(unsigned interval_msec);

            //! Tier-ID for this object.
            const u32 m_tier_id;

        private:
            // Event notifications from the TelemetryAggregator.
            friend satcat5::net::TelemetryAggregator;
            void telem_poll(satcat5::net::TelemetryCbor& cbor);

            // Linked list of other TelemetryTier objects.
            friend satcat5::util::ListCore;
            satcat5::net::TelemetryTier* m_next;

            // Internal state for this tier.
            satcat5::net::TelemetryAggregator* const m_tlm;
            satcat5::net::TelemetrySource* const m_src;
            unsigned m_time_interval;
            unsigned m_time_count;
        };

        //! Protocol-agnostic handler for one or more TelemetryTier objects.
        //! Requires a protocol-specific wrapper for use (see below).
        //! \see net_telemetry.h, net::TelemetrySink, net::TelemetrySource.
        class TelemetryAggregator : protected satcat5::poll::Timer {
        public:
            //! Constructor and destructor.
            explicit TelemetryAggregator(bool concat_tiers);

            //! Change to concatenated or per-tier mode.
            inline void telem_concat(bool concat_tiers)
                { m_tlm_concat = concat_tiers; }

            //! Send data to all attached TelemetrySink objects.
            //! This is normally called automatically, but calling
            //! it directly may be used for unscheduled messages.
            void telem_send(TelemetryCbor& cbor, u32 tier_id);

            //! Query the polling interval for this aggregator.
            //! Rate is adjusted automatically based on active sources.
            inline unsigned timer_interval() const
                { return satcat5::poll::Timer::timer_interval(); }

        protected:
            // Timer event handler is called every N msec.
            void timer_event() override;

            // Set per-tier or concatenated mode for this aggregator.
            bool m_tlm_concat;

            // Linked-list of associated TelemetrySink objects.
            friend satcat5::net::TelemetrySink;
            satcat5::util::List<satcat5::net::TelemetrySink> m_sinks;

            // Linked-list of associated TelemetryTier objects.
            friend satcat5::net::TelemetryTier;
            satcat5::util::List<satcat5::net::TelemetryTier> m_tiers;

            // Statically allocated working buffer.
            u8 m_buff[SATCAT5_QCBOR_BUFFER];
        };

        //! Callback API for incoming telemetry items.
        //! \see net_telemetry.h, net::TelemetryRx.
        class TelemetryWatcher {
        public:
            //! Callback for each received key/value pair.
            //! The child object MUST override this callback method.
            //! Users with string keys should compare against the hash first,
            //! to ensure the matching process can iterate quickly.
            //! \param key  Integer key, or CRC32 hash of a string key.
            //! \param item Value associated with this key.
            //! \param cbor QCBOR decoder for reading complex data structures.
            //!   This pointer is provided for maps and arrays, not for simple
            //!   items. The callback MUST NOT call ExitArray or ExitMap.
            virtual void telem_rcvd(
                u32 key, const QCBORItem& item,
                QCBORDecodeContext* cbor) = 0;

        protected:
            //! Constructor and destructor are accessible to the child only.
            explicit TelemetryWatcher(satcat5::net::TelemetryRx* rx);
            ~TelemetryWatcher() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the receive-and-decode object.
            satcat5::net::TelemetryRx* const m_rx;

        private:
            // Linked list for the net::TelemetryRx class.
            friend satcat5::util::ListCore;
            satcat5::net::TelemetryWatcher* m_next;
        };

        //! String constant, plus the CRC32 hash of that string.
        //! Calculates string-hash for use with TelemetryWatcher::telem_rcvd().
        struct TelemetryKey {
            explicit TelemetryKey(const char* label);

            const char* key;    //!< String key.
            const u32 hash;     //!< CRC32 of that string.
        };

        //! Example TelemetryWatcher that logs received key/value pairs.
        //! If a specific key-string is specified, it only responds to that key.
        class TelemetryLogger : public satcat5::net::TelemetryWatcher {
        public:
            //! Constructor for string keys, or default null = no filter.
            explicit TelemetryLogger(
                satcat5::net::TelemetryRx* rx, const char* kstr = nullptr);
            //! Constructor for integer keys.
            explicit TelemetryLogger(
                satcat5::net::TelemetryRx* rx, u32 key);

        protected:
            void telem_rcvd(
                u32 key, const QCBORItem& item,
                QCBORDecodeContext* cbor) override;
            satcat5::util::optional<u32> m_filter;
        };

        //! Parse incoming CBOR telemetry and notify TelemetryWatcher callbacks.
        //! \see net_telemetry.h, net::TelemetryWatcher.
        class TelemetryRx {
        public:
            //! Manage the list of registered callback objects.
            //!@{
            inline void add_watcher(TelemetryWatcher* callback)
                { m_watchers.add(callback); }
            inline void remove_watcher(TelemetryWatcher* callback)
                { m_watchers.remove(callback); }
            //!@}

            //! The child object MUST call this method for each received message.
            //! This API is also used by net::TelemetryLoopback.
            void telem_packet(satcat5::io::LimitedRead& src);

        protected:
            //! Constructor is only accessible to the child object.
            TelemetryRx() {}
            ~TelemetryRx() {}

        private:
            //! Internal callback delivers one item to each watcher.
            void telem_item(QCBORDecodeContext* cbor, const QCBORItem& item);

            //! Linked list of registered callback objects.
            satcat5::util::List<satcat5::net::TelemetryWatcher> m_watchers;
        };

        //! Loopback adapter for telemetry messages.
        //! This loopback adapter is a TelemetrySink that carbon-copies
        //! outgoing messages to a local interface, for internal messaging.
        class TelemetryLoopback : public satcat5::net::TelemetrySink {
        public:
            //! Link source and destination interfaces.
            TelemetryLoopback(
                satcat5::net::TelemetryAggregator* src,
                satcat5::net::TelemetryRx* dst);

            //! Carbon-copy outgoing messages to the designated interface.
            void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) override;

        protected:
            satcat5::net::TelemetryRx* const m_dst;
        };
    }

    namespace eth {
        //! Thin wrapper for sending CBOR telemetry over raw-Ethernet.
        //! \see net_telemetry.h, net::Telemetry, eth::TelemetryRx.
        class Telemetry final
            : public satcat5::eth::AddressContainer
            , public satcat5::net::TelemetryAggregator
            , public satcat5::net::TelemetrySink
        {
        public:
            //! Link this object to a network interface.
            //! User must call connect() to begin sending telemetry.
            Telemetry(
                satcat5::eth::Dispatch* eth,        // Ethernet interface
                bool concat_tiers = true);          // Concatenate mode?
            ~Telemetry() {}

            //! Set the destination MAC address and EtherType.
            //! Recommended EtherType is satcat5::eth::ETYPE_CBOR_TLM.
            inline void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE)
                { m_addr.connect(addr, type, vtag); }

            //! Close the connection and stop transmission.
            inline void close()
                { m_addr.close(); }

        protected:
            // Event handler for the TelemetrySink API.
            void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) override
                { m_addr.write_packet(nbytes, data); }
        };

        //! Thin wrapper for receiving CBOR telemetry over raw-Ethernet.
        //! \see net_telemetry.h, net::TelemetryWatcher, eth::Telemetry.
        class TelemetryRx final
            : public satcat5::net::Protocol
            , public satcat5::net::TelemetryRx
        {
        public:
            //! Constructor sets network interface and incoming EtherType.
            TelemetryRx(
                satcat5::eth::Dispatch* iface,
                const satcat5::eth::MacType& type);
            ~TelemetryRx() SATCAT5_OPTIONAL_DTOR;

        protected:
            // Required callback from net::Protocol.
            void frame_rcvd(satcat5::io::LimitedRead& src);

            satcat5::eth::Dispatch* const m_iface;
        };
    }

    namespace udp {
        //! Thin wrapper for sending CBOR telemetry over UDP.
        //! \see net_telemetry.h, net::Telemetry, udp::TelemetryRx.
        class Telemetry final
            : public satcat5::udp::AddressContainer
            , public satcat5::net::TelemetryAggregator
            , public satcat5::net::TelemetrySink
        {
        public:
            //! Link this object to a network interface.
            //! User must call connect() to begin sending telemetry.
            Telemetry(
                satcat5::udp::Dispatch* udp,        // UDP interface
                bool concat_tiers = true);          // Concatenate mode?
            ~Telemetry() {}

            //! Set the destination IP address and UDP port.
            //! Recommended destination port is satcat5::udp::PORT_CBOR_TLM.
            inline void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport = satcat5::udp::PORT_CBOR_TLM,
                const satcat5::eth::VlanTag& vtag = satcat5::eth::VTAG_NONE)
                { m_addr.connect(dstaddr, dstport, satcat5::udp::PORT_NONE, vtag);}

            //! Close the connection and stop transmission.
            inline void close()
                { m_addr.close(); }

        protected:
            // Event handler for the TelemetrySink API.
            void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) override
                { m_addr.write_packet(nbytes, data); }
        };

        //! Thin wrapper for receiving CBOR telemetry over UDP.
        //! \see net_telemetry.h, net::TelemetryWatcher, udp::Telemetry.
        class TelemetryRx final
            : public satcat5::net::Protocol
            , public satcat5::net::TelemetryRx
        {
        public:
            //! Constructor sets network interface and incoming UDP port.
            explicit TelemetryRx(
                satcat5::udp::Dispatch* iface,
                const satcat5::udp::Port& port = satcat5::udp::PORT_CBOR_TLM);
            ~TelemetryRx() SATCAT5_OPTIONAL_DTOR;

        protected:
            // Required callback from net::Protocol.
            void frame_rcvd(satcat5::io::LimitedRead& src);

            satcat5::udp::Dispatch* const m_iface;
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
