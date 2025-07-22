//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Basic Network Address Translation (NAT) for the IPv4 router.

#pragma once

#include <satcat5/eth_plugin.h>
#include <satcat5/ip_core.h>

namespace satcat5 {
    namespace router2 {
        //! Basic Network Address Translation (NAT) for the IPv4 router.
        //! This block implements "Basic NAT" as defined in IETF RFC-3022:
        //!  https://www.rfc-editor.org/rfc/rfc3022
        //! Acting as a plugin, the BasicNat block attaches to a router port
        //! and translates applicable IP addresses in the ARP and IPv4 headers.
        //! It requires that the internal and external address ranges are equal
        //! in size, allowing trivial one-to-one mapping of subnet addresses.
        //! This is the software analogue of the "router2_basic_nat" VHDL block.
        class BasicNat : public satcat5::eth::PluginPort {
        public:
            //! Attach this object to the designated router port.
            //! Default mode is simple passthrough of all addresses.
            explicit BasicNat(satcat5::eth::SwitchPort* port);

            //! Change the NAT configuration.
            //! \param ip_ext External/egress subnet.
            //! \param ip_int Internal/ingress subnet.
            //! \return True if the new configuration is accepted.
            bool config(
                const satcat5::ip::Subnet& ip_ext,
                const satcat5::ip::Subnet& ip_int);

        protected:
            // Override plugin callbacks.
            void ingress(satcat5::eth::PluginPacket& pkt) override;
            void egress(satcat5::eth::PluginPacket& pkt) override;

            // NAT configuration.
            satcat5::ip::Subnet m_ext, m_int;
        };
    }
}
