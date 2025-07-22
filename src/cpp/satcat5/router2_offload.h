//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Offload port for gateware-accelerated IPv4 routers

#pragma once

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/router2_dispatch.h>

namespace satcat5 {
    namespace router2 {
        // Define policy configuration flags matching "router2_gateway.vhd".
        // Setting a policy mask blocks packets of the specified type.
        constexpr u32
            RULE_ALL        = (0xFFFF0000u),    //!< Bit-mask for all rule flags.
            RULE_LCL_BCAST  = (1u << 21),       //!< Forward IPv4 broadcast to router CPU?
            RULE_NOIP_ALL   = (1u << 20),       //!< Allow non-IPv4 packets of any kind?
            RULE_NOIP_BCAST = (1u << 19),       //!< Allow non-IPv4 broadcast packets?
            RULE_IPV4_MCAST = (1u << 18),       //!< Allow IPv4 multicast?
            RULE_IPV4_BCAST = (1u << 17),       //!< Allow IPv4 broadcast?
            RULE_BAD_DMAC   = (1u << 16);       //!< Allow non-matching destination MAC?

        //! Offload port for gateware-accelerated IPv4 routers
        //!
        //! When the router2::Dispatch class is used in conjunction with the VHDL
        //! "router2_core" block, the VHDL handles bulk traffic for gateware-defined
        //! ports but offloads complex edge-cases to the software.  This block acts
        //! as the gateware/software bridge for that offload function.
        class Offload
            : protected satcat5::cfg::Interrupt
            , protected satcat5::io::MultiWriter
        {
        public:
            //! Constructor sets the number of associated hardware ports.
            //! Always create this object BEFORE registering software ports.
            Offload(
                satcat5::cfg::ConfigBusMmap* cfg, unsigned devaddr,
                satcat5::router2::Dispatch* router, unsigned hw_ports);
            ~Offload() SATCAT5_OPTIONAL_DTOR;

            //! Set specific router policy flags.
            void rule_allow(u32 mask);
            //! Clear specific router policy flags.
            void rule_block(u32 mask);
            //! Enable or disable zero-padding.
            inline void rule_zpad(bool enable)
                { m_zero_pad = enable; }

            //! Deliver a given packet to the hardware queue.
            void deliver(const satcat5::eth::PluginPacket& meta);

            //! Get packet-logging register. \see eth_sw_log.h.
            //! Do not call this method unless LOG_CFGBUS is enabled.
            inline satcat5::cfg::Register get_log_register() const
                { return m_pktlog; }

            //! Reload router IP address and MAC address.
            //! The router2::Dispatch class calls this after any address change.
            //! Return value is for internal use only and should be ignored.
            u32 reconfigure();

            //! Mask indicating hardware-defined ports in the shutdown state.
            inline u32 link_shdn_hw()
                { return m_ctrl->port_shdn; }
            //! Mask indicating software-defined ports in the shutdown state.
            inline SATCAT5_PMASK_TYPE link_shdn_sw()
                { return SATCAT5_PMASK_TYPE(link_shdn_hw()) << m_port_index; }

            //! Convert hardware port index to a software port-index.
            inline unsigned port_index(unsigned hw_idx) const
                { return m_port_index + hw_idx; }
            //! Convert hardware port index to a software port-mask.
            inline SATCAT5_PMASK_TYPE port_mask(unsigned hw_idx) const
                { return satcat5::eth::idx2mask(port_index(hw_idx)); }
            //! Return a port-mask containing all connected ports.
            inline SATCAT5_PMASK_TYPE port_mask_all() const
                { return m_port_mask; }

        protected:
            // Internal event-handlers.
            void irq_event() override;

            // Hardware register map:
            // TODO: Provide accessors for some of these hardware registers?
            struct ctrl_reg {
                u8 txrx_buff[1600];                 // Reg 0-399
                u32 rx_rsvd[89];                    // Reg 400-488
                volatile u32 pkt_log;               // Reg 489
                volatile u32 vlan_vid;              // Reg 490
                volatile u32 vlan_mask;             // Reg 491
                volatile u32 vlan_rate;             // Reg 492
                volatile u32 pkt_count;             // Reg 493
                volatile u32 port_shdn;             // Reg 494
                volatile u32 info;                  // Reg 495
                volatile u32 ecn_red;               // Reg 496
                volatile u32 nat_ctrl;              // Reg 497
                volatile u32 gateway;               // Reg 498
                volatile u32 tx_mask;               // Reg 499
                volatile u32 tx_ctrl;               // Reg 500
                volatile u32 ptp_2step;             // Reg 501
                volatile u32 port_count;            // Reg 502
                volatile u32 data_width;            // Reg 503
                volatile u32 core_clock;            // Reg 504
                volatile u32 table_size;            // Reg 505
                volatile u32 noip_data;             // Reg 506
                volatile u32 noip_ctrl;             // Reg 507
                volatile u32 cidr_data;             // Reg 508
                volatile u32 cidr_ctrl;             // Reg 509
                volatile u32 rx_irq;                // Reg 510
                volatile u32 rx_ctrl;               // Reg 511
                u32 port_cfg[512];                  // Reg 512-1023
            };
            ctrl_reg* const m_ctrl;

            // Connection to the parent object.
            satcat5::router2::Dispatch* const m_router;
            satcat5::cfg::Register m_pktlog;        // Packet-logging register
            const unsigned m_port_index;            // Index of hardware port #0.
            bool m_zero_pad;                        // Enable zero-padding?
            SATCAT5_PMASK_TYPE m_port_mask;         // Mask of all associated ports.
            u32 m_policy;                           // Block specific packet types?
        };
    }
}
