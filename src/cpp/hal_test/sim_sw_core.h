//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus emulator for the eth::SwitchConfig driver.

#pragma once

#include <satcat5/eth_switch.h>
#include <satcat5/eth_sw_cache.h>
#include <satcat5/eth_sw_vlan.h>

namespace satcat5 {
    namespace test {
        //! ConfigBus emulator for the eth::SwitchConfig driver.
        //!
        //! This class is used to simulate systems where a gateware Ethernet
        //! switch is managed over ConfigBus. i.e., VHDL "switch_core" block
        //! interacting with the eth::SwitchConfig driver.
        //!
        //! When emulating such systems, the switch is simulated using a
        //! software-defined switch (i.e., the eth::SwitchCore class). This
        //! class provides that system, plus a ConfigBus API that accepts reads
        //! and writes. This class infers the underlying intent, and forwards
        //! high-level configuration commands to the software-defined switch.
        class SimSwitchCore : public satcat5::cfg::ConfigBus {
        public:
            //! Constructor creates a simulated Ethernet switch.
            SimSwitchCore();

            //! Get access to the underlying switch and its plugins.
            //!@{
            inline satcat5::eth::SwitchCore* core()
                { return &m_eth_sw; }
            inline satcat5::eth::SwitchCacheInner* table()
                { return &m_eth_tbl; }
            inline satcat5::eth::SwitchVlanInner* vlan()
                { return &m_eth_vlan; }
            //!@}

            // Basic read and write operations for ConfigBus API.
            satcat5::cfg::IoStatus read(unsigned regaddr, u32& rdval) override;
            satcat5::cfg::IoStatus write(unsigned regaddr, u32 wrval) override;

        protected:
            void mac_table_ctrl(u32 wrval);
            void vlan_rate_ctrl(u32 wrval);

            satcat5::eth::SwitchCoreStatic<65536> m_eth_sw;
            satcat5::eth::SwitchCache<64> m_eth_tbl;
            satcat5::eth::SwitchVlan<64> m_eth_vlan;
            u16 m_next_vid;
            u16 m_rate_ctr;
            u32 m_rate_1st;
            u32 m_rate_2nd;
            u32 m_mac_lsb;
            u32 m_mac_msb;
            u32 m_mac_ctrl;
            u32 m_traffic_count;
            u32 m_reg_echo[satcat5::cfg::REGS_PER_DEVICE];
        };
    }
}
