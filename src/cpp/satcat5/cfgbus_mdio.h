//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////
// ConfigBus MDIO interface
//
// MDIO is a common interface for configuring an Ethernet PHY.  It is similar
// to I2C, but typically runs at ~1.6 Mbps.  This class provides a simple
// interface to the "cfgbus_mdio" block, allowing both writes and reads.

#pragma once

#include <satcat5/cfgbus_core.h>
#include <satcat5/polling.h>
#include <satcat5/types.h>

// Set default buffer size
#ifndef SATCAT5_MDIO_BUFFSIZE
#define SATCAT5_MDIO_BUFFSIZE   8
#endif

namespace satcat5 {
    namespace cfg {
        // Prototype for the SPI Event Handler callback interface.
        // To use, inherit from this class and override the spi_done() method.
        class MdioEventListener {
        public:
            virtual void mdio_done(u16 regaddr, u16 regval) = 0;
        protected:
            ~MdioEventListener() {}
        };

        // Example implementation that writes to log.
        class MdioLogger : public satcat5::cfg::MdioEventListener {
            void mdio_done(u16 regaddr, u16 regval) override;
        };

        class Mdio : public satcat5::poll::Always
        {
        public:
            // Constructor
            Mdio(satcat5::cfg::ConfigBus* cfg, unsigned devaddr,
                unsigned regaddr = satcat5::cfg::REGADDR_ANY);

            // Write to designated MDIO register.
            // (Returns true if successful.)
            bool write(unsigned phy, unsigned reg, unsigned data);

            // Read from designated MDIO register.
            // (Returns true if successful. Result sent to callback.)
            bool read(unsigned phy, unsigned reg,
                    satcat5::cfg::MdioEventListener* callback);

        protected:
            // Poll hardware status.
            void poll_always();

            // Internal accessors.
            u32 hw_rd_status();
            bool hw_wr_command(u32 cmd);

            // Control register address.
            satcat5::cfg::Register m_ctrl_reg;

            // Queue for read callbacks and associated metadata.
            unsigned m_addr_rdidx;
            unsigned m_addr_wridx;
            u16 m_addr_buff[SATCAT5_MDIO_BUFFSIZE];
            satcat5::cfg::MdioEventListener* m_callback[SATCAT5_MDIO_BUFFSIZE];
        };
    }
}
