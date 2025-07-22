//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Incoming packet dispatch for the IPv4 router

#pragma once

#include <satcat5/eth_switch.h>
#include <satcat5/ip_core.h>
#include <satcat5/port_adapter.h>

namespace satcat5 {
    namespace router2 {
        //! Packet-processing pipeline for the IPv4 router.
        //!
        //! The router2::Dispatch class is the core of the IPv4 router, parsing
        //! each incoming packet, then deciding the appropriate action.
        //!
        //! The Dispatch class supports up to 32 ports in total.  It may operate
        //! with a mixture of software-controlled ports and hardware-accelerated
        //! ports.  Software-controlled ports use the Dispatch class for all
        //! packet processing and are attached using any of the port::Adapter
        //! classes (see port_adapter.h), using the same API as eth::SwitchCore.
        //! Hardware-accelerated ports use HDL for routine routing, but offload
        //! rare-but-complex operations to to this class through router2::Offload.
        //!
        //! The implementation uses eth::SwitchCore as a parent class for buffer
        //! and I/O handling, allowing use of many of the same plugin and port
        //! interface objects. However, it completely replaces the packet delivery
        //! logic to implement the IPv4 router functionality.
        //!
        //! For an all-in-one turnkey solution that instantiates router2::Dispatch
        //! along with all required helper objects, see "router2_stack.h".
        class Dispatch : public satcat5::eth::SwitchCore {
        public:
            //! Configure this object and link to the working buffer.
            Dispatch(u8* buff, unsigned nbytes);

            //! Link this dispatch unit to other parts of the IP/UDP stack.
            //! These methods must be called after the constructor, to break
            //! the chicken-and-egg problem for various helper objects.
            //!@{
            inline satcat5::io::Readable* get_local_rd()
                { return &m_local_port; }
            inline satcat5::io::Writeable* get_local_wr()
                { return &m_local_port; }
            inline void set_defer_fwd(satcat5::router2::DeferFwd* fwd)
                { m_defer_fwd = fwd; }
            inline void set_local_iface(satcat5::ip::Dispatch* iface)
                { m_local_iface = iface; }
            inline void set_offload(satcat5::router2::Offload* iface)
                { m_offload = iface; }
            //!@}

            //! Enable or disable specific port(s).
            //!@{
            inline void port_enable(const SATCAT5_PMASK_TYPE& mask)
                { m_port_shdn &= ~mask; }
            inline void port_disable(const SATCAT5_PMASK_TYPE& mask)
                { m_port_shdn |= mask; }
            //!@}

            // Other accessors.
            inline satcat5::ip::Dispatch* iface() const
                { return m_local_iface; }
            satcat5::ip::Addr ipaddr() const;
            satcat5::eth::MacAddr macaddr() const;
            void set_ipaddr(const satcat5::ip::Addr& addr);

        protected:
            // Deferred forwarding needs privileged access.
            friend satcat5::router2::DeferFwd;

            // Override the SwitchCore::deliver() method.
            unsigned deliver(satcat5::io::MultiPacket* packet) override;

            // Internal event-handlers called from deliver(...).
            void adjust_mac(
                const satcat5::eth::MacAddr& dst,
                satcat5::eth::PluginPacket& meta);
            bool decrement_ttl(
                satcat5::eth::PluginPacket& meta);
            unsigned process_gateway(
                satcat5::eth::PluginPacket& meta);
            unsigned deliver_arp(
                satcat5::eth::PluginPacket& meta);
            unsigned deliver_defer(
                const satcat5::eth::PluginPacket& meta);
            unsigned deliver_local(
                const satcat5::eth::PluginPacket& meta);
            unsigned deliver_offload(
                const satcat5::eth::PluginPacket& meta);
            bool icmp_reply(
                u16 errtyp, u32 arg,
                const satcat5::eth::PluginPacket& meta);
            bool is_from_offload(
                const satcat5::eth::PluginPacket& meta);
            SATCAT5_PMASK_TYPE link_up_mask();

            // Internal state:
            satcat5::router2::DeferFwd* m_defer_fwd;
            satcat5::port::NullAdapter m_local_port;
            satcat5::ip::Dispatch* m_local_iface;
            satcat5::router2::Offload* m_offload;
            SATCAT5_PMASK_TYPE m_port_shdn;
        };
    }
}
