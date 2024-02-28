//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Memory-mapped ConfigBus for POSIX user applications
//
// Most local ConfigBus interfaces use a direct memory-map interface.
// However, physical memory is not typically accessible to POSIX user-space
// applications.  This class provides the necessary adaptation using "mmap"
// to open "/dev/mem".  This action typically requires "sudo" privileges.
//

#pragma once

#include <satcat5/cfgbus_core.h>

namespace satcat5 {
    namespace cfg {
        // Memory-mapped local ConfigBus.
        class ConfigBusPosix
            : public satcat5::cfg::ConfigBusMmap
        {
        public:
            // Constructor accepts the physical base address for the memory-map interface,
            // and the interrupt-index for the shared ConfigBus interrupt, if any.
            ConfigBusPosix(void* base_addr, int irq);
            ~ConfigBusPosix();

        protected:
            // file descriptor for /dev/mem which provide access to physical
            // memory on posix systems
            int m_fd = 0;
        };
    }
}
