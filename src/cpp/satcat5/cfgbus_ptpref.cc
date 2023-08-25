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

#include <satcat5/cfgbus_ptpref.h>
#include <satcat5/ptp_time.h>

using satcat5::cfg::ConfigBus;
using satcat5::cfg::PtpRealtime;
using satcat5::cfg::PtpReference;
using satcat5::cfg::Register;
using satcat5::ptp::SUBNS_PER_NSEC;
using satcat5::ptp::Time;

// Register map and opcodes for real-time clock.
static constexpr unsigned RTC_SEC_MSB   = 0;
static constexpr unsigned RTC_SEC_LSB   = 1;
static constexpr unsigned RTC_NSEC      = 2;
static constexpr unsigned RTC_SUBNS     = 3;
static constexpr unsigned RTC_COMMAND   = 4;
static constexpr unsigned RTC_RATE      = 5;
static constexpr u32 OPCODE_READ        = 1;
static constexpr u32 OPCODE_WRITE       = 2;
static constexpr u32 OPCODE_INCR        = 4;

// Rate register requires multiple operations to write.
inline u32 wide_write(Register& reg, s64 offset)
{
    u64 tmp = (u64)offset;
    *reg = u32(tmp >> 32);  // Write MSBs
    *reg = u32(tmp >> 0);   // Write LSBs
    return *reg;            // Read + Discard
}

PtpReference::PtpReference(ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_reg(cfg->get_register(devaddr, regaddr))
{
    // No other initialization required.
}

Time PtpReference::clock_adjust(const Time& amount)
{
    // Note: This clock doesn't support coarse adjustments,
    // so the residual error is equal to the requested shift.
    return amount;
}

void PtpReference::clock_rate(s64 offset)
{
    // Note: Cast to void prevents unused-value warnings.
    (void)wide_write(m_reg, offset);
}

PtpRealtime::PtpRealtime(ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_reg(cfg->get_register(devaddr, regaddr))
{
    // No other initialization required.
}

Time PtpRealtime::clock_adjust(const Time& amount)
{
    // Note: Full-precision shift, so residual error is zero.
    load(amount);
    m_reg[RTC_COMMAND] = OPCODE_INCR;
    return Time(0);
}

void PtpRealtime::clock_rate(s64 offset)
{
    // Note: Cast to void prevents unused-value warnings.
    Register tmp = m_reg + RTC_RATE;
    (void)wide_write(tmp, offset);
}

Time PtpRealtime::clock_ext()
{
    u64 sec_msb = m_reg[RTC_SEC_MSB];
    u64 sec_lsb = m_reg[RTC_SEC_LSB];
    u32 nsec    = m_reg[RTC_NSEC];
    u32 subns   = m_reg[RTC_SUBNS];
    u64 sec = (sec_msb << 32) + sec_lsb;
    return Time(sec, nsec, (u16)subns);
}

Time PtpRealtime::clock_now()
{
    m_reg[RTC_COMMAND] = OPCODE_READ;
    return clock_ext();
}

void PtpRealtime::clock_set(const Time& new_time)
{
    load(new_time);
    m_reg[RTC_COMMAND] = OPCODE_WRITE;
}

void PtpRealtime::load(const Time& time)
{
    u64 sec = (u64)time.secs();
    u64 sub = time.subns();
    m_reg[RTC_SEC_MSB] = (u32)(sec >> 32);
    m_reg[RTC_SEC_LSB] = (u32)(sec >> 0);
    m_reg[RTC_NSEC]    = (u32)(sub / SUBNS_PER_NSEC);
    m_reg[RTC_SUBNS]   = (u32)(sub % SUBNS_PER_NSEC);
}
