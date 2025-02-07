//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! Top-level classes for the the IPv4 router
//!
//! \details
//! The classes defined here are the preferred top-level container for
//! the entire IPv4 router. It instantiates all required subsystems:
//!  * A local IP/UDP stack for ARP and ICMP handling.
//!  * router2::Dispatch for buffering and bulk packet handling.
//!  * router2::DeferFwd for deferred forwarding to unknown MAC addresses.
//!  * router2::Offload for hardware-accerated HDL/SW interfacing.
//!  * router2::Table for synchronizing HDL/SW routing-table contents.
//!
//! Variants are available for an all-software solution and a hybrid solution:
//!  * router2::StackCommon is the shared parent for other variants.
//!  * router2::StackGateware creates a gateware-only or hybrid router.
//!  * router2::StackSoftware creates a software-only router.
//!
//! As with the ip::Stack class, these classes connect various building blocks
//! but have no logic beyond initialization.  The intent is a monolithic
//! turnkey system suitable for the most common use-cases (especially for
//! new users) that doubles as a checklist for advanced or specialized cases.
//!
//! Software ports and IP routing tables MUST be configured manually after
//! instantiating any of the router variants.  See "ip_table.h".

#pragma once

#include <satcat5/ip_stack.h>
#include <satcat5/router2_deferfwd.h>
#include <satcat5/router2_dispatch.h>
#include <satcat5/router2_offload.h>
#include <satcat5/router2_table.h>

namespace satcat5 {
    namespace router2 {
        //! Common parent for StackGateware and StackSoftware.
        //!
        //! \see router2_stack.h
        //!
        //! This class defines shared functions, but cannot be used on its
        //! own. Users should instantiate StackGateware or StackSoftware.
        class StackCommon {
        public:
            // Enable or disable specific ports.
            inline void port_enable(const SATCAT5_PMASK_TYPE& mask)
                { m_dispatch.port_enable(mask); }
            inline void port_disable(const SATCAT5_PMASK_TYPE& mask)
                { m_dispatch.port_disable(mask); }

            // Other accessors.
            inline satcat5::eth::Dispatch* eth()
                { return &m_eth; }
            inline satcat5::ip::Dispatch* ip()
                { return &m_ip; }
            inline satcat5::ip::Addr ipaddr() const
                { return m_ip.ipaddr(); }
            inline satcat5::eth::MacAddr macaddr() const
                { return m_eth.macaddr(); }
            inline satcat5::router2::Dispatch* router()
                { return &m_dispatch; }
            inline satcat5::ip::Table* table()
                { return m_ip.table(); }
            inline satcat5::udp::Dispatch* udp()
                { return &m_udp; }
            inline void set_ipaddr(const satcat5::ip::Addr& addr)
                { return m_dispatch.set_ipaddr(addr); }

        protected:
            //! Constructor should only be called by the child class.
            StackCommon(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                satcat5::ip::Table* table,              // Routing table
                u8* buff, unsigned nbytes)              // Internal working buffer
                : m_dispatch(buff, nbytes)
                , m_fwd(&m_dispatch)
                , m_eth(local_mac, m_dispatch.get_local_wr(), m_dispatch.get_local_rd())
                , m_ip(local_ip, &m_eth, table)
                , m_udp(&m_ip)
            {
                m_dispatch.set_defer_fwd(&m_fwd);
                m_dispatch.set_local_iface(&m_ip);
            }

            //! Destructor should only be called by the child class.
            ~StackCommon() {}

            // Router logic.
            satcat5::router2::Dispatch m_dispatch;      // Incoming packet processing
            satcat5::router2::DeferFwdStatic<> m_fwd;   // Deferred-fowarding buffer

            // Internal IP stack.
            satcat5::eth::Dispatch      m_eth;          // Ethernet layer
            satcat5::ip::Dispatch       m_ip;           // IPv4 and ICMP layer
            satcat5::udp::Dispatch      m_udp;          // UDP layer
        };

        //! Router implementation where some or all ports are gateware.
        //!
        //! \see router2_stack.h
        //!
        //! Use this class to control an FPGA "router2_core.vhd" block,
        //! and optionally link additional software-defined ports.
        //! (i.e., A full-FPGA router or a hybrid FPGA/software router.)
        template <unsigned BSIZE = 8192>
        class StackGateware : public satcat5::router2::StackCommon {
        public:
            StackGateware(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip,      // Local IP address
                satcat5::cfg::ConfigBusMmap* cfg,       // ConfigBus interface
                unsigned devaddr,                       // ConfigBus address
                unsigned hw_ports)                      // Number of hardware ports
                : StackCommon(local_mac, local_ip, &m_table, m_buff, BSIZE)
                , m_offload(cfg, devaddr, &m_dispatch, hw_ports)
                , m_table(cfg, devaddr)
            {
                m_dispatch.set_offload(&m_offload);
            }

            // Additional accessors.
            inline satcat5::router2::Offload* offload()
                { return &m_offload; }

        protected:
            // Internal variables.
            satcat5::router2::Offload m_offload;
            satcat5::router2::Table m_table;
            u8 m_buff[BSIZE];
        };

        //! Router implementation where all ports are software-defined.
        //!
        //! \see router2_stack.h
        //!
        //! Use this class for a pure-software router that does not use
        //! FPGA components (i.e., no integration with "router2_core.vhd").
        template <unsigned BSIZE = 16384>
        class StackSoftware : public satcat5::router2::StackCommon {
        public:
            StackSoftware(
                const satcat5::eth::MacAddr& local_mac, // Local MAC address
                const satcat5::ip::Addr& local_ip)      // Local IP address
                : StackCommon(local_mac, local_ip, &m_table, m_buff, BSIZE)
                , m_table()
                {}  // Nothing else to initialize.

        protected:
            // Internal variables.
            satcat5::ip::Table m_table;
            u8 m_buff[BSIZE];
        };
    }
}
