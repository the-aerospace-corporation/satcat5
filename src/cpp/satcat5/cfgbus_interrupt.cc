//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// ConfigBus core definitions
//
// Define a memory-mapped "ConfigBus" interface, based on a base address.
// All registers in this interface correspond to volatile pointers.
//

#include <satcat5/cfgbus_interrupt.h>

using satcat5::cfg::Interrupt;

// Status and command codes for interrupt-control register
static constexpr u32 IRQ_DISABLE    = 0;
static constexpr u32 IRQ_ENABLE     = (1u << 0);
static constexpr u32 IRQ_REQUEST    = (1u << 1);

Interrupt::Interrupt(cfg::ConfigBus* cfg)
    : m_cfg(cfg)
    , m_ctrl(SATCAT5_NULL_REGISTER)
    , m_next(0)
{
    cfg->register_irq(this);
}

Interrupt::Interrupt(
        cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_cfg(cfg)
    , m_ctrl(cfg->get_register(devaddr, regaddr))
    , m_next(0)
{
    cfg->register_irq(this);
    *m_ctrl = IRQ_ENABLE;
}

#if SATCAT5_ALLOW_DELETION
Interrupt::~Interrupt()
{
    if (!!m_ctrl) *m_ctrl = 0;
    m_cfg->unregister_irq(this);
}
#endif

void Interrupt::irq_check()
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

void Interrupt::irq_enable()
{
    if (!!m_ctrl) *m_ctrl = IRQ_ENABLE;
}

void Interrupt::irq_disable()
{
    if (!!m_ctrl) *m_ctrl = IRQ_DISABLE;
}
