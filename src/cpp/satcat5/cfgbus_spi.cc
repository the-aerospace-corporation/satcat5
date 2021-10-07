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

#include <satcat5/cfgbus_spi.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace util  = satcat5::util;

// Command opcodes
static inline u32 CMD_OPCODE(u32 c, u32 x)
    {return ((c << 8) | (x & 0xFF));}
static inline u32 CMD_START(u32 x)
    {return CMD_OPCODE(0, x);}
static inline u32 CMD_TXONLY(u32 x)
    {return CMD_OPCODE(1, x);}
static inline u32 CMD_TXRX(u32 x)
    {return CMD_OPCODE(2, x);}
static const u32 CMD_RXONLY = CMD_OPCODE(3, 0);
static const u32 CMD_STOP   = CMD_OPCODE(4, 0);

// Suppress static-analysis warnings for uninitialized members.
// (Large array "m_callback" is always written before use.)
// cppcheck-suppress uninitMemberVar

cfg::Spi::Spi(ConfigBus* cfg, unsigned devaddr)
    : cfg::MultiSerial(cfg, devaddr, SATCAT5_SPI_MAXCMD,
        m_txbuff, SATCAT5_SPI_TXBUFF,
        m_rxbuff, SATCAT5_SPI_RXBUFF)
{
    // No other initialization at this time.
}

void cfg::Spi::configure(
    unsigned clkref_hz,
    unsigned baud_hz,
    unsigned mode)
{
    u32 clkdiv = util::div_ceil_u32(clkref_hz, 2 * baud_hz);
    m_ctrl[REGADDR_CFG] = (mode << 8) | (clkdiv);
}

bool cfg::Spi::query(
        u8 devidx, const u8* wrdata, u8 wrbytes, u8 rdbytes,
        cfg::SpiEventListener* callback)
{
    // How many opcodes required for this command?
    unsigned ncmd = 2 + wrbytes + rdbytes;

    // Can we queue this command now?
    if (!write_check(ncmd, rdbytes)) return false;

    // Queue up each opcode.
    m_tx.write_u16(CMD_START(devidx));
    for (unsigned a = 0 ; a < wrbytes ; ++a)
        m_tx.write_u16(CMD_TXONLY(wrdata[a]));
    for (unsigned a = 0 ; a < rdbytes ; ++a)
        m_tx.write_u16(CMD_RXONLY);
    m_tx.write_u16(CMD_STOP);

    // Finalize write and note metadata for later.
    unsigned idx = write_finish();
    m_callback[idx] = callback;
    return true;    // Success!
}

void cfg::Spi::read_done(unsigned idx)
{
    u8 rxbuff[SATCAT5_SPI_RXBUFF];
    if (m_callback[idx]) {
        // Copy data to working buffer; ignore the extraneous error flag.
        unsigned nread = m_rx.get_read_ready();
        if (nread > 1) m_rx.read_bytes(nread-1, rxbuff);
        // Notify callback.
        m_callback[idx]->spi_done(nread-1, rxbuff);
    }
}
