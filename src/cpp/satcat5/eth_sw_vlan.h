//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//! \file
//! IEEE802.1Q Virtual-LAN plugin for the software-defined Ethernet switch
//!
//! \details
//! Virtual-LAN (VLAN) is a protocol that allows software-defined control
//! of port-to-port connectivity, rate-limiting, and other functions on
//! an Ethernet LAN.  This file defines a plugin for implementing such
//! policies for any number of VLAN IDs (VIDs), numbered 0 to 4095.
//!
//! VLAN also allows packet prioritization, but this feature is not
//! currently supported by the software-defined switch.

#pragma once

#include <satcat5/eth_plugin.h>

namespace satcat5 {
    namespace eth {
        //! Port plugin for egress formatting of Virtual-LAN tags.
        //! \see eth_sw_vlan.h
        class SwitchVlanEgress : public satcat5::eth::PluginPort {
        public:
            //! Constructor links to a specified port.
            explicit SwitchVlanEgress(satcat5::eth::SwitchPort* port)
                : PluginPort(port) {}

            // Implement the required PluginPort API.
            void egress(PluginPacket& pkt) override;
        };

        //! Switch plugin for Virtual-LAN connectivity and rate-limiting rules.
        //!
        //! \see eth_sw_vlan.h
        //!
        //! Configuration methods mimic the eth::SwitchConfig API.
        //! (See also: SwitchVlan template, defined below.)
        class SwitchVlanInner
            : public satcat5::eth::PluginCore
            , public satcat5::poll::Timer
        {
        public:
            // Implement the required PluginCore API.
            void query(PluginPacket& pkt) override;

            //! Revert to default VLAN settings for all ports and VIDs.
            //! The "lockdown" setting controls whether rules default to
            //! permissive (i.e., allow by default with a short blocklist)
            //! or lockdown (the opposite).
            void vlan_reset(bool lockdown = false);
            //! Get allowed-connectivity port-mask for designated VID.
            SATCAT5_PMASK_TYPE vlan_get_mask(u16 vid);
            //! Limit the specified VID to the designated port(s).
            void vlan_set_mask(u16 vid, SATCAT5_PMASK_TYPE mask);
            //! Set a port's tag policy and other VLAN settings.
            void vlan_set_port(const VtagPolicy& cfg);
            //! Port should join VLAN, updating #vlan_get_mask.
            void vlan_join(u16 vid, unsigned port);
            //! Port should leave VLAN, updating #vlan_get_mask.
            void vlan_leave(u16 vid, unsigned port);
            //! Set rate-limiting options for the designated VID.
            void vlan_set_rate(u16 vid, const satcat5::eth::VlanRate& cfg);

        protected:
            // Data structure for the internal configuration tables.
            struct VlanPolicy {
                satcat5::eth::VlanRate vrate;   // Rate-limiter policy
                SATCAT5_PMASK_TYPE pmask;       // Connected ports mask
                u32 tcount;                     // Token-bucket counter
            };

            // Configure this object and link to the working buffer.
            SwitchVlanInner(
                satcat5::eth::SwitchCore* sw,
                VlanPolicy* vptr, unsigned vmax, bool lockdown);

            // Timer-event handler for updating rate-limiter state.
            void timer_event() override;

            // Store VLAN policy and rate-limiter state for each VID.
            VlanPolicy* const m_policy;         // Table of VLAN states
            const unsigned m_vmax;              // Supported VIDs = [1..N]
        };

        //! Wrapper for SwitchVlanInner with statically-allocated working memory.
        //!
        //! \see eth_sw_vlan.h
        //!
        //! The maximum VID is adjustable to save memory, the default
        //! setting VMAX = 4095 allows all possible VLAN IDs [1..4095].
        template <unsigned VMAX = 4095>
        class SwitchVlan : public satcat5::eth::SwitchVlanInner
        {
        public:
            //! Create this plugin and link it to the designated switch.
            //! \param sw Links this plugin to an Ethernet switch object.
            //! \param lockdown Sets the default configuration to allow-all or allow-none.
            explicit SwitchVlan(satcat5::eth::SwitchCore* sw, bool lockdown = false)
                : SwitchVlanInner(sw, m_vtable, VMAX, lockdown) {}
        protected:
            satcat5::eth::SwitchVlanInner::VlanPolicy m_vtable[VMAX];
        };
    }
}
