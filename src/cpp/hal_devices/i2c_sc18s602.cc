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
// Device driver for the NXP SC18IS602B I2C-to-SPI bridge
//
// The SC18IS602B is an SPI master that is controlled through an I2C bus,
// allowing indirect control of downstream SPI peripherals.  This driver
// concerts each SPI transaction into a series of I2C commands.
//
// Reference: https://www.nxp.com/docs/en/data-sheet/SC18IS602B.pdf
//

#include <hal_devices/i2c_sc18s602.h>
#include <satcat5/log.h>
#include <cstring>

namespace log = satcat5::log;
using satcat5::cfg::I2cGeneric;
using satcat5::cfg::I2cEventListener;
using satcat5::cfg::SpiGeneric;
using satcat5::device::i2c::Sc18is602;
using satcat5::util::I2cAddr;

Sc18is602::Sc18is602(I2cGeneric* i2c, const I2cAddr& devaddr)
    : m_parent(i2c)
    , m_devaddr(devaddr)
    , m_callback(0)
    , m_busy(0)
    , m_skip(0)
{
    // Nothing else to initialize.
}

bool Sc18is602::configure(unsigned spi_mode)
{
    // Sanity check before we start.
    if (spi_mode > 3) return false;

    // Function code 0xF0 = Configure SPI interface (Section 7.1.5):
    //  ORDER (bit 5)   = 0 (MSB-first)
    //  MODE (bits 3:2) = User-specified 0/1/2/3
    //  RATE (bits 1:0) = 0 (1843 kHz)
    u8 flags = (u8)(spi_mode << 2);
    return m_parent->write(m_devaddr, 1, 0xF0, 1, &flags);
}

bool Sc18is602::exchange(
    u8 devidx, const u8* wrdata, u8 rwbytes,
    satcat5::cfg::SpiEventListener* callback)
{
    // Sanity check before we start.
    if (m_busy > 0) return false;
    if (devidx > 3) return false;

    // This mode keeps the entire reply.
    if (execute(devidx, wrdata, rwbytes, 0)) {
        m_callback = callback;
        return true;
    } else {
        return false;
    }
}

bool Sc18is602::query(
    u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
    satcat5::cfg::SpiEventListener* callback)
{
    u8 temp[200];

    // Sanity check before we start.
    if (m_busy > 0) return false;
    if (devidx > 3) return false;
    if (wrbytes > sizeof(temp)) return false;
    if (rdbytes > sizeof(temp)) return false;
    if (wrbytes + rdbytes > sizeof(temp)) return false;

    // Do we need to zero-pad outgoing data?
    const u8* rwdata = wrdata;  // Use original
    if (rdbytes > 0) {
        if (wrbytes > 0) memcpy(temp, wrdata, wrbytes);
        memset(temp + wrbytes, 0, rdbytes);
        rwdata = temp;          // Use padded copy
    }

    // This mode skips first N bytes of reply.
    if (execute(devidx, rwdata, wrbytes + rdbytes, wrbytes)) {
        m_callback = callback;
        return true;
    } else {
        return false;
    }
}

bool Sc18is602::execute(u8 devidx, const u8* wrdata, u8 rwbytes, u8 skip)
{
    // Callback is set only if we succeed.
    m_callback = 0;
    m_skip = skip;

    // Issue the write command.
    u32 devmask = (1u << devidx);
    if (!m_parent->write(m_devaddr, 1, devmask, rwbytes, wrdata, this))
        return false;   // Unable to queue command, abort
    ++m_busy;           // Expect 1st callback event

    // Can we skip the read command?
    if (skip >= rwbytes) return true;

    // Issue the read command.
    if (!m_parent->read(m_devaddr, 0, 0, rwbytes, this))
        return false;   // Unable to queue command, abort
    ++m_busy;           // Expect 2nd callback event

    return true;        // Success!
}

void Sc18is602::i2c_done(
    bool noack, const I2cAddr& devaddr,
    u32 regaddr, unsigned nread, const u8* rdata)
{
    // Sanity check before proceeding...
    if (m_busy == 0) {
        log::Log(log::WARNING, "SC18IS602", "Unexpected callback.");
        return;
    } else if (noack) {
        log::Log(log::WARNING, "SC18IS602", "Missing ACK from I2C address")
            .write(m_devaddr.m_addr);
    }

    // Issue SPI callback on the last event only.
    if (--m_busy > 0) return;
    if (m_callback && nread <= m_skip)
        m_callback->spi_done(0, 0);
    else if (m_callback)
        m_callback->spi_done(nread - m_skip, rdata + m_skip);
}
