//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Plugins for the software-defined Ethernet switch and IPv4 router.
//!
//! \details
//! This file defines the extensible plugin APIs for the software-defined
//! Ethernet switch (eth::SwitchCore) and IPv4 router (router2::Dispatch).
//! The same API is also used for both, and many plugins are intercompatible.
//!
//! There are two plugin types.  The first type, eth::PluginCore, is attached
//! to the eth::SwitchCore and affects all packets traversing the switch or
//! router.  This API uses a single `query` callback.
//!
//! The second type, eth::PluginPort, is attached to an eth::SwitchPort and
//! affects only packets entering or leaving that specific port.  This API
//! uses separate `ingress` and `egress` callbacks.
//!
//! Plugins that modify packet headers should update those fields directly
//! in the PluginPacket struct, then setting the FLAG_HEADER_CHANGE bit in
//! the `flags` field.  Additional restrictions may apply in some cases.
//! In particular, only PluginPort::egress callbacks are allowed to make
//! changes that affect the total length of packet headers.
//!
//! Both plugin APIs use the eth::PluginPacket data-structure, which contains
//! pointers to the packet contents (i.e., for direct modification) and
//! pre-parsed packet headers for several commonly-used protocols.


#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/eth_header.h>
#include <satcat5/eth_switch.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>
#include <satcat5/tcp_core.h>
#include <satcat5/types.h>
#include <satcat5/udp_core.h>

namespace satcat5 {
    namespace eth {
        //! Ephemeral data structure provided to plugin callbacks.
        //! New fields may be added to this structure in future versions.
        //! \see eth_plugin.h, eth::PluginCore, eth::PluginPort.
        struct PluginPacket {
        public:
            //! Complete packet contents.
            satcat5::io::MultiPacket* pkt;

            //! Copy of Ethernet header fields.
            //! The Ethernet header is present in all valid packets.
            satcat5::eth::Header hdr;

            //! Copy of additional header fields, if present.
            //! Use #is_ip, #is_arp, #is_tcp, #is_udp to test if these fields
            //! are present and populated. Otherwise, they are uninitialized.
            //!@{
            satcat5::eth::ArpHeader arp;
            satcat5::ip::Header ip;
            satcat5::tcp::Header tcp;
            satcat5::udp::Header udp;
            //!@}

            //! Destination mask for which port(s) receive this packet.
            //! The destination mask is sets one bit for each destination port
            //! eligible to receive a packet. It is initialized to all ones.
            //! Plugins may clear bits but should never set them, i.e., plugins
            //! should always bitwise-and (&=) with the previous mask value.
            //!  Example: Return 0x14 = 2^4 + 2^2 = Send to ports #2 and #4.
            //!  Example: Return 0xFFFF... = Send to all ports (broadcast).
            //!  Example: Return 0 = Drop packet (no eligible ports).
            SATCAT5_PMASK_TYPE dst_mask;

            //! Original header length.
            u16 hlen;

            //! Additional status flags indicating packet status.
            u16 flags;

            //! Default constructor only, with no copy-constructor.
            //! Use `read_from` to initialize this data structure.
            constexpr PluginPacket()
                : pkt(nullptr), hdr{}, arp(), ip{}, tcp{}
                , udp(udp::HEADER_EMPTY), dst_mask(0), hlen(0), flags(0) {}

            //! Read metadata from a packet object.
            //! Always reads #hdr. If present, also reads #ip, #arp, #tcp, #udp.
            //! \returns True if all applicable headers were parsed successfully.
            bool read_from(satcat5::io::MultiPacket* packet);

            //! Copy packet headers to the specified destination.
            //! Always writes #hdr. If present, also writes #arp, #ip, #tcp, and #udp.
            void write_to(satcat5::io::Writeable* wr) const;

            //! Notify parent that header contents have changed.
            //! Plugins that change frame-header parameters MUST call this
            //! method before returning from egress(), ingress(), or query().
            //! When set, the SwitchCore rewrites buffer contents based
            //! on the new contents of #hdr, #ip, #arp, #tcp, and #udp.
            inline void adjust()
                { flags |= FLAG_HEADER_CHANGE; }

            //! Divert this frame for deferred processing.
            //! Setting this flag diverts this frame for exclusive use by the
            //! plugin itself, skipping any subsequent plugins and SwitchCore
            //! processing. In such cases, the plugin takes responsibility,
            //! and it MUST eventually call MultiBuffer::free_packet().
            //! The plugin SHOULD NOT call free_packet() before returning.
            inline void divert()
                { flags |= FLAG_DIVERT; }

            //! Drop this frame, indicating why. \see SwitchLogMessage.
            inline void drop(u8 reason)
                { dst_mask = 0; flags = u16(reason); }

            //! Accessors and shortcuts for packet metadata.
            //! Some packet metadata fields are stored in "pkt->m_user[*]".
            //! These values are populated by SwitchPort::write_finalize().
            //!@{
            inline bool is_adjusted() const
                { return !!(flags & FLAG_HEADER_CHANGE); }
            inline bool is_diverted() const
                { return !!(flags & FLAG_DIVERT); }
            inline bool is_ip() const
                { return hdr.type == satcat5::eth::ETYPE_IPV4; }
            inline bool is_arp() const
                { return hdr.type == satcat5::eth::ETYPE_ARP; }
            inline bool is_tcp() const
                { return is_ip() && ip.proto() == satcat5::ip::PROTO_TCP; }
            inline bool is_udp() const
                { return is_ip() && ip.proto() == satcat5::ip::PROTO_UDP; }
            inline unsigned length() const
                { return pkt->m_length; }
            inline SATCAT5_PMASK_TYPE src_mask() const
                { return idx2mask(src_port()); }
            inline unsigned src_port() const
                { return unsigned(pkt->m_user[0]); }
            inline satcat5::eth::VtagPolicy port_vcfg() const
                { return satcat5::eth::VtagPolicy{pkt->m_user[1]}; }
            inline u8 reason() const
                { return u8(flags & 0xFF); }
            //!@}

        protected:
            //! Packet diverted from normal processing. \see divert, flags.
            static const u16 FLAG_DIVERT        = (1u << 8);
            //! Header contents changed. \see changed, flags.
            static const u16 FLAG_HEADER_CHANGE = (1u << 9);

            //! Internal use only.
            bool read_internal(satcat5::io::Readable* rd);
        };

        //! Ethernet switch plugin API.
        //! Switch plugins are attached to an eth::SwitchCore object, and
        //! receive a `query` callback for every incoming packet that crosses
        //! through the switch. (In contrast with the eth::SwitchPortPlugin
        //! API for packets traversing a specific port.)  The callback may
        //! adjust the contents and/or handling of the packet.
        //! \see eth_plugin.h, eth::SwitchCacheInner, eth::SwitchVlanInner.
        class PluginCore {
        public:
            //! Packet-received callback.
            //! The `query` method is called for each incoming packet, passing
            //! a PluginPacket object that plugins can read or modify in-place.
            //! Plugins that alter header fields MUST set FLAG_HEADER_CHANGE
            //! and MUST NOT make any change that affects header length.
            //! The child class MUST override this method.
            virtual void query(PluginPacket& pkt) = 0;

        protected:
            //! Associate this plugin object with the designated switch.
            //! Automatically calls plugin_add() and plugin_remove().
            explicit PluginCore(satcat5::eth::SwitchCore* sw);
            ~PluginCore() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the associated SwitchCore object.
            satcat5::eth::SwitchCore* const m_switch;

        private:
            // Linked list for chaining multiple plugins.
            friend satcat5::util::ListCore;
            satcat5::eth::PluginCore* m_next;
        };

        //! Ethernet port plugin API.
        //! Port plugins are attached to an eth::SwitchPort object, and
        //! receive separate `ingress` and `egress` queries for each packet
        //! passing through a particular port.  (In contrast with the
        //! eth::PluginCore API for affecting packets on all ports.)
        //! The child class must override `ingress`, `egress`, or both.
        //! \see eth_plugin.h, eth::SwitchPort, eth::PluginCore.
        class PluginPort {
        public:
            //! Packet-received callback.
            //! The `ingress` method is called as each packet enters the
            //! associated eth::SwitchPort, immediately before processing
            //! by eth::SwitchCore and calls to eth::PluginCore::query.
            //! Plugins that alter header fields MUST set FLAG_HEADER_CHANGE
            //! and MUST NOT make any change that affects header length.
            //! Override the default implementation to process this event.
            virtual void ingress(PluginPacket& pkt) {}  // GCOVR_EXCL_LINE

            //! Packet-transmit callback.
            //! The `egress` method is called as each packet is queued for
            //! transmission by the eth::SwitchPort. Plugins that alter header
            //! fields MUST set FLAG_HEADER_CHANGE. Unlike other contexts, the
            //! `egress` callback may change header length.
            //! Override the default implementation to process this event.
            virtual void egress(PluginPacket& pkt) {}   // GCOVR_EXCL_LINE

        protected:
            //! Associate this plugin object with the designated port.
            //! Automatically calls plugin_add() and plugin_remove().
            explicit PluginPort(satcat5::eth::SwitchPort* port);
            ~PluginPort() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the associated SwitchPort object.
            satcat5::eth::SwitchPort* const m_port;

        private:
            // Linked list for chaining multiple plugins.
            friend satcat5::util::ListCore;
            satcat5::eth::PluginPort* m_next;
        };
    }
}
