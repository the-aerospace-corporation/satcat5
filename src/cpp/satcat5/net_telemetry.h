//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
// State-of-health telemetry using QCBOR
//
// This file implements a multipurpose system for reporting state-of-health
// telemetry, typically over a network interface.  All messages in this
// system are CBOR-encoded as a key-value dictionary with integer keys.
//
// The API can be operated in raw-Ethernet mode (eth::Telemetry) or UDP mode
// (udp::Telemetry).  In both cases, the destination address is broadcast by
// default, but can be changed to unicast by calling connect(...).  Users
// can also create their own protocols using the net::TelemetrySink API.
//
// The system is made of several interlocking classes:
//  * net::TelemetryAggregator
//      This is the parent class that handles encoded data delivery, creation
//      of the CBOR encoder, timer polling, etc.  Each TelemetryAggregator
//      object operates a linked list of associated TelemetryTier object(s).
//      Encoded CBOR data is passed to one or more TelemetrySink object(s).
//  * net::TelemetryTier
//      This class sets the reporting interval for a specific "tier" of data
//      for a given TelemetrySource.  Each TelemetrySource may have multiple
//      tiers operating at different rates, identified by an ID number.
//      ID-codes are optional parameters used by sources and sinks to indicate
//      the content and priority of data, for filtering or other purposes.
//      (i.e., Sources with only one tier can simply set the ID to zero.)
//  * net::TelemetrySink
//      This class is a destination for encoded telemetry data.  Users should
//      inherit from this class or use one of the provided implementations.
//      Custom sinks must override telem_ready(...) method.
//  * net::TelemetrySource
//      This class is a user-defined data source.  Users MUST define a class
//      that inherits from the net::TelemetrySource class and overrides the
//      telem_event(...) method.  Sources MAY instantiate any number of
//      TelemetryTier member variables as part of their class definition.
//  * net::TelemetryCbor
//      An ephemeral wrapper passed to the TelemetrySource::telem_event(...)
//      method.  Use the provided helper methods (add_*) or call QCBOR
//      functions directly using the provided "EncodeContext" pointer.
//  * eth::Telemetry
//      All-in-one wrapper using raw-Ethernet frames.
//      (Combined net::TelemetryAggregator + net::TelemetrySink.)
//  * udp::Telemetry
//      All-in-one wrapper using UDP datagrams.
//      (Combined net::TelemetryAggregator + net::TelemetrySink.)
//

#pragma once

#include <satcat5/eth_socket.h>
#include <satcat5/list.h>
#include <satcat5/polling.h>
#include <satcat5/types.h>
#include <satcat5/udp_socket.h>

// Set the size of the working buffer.
#ifndef SATCAT5_QCBOR_BUFFER
#define SATCAT5_QCBOR_BUFFER 1500
#endif

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE
#include <qcbor/qcbor_encode.h>

namespace satcat5 {
    namespace net {
        // Ephemeral wrapper class for the CBOR encoder.
        struct TelemetryCbor final {
            // Pointer to the underlying QCBOR object.
            // Use this pointer directly for writing complex data structures.
            _QCBOREncodeContext* const cbor;

            // Helper methods for writing various arrays.
            void add_array(s64 key, u32 len, const s8* value) const;
            void add_array(s64 key, u32 len, const u8* value) const;
            void add_array(s64 key, u32 len, const s16* value) const;
            void add_array(s64 key, u32 len, const u16* value) const;
            void add_array(s64 key, u32 len, const s32* value) const;
            void add_array(s64 key, u32 len, const u32* value) const;
            void add_array(s64 key, u32 len, const s64* value) const;
            void add_array(s64 key, u32 len, const u64* value) const;
            void add_array(s64 key, u32 len, const float* value) const;

            // Shortcuts for simple key/value pairs.
            inline void add_bool(s64 key, bool value) const
                { QCBOREncode_AddBoolToMapN(cbor, key, value); }
            inline void add_bytes(s64 key, u32 len, const u8* value) const
                { QCBOREncode_AddBytesToMapN(cbor, key, {value, len}); }
            inline void add_item(s64 key, s8 value) const
                { QCBOREncode_AddInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, s16 value) const
                { QCBOREncode_AddInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, s32 value) const
                { QCBOREncode_AddInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, s64 value) const
                { QCBOREncode_AddInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, u8 value) const
                { QCBOREncode_AddUInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, u16 value) const
                { QCBOREncode_AddUInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, u32 value) const
                { QCBOREncode_AddUInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, u64 value) const
                { QCBOREncode_AddUInt64ToMapN(cbor, key, value); }
            inline void add_item(s64 key, float value) const
                { QCBOREncode_AddFloatToMapN(cbor, key, value); }
            inline void add_null(s64 key) const
                { QCBOREncode_AddNULLToMapN(cbor, key); }
            inline void add_string(s64 key, const char* value) const
                { QCBOREncode_AddSZStringToMapN(cbor, key, value); }
        };

        // User data sinks must inherit from the TelemetrySink class.
        class TelemetrySink {
        public:
            // This method is called for each outgoing telemetry message.
            //  * If the aggregator is in concatenate mode (default), all tiers
            //    are added to a single dictionary and the method is called once.
            //    (Placeholder tier_id = 0.)
            //  * If the aggregator is in per-tier mode, the method is called
            //    for each telemetry tier and sets the appropriate tier_id.
            // Child class MUST override this method.
            virtual void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) = 0;

        protected:
            // Only children can safely access constructor/destructor.
            explicit TelemetrySink(satcat5::net::TelemetryAggregator* tlm);
            ~TelemetrySink() SATCAT5_OPTIONAL_DTOR;

            // Pointer to the parent object.
            satcat5::net::TelemetryAggregator* const m_tlm;

        private:
            // Linked list of other TelemetrySink objects.
            friend satcat5::util::ListCore;
            satcat5::net::TelemetrySink* m_next;
        };

        // User data sources must inherit from the TelemetrySource class.
        class TelemetrySource {
        public:
            // User method for writing each telemetry message.
            // Child class MUST override this method.
            virtual void telem_event(
                u32 tier_id, const satcat5::net::TelemetryCbor& cbor) = 0;
        };

        // Rate control for a particular telemetry "tier".
        // (A given TelemetrySource may have one or more tiers.)
        class TelemetryTier final {
        public:
            // Constructor is typically called by the TelemetrySource.
            TelemetryTier(
                satcat5::net::TelemetryAggregator* tlm,
                satcat5::net::TelemetrySource* src,
                u32 tier_id, unsigned interval_msec = 0);
            ~TelemetryTier() SATCAT5_OPTIONAL_DTOR;

            // Set the reporting interval for this tier, or zero to disable.
            void set_interval(unsigned interval_msec);

            // Tier-ID for this object.
            const u32 m_tier_id;

        private:
            // Event notifications from the TelemetryAggregator.
            friend satcat5::net::TelemetryAggregator;
            void telem_poll(const satcat5::net::TelemetryCbor& cbor);

            // Linked list of other TelemetryTier objects.
            friend satcat5::util::ListCore;
            satcat5::net::TelemetryTier* m_next;

            // Internal state for this tier.
            satcat5::net::TelemetryAggregator* const m_tlm;
            satcat5::net::TelemetrySource* const m_src;
            unsigned m_time_interval;
            unsigned m_time_count;
        };

        // Protocol-agnostic handler for one or more TelemetryTier objects.
        // Requires a protocol-specific wrapper for use (see below).
        class TelemetryAggregator : public satcat5::poll::Timer
        {
        public:
            // Constructor and destructor.
            explicit TelemetryAggregator(bool concat_tiers);

            // Change to concatenated or per-tier mode.
            inline void telem_concat(bool concat_tiers)
                { m_tlm_concat = concat_tiers; }

        private:
            // Timer event handler is called every N msec.
            void timer_event() override;

            // Initialize a QCBOR encoder state.
            void telem_init(_QCBOREncodeContext* cbor);

            // Send data to all attached TelemetrySink objects.
            void telem_send(_QCBOREncodeContext* cbor, u32 tier_id);

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
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        class Telemetry final
            : public satcat5::eth::AddressContainer
            , public satcat5::net::TelemetryAggregator
            , public satcat5::net::TelemetrySink
        {
        public:
            // Constructor and destructor.
            Telemetry(
                satcat5::eth::Dispatch* eth,        // Ethernet interface
                const satcat5::eth::MacType& typ,   // Destination EtherType
                bool concat_tiers = true);          // Concatenate mode?
            ~Telemetry() {}

            // Set the destination address.
            inline void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type)
                { m_addr.connect(addr, type); }
            inline void close()
                { m_addr.close(); }

        protected:
            // Event handler for the TelemetrySink API.
            void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) override
                { m_addr.write_packet(nbytes, data); }
        };
    }

    namespace udp {
        class Telemetry final
            : public satcat5::udp::AddressContainer
            , public satcat5::net::TelemetryAggregator
            , public satcat5::net::TelemetrySink
        {
        public:
            // Constructor and destructor.
            Telemetry(
                satcat5::udp::Dispatch* udp,        // UDP interface
                const satcat5::udp::Port& dstport,  // Destination port
                bool concat_tiers = true);          // Concatenate mode?
            ~Telemetry() {}

            // Set the destination address.
            inline void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport)
                { m_addr.connect(dstaddr, dstport, 0);}
            inline void close()
                { m_addr.close(); }

        protected:
            // Event handler for the TelemetrySink API.
            void telem_ready(
                u32 tier_id, unsigned nbytes, const void* data) override
                { m_addr.write_packet(nbytes, data); }
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
