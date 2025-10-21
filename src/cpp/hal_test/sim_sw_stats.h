//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus emulator for the cfg::NetworkStats driver.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/eth_sw_log.h>

namespace satcat5 {
    namespace test {
        //! ConfigBus emulator for the cfg::NetworkStats driver.
        //!
        //! This class is used to simulate systems where a gateware
        //! Ethernet switch reports traffic statistics over ConfigBus.
        //! i.e., VHDL blocks "switch_core" and "cfgbus_port_stats",
        //! interacting with the cfg::NetworkStats driver.
        //!
        //! When emulating such systems, the switch is simulated using
        //! a software-defined switch (i.e., the eth::SwitchCore class).
        //! This class monitors traffic on the simulated switch, then
        //! makes those statistics available over a simulated ConfigBus
        //! API, as if it were being read from the "config_stats" block.
        //! That API can be read by the cfg::NetworkStats driver.
        class SimSwitchStats
            : public satcat5::cfg::ConfigBus
            , protected satcat5::eth::SwitchLogStats {
        public:
            //! Constructor attaches to a simulated Ethernet switch.
            explicit SimSwitchStats(satcat5::eth::SwitchCore* sw);
            ~SimSwitchStats();

            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& rdval) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

        protected:
            // Maximum port count is limited by the ConfigBus address space.
            static constexpr unsigned REGS_PER_PORT = 16;
            static constexpr unsigned MAX_PORTS =
                satcat5::cfg::REGS_PER_DEVICE / REGS_PER_PORT;

            satcat5::eth::SwitchCore* const m_sw;
            satcat5::eth::SwitchLogStats::TrafficStats m_accum[MAX_PORTS];
            u32 m_regs[satcat5::cfg::REGS_PER_DEVICE];
        };
    }
}
