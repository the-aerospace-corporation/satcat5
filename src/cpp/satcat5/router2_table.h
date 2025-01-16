//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Internet Protocol v4 (IPv4) forwarding table with mirroring

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/ip_table.h>

namespace satcat5 {
    namespace router2 {
        //! IPv4 forwarding table with hardware mirroring.
        //!
        //! This thin-wrapper for the ip::Table class overrides specific
        //! methods to allow routing-table contents to be mirrored to the
        //! FPGA's CIDR table ("router2_table.vhd").
        //!
        //! \ref satcat5::router2::StackGateware "Gateware and hybrid routers"
        //! must use this block instead of of the basic ip::Table class.
        class Table : public satcat5::ip::Table {
        public:
            //! Link this object to its hardware counterpart.
            Table(satcat5::cfg::ConfigBus* cfg, unsigned devaddr);

            //! Read the size of the hardware table.
            unsigned table_size();

        protected:
            // Override the required parent methods..
            bool route_wrdef(const satcat5::ip::Route& route) override;
            bool route_write(unsigned idx, const satcat5::ip::Route& route) override;

            // Internal helper method.
            bool route_load(u32 opcode, const satcat5::ip::Route& route);

            // ConfigBus register interface.
            satcat5::cfg::Register m_cfg;
        };
    }
}
