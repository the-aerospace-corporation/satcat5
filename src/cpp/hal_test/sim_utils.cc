//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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

#include "sim_utils.h"
#include <cmath>
#include <cstdio>
#include <ctime>
#include <hal_test/sim_cfgbus.h>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

using satcat5::test::ConstantTimer;
using satcat5::test::LogProtocol;
using satcat5::test::MockConfigBusMmap;
using satcat5::test::MockInterrupt;
using satcat5::test::Statistics;

bool satcat5::test::write(
    satcat5::io::Writeable* dst,
    unsigned nbytes, const u8* data)
{
    dst->write_bytes(nbytes, data);
    return dst->write_finalize();
}

bool satcat5::test::read(
    satcat5::io::Readable* src,
    unsigned nbytes, const u8* data)
{
    // Even if the lengths don't match, compare as much as we can.
    unsigned rcvd = src->get_read_ready(), match = 0;
    for (unsigned a = 0 ; a < nbytes && src->get_read_ready() ; ++a) {
        u8 next = src->read_u8();
        if (next == data[a]) {
            ++match;
        } else {
            log::Log(log::ERROR, "String mismatch @ index")
                .write(a).write(next).write(data[a]);
        }
    }

    // End-of-frame cleanup.
    src->read_finalize();

    // Check for leftover bytes in either direction.
    if (rcvd > nbytes) {
        u16 diff = satcat5::util::min_u16(65535, rcvd - nbytes);
        log::Log(log::ERROR, "Unexpected trailing bytes").write(diff);
        return false;
    } else if (rcvd < nbytes) {
        u16 diff = satcat5::util::min_u16(65535, nbytes - rcvd);
        log::Log(log::ERROR, "Missing expected bytes").write(diff);
        return false;
    } else {
        return (match == nbytes);
    }
}

ConstantTimer::ConstantTimer(u32 val)
    : satcat5::util::GenericTimer(16)  // 16 ticks = 1 microsecond
    , m_now(val)
{
    // Nothing else to initialize.
}

LogProtocol::LogProtocol(
        satcat5::eth::Dispatch* dispatch,
        const satcat5::eth::MacType& ethertype)
    : satcat5::eth::Protocol(dispatch, ethertype)
{
    // Nothing else to initialize.
}

void LogProtocol::frame_rcvd(satcat5::io::LimitedRead& src)
{
    satcat5::log::Log(satcat5::log::INFO, "Frame received")
        .write(m_etype.value).write(", Len")
        .write((u16)src.get_read_ready());
}

MockConfigBusMmap::MockConfigBusMmap()
    : satcat5::cfg::ConfigBusMmap(m_regs, satcat5::irq::IRQ_NONE)
{
    clear_all();
}

void MockConfigBusMmap::clear_all(u32 val)
{
    for (unsigned a = 0 ; a < cfg::MAX_DEVICES ; ++a)
        clear_dev(a, val);
}

void MockConfigBusMmap::clear_dev(unsigned devaddr, u32 val)
{
    u32* dev = m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE;
    for (unsigned a = 0 ; a < cfg::REGS_PER_DEVICE ; ++a)
        dev[a] = val;
}

void MockConfigBusMmap::irq_event()
{
    satcat5::cfg::ConfigBusMmap::irq_event();
}

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg)
    : satcat5::cfg::Interrupt(cfg)
    , m_cfg(cfg)
    , m_count(0)
    , m_regaddr(0)
{
    // Nothing else to initialize.
}

static constexpr u32 MOCK_IRQ_ENABLE    = (1u << 0);
static constexpr u32 MOCK_IRQ_REQUEST   = (1u << 1);

MockInterrupt::MockInterrupt(satcat5::cfg::ConfigBus* cfg, unsigned regaddr)
    : satcat5::cfg::Interrupt(cfg, 0, regaddr)
    , m_cfg(cfg)
    , m_count(0)
    , m_regaddr(regaddr)
{
    // Nothing else to initialize.
}

void MockInterrupt::fire() {
    u32 rdval;
    if (m_regaddr) {
        // Register mode -> Always set request bit, fire only if enabled.
        m_cfg->read(m_regaddr, rdval);
        m_cfg->write(m_regaddr, rdval | MOCK_IRQ_REQUEST);
        if (rdval & MOCK_IRQ_ENABLE) m_cfg->irq_poll();
    } else {
        // No-register mode -> Always fire as if enabled.
        m_cfg->irq_poll();
    }
}

Statistics::Statistics()
    : m_count(0)
    , m_sum(0.0)
    , m_sumsq(0.0)
    , m_min(0.0)
    , m_max(0.0)
{
    // Nothing else to initialize.
}

void Statistics::add(double x)
{
    if ((m_count == 0) || (x < m_min)) m_min = x;
    if ((m_count == 0) || (x > m_max)) m_max = x;
    ++m_count;
    m_sum += x;
    m_sumsq += x*x;
}

double Statistics::mean() const
    { return m_sum / m_count; }
double Statistics::msq() const
    { return m_sumsq / m_count; }
double Statistics::rms() const
    { return sqrt(msq()); }
double Statistics::std() const
    { return sqrt(var()); }
double Statistics::var() const
    { return msq() - mean()*mean(); }
double Statistics::min() const
    { return m_min; }
double Statistics::max() const
    { return m_max; }

void satcat5::test::TimerAlways::sim_wait(unsigned dly_msec)
{
    // Without a reference (timekeeper::set_clock), each call
    // to service_all() represents one elapsed millisecond.
    satcat5::poll::timekeeper.set_clock(0);
    for (unsigned a = 0 ; a < dly_msec ; ++a)
        satcat5::poll::service_all();
}

