//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_pps.h>
#include <satcat5/ptp_time.h>
#include <satcat5/ptp_tracking.h>

using satcat5::cfg::PpsInput;
using satcat5::cfg::PpsOutput;
using satcat5::cfg::Register;

PpsInput::PpsInput(Register reg, bool rising)
    : m_reg(reg)
    , m_callback(0)
    , m_offset(0)
{
    reset(rising);
    timer_every(50);
}

void PpsInput::reset(bool rising) {
    *m_reg = rising ? 1 : 0;
}

bool PpsInput::read_pulse() {
    // Bit-masks used for the FIFO register.
    constexpr u32 REG_LAST  = (1u << 31);
    constexpr u32 REG_VALID = (1u << 30);
    constexpr u32 REG_DATA  = (1u << 24) - 1;

    // Any data available?
    bool ok = false;
    u32 reg0 = *m_reg;
    if (reg0 & REG_VALID) {
        // Read the rest of the pulse descriptor (4 words total).
        u32 reg1 = *m_reg;
        u32 reg2 = *m_reg;
        u32 reg3 = *m_reg;

        // Is the pulse descriptor valid?
        ok = (reg1 & REG_VALID) && (reg2 & REG_VALID) && (reg3 & REG_LAST);
        if (ok) {
            // Read the fractional-second component in reg2 and reg3.
            // (Discard the whole-seconds component in reg0 and reg1.)
            u64 subns = u64(reg2 & REG_DATA) << 24 | u64(reg3 & REG_DATA);

            // Calculate phase-difference from nominal.
            // PPS signal should be aligned to the GPS epoch + m_offset.
            // After subtraction, range is now -0.5 to +1.5 seconds.
            s64 phase = s64(subns) - m_offset;

            // Normalize to the nearest second (i.e., +/- 500 msec).
            constexpr s64 HALF = satcat5::ptp::SUBNS_PER_SEC / 2;
            while (phase > HALF) phase -= satcat5::ptp::SUBNS_PER_SEC;

            // If a callback exists, notify it.
            // Timestamp of +0.1 sec means our local clock is running fast,
            // so slow it down by applying a negative control signal.
            satcat5::ptp::Time delta(-phase);
            if (m_callback) m_callback->update(delta);
        }
    }

    return ok;
}

void PpsInput::timer_event() {
    // Keep reading until we exhaust the FIFO.
    while (read_pulse()) {}
}

PpsOutput::PpsOutput(Register reg, bool rising)
    : m_reg(reg)
    , m_offset(0)
    , m_rising(rising)
{
    configure();
}

void PpsOutput::set_offset(s64 offset) {
    m_offset = offset;
    configure();
}

void PpsOutput::set_polarity(bool rising) {
    m_rising = rising;
    configure();
}

// Update requires two consecutive writes, then a read.
static inline u32 wide_write(Register& reg, u64 val) {
    *reg = u32(val >> 32);  // Write MSBs
    *reg = u32(val >> 0);   // Write LSBs
    return *reg;            // Read + Discard
}

void PpsOutput::configure() {
    constexpr u64 REG_RISING = (1ull << 63);
    constexpr u64 REG_OFFSET = (1ull << 48) - 1;

    // Format the configuration word.
    u64 cfg = u64(m_offset) & REG_OFFSET;
    if (m_rising) cfg |= REG_RISING;

    // Update the hardware configuration register.
    // Note: Cast to void prevents unused-value warnings.
    (void)wide_write(m_reg, cfg);
}
