//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Handler for ConfigBus network commands
//
// This protocol allows a local ConfigBus to be commanded remotely
// over Ethernet or UDP, depending on how it is instantiated.
//
// It is equivalent to the one in cfgbus_host_eth.vhd, but implemented in
// software.  This can be used to implement mixed local/remote control,
// provide diagnostics, etc.
//
// The driver only supports memory-mapped local ConfigBus (i.e., an instance
// of the cfg::ConfigBusMmap class). Support for masked writes is optional,
// and disabled by default. Set SATCAT5_PROTOCFG_SUPPORT_WRMASK = 1 to enable
// this feature.
//
// Refer to cfgbus_host_eth.vhd for details of the packet format.
//

#pragma once

#include <satcat5/net_core.h>

namespace satcat5 {
    namespace net {
        // Generic version requires a wrapper to be used.
        class ProtoConfig : public satcat5::net::Protocol {
        protected:
            // Only children can safely access constructor/destructor.
            ProtoConfig(
                satcat5::cfg::ConfigBusMmap* cfg,
                satcat5::net::Dispatch* iface,
                const satcat5::net::Type& cmd,
                const satcat5::net::Type& ack,
                unsigned max_devices);
            ~ProtoConfig() SATCAT5_OPTIONAL_DTOR;

            // Event handler for incoming frames.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            satcat5::cfg::ConfigBusMmap* const m_cfg;
            satcat5::net::Dispatch* const m_iface;
            satcat5::net::Type const m_acktype;
            const unsigned m_max_devices;
        };
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        class ProtoConfig final : public satcat5::net::ProtoConfig {
        public:
            ProtoConfig(
                satcat5::eth::Dispatch* iface,
                satcat5::cfg::ConfigBusMmap* cfg,
                unsigned max_devices = satcat5::cfg::DEVS_PER_CFGBUS);
        };
    }

    namespace udp {
        class ProtoConfig final : public satcat5::net::ProtoConfig {
        public:
            ProtoConfig(
                satcat5::udp::Dispatch* iface,
                satcat5::cfg::ConfigBusMmap* cfg,
                unsigned max_devices = satcat5::cfg::DEVS_PER_CFGBUS);
        };
    }
}
