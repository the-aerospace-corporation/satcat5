//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Software-defined Ethernet switch
//!
//! \details
//! This file defines a layer-2 Ethernet switch, using a shared-memory
//! architecture defined by the MultiBuffer class (multi_buffer.h).
//! The SwitchCore class supports a maximum of 32 ports by default.
//!
//! Connected ports implement the "eth::SwitchPort" API, defined below.
//! For examples suitable for use with various SatCat5 I/O objects, see
//! the classes defined in "port_adapter.h".
//!
//! An extensible plugin system directs packets to the appropriate
//! destination(s). Provided plugins include basic MAC-address learning
//! systems (eth_sw_cache.h) and Virtual-LAN functions (eth_sw_vlan.h).
//!
//! Precision Time Protocol (PTP) is not currently supported.

#pragma once

#include <satcat5/eth_header.h>
#include <satcat5/ip_core.h>
#include <satcat5/list.h>
#include <satcat5/multi_buffer.h>
#include <satcat5/switch_cfg.h>
#include <satcat5/types.h>

//! Set the integer type used to identify source and destination ports.
//! The size of the "pmask" data type sets the maximum number of ports
//! for SatCat5 switches and routers (e.g., default "u32" = max 32 ports).
//! Supported alternate sizes are u8, u16, u32, and u64.
#ifndef SATCAT5_PMASK_TYPE
#define SATCAT5_PMASK_TYPE u32
#endif

namespace satcat5 {
    namespace eth {
        //! Global port-mask indicating every port (i.e., broadcast).
        constexpr SATCAT5_PMASK_TYPE PMASK_ALL(-1);

        //! Global port-mask indicating no ports (i.e., drop).
        constexpr SATCAT5_PMASK_TYPE PMASK_NONE(0);

        //! Macro converting port-index to a bit-mask.
        constexpr SATCAT5_PMASK_TYPE idx2mask(unsigned idx)
            { return (idx < 65536) ? (SATCAT5_PMASK_TYPE(1) << idx) : 0; }

        //! Define the API for Ethernet switch plugins.
        //! See examples in "eth_sw_cache.h" and "eth_sw_vlan.h".
        class SwitchPlugin {
        public:
            //! Ephemeral data structure provided to the "query" method.
            //! (New fields may be added to this structure in future versions.)
            struct PacketMeta {
                //! Complete packet contents.
                satcat5::io::MultiPacket* pkt;

                //! Copy of Ethernet header fields.
                //! The Ethernet header is present in all valid packets.
                //! This field is populated from #pkt by the "read_from" method.
                satcat5::eth::Header hdr;

                //! Copy of IPv4 header fields, if present.
                //! The IPv4 header is present if hdr.type == ETYPE_IPV4.
                //! This field is populated from #pkt by the "read_from" method.
                satcat5::ip::Header ip;

                //! Destination mask sets one bit for each destination port
                //! eligible to receive a packet. Plugins that affect this
                //! should bitwise-and (&=) with the previous mask value:
                //!  Example: Return 0x14 = 2^4 + 2^2 = Send to ports #2 and #4.
                //!  Example: Return 0xFFFF... = Send to all ports (broadcast).
                //!  Example: Return 0 = Drop packet (no eligible ports).
                SATCAT5_PMASK_TYPE dst_mask;

                //! Read metadata from a packet object, populating "hdr" and "ip".
                //! \returns True if all applicable headers were parsed successfully.
                bool read_from(satcat5::io::MultiPacket* packet);

                //! Accessors and shortcuts for packet metadata.
                //! Some packet metadata fields are stored in "pkt->m_user[*]".
                //! These values are populated by SwitchPort::write_finalize().
                //!@{
                inline unsigned length() const
                    { return pkt->m_length; }
                inline SATCAT5_PMASK_TYPE src_mask() const
                    { return idx2mask(src_port()); }
                inline unsigned src_port() const
                    { return unsigned(pkt->m_user[0]); }
                inline satcat5::eth::VtagPolicy port_vcfg() const
                    { return satcat5::eth::VtagPolicy{pkt->m_user[1]}; }
                //!@}
            };

            //! Packet-received callback
            //!
            //! The "query" function is called for each incoming packet, passing
            //! a PacketMeta object that plugins should modify in-place.
            //! The child class MUST override this method.
            //! Return true to proceed with normal delivery (dst_mask), or false
            //! to divert the packet for exclusive use by the plugin itself. In
            //! the latter case, the plugin MUST eventually call free_packet().
            virtual bool query(PacketMeta& pkt) = 0;

        protected:
            //! Associate this plugin object with the designated switch.
            //! Automatically calls plugin_add() and plugin_remove().
            explicit SwitchPlugin(satcat5::eth::SwitchCore* sw);
            ~SwitchPlugin() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the associated Switch object.
            satcat5::eth::SwitchCore* const m_switch;

        private:
            // Linked list for chaining multiple plugins.
            friend satcat5::util::ListCore;
            satcat5::eth::SwitchPlugin* m_next;
        };

        //! A shared-memory Ethernet switch based on the MultiBuffer class.
        //!
        //! \copydoc eth_switch.h
        //!
        //! This class implements packet delivery using plugins.  At minimum,
        //! users should add "eth::SwitchCache" or a similar plugin to provide
        //! automatic MAC-address association with each port.  Other plugins
        //! such as "eth::SwitchVlan" add optional features.
        //!
        //! Use this class directly to define custom memory allocation;
        //! otherwise users should use the "SwitchCoreStatic" class.
        //!
        //! Configuration methods mimic the eth::SwitchConfig API.
        class SwitchCore : public satcat5::io::MultiBuffer {
        public:
            //! Configure this object and link to the provided working buffer.
            SwitchCore(u8* buff, unsigned nbytes);

            //! Plugin management
            //! The switch maintains a linked list of regstered SwitchPlugin
            //! objects.  For each incoming packet, the switch calls query(...)
            //! on each registered plugin.  These methods are automatically
            //! called by the SwitchPlugin constructor and destructor.
            //!@{
            inline void plugin_add(satcat5::eth::SwitchPlugin* plugin)
                { m_plugins.add(plugin); }
            inline void plugin_remove(satcat5::eth::SwitchPlugin* plugin)
                { m_plugins.remove(plugin); }
            //!@}

            //! Port management: The maximum number of ports is limited by
            //! the size of SATCAT5_PMASK_TYPE (e.g., "u32" = up to 32 ports).
            //! Most SwitchPort objects are one-to-one, but some represent
            //! multiple; call "next_port_mask()" once for each logical port.
            //!@{
            inline satcat5::eth::SwitchPort* get_port(unsigned idx)
                { return m_ports.get_index(idx); }
            inline u32 port_count() const
                { return m_ports.len(); }
            SATCAT5_PMASK_TYPE next_port_mask();
            void port_add(satcat5::eth::SwitchPort* port);
            void port_remove(satcat5::eth::SwitchPort* port);
            void port_remove(const SATCAT5_PMASK_TYPE& mask);
            //!@}

            //! Enable or disable "promiscuous" flag on the specified port index.
            //! For as long as the flag is set, those port(s) will receive ALL
            //! switch traffic regardless of the destination address, etc.
            void set_promiscuous(unsigned port_idx, bool enable);
            //! Return a bit-mask identifying all "promiscuous" ports.
            inline SATCAT5_PMASK_TYPE get_promiscuous_mask() const {return m_prom_mask;}

            //! Configure EtherType filter for traffic reporting. (0 = Any type)
            void set_traffic_filter(u16 etype = 0);
            //! Return the current filter configuration. (0 = Any type)
            inline u16 get_traffic_filter() const {return m_stats_filter;}

            //! Query traffic statistics
            //! Count received frames that match the current traffic filter,
            //! starting from the previous call to get_traffic_count().
            //! \returns the number of matching frames.
            u32 get_traffic_count();

        protected:
            // Override the MultiBuffer::deliver() method.
            unsigned deliver(satcat5::io::MultiPacket* packet) override;

            // Internal event-handlers called from deliver(...).
            void process_stats(const satcat5::eth::SwitchPlugin::PacketMeta& meta);
            bool process_plugins(satcat5::eth::SwitchPlugin::PacketMeta& meta);
            unsigned deliver_switch(const satcat5::eth::SwitchPlugin::PacketMeta& meta);

            // Linked list of attached plugins and Ethernet ports.
            satcat5::util::List<satcat5::eth::SwitchPlugin> m_plugins;
            satcat5::util::List<satcat5::eth::SwitchPort> m_ports;

            // Other configuration variables.
            SATCAT5_PMASK_TYPE m_free_pmask;
            SATCAT5_PMASK_TYPE m_prom_mask;
            u16 m_stats_filter;
            u32 m_stats_count;
        };

        //! Wrapper for SwitchCore with a statically-allocated working buffer.
        template <unsigned BSIZE = 65536>
        class SwitchCoreStatic : public satcat5::eth::SwitchCore {
        public:
            SwitchCoreStatic() : SwitchCore(m_buff, BSIZE) {}
        protected:
            u8 m_buff[BSIZE];
        };

        //! Generic packetized I/O interface for use with SwitchCore.
        //!
        //! Each SwitchPort represents one logical port on the Ethernet switch.
        //! This class cannot be used directly; child objects define how the
        //! port behavior and how it attaches to the outside world.
        //!
        //! The object itself defines the io::Writeable interface for data
        //! entering the switch.  Data leaving the switch is accessed through
        //! the io::Readable interface of member variable "m_egress".
        //!
        //! See "port_adapter.h" for several commonly-used variants.
        class SwitchPort : public satcat5::io::MultiWriter {
        public:
            // Accept delivery of a given packet?
            bool accept(SATCAT5_PMASK_TYPE dst_mask, satcat5::io::MultiPacket* packet);

            // Miscellaneous accessors.
            inline bool consistency() const
                { return m_egress.consistency(); }
            inline unsigned port_index() const
                { return m_port_index; }
            inline SATCAT5_PMASK_TYPE port_mask() const
                { return m_port_mask; }
            inline satcat5::eth::VtagPolicy vlan_config() const
                { return m_vlan_cfg; }
            inline void vlan_config(const VtagPolicy& cfg)
                { m_vlan_cfg = cfg; }

            // Override write_finalize() to store metadata.
            // Children with multiple logical ports MUST override this method
            //  to indicate the correct specific source port index.
            bool write_finalize() override;

        protected:
            //! Link this port to the designated switch.
            //! Implement a child object to use this class.
            explicit SwitchPort(satcat5::eth::SwitchCore* sw);
            ~SwitchPort() SATCAT5_OPTIONAL_DTOR;

            //! Pointer to the associated switch.
            satcat5::eth::SwitchCore* const m_switch;

            //! Define this port's connection to the switch.
            //! Note: Usually m_port_mask contains a single '1' bit,
            //!  but some port objects represent several logical ports.
            //!  The "m_port_index" SHOULD NOT be used in such cases.
            //!@{
            SATCAT5_PMASK_TYPE m_port_mask;
            const unsigned m_port_index;
            //!@}

            //! Metadata required for VLAN functionality.
            satcat5::eth::VtagPolicy m_vlan_cfg;
            // TODO: Support for PAUSE commands?

            //! Access data leaving the switch through this port.
            //! The child class ensures the following:
            //!  * The child or its upstream processing MUST verify the FCS of
            //!    each incoming Ethernet frame before calling write_finalize().
            //!    (i.e., This function may be performed in software or HDL.)
            //!  * The ingress data stream MUST NOT include preambles or FCS.
            //!  * The ingress data SHOULD retain VLAN headers if applicable.
            //!  * The ingress data SHALL be written to this parent object.
            //!  * The egress data stream MAY include VLAN headers.
            //!    The child SHOULD add, remove, or reformat VLAN tags as needed.
            //!  * The egress data SHALL be read from the "m_egress" object.
            //!  * The child or its downstream processing MUST recalculate and
            //!    append an FCS to each outgoing frame.
            //!    (i.e., This function may be performed in software or HDL.)
            satcat5::io::MultiReaderPriority m_egress;

        private:
            // Linked list of other SwitchPort objects.
            friend satcat5::util::ListCore;
            satcat5::eth::SwitchPort* m_next;
        };
    }
}
