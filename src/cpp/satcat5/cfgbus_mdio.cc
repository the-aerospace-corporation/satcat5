//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_core.h>
#include <satcat5/cfgbus_mdio.h>
#include <satcat5/interrupts.h>
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

// Bit masks for the status register:
static const u32 HWSTATUS_WRFULL    = (1u << 31);
static const u32 HWSTATUS_RVALID    = (1u << 30);
static const u32 HWSTATUS_RDATA     = (0xFFFF);

cfg::Mdio::Mdio(
        cfg::ConfigBus* cfg, unsigned devaddr, unsigned regaddr)
    : m_ctrl_reg(cfg->get_register(devaddr, regaddr))
    , m_addr_rdcount(0)
    , m_addr_rdidx(0)
{
    // No other initialization at this time.
}

void cfg::Mdio::poll_always()
{
    // Read status until FIFO is empty.
    while (hw_rd_status() & HWSTATUS_RVALID) {}
}

bool cfg::Mdio::direct_write(unsigned phy, unsigned reg, unsigned data)
{
    // Construct and attempt to queue write the command.
    return hw_wr_command(HW_DIR_WRITE(phy, reg, data));
}

bool cfg::Mdio::direct_read(unsigned phy, unsigned reg, unsigned ref,
        cfg::MdioEventListener* callback)
{
    // Attempt to add this command to he hardware queue...
    if (can_read() && hw_wr_command(HW_DIR_READ(phy, reg))) {
        // Store new callback parameters.
        satcat5::irq::AtomicLock lock("MDIO");
        unsigned wridx = util::modulo_add_uns(
            m_addr_rdidx + m_addr_rdcount, SATCAT5_MDIO_BUFFSIZE);
        m_callback[wridx] = callback;
        m_addr_buff[wridx] = (u16)ref;
        ++m_addr_rdcount;   // Increment pending read counter
        return true;        // Success (accept metadata)
    } else {
        return false;       // Failure (discard metadata)
    }
}

// Always use this method to read status register.
// (Otherwise we can accidentally discard received data.)
u32 cfg::Mdio::hw_rd_status()
{
    // Read the status register.
    u32 status = *m_ctrl_reg;

    // Handle received messages.
    u16 regaddr = 0, regval = (u16)(status & HWSTATUS_RDATA);
    cfg::MdioEventListener* callback = 0;
    if ((m_addr_rdcount > 0) && (status & HWSTATUS_RVALID)) {
        // Pop register address and callback off the queue.
        satcat5::irq::AtomicLock lock("MDIO");
        regaddr = m_addr_buff[m_addr_rdidx];
        callback = m_callback[m_addr_rdidx];
        m_addr_rdidx = util::modulo_add_uns(m_addr_rdidx + 1, SATCAT5_MDIO_BUFFSIZE);
        --m_addr_rdcount;
    }

    // Notify callback object, if applicable.
    if (callback) callback->mdio_done(regaddr, regval);

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
}

void cfg::MdioLogger::mdio_done(u16 regaddr, u16 regval)
{
    log::Log(log::INFO, "MDIO read").write(regaddr).write(regval);
}

//////////////////////////////////////////////////////////////////////////
// Thin wrappers for indirect register access on a specific PHY device.
//////////////////////////////////////////////////////////////////////////

bool cfg::MdioGenericMmd::write(unsigned reg, unsigned data)
{
    if (reg < 0x20) {               // Direct write
        return m_mdio->direct_write(m_phy, reg, data);
    } else {                        // Indirect write
        return m_mdio->direct_write(m_phy, 0x0D, 0x001F)
            && m_mdio->direct_write(m_phy, 0x0E, reg)
            && m_mdio->direct_write(m_phy, 0x0D, 0x401F)
            && m_mdio->direct_write(m_phy, 0x0E, data);
    }
}

bool cfg::MdioGenericMmd::read(unsigned reg, satcat5::cfg::MdioEventListener* callback)
{
    if (reg < 0x20) {               // Direct read
        return m_mdio->direct_read(m_phy, reg, reg, callback);
    } else {                        // Indirect read
        return m_mdio->can_read()   // Check before we queue writes
            && m_mdio->direct_write(m_phy, 0x0D, 0x001F)
            && m_mdio->direct_write(m_phy, 0x0E, reg)
            && m_mdio->direct_write(m_phy, 0x0D, 0x401F)
            && m_mdio->direct_read (m_phy, 0x0E, reg, callback);
    }
}

bool cfg::MdioMarvell::write(unsigned reg, unsigned data)
{
    unsigned page = (reg >> 8);
    return m_mdio->direct_write(m_phy, 0x16, page)
        && m_mdio->direct_write(m_phy, reg, data);
}

bool cfg::MdioMarvell::read(unsigned reg, satcat5::cfg::MdioEventListener* callback)
{
    unsigned page = (reg >> 8);
    return m_mdio->can_read()       // Check before we queue writes
        && m_mdio->direct_write(m_phy, 0x16, page)
        && m_mdio->direct_read (m_phy, reg, reg, callback);
}
