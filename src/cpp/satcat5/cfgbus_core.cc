//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2023 The Aerospace Corporation
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

using satcat5::cfg::ConfigBus;
using satcat5::cfg::ConfigBusMmap;
using satcat5::cfg::Interrupt;
using satcat5::cfg::IoStatus;
using satcat5::cfg::Register;
using satcat5::cfg::WrappedRegister;
using satcat5::cfg::WrappedRegisterPtr;
namespace log = satcat5::log;

// By default, check for duplicate interrupt handlers.
#ifndef SATCAT5_CHECK_DUPIRQ
#define SATCAT5_CHECK_DUPIRQ    1
#endif

WrappedRegister::WrappedRegister(ConfigBus* cfg, unsigned reg)
    : m_cfg(cfg)
    , m_reg(reg)
{
    // Nothing else to initialize.
}

WrappedRegister::operator u32()
{
    u32 tmp;
    m_cfg->read(m_reg, tmp);
    return tmp;
}

void WrappedRegister::operator=(u32 wrval)
{
    m_cfg->write(m_reg, wrval);
}

void WrappedRegister::write_repeat(unsigned count, const u32* data)
{
    m_cfg->write_repeat(m_reg, count, data);
}

WrappedRegisterPtr::WrappedRegisterPtr(ConfigBus* cfg, unsigned reg)
    : m_cfg(cfg)
    , m_reg(reg)
{
    // Nothing else to initialize.
}

bool WrappedRegisterPtr::operator!() const
{
    return !m_cfg;
}

WrappedRegister WrappedRegisterPtr::operator*()
{
    return WrappedRegister(m_cfg, m_reg);
}

WrappedRegister WrappedRegisterPtr::operator[](unsigned idx)
{
    return WrappedRegister(m_cfg, m_reg + idx);
}

WrappedRegisterPtr WrappedRegisterPtr::operator+(unsigned idx)
{
    return WrappedRegisterPtr(m_cfg, m_reg + idx);
}

void ConfigBus::register_irq(Interrupt* obj)
{
    // Traverse the linked list to confirm this entry isn't a duplicate.
    // (Otherwise, this action will create an infinite loop.)
    if (SATCAT5_CHECK_DUPIRQ && m_irq_list.contains(obj)) {
        log::Log(log::ERROR, "ConfigBus IRQ duplicate");
    } else {
        m_irq_list.add(obj);
    }
}

void ConfigBus::unregister_irq(Interrupt* obj)
{
    m_irq_list.remove(obj);
}

unsigned ConfigBus::count_irq() const
{
    return m_irq_list.len();
}

Register ConfigBus::get_register(unsigned dev, unsigned reg)
{
    unsigned idx = get_regaddr(dev, reg);
#if SATCAT5_CFGBUS_DIRECT
    return (volatile u32*)(m_base_ptr + idx);
#else
    return WrappedRegisterPtr(this, idx);
#endif
}

void ConfigBus::irq_poll()
{
    // Traverse the linked list and poll each handler.
    Interrupt* ptr = m_irq_list.head();
    while (ptr != 0) {
        ptr->irq_check();
        ptr = ptr->m_next;
    }
}

ConfigBus::ConfigBus(void* base_ptr)
    : m_base_ptr((volatile u32*)base_ptr)
{
    // Nothing else to initialize at this time.
}

IoStatus ConfigBus::read_array(
    unsigned regaddr, unsigned count, u32* result)
{
    IoStatus status = IoStatus::OK;
    for (unsigned a = 0 ; a < count ; ++a) {
        IoStatus tmp = read(regaddr+a, result[a]);
        if (tmp != IoStatus::OK) status = tmp;
    }
    return status;
}

IoStatus ConfigBus::read_repeat(
    unsigned regaddr, unsigned count, u32* result)
{
    IoStatus status = IoStatus::OK;
    for (unsigned a = 0 ; a < count ; ++a) {
        IoStatus tmp = read(regaddr, result[a]);
        if (tmp != IoStatus::OK) status = tmp;
    }
    return status;
}

IoStatus ConfigBus::write_array(
    unsigned regaddr, unsigned count, const u32* data)
{
    IoStatus status = IoStatus::OK;
    for (unsigned a = 0 ; a < count ; ++a) {
        IoStatus tmp = write(regaddr+a, data[a]);
        if (tmp != IoStatus::OK) status = tmp;
    }
    return status;
}

IoStatus ConfigBus::write_repeat(
    unsigned regaddr, unsigned count, const u32* data)
{
    IoStatus status = IoStatus::OK;
    for (unsigned a = 0 ; a < count ; ++a) {
        IoStatus tmp = write(regaddr, data[a]);
        if (tmp != IoStatus::OK) status = tmp;
    }
    return status;
}

IoStatus ConfigBusMmap::read(unsigned regaddr, u32& val) {
    val = m_base_ptr[regaddr];
    return IoStatus::OK;
}

IoStatus ConfigBusMmap::write(unsigned regaddr, u32 val) {
    m_base_ptr[regaddr] = val;
    return IoStatus::OK;
}

ConfigBusMmap::ConfigBusMmap(void* base_ptr, int irq)
    : ConfigBus(base_ptr)
    , irq::Handler("ConfigBus", irq)
{
    // Nothing else to initialize at this time.
}

void* ConfigBusMmap::get_device_mmap(unsigned dev) const
{
    return (void*)(m_base_ptr + get_regaddr(dev,0));
}

void ConfigBusMmap::irq_event() {
    // Forward interrupt events to parent.
    irq_poll();
}

