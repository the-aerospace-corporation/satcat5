//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_i2c.h>
#include <satcat5/log.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace log   = satcat5::log;
namespace util  = satcat5::util;

// Diagnostic options
static const unsigned DEBUG_VERBOSE = 0;    // Verbosity level (0/1/2)

// Define control-register commands:
static const u32 CMD_DELAY      = 0x0000u;
static const u32 CMD_START      = 0x0100u;
static const u32 CMD_RESTART    = 0x0200u;
static const u32 CMD_STOP       = 0x0300u;
static const u32 CMD_TXBYTE     = 0x0400u;
static const u32 CMD_RXBYTE     = 0x0500u;
static const u32 CMD_RXFINAL    = 0x0600u;
static const u32 CFG_NOSTRETCH  = (1u << 31);

cfg::I2c::I2c(cfg::ConfigBus* cfg, unsigned devaddr)
    : cfg::MultiSerial(cfg, devaddr, SATCAT5_I2C_MAXCMD,
        m_txbuff, SATCAT5_I2C_TXBUFF,
        m_rxbuff, SATCAT5_I2C_RXBUFF)
{
    // No other initialization required.
}

void cfg::I2c::configure(
    unsigned refclk_hz, unsigned baud_hz, bool clock_stretch)
{
    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "I2C: Reconfig @ baud").write((u32)baud_hz);

    u32 div_qtr = util::div_ceil_u32(refclk_hz, 4*baud_hz) - 1;
    if (clock_stretch)
        m_ctrl[REGADDR_CFG] = div_qtr;
    else
        m_ctrl[REGADDR_CFG] = div_qtr | CFG_NOSTRETCH;
}

bool cfg::I2c::busy()
{
    return !idle();
}

bool cfg::I2c::read(
    const util::I2cAddr& devaddr,
    u8 regbytes, u32 regaddr, u8 nread,
    cfg::I2cEventListener* callback)
{
    bool ok = enqueue_cmd(devaddr, regbytes, regaddr, 0, 0, nread, callback);

    if (ok && DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "I2C: Read").write(devaddr.m_addr).write(nread);

    return ok;
}

bool cfg::I2c::write(
    const util::I2cAddr& devaddr,
    u8 regbytes, u32 regaddr, u8 nwrite, const u8* data,
    cfg::I2cEventListener* callback)
{
    bool ok = enqueue_cmd(devaddr, regbytes, regaddr, nwrite, data, 0, callback);

    if (ok && DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "I2C: Write").write(devaddr.m_addr).write(nwrite);

    return ok;
}

bool cfg::I2c::enqueue_cmd(
    const util::I2cAddr& devaddr,
    u8 regbytes, u32 regaddr,
    u8 nwrite, const u8* data, u8 nread,
    cfg::I2cEventListener* callback)
{
    // Sanity check on inputs.
    if (regbytes > 4) return false;

    // How many opcodes required for this command?
    unsigned ndev = 1;                      // Bytes per device address
    if (devaddr.is_10b()) ++ndev;           // 10-bit address?
    unsigned ncmd = 2 + ndev;               // Start + devaddr + stop
    ncmd += regbytes + nwrite + nread;      // Requested I/O
    if ((regbytes || nwrite) && nread)      // Extra for restart?
        ncmd += 1 + ndev;                   // Restart + devaddr

    // Can we queue this command now?
    if (!write_check(ncmd, nread)) return false;

    // Split device address into individual bytes.
    u16 dev_msb = (devaddr.m_addr >> 8) & 0xFF;
    u16 dev_lsb = (devaddr.m_addr >> 0) & 0xFF;

    // Queue up each opcode.
    m_tx.write_u16(CMD_START);
    if (regbytes || nwrite) {
        // Big-endian conversion for regaddr field.
        u8 regarray[4];
        util::write_be_u32(regarray, regaddr);
        const u8* regptr = regarray + 4 - regbytes;
        // Write command with device register address.
        if (devaddr.is_10b()) {
            m_tx.write_u16(CMD_TXBYTE | dev_msb);
            m_tx.write_u16(CMD_TXBYTE | dev_lsb);
        } else {
            m_tx.write_u16(CMD_TXBYTE | dev_lsb);
        }
        for (unsigned a = 0 ; a < regbytes ; ++a)
            m_tx.write_u16(CMD_TXBYTE | regptr[a]);
        for (unsigned a = 0 ; a < nwrite ; ++a)
            m_tx.write_u16(CMD_TXBYTE | data[a]);
        // Follow up with a read transaction?
        if (nread) m_tx.write_u16(CMD_RESTART);
    }
    if (nread) {
        // Read command with device address.
        if (devaddr.is_10b()) {
            m_tx.write_u16(CMD_TXBYTE | dev_msb | 1);
            m_tx.write_u16(CMD_TXBYTE | dev_lsb);
        } else {
            m_tx.write_u16(CMD_TXBYTE | dev_lsb | 1);
        }
        for (unsigned a = 1 ; a < nread ; ++a)
            m_tx.write_u16(CMD_RXBYTE);
        m_tx.write_u16(CMD_RXFINAL);
    }
    m_tx.write_u16(CMD_STOP);

    // Finalize write and note metadata for later.
    unsigned idx = write_finish();
    m_callback[idx] = callback;
    m_devaddr[idx]  = devaddr.m_addr;
    m_regaddr[idx]  = regaddr;
    return true;    // Success!
}

void cfg::I2c::read_done(unsigned idx)
{
    u8 rxbuff[SATCAT5_I2C_RXBUFF];
    if (DEBUG_VERBOSE || m_callback[idx]) {
        // Copy data to working buffer; error flag in the last byte.
        unsigned nread = m_rx.get_read_ready();
        m_rx.read_bytes(nread, rxbuff);
        u8 noack = rxbuff[nread-1];
        // Optional diagnostic logging.
        if (DEBUG_VERBOSE) {
            log::Log msg(log::DEBUG, "I2C: Done");
            if (noack) msg.write(" (noack)");
            if (DEBUG_VERBOSE > 1) msg.write(rxbuff, nread-1);
        }
        // Notify callback.
        if (m_callback[idx]) {
            auto devaddr = util::I2cAddr::native(m_devaddr[idx]);
            m_callback[idx]->i2c_done(
                noack, devaddr, m_regaddr[idx], nread-1, rxbuff);
        }
    }
}
