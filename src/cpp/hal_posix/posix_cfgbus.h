//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Memory-mapped ConfigBus for POSIX user applications

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {
        //! Memory-mapped local ConfigBus.
        //! Most local ConfigBus interfaces use a direct memory-map interface.
        //! For system-on-chip platforms like the Xilinx Zynq series or the
        //! Microchip Polarfire-SoC, this is a convenient way to control FPGA
        //! fabric from the attached CPU.  However, physical memory is not
        //! typically accessible to POSIX applications.  This class provides
        //! the necessary adaptation using "mmap" to open "/dev/mem".  This
        //! action typically requires "sudo" privileges, but can be run from
        //! user-space, so no kernel device-drivers are required.
        class ConfigBusPosix
            : public satcat5::cfg::ConfigBusMmap
        {
        public:
            //! Constructor sets physical-memory parameters.
            //! \param base_addr Physical base address for the memory-map interface.
            //! \param irq Interrupt-index for the shared ConfigBus interrupt, if any.
            ConfigBusPosix(void* base_addr, int irq);
            ~ConfigBusPosix();

        protected:
            //! File descriptor for /dev/mem which provide access to physical
            //! memory on POSIX systems.
            int m_fd = 0;
        };
    }
}
