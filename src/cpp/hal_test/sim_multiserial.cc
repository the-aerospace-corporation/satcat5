//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "sim_multiserial.h"
#include <hal_test/catch.hpp>
#include <satcat5/polling.h>
#include <cstdio>

using satcat5::cfg::IoStatus;
using satcat5::test::MultiSerial;

// Debugging verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Define the MST register map:
static const unsigned REG_IRQ       = 0;
static const unsigned REG_CONFIG    = 1;
static const unsigned REG_STATUS    = 2;
static const unsigned REG_DATA      = 3;

// Command flags for load_refcmd
const u8 satcat5::test::MST_ERROR   = (1u << 0);    // Sets error flag
const u8 satcat5::test::MST_READ    = (1u << 1);    // Triggers read
const u8 satcat5::test::MST_START   = (1u << 2);    // Clears error flag

// Bits in the status word:
static const u32 STATUS_ERROR       = (1u << 3);
static const u32 STATUS_BUSY        = (1u << 2);
static const u32 STATUS_CMDFULL     = (1u << 1);
static const u32 STATUS_RDVALID     = (1u << 0);
static const u32 DATA_RDVALID       = (1u << 8);

MultiSerial::MultiSerial(unsigned cmd_max)
    : m_cmd_max(cmd_max)
    , m_cmd_idx(0)
    , m_config(0)
    , m_busy(false)
    , m_error(false)
    , m_irq(false)
    , m_rd_count(0)
    , m_rd_ready(0)
{
    // Nothing else to initialize.
}

void MultiSerial::load_refcmd(u16 next, u8 flags)
{
    m_cmd_ref.push_back(next);
    m_cmd_flags.push_back(flags);
}

void MultiSerial::poll()
{
    step();                         // Update internal simulation
    satcat5::poll::service();       // Main polling loop
    irq_poll();                     // Poll ConfigBus interrupts
}

void MultiSerial::reply_rcvd(unsigned count)
{
    m_irq = true;                   // Set interrupt for new data
    m_rd_ready += count;            // Increment counter
    CHECK(m_rd_ready <= m_cmd_max); // Read-data overflow?
}

IoStatus MultiSerial::read(unsigned regaddr, u32& rdval)
{
    // Extract register address from the overall address.
    regaddr = (regaddr % satcat5::cfg::REGS_PER_DEVICE);

    if (regaddr == REG_IRQ) {
        // Interrupt status: bit 0 = enable, bit 1 = request
        rdval = m_irq ? 0x03 : 0x01;
    } else if (regaddr == REG_CONFIG) {
        // Echo the last written configuration word.
        rdval = m_config;
    } else if (regaddr == REG_STATUS) {
        // Status word.
        rdval = 0;
        if (m_error)
            rdval |= STATUS_ERROR;
        if (m_busy || !m_cmd_fifo.empty())
            rdval |= STATUS_BUSY;
        if (m_cmd_fifo.size() >= m_cmd_max)
            rdval |= STATUS_CMDFULL;
        if (m_rd_ready > 0)
            rdval |= STATUS_RDVALID;
    } else if (regaddr == REG_DATA) {
        // Read next received byte, if one is available.
        if (m_rd_ready > 0) {
            rdval = DATA_RDVALID | m_rd_count;
            ++m_rd_count; --m_rd_ready;
        } else {
            rdval = 0;
        }
    } else {
        // All other reads are invalid.
        WARN("Read from invalid register address.");
        return IoStatus::BUSERROR;
    }

    if (DEBUG_VERBOSE > 1)
        printf("MST: Read  @ %2X = 0x%08X\n", regaddr, rdval);
    return IoStatus::OK;
}

IoStatus MultiSerial::write(unsigned regaddr, u32 wrval)
{
    // Extract register address from the overall address.
    regaddr = (regaddr % satcat5::cfg::REGS_PER_DEVICE);
    if (DEBUG_VERBOSE > 1)
        printf("MST: Write @ %2X = 0x%08X\n", regaddr, wrval);

    if (regaddr == REG_IRQ) {
        // Any write to this register clears the IRQ flag.
        m_irq = false;
    } else if (regaddr == REG_CONFIG) {
        // Echo the last written configuration word.
        m_config = wrval;
    } else if (regaddr == REG_DATA) {
        // Write to the command FIFO.
        m_cmd_fifo.push_back((u16)wrval);
    } else {
        // All other writes are invalid.
        WARN("Write to invalid register address.");
        return IoStatus::BUSERROR;
    }

    return IoStatus::OK;
}

void MultiSerial::step()
{
    // Anything to do this timestep?
    if (m_cmd_fifo.empty()) return;

    // Is there an associated reference value?
    if (m_cmd_ref.empty() || m_cmd_flags.empty()) {
        WARN("Unexpected command in queue.");
        return;
    }

    // Pop next command off the queue...
    u16 next    = m_cmd_fifo.front();   m_cmd_fifo.pop_front();
    u16 ref     = m_cmd_ref.front();    m_cmd_ref.pop_front();
    u8  flags   = m_cmd_flags.front();  m_cmd_flags.pop_front();
    if (DEBUG_VERBOSE > 0)
        printf("MST: Exec  @ %2X = 0x%04X\n", m_cmd_idx, next);
    ++m_cmd_idx;

    // Did we get the expected command?
    CHECK(next == ref);

    // Update simulation state.
    if (flags & MST_START) {
        m_rd_count  = 0;
        m_error     = false;
    }
    if (flags & MST_ERROR) {
        m_error     = true;
    }
    if (flags & MST_READ) {
        ++m_rd_ready;
        CHECK(m_rd_ready <= m_cmd_max); // Read-data overflow?
    }

    // Trigger interrupt?
    if (m_cmd_fifo.empty())
        m_irq = true;
}
