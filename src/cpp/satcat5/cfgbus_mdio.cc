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

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_mdio.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace log   = satcat5::log;
namespace util  = satcat5::util;

// Bit masks for the command register:
static const u32 HWREG_OPWR         = (1u << 26);
static const u32 HWREG_OPRD         = (2u << 26);
inline u32 HWREG_PADDR(unsigned x)  {return (x & 0x1F) << 21;}
inline u32 HWREG_RADDR(unsigned x)  {return (x & 0x1F) << 16;}
inline u32 HWREG_WDATA(u16 x)       {return x & 0xFFFF;}

// Shortcuts for direct register access (REG < 0x20)
inline u32 HW_DIR_WRITE(unsigned p, unsigned r, unsigned d)
    {return HWREG_OPWR | HWREG_PADDR(p) | HWREG_RADDR(r) | HWREG_WDATA(d);}
inline u32 HW_DIR_READ(unsigned p, unsigned r)
    {return HWREG_OPRD | HWREG_PADDR(p) | HWREG_RADDR(r);}

// Shortcuts for indirect register access (REGCR, ADDAR)
inline u32 HW_IND_ADDR(unsigned p)
    {return HW_DIR_WRITE(p, 0x0D, 0x001F);}
inline u32 HW_IND_DATA(unsigned p)
    {return HW_DIR_WRITE(p, 0x0D, 0x401F);}
inline u32 HW_IND_WR(unsigned p, unsigned d)
    {return HW_DIR_WRITE(p, 0x0E, d);}
inline u32 HW_IND_RD(unsigned p)
    {return HW_DIR_READ(p, 0x0E);}

// Bit masks for the status register:
static const u32 HWSTATUS_WRFULL    = (1u << 31);
static const u32 HWSTATUS_RVALID    = (1u << 30);
static const u32 HWSTATUS_RDATA     = (0xFFFF);

cfg::Mdio::Mdio(
        cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_ctrl_reg(cfg->get_register(devaddr, regaddr))
    , m_addr_rdidx(0)
    , m_addr_wridx(0)
{
    // No other initialization at this time.
}

void cfg::Mdio::poll_always()
{
    // Read status until FIFO is empty.
    while (hw_rd_status() & HWSTATUS_RVALID) {}
}

bool cfg::Mdio::write(unsigned phy, unsigned reg, unsigned data)
{
    // Construct and attempt to queue write command(s).
    if (reg < 0x20) {
        // Direct write
        return hw_wr_command(HW_DIR_WRITE(phy, reg, data));
    } else {
        // Indirect write
        return hw_wr_command(HW_IND_ADDR(phy))
            && hw_wr_command(HW_IND_WR(phy, reg))
            && hw_wr_command(HW_IND_DATA(phy))
            && hw_wr_command(HW_IND_WR(phy, data));
    }
}

bool cfg::Mdio::read(unsigned phy, unsigned reg,
        cfg::MdioEventListener* callback)
{
    // Make sure we have room in the software queue...
    u32 wr_next = util::modulo_add_uns(m_addr_wridx + 1, SATCAT5_MDIO_BUFFSIZE);
    if (wr_next == m_addr_rdidx) return false;

    // Set callback parameters first.
    // (They may get called during the polling process, since reading
    //  the status register may potentially pull the next reply word.)
    m_callback[m_addr_wridx] = callback;
    m_addr_buff[m_addr_wridx] = reg;

    // Attempt to add this read to in the hardware queue.
    bool ok;
    if (reg < 0x20) {
        // Direct read
        ok = hw_wr_command(HW_DIR_READ(phy, reg));
    } else {
        // Indirect read
        ok = hw_wr_command(HW_IND_ADDR(phy))
          && hw_wr_command(HW_IND_WR(phy, reg))
          && hw_wr_command(HW_IND_DATA(phy))
          && hw_wr_command(HW_IND_RD(phy));
    }

    // If successful, increment the write pointer.
    if (ok) m_addr_wridx = wr_next;
    return ok;
}

// Always use this method to read status register.
// (Otherwise we can accidentally discard received data.)
u32 cfg::Mdio::hw_rd_status()
{
    // Read the status register.
    u32 status = *m_ctrl_reg;

    // Sanity check: Are we expecting a read?
    if (m_addr_rdidx == m_addr_wridx) return status;

    // Handle received messages.
    if (status & HWSTATUS_RVALID) {
        // Pop register address off the queue.
        cfg::MdioEventListener* callback = m_callback[m_addr_rdidx];
        u16 regaddr = m_addr_buff[m_addr_rdidx];
        m_addr_rdidx = util::modulo_add_uns(m_addr_rdidx + 1, SATCAT5_MDIO_BUFFSIZE);
        // Log address + received value.
        u16 regval = (u16)(status & HWSTATUS_RDATA);
        // Notify callback object.
        if (callback) callback->mdio_done(regaddr, regval);
    }

    return status;
}

bool cfg::Mdio::hw_wr_command(u32 cmd)
{
    // Confirm FIFO isn't already full...
    u32 status = hw_rd_status();
    if (status & HWSTATUS_WRFULL) {
        return false;   // Abort
    } else {
        *m_ctrl_reg = cmd;
        return true;    // Success!
    }
    return true;
}

void cfg::MdioLogger::mdio_done(u16 regaddr, u16 regval)
{
    log::Log(log::INFO, "MDIO read").write(regaddr).write(regval);
}
