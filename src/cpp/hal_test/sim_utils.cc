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

#include "sim_utils.h"
#include <cstdio>
#include <ctime>
#include <satcat5/io_core.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

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

satcat5::test::ConstantTimer::ConstantTimer(u32 val)
    : satcat5::util::GenericTimer(16)  // 16 ticks = 1 microsecond
    , m_now(val)
{
    // Nothing else to initialize.
}

satcat5::test::LogProtocol::LogProtocol(
        satcat5::eth::Dispatch* dispatch,
        const satcat5::eth::MacType& ethertype)
    : satcat5::eth::Protocol(dispatch, ethertype)
{
    // Nothing else to initialize.
}

void satcat5::test::LogProtocol::frame_rcvd(satcat5::io::LimitedRead& src)
{
    satcat5::log::Log(satcat5::log::INFO, "Frame received")
        .write(m_etype.value).write(", Len")
        .write((u16)src.get_read_ready());
}

satcat5::test::MockConfigBusMmap::MockConfigBusMmap()
    : satcat5::cfg::ConfigBusMmap(m_regs, satcat5::irq::IRQ_NONE)
{
    clear_all();
}

void satcat5::test::MockConfigBusMmap::clear_all(u32 val)
{
    for (unsigned a = 0 ; a < cfg::MAX_DEVICES ; ++a)
        clear_dev(a, val);
}

void satcat5::test::MockConfigBusMmap::clear_dev(unsigned devaddr, u32 val)
{
    u32* dev = m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE;
    for (unsigned a = 0 ; a < cfg::REGS_PER_DEVICE ; ++a)
        dev[a] = val;
}

void satcat5::test::MockConfigBusMmap::irq_event()
{
    satcat5::cfg::ConfigBusMmap::irq_event();
}
