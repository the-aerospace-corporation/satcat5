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

#include <satcat5/cfgbus_uart.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace util  = satcat5::util;

// Define hardware register map.
static const unsigned REGADDR_IRQ       = 0;
static const unsigned REGADDR_CFG       = 1;
static const unsigned REGADDR_STATUS    = 2;
static const unsigned REGADDR_DATA      = 3;

// Status and command codes for the multiserial control registers.
static const u32 MS_DVALID      = (1u << 8);
static const u32 MS_RD_READY    = (1u << 0);
static const u32 MS_CMD_FULL    = (1u << 1);

cfg::Uart::Uart(cfg::ConfigBus* cfg, unsigned devaddr)
    : io::BufferedIO(m_txbuff, SATCAT5_UART_BUFFSIZE, 0,
                     m_rxbuff, SATCAT5_UART_BUFFSIZE, 0)
    , cfg::Interrupt(cfg, devaddr, REGADDR_IRQ)
    , m_ctrl(cfg->get_register(devaddr))
{
    // No other initialization at this time.
}

void cfg::Uart::configure(
    unsigned clkref_hz,
    unsigned baud_hz)
{
    // Note: Writing to Config register also resets hardware FIFOs.
    m_ctrl[REGADDR_CFG] = util::div_round_u32(clkref_hz, baud_hz);
}

void cfg::Uart::data_rcvd()
{
    // Forward data from Tx-FIFO to hardware.
    while (m_tx.get_read_ready()) {
        u32 status = m_ctrl[REGADDR_STATUS];
        if (status & MS_CMD_FULL) break;
        m_ctrl[REGADDR_DATA] = m_tx.read_u8();
    }
}

void cfg::Uart::irq_event()
{
    // Read any data waiting in the hardware FIFO.
    // (Let PacketBuffer object handle overflow, if it occurs.)
    unsigned nwrite = 0;
    while (1) {
        u32 data = m_ctrl[REGADDR_DATA];
        if (data & MS_DVALID) {
            u8 byte = (u8)(data & 0xFF);
            m_rx.write_u8(byte);
            ++nwrite;
        } else {
            break;
        }
    }

    // Finalize new data to ensure downstream notifications.
    if (nwrite) m_rx.write_finalize();
}
