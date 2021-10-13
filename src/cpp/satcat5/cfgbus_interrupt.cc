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
// ConfigBus core definitions
//
// Define a memory-mapped "ConfigBus" interface, based on a base address.
// All registers in this interface correspond to volatile pointers.
//

#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/log.h>

// Status and command codes for interrupt-control register
static const u32 IRQ_ENABLE     = (1u << 0);
static const u32 IRQ_REQUEST    = (1u << 1);

satcat5::cfg::Interrupt::Interrupt(cfg::ConfigBus* cfg)
    : m_cfg(cfg)
    , m_ctrl(SATCAT5_NULL_REGISTER)
    , m_next(0)
{
    cfg->register_irq(this);
}

satcat5::cfg::Interrupt::Interrupt(
        cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_cfg(cfg)
    , m_ctrl(cfg->get_register(devaddr, regaddr))
    , m_next(0)
{
    cfg->register_irq(this);
    *m_ctrl = IRQ_ENABLE;
}

#if SATCAT5_ALLOW_DELETION
satcat5::cfg::Interrupt::~Interrupt()
{
    if (!!m_ctrl) *m_ctrl = 0;
    m_cfg->unregister_irq(this);
}
#endif

void satcat5::cfg::Interrupt::irq_check()
{
    // For nonstandard interfaces, always call irq_event().
    // Otherwise, prescreen based on the individual request flag.
    if (!m_ctrl) {
        irq_event();            // Call designated handler
    } else if (*m_ctrl & IRQ_REQUEST) {
        irq_event();            // Call designated handler
        *m_ctrl = IRQ_ENABLE;   // Acknowledge interrupt event
    }
}
