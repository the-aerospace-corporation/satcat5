//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
//
// Recovery Subsystem


#pragma once

#include <satcat5/eth_checksum.h>
#include <satcat5/eth_header.h>
#include <satcat5/eth_plugin.h>
#include <satcat5/eth_switch.h>
#include <satcat5/io_core.h>
#include <satcat5/pkt_buffer.h>
#include <satcat5/switch_cfg.h>

#define SATCAT5_RECOVERY_SWITCH_BUFFER_SIZE 2048

namespace satcat5 {
    namespace port {
        //! Intercepts all packets with the ETYPE_RECOVERY_IN ethertype and puts them into
        //! a buffer that can be read using the Readable interface returned by read().
        class RecoveryIngress : public satcat5::eth::PluginCore {
        public:
            //! Ingress interface attaches to an Ethernet switch.
            explicit RecoveryIngress(satcat5::eth::SwitchCore* sw);

            //! Return the buffer's Readable interface.
            inline satcat5::io::Readable* read()
                { return &m_recov_in_buff; }

        protected:
            // Plugin Query Callback
            void query(satcat5::eth::PluginPacket& packet) override;
            satcat5::io::PacketBuffer m_recov_in_buff;
            u8 m_raw_buff_in[SATCAT5_RECOVERY_SWITCH_BUFFER_SIZE];
        };

        //! MultiWriter that slips packets written to it into the
        //! port's egress buffer.
        class RecoveryEgress : public satcat5::io::MultiWriter {
        public:
            //! Egress interface attaches to an Ethernet port.
            explicit RecoveryEgress(satcat5::eth::SwitchPort* port);

            //! Override write_finalize so it calls write_bypass instead.
            bool write_finalize() override;

        protected:
            satcat5::io::MultiReader* const m_egress;
        };
    }
}