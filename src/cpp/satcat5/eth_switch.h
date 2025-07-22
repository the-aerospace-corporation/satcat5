//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Software-defined Ethernet switch.
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
//! destination(s). \see eth_sw_plugin.h.
//!
//! Precision Time Protocol (PTP) is not currently supported.

#pragma once

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

        //! Maximum number of switch ports, based on SATCAT5_PMASK_TYPE.
        //! The maximum number of ports is limited by the size of bit-mask
        //! SATCAT5_PMASK_TYPE (e.g., "u32" = up to 32 ports).
        constexpr unsigned PMASK_SIZE()
            { return 8 * sizeof(SATCAT5_PMASK_TYPE); }

        //! Define the API for packet-logging callbacks from eth::SwitchCore.
        //! This class is the parent for SwitchLogStats and SwitchLogWriter.
        class SwitchLogHandler {
        public:
            //! This method is called exactly once for each incoming packet.
            //! The child class MUST override this method.
            virtual void log_packet(const satcat5::eth::SwitchLogMessage& msg) = 0;

        protected:
            //! Constructor is accessible only to children.
            constexpr SwitchLogHandler() : m_next(nullptr) {}

        private:
            //! Linked list of other handler objects.
            friend satcat5::util::ListCore;
            satcat5::eth::SwitchLogHandler* m_next;
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

            //! Fetch a SwitchPort object by port-index.
            //! Ports are numbered in the order they are created. \see port_add.
            //! The maximum number of ports is given by eth::PMASK_SIZE.
            inline satcat5::eth::SwitchPort* get_port(unsigned idx)
                { return m_ports.get_index(idx); }

            //! Get next available bit-mask for new SwitchPort objects.
            //! Most SwitchPort objects are one-to-one, but some represent
            //! multiple; call "next_port_mask()" once for each logical port.
            SATCAT5_PMASK_TYPE next_port_mask();

            //! Get the number of attached ports.
            inline u32 port_count() const
                { return m_ports.len(); }

            //! Optional debug interface gets a carbon copy of each packet.
            inline void set_debug(satcat5::io::Writeable* debug)
                { m_debug = debug; }

            //! Optional logging interface records a summary of every packet.
            //! Function and formatting are the same as "mac_log_core.vhd".
            inline void add_log(satcat5::eth::SwitchLogHandler* log)
                { m_pktlogs.add(log); }
            inline void remove_log(satcat5::eth::SwitchLogHandler* log)
                { m_pktlogs.remove(log); }

            //! Enable or disable "promiscuous" flag on the specified port index.
            //! For as long as the flag is set, those port(s) will receive ALL
            //! switch traffic regardless of the destination address, etc.
            void set_promiscuous(unsigned port_idx, bool enable);
            //! Return a bit-mask identifying all "promiscuous" ports.
            inline SATCAT5_PMASK_TYPE get_promiscuous_mask() const
                { return m_prom_mask; }

            //! Configure EtherType filter for traffic reporting. (0 = Any type)
            void set_traffic_filter(u16 etype = 0);
            //! Return the current filter configuration. (0 = Any type)
            inline u16 get_traffic_filter() const
                { return m_stats_filter; }

            //! Query traffic statistics
            //! Count received frames that match the current traffic filter,
            //! starting from the previous call to get_traffic_count().
            //! \returns the number of matching frames.
            u32 get_traffic_count();

            //! Carbon-copy a packet to the debug port, if it is enabled.
            //! Reserved for use by SwitchCore, SwitchPort, or their children.
            void debug_if(const satcat5::eth::PluginPacket& pkt, unsigned mask) const;

            //! If logging is enabled, record the outcome for this packet.
            void debug_log(
                const satcat5::io::MultiPacket* pkt,
                u8 reason, SATCAT5_PMASK_TYPE dst = 0) const;

        protected:
            //! Override the MultiBuffer::deliver() method.
            unsigned deliver(satcat5::io::MultiPacket* packet) override;

            //! Internal event-handlers called from deliver(...).
            //!@{
            void process_stats(const satcat5::eth::PluginPacket& pkt);
            satcat5::util::optional<unsigned> process_plugins(satcat5::eth::PluginPacket& pkt);
            satcat5::util::optional<unsigned> pkt_has_dropped(satcat5::eth::PluginPacket& pkt);
            unsigned deliver_switch(const satcat5::eth::PluginPacket& pkt);
            //!@}

            //! Plugin management for use by eth::PluginCore constructor.
            //! For each incoming packet, call each plugin's query(...) method.
            //!@{
            friend satcat5::eth::PluginCore;
            void plugin_add(satcat5::eth::PluginCore* plugin);
            void plugin_remove(satcat5::eth::PluginCore* plugin);
            //!@}

            //! Port management methods used by eth::SwitchPort constructor.
            //!@{
            friend satcat5::eth::SwitchPort;
            void port_add(satcat5::eth::SwitchPort* port);
            void port_remove(satcat5::eth::SwitchPort* port);
            void port_remove(const SATCAT5_PMASK_TYPE& mask);
            //!@}

            //! Linked list of attached plugins.
            satcat5::util::List<satcat5::eth::PluginCore> m_plugins;

            //! Linked list of attached Ethernet ports.
            satcat5::util::List<satcat5::eth::SwitchPort> m_ports;

            // Other configuration variables.
            satcat5::io::Writeable* m_debug;
            satcat5::util::List<satcat5::eth::SwitchLogHandler> m_pktlogs;
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
        //! Ingress data (i.e., data entering the port on its way to the
        //! SwitchCore) is written directly to the SwitchPort object.
        //! The SwitchPort automatically handles PluginPort egress events.
        //!
        //! Egress data (i.e., data leaving the SwitchCore) and associated
        //! plugin events are typically handled by the SwitchPort itself, by
        //! providing an io::Writeable to the constructor where processed
        //! egress data should be copied. If the child object prefers to take
        //! both responsibilities, it may instead provide a null pointer. In
        //! the latter case, the child reads directly from `m_egress`.
        //!
        //! Formatting for the ingress and egress streams is as follows:
        //!  * The child or its upstream processing MUST verify the FCS of
        //!    each incoming Ethernet frame before calling write_finalize().
        //!    (i.e., This function may be performed in software or HDL.)
        //!  * The ingress data stream MUST NOT include preambles or FCS.
        //!  * The ingress data SHOULD retain VLAN headers if applicable.
        //!  * The ingress data SHALL be written to this parent object.
        //!  * The egress data stream MAY include VLAN headers.
        //!  * The child SHOULD add, remove, or reformat VLAN tags as needed.
        //!    \see eth::SwitchVlanEgress, port::VlanAdapter for examples.
        //!  * The child or its downstream processing MUST recalculate and
        //!    append an FCS to each outgoing frame.
        //!    (i.e., This function may be performed in software or HDL.)
        //!
        //! For a complete example, \see port::MailAdapter, port::SlipAdapter.
        class SwitchPort
            : public satcat5::io::EventListener
            , public satcat5::io::MultiWriter
        {
        public:
            //! Accept delivery of a given packet?
            bool accept(SATCAT5_PMASK_TYPE dst_mask, satcat5::io::MultiPacket* packet);

            //! Plugin management.
            //! The switch maintains a linked list of regstered PluginCore
            //! objects.  For each incoming packet, the switch calls query(...)
            //! on each registered plugin.  These methods are automatically
            //! called by the PluginCore constructor and destructor.
            //!@{
            void plugin_add(satcat5::eth::PluginPort* plugin);
            void plugin_remove(satcat5::eth::PluginPort* plugin);
            //!@}

            //! Issue notifications to all attached plugins.
            //!@{
            void plugin_ingress(satcat5::eth::PluginPacket& pkt);
            void plugin_egress(satcat5::eth::PluginPacket& pkt);
            //!@}

            //! Internal consistency check, mainly used for unit testing.
            inline bool consistency() const
                { return m_egress.consistency(); }

            //! Source for data leaving the switch through this port.
            inline satcat5::io::MultiReaderPriority* get_egress()
                { return &m_egress; }

            //! Pointer to the parent SwitchCore object.
            inline satcat5::eth::SwitchCore* get_switch()
                { return m_switch; }

            //! Enable or disable this port, pausing data-flow.
            inline void port_enable(bool enable)
                { m_egress.set_port_enable(enable); }

            //! Is this port currently enabled?
            inline bool port_enabled() const
                { return m_egress.get_port_enable(); }

            //! Discard all pending ingress and egress data.
            inline void port_flush()
                { write_abort(); m_egress.flush(); }

            //! Port number for attachment to the parent SwitchCore.
            //! Note: Does not apply to multi-port API, \see router2::Offload.
            inline unsigned port_index() const
                { return m_port_index; }

            //! Bit-mask for all port(s) associated with this interface.
            inline SATCAT5_PMASK_TYPE port_mask() const
                { return m_port_mask; }

            //! Set egress data callback, mainly used for unit testing.
            inline void set_callback(satcat5::io::EventListener* cb)
                { m_egress.set_callback(cb); }

            //! Return this port's VLAN configuration.
            inline satcat5::eth::VtagPolicy vlan_config() const
                { return m_vlan_cfg; }

            //! Set this port's VLAN configuration.
            inline void vlan_config(const VtagPolicy& cfg)
                { m_vlan_cfg = cfg; }

            //! Override write_abort() to allow additional error handling.
            //! For example, logging of dropped packets. \see `eth_sw_log.h`.
            void write_abort() override;

            //! Override write_finalize() to store metadata.
            //! Children with multiple logical ports MUST override this method
            //!  to indicate the correct specific source port index.
            bool write_finalize() override;

        protected:
            //! Link this port to the designated switch.
            //! Implement a child object to use this class.
            explicit SwitchPort(
                satcat5::eth::SwitchCore* sw,
                satcat5::io::Writeable* dst);
            ~SwitchPort() SATCAT5_OPTIONAL_DTOR;

            // Override for EventListener callback.
            void data_rcvd(satcat5::io::Readable* src) override;

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

            // Egress pipeline.
            satcat5::io::MultiReaderPriority m_egress;  //!< Egress data source.
            satcat5::io::Writeable* const m_eg_dst;     //!< Egress destination.
            bool m_eg_hdr;                              //!< Frame header copied?

            //! Linked list of attached plugins.
            satcat5::util::List<satcat5::eth::PluginPort> m_plugins;

        private:
            // Linked list of other SwitchPort objects.
            friend satcat5::util::ListCore;
            satcat5::eth::SwitchPort* m_next;
        };
    }
}
