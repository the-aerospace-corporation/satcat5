//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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

        // Interface object for a "cfgbus_mdio" block (direct registers only).
        class Mdio final : public satcat5::poll::Always
        {
        public:
            // Constructor and destructor.
            Mdio(satcat5::cfg::ConfigBus* cfg, unsigned devaddr,
                unsigned regaddr = satcat5::cfg::REGADDR_ANY);
            ~Mdio() {}

            // Is there space in the callback queue?
            // (Note: Reads may still fail if hardware queue is full.)
            inline bool can_read() const
                {return m_addr_rdcount < SATCAT5_MDIO_BUFFSIZE;}

            // Direct write to designated MDIO register.
            // (Returns true if successful.)
            bool direct_write(unsigned phy, unsigned reg, unsigned data);

            // Direct read from designated MDIO register.
            // The "ref" argument is echoed to the callback's "regaddr", to
            // handle indirect read sequences.  See also: "MdioGenericMmd"
            // (Returns true if successful.)
            bool direct_read(unsigned phy, unsigned reg, unsigned ref,
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
            unsigned m_addr_rdcount;
            unsigned m_addr_rdidx;
            u16 m_addr_buff[SATCAT5_MDIO_BUFFSIZE];
            satcat5::cfg::MdioEventListener* m_callback[SATCAT5_MDIO_BUFFSIZE];
        };

        // Thin wrapper that attaches to an MDIO interface object.
        // The wrapper is an ephemeral objects with no persistent state.
        class MdioWrapper {
        public:
            // Public constructor so we can inherit cleanly.
            MdioWrapper(satcat5::cfg::Mdio* mdio, unsigned phyaddr)
                : m_mdio(mdio), m_phy(phyaddr) {}

            // Read and write methods allow indirect access.
            virtual bool write(unsigned reg, unsigned data) = 0;
            virtual bool read(unsigned reg, satcat5::cfg::MdioEventListener* callback) = 0;

        protected:
            // Restricted access avoids need for virtual destructor.
            ~MdioWrapper() {}

            // Parameters for the wrapped interface.
            satcat5::cfg::Mdio* const m_mdio;
            const unsigned m_phy;
        };

        // Thin wrappers for indirect register access on specific devices.
        // (Unfortunately, this is widely needed but unevenly standardized.)
        class MdioGenericMmd final : public satcat5::cfg::MdioWrapper {
        public:
            // MMD standard (e.g., Atheros AR8031, Texas Instruments DP83867)
            using satcat5::cfg::MdioWrapper::MdioWrapper;
            bool write(unsigned reg, unsigned data) override;
            bool read(unsigned reg, satcat5::cfg::MdioEventListener* callback) override;
        };

        class MdioMarvell final : public satcat5::cfg::MdioWrapper {
        public:
            // Marvell Alaska 88E1111 or 88E151x
            using satcat5::cfg::MdioWrapper::MdioWrapper;
            bool write(unsigned reg, unsigned data) override;
            bool read(unsigned reg, satcat5::cfg::MdioEventListener* callback) override;
        };
    }
}
