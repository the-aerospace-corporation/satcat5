//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Handler for ConfigBus network commands

#pragma once

#include <satcat5/net_core.h>

namespace satcat5 {
    namespace net {
        //! Handler for ConfigBus network commands.
        //! This protocol allows a local ConfigBus to be commanded remotely
        //! over Ethernet or UDP, depending on how it is instantiated.
        //!
        //! This server is equivalent to the ConfigBus host defined in
        //! "cfgbus_host_eth.vhd", but this server implemented in software.
        //! This can be used to implement mixed local/remote control, provide
        //! diagnostics, etc.  The local ConfigBus can be shared between local
        //! and remote operation.
        //!
        //! The driver only supports memory-mapped local ConfigBus (i.e., an
        //! instance of the cfg::ConfigBusMmap class). Support for masked writes
        //! is optional, and disabled by default. Set
        //! `SATCAT5_PROTOCFG_SUPPORT_WRMASK = 1` to enable this feature.
        //!
        //! Refer to cfgbus_host_eth.vhd for details of the packet format.
        class ProtoConfig : public satcat5::net::Protocol {
        protected:
            //! Only children can access constructor/destructor.
            //! @{
            ProtoConfig(
                satcat5::cfg::ConfigBusMmap* cfg,
                satcat5::net::Dispatch* iface,
                const satcat5::net::Type& cmd,
                const satcat5::net::Type& ack,
                unsigned max_devices);
            ~ProtoConfig() SATCAT5_OPTIONAL_DTOR;
            //! @}

            //! Event handler to process incoming frames and respond.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Member variables
            satcat5::cfg::ConfigBusMmap* const m_cfg;   //!< ConfigBus instance.
            satcat5::net::Dispatch* const m_iface;      //!< Registered iface.
            satcat5::net::Type const m_acktype;         //!< Type for replies.
            const unsigned m_max_devices;               //!< Max # of devices.
        };
    }

    namespace eth {
        //! Thin wrapper for access via ethernet frames through eth::Dispatch.
        //! \copydoc satcat5::net::ProtoConfig
        class ProtoConfig final : public satcat5::net::ProtoConfig {
        public:
            ProtoConfig(
                satcat5::eth::Dispatch* iface,
                satcat5::cfg::ConfigBusMmap* cfg,
                unsigned max_devices = satcat5::cfg::DEVS_PER_CFGBUS);
        };
    }

    namespace udp {
        //! Thin wrapper for access via UDP/IP through udp::Dispatch.
        //! \copydoc satcat5::net::ProtoConfig
        class ProtoConfig final : public satcat5::net::ProtoConfig {
        public:
            ProtoConfig(
                satcat5::udp::Dispatch* iface,
                satcat5::cfg::ConfigBusMmap* cfg,
                unsigned max_devices = satcat5::cfg::DEVS_PER_CFGBUS);
        };
    }
}
