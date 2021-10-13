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
// Test cases for the ConfigBus MDIO controller

#include <cstdio>
#include "sim_cfgbus.h"

using satcat5::test::CfgRegister;
using satcat5::test::CfgDevice;

CfgRegister::CfgRegister()
    : m_rd_mode(MODE_UNSAFE)
    , m_rd_dval(0)
{
    // Nothing else to initialize.
}

void CfgRegister::read_default_none()
{
    m_rd_mode   = MODE_STRICT;
    m_rd_dval   = 0;
}

void CfgRegister::read_default_echo()
{
    m_rd_mode   = MODE_ECHO;
    m_rd_dval   = 0;
}

void CfgRegister::read_default(u32 val)
{
    m_rd_mode   = MODE_CONSTANT;
    m_rd_dval   = val;
}

void CfgRegister::read_push(u32 val)
{
    m_queue_rd.push_back(val);
}

unsigned CfgRegister::read_count() const
{
    return m_queue_rd.size();
}

unsigned CfgRegister::write_count() const
{
    return m_queue_wr.size();
}

u32 CfgRegister::write_pop()
{
    if (m_queue_wr.empty()) {
        fprintf(stderr, "Write queue empty.\n");
        return 0;       // Error
    } else {
        u32 next = m_queue_wr.front();
        m_queue_wr.pop_front();
        return next;    // Next item from queue
    }
}

satcat5::cfg::IoStatus CfgRegister::read(unsigned regaddr, u32& rdval)
{
    if (m_rd_mode == MODE_UNSAFE) {
        // Read from an undefined register.
        fprintf(stderr, "Unsafe register read: %u\n", regaddr);
        rdval = 0;          // Memory access error
        return satcat5::cfg::IOSTATUS_BUSERROR;
    } else if (m_queue_rd.empty()) {
        // If the read-queue is empty, return the specified default.
        // (In strict mode, this is an error condition.)
        if (m_rd_mode == MODE_STRICT)
            fprintf(stderr, "Unqueued register read: %u\n", regaddr);
        rdval = m_rd_dval;  // Constant or echo mode
        return satcat5::cfg::IOSTATUS_OK;
    } else {
        // If anything is in the queue, return the next value.
        u32 next = m_queue_rd.front();
        m_queue_rd.pop_front();
        rdval = next;       // Next item from queue
        return satcat5::cfg::IOSTATUS_OK;
    }
}

satcat5::cfg::IoStatus CfgRegister::write(unsigned regaddr, u32 wrval)
{
    if (m_rd_mode == MODE_UNSAFE) {
        fprintf(stderr, "Unsafe register write: %u\n", regaddr);
        return satcat5::cfg::IOSTATUS_BUSERROR;
    } else if (m_rd_mode == MODE_ECHO) {
        m_rd_dval = wrval;
    }
    m_queue_wr.push_back(wrval);
    return satcat5::cfg::IOSTATUS_OK;
}

satcat5::cfg::IoStatus CfgDevice::read(unsigned regaddr, u32 &rdval)
{
    regaddr = regaddr % satcat5::cfg::REGS_PER_DEVICE;
    return reg[regaddr].read(regaddr, rdval);
}

satcat5::cfg::IoStatus CfgDevice::write(unsigned regaddr, u32 wrval)
{
    regaddr = regaddr % satcat5::cfg::REGS_PER_DEVICE;
    return reg[regaddr].write(regaddr, wrval);
}
