//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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

#include <hal_devices/i2c_tca9548.h>

using satcat5::cfg::I2cGeneric;
using satcat5::cfg::I2cEventListener;
using satcat5::device::i2c::Tca9548;
using satcat5::util::I2cAddr;
using satcat5::util::modulo_add_uns;

Tca9548::Tca9548(I2cGeneric* i2c, const I2cAddr& devaddr)
    : m_parent(i2c)
    , m_devaddr(devaddr)
    , m_cb_count(0)
    , m_cb_rdidx(0)
{
    // Nothing else to initialize.
}

bool Tca9548::select_mask(u8 mask)
{
    // Issue the "select" command only if bus is idle.
    if (m_cb_count > 0) return false;
    return m_parent->write(m_devaddr, 0, 0, 1, &mask);
}

bool Tca9548::read(const I2cAddr& devaddr,
    u8 regbytes, u32 regaddr, u8 nread,
    I2cEventListener* callback)
{
    // Reject command if our callback queue is full.
    if (m_cb_count >= SATCAT5_I2C_MAXCMD) return false;

    // Otherwise, store the pointer and call parent.
    m_cb_queue[cb_wridx()] = callback;
    bool ok = m_parent->read(devaddr, regbytes, regaddr, nread, this);

    // If the parent succeeds, increment the queue count.
    if (ok) ++m_cb_count;
    return ok;
}

bool Tca9548::write(const I2cAddr& devaddr,
    u8 regbytes, u32 regaddr, u8 nwrite, const u8* data,
    I2cEventListener* callback)
{
    // Reject command if our callback queue is full.
    if (m_cb_count >= SATCAT5_I2C_MAXCMD) return false;

    // Otherwise, store the pointer and call parent.
    m_cb_queue[cb_wridx()] = callback;
    bool ok = m_parent->write(devaddr, regbytes, regaddr, nwrite, data, this);

    // If the parent succeeds, increment the queue count.
    if (ok) ++m_cb_count;
    return ok;
}

void Tca9548::i2c_done(
    bool noack, const I2cAddr& devaddr,
    u32 regaddr, unsigned nread, const u8* rdata)
{
    // Pop callback off the circular buffer.
    I2cEventListener* cb = m_cb_queue[m_cb_rdidx];
    m_cb_rdidx = modulo_add_uns(m_cb_rdidx + 1, SATCAT5_I2C_MAXCMD);
    --m_cb_count;

    // Forward the callback event if applicable.
    if (cb) cb->i2c_done(noack, devaddr, regaddr, nread, rdata);
}
