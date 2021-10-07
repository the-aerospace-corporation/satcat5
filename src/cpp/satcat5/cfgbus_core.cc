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

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_interrupt.h>
#include <satcat5/log.h>

namespace cfg   = satcat5::cfg;
namespace log   = satcat5::log;

// By default, check for duplicate interrupt handlers.
#ifndef SATCAT5_CHECK_DUPIRQ
#define SATCAT5_CHECK_DUPIRQ    1
#endif

cfg::WrappedRegister::WrappedRegister(cfg::ConfigBus* cfg, unsigned reg)
    : m_cfg(cfg)
    , m_reg(reg)
{
    // Nothing else to initialize.
}

cfg::WrappedRegister::operator u32()
{
    u32 tmp;
    m_cfg->read(m_reg, tmp);
    return tmp;
}

void cfg::WrappedRegister::operator=(u32 wrval)
{
    m_cfg->write(m_reg, wrval);
}

cfg::WrappedRegisterPtr::WrappedRegisterPtr(cfg::ConfigBus* cfg, unsigned reg)
    : m_cfg(cfg)
    , m_reg(reg)
{
    // Nothing else to initialize.
}

bool cfg::WrappedRegisterPtr::operator!() const
{
    return !m_cfg;
}

cfg::WrappedRegister cfg::WrappedRegisterPtr::operator*()
{
    return cfg::WrappedRegister(m_cfg, m_reg);
}

cfg::WrappedRegister cfg::WrappedRegisterPtr::operator[](unsigned idx)
{
    return cfg::WrappedRegister(m_cfg, m_reg + idx);
}

void cfg::ConfigBus::register_irq(cfg::Interrupt* obj)
{
    // Traverse the linked list to confirm this entry isn't a duplicate.
    // (Otherwise, this action will create an infinite loop.)
    if (SATCAT5_CHECK_DUPIRQ && m_irq_list.contains(obj)) {
        log::Log(log::ERROR, "ConfigBus IRQ duplicate");
    } else {
        m_irq_list.add(obj);
    }
}

void cfg::ConfigBus::unregister_irq(cfg::Interrupt* obj)
{
    m_irq_list.remove(obj);
}

unsigned cfg::ConfigBus::count_irq() const
{
    return m_irq_list.len();
}

cfg::Register cfg::ConfigBus::get_register(unsigned dev, unsigned reg)
{
    unsigned idx = REGS_PER_DEVICE * dev + reg;
#if SATCAT5_CFGBUS_DIRECT
    return (volatile u32*)(m_base_ptr + idx);
#else
    return cfg::WrappedRegisterPtr(this, idx);
#endif
}

void cfg::ConfigBus::irq_poll()
{
    // Traverse the linked list and poll each handler.
    cfg::Interrupt* ptr = m_irq_list.head();
    while (ptr != 0) {
        ptr->irq_check();
        ptr = ptr->m_next;
    }
}

cfg::ConfigBus::ConfigBus(void* base_ptr)
    : m_base_ptr((volatile u32*)base_ptr)
{
    // Nothing else to initialize at this time.
}

cfg::ConfigBusMmap::ConfigBusMmap(void* base_ptr, int irq)
    : cfg::ConfigBus(base_ptr)
    , irq::Handler("ConfigBus", irq)
{
    // Nothing else to initialize at this time.
}

void* cfg::ConfigBusMmap::get_device_mmap(unsigned dev) const
{
    return (void*)(m_base_ptr + REGS_PER_DEVICE * dev);
}

cfg::IoStatus cfg::ConfigBusMmap::read(unsigned regaddr, u32& val) {
    val = m_base_ptr[regaddr];
    return cfg::IOSTATUS_OK;
}

cfg::IoStatus cfg::ConfigBusMmap::write(unsigned regaddr, u32 val) {
    m_base_ptr[regaddr] = val;
    return cfg::IOSTATUS_OK;
}

void cfg::ConfigBusMmap::irq_event() {
    // Forward interrupt events to parent.
    irq_poll();
}
