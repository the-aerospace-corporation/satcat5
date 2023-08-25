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

#include <satcat5/cfgbus_gpio.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace irq   = satcat5::irq;
namespace util  = satcat5::util;

static constexpr unsigned REG_MODE = 0;
static constexpr unsigned REG_OUT  = 1;
static constexpr unsigned REG_IN   = 2;

cfg::GpiRegister::GpiRegister(cfg::ConfigBus* cfg,
        unsigned devaddr, unsigned regaddr)
    : m_reg(cfg->get_register(devaddr, regaddr))
{
    // No other initialization required.
}

u32 cfg::GpiRegister::read_sync()
{
    // Write any value to resync the register.
    *m_reg = 0;
    // Short delay before returning the new value.
    for (volatile unsigned a = 16 ; a > 0 ; --a) {}
    return *m_reg;
}

cfg::GpoRegister::GpoRegister(cfg::ConfigBus* cfg,
        unsigned devaddr, unsigned regaddr)
    : m_reg(cfg->get_register(devaddr, regaddr))
{
    // No other initialization required.
}

void cfg::GpoRegister::out_clr(u32 mask)
{
    u32 tmp = *m_reg;
    util::clr_mask_u32(tmp, mask);
    *m_reg = tmp;
}

void cfg::GpoRegister::out_set(u32 mask)
{
    u32 tmp = *m_reg;
    util::set_mask_u32(tmp, mask);
    *m_reg = tmp;
}

cfg::GpioRegister::GpioRegister(
        cfg::ConfigBus* cfg, unsigned devaddr)
    : m_reg(cfg->get_register(devaddr))
{
    // No other initialization required.
}

void cfg::GpioRegister::mode(u32 val)
{
    m_reg[REG_MODE] = val;
}

void cfg::GpioRegister::write(u32 val)
{
    m_reg[REG_OUT] = val;
}

u32 cfg::GpioRegister::read()
{
    return m_reg[REG_IN];
}

void cfg::GpioRegister::mode_clr(u32 mask)
{
    u32 tmp = m_reg[REG_MODE];
    util::clr_mask_u32(tmp, mask);
    m_reg[REG_MODE] = tmp;
}

void cfg::GpioRegister::mode_set(u32 mask)
{
    u32 tmp = m_reg[REG_MODE];
    util::set_mask_u32(tmp, mask);
    m_reg[REG_MODE] = tmp;
}

void cfg::GpioRegister::out_clr(u32 mask)
{
    u32 tmp = m_reg[REG_OUT];
    util::clr_mask_u32(tmp, mask);
    m_reg[REG_OUT] = tmp;
}

void cfg::GpioRegister::out_set(u32 mask)
{
    u32 tmp = m_reg[REG_OUT];
    util::set_mask_u32(tmp, mask);
    m_reg[REG_OUT] = tmp;
}
