//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/cfgbus_core.h>
#include <satcat5/ethernet.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/net_cfgbus.h>
#include <satcat5/udp_core.h>
#include <satcat5/udp_dispatch.h>

namespace log = satcat5::log;
using satcat5::cfg::REGS_PER_DEVICE;
using satcat5::net::ProtoConfig;
using satcat5::net::Type;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Define command opcodes
static const u8 OPMASK_CMD      = 0xF0;     // MSBs = Command
static const u8 OPMASK_WREN     = 0x0F;     // LSBs = Write-mask
static const u8 OPCODE_NOOP     = 0x00;     // No-op
static const u8 OPCODE_WRITE0   = 0x20;     // Write no-increment
static const u8 OPCODE_WRITE1   = 0x30;     // Write auto-increment
static const u8 OPCODE_READ0    = 0x40;     // Read no-increment
static const u8 OPCODE_READ1    = 0x50;     // Read auto-increment

// Define Type codes for each supported protocol.
static const Type TYPE_ETH_CMD =
    Type(satcat5::eth::ETYPE_CFGBUS_CMD.value);
static const Type TYPE_ETH_ACK =
    Type(satcat5::eth::ETYPE_CFGBUS_ACK.value);
static const Type TYPE_UDP_CMD =
    Type(satcat5::udp::PORT_CFGBUS_CMD.value);
static const Type TYPE_UDP_ACK =
    Type(satcat5::udp::PORT_CFGBUS_ACK.value);

// Support non-word-atomic writes?
// (These are extremely rare in remotely-operated systems.)
#ifndef SATCAT5_PROTOCFG_SUPPORT_WRMASK
#define SATCAT5_PROTOCFG_SUPPORT_WRMASK 0
#endif

// Helper function for byte-by-byte writes, if enabled.
inline void write_mask(volatile u32* reg, u32 val, u8 mask)
{
#if SATCAT5_PROTOCFG_SUPPORT_WRMASK
    // Break the command into individual byte-writes.
    u8* val8 = (u8*)&val;
    volatile u8* reg8 = (volatile u8*)ptr;
    if (satcat5::HOST_BYTE_ORDER() == satcat5::SATCAT5_BIG_ENDIAN) {
        if (mask & 0x08) reg8[0] = val8[0];
        if (mask & 0x04) reg8[1] = val8[1];
        if (mask & 0x02) reg8[2] = val8[2];
        if (mask & 0x01) reg8[3] = val8[3];
    } else {
        if (mask & 0x01) reg8[0] = val8[0];
        if (mask & 0x02) reg8[1] = val8[1];
        if (mask & 0x04) reg8[2] = val8[2];
        if (mask & 0x08) reg8[3] = val8[3];
    }
#endif
}

satcat5::eth::ProtoConfig::ProtoConfig(
        satcat5::eth::Dispatch* iface,
        satcat5::cfg::ConfigBusMmap* cfg,
        unsigned max_devices)
    : satcat5::net::ProtoConfig(
        cfg, iface, TYPE_ETH_CMD, TYPE_ETH_ACK, max_devices)
{
    // Nothing else to initialize.
}

satcat5::udp::ProtoConfig::ProtoConfig(
        satcat5::udp::Dispatch* iface,
        satcat5::cfg::ConfigBusMmap* cfg,
        unsigned max_devices)
    : satcat5::net::ProtoConfig(
        cfg, iface, TYPE_UDP_CMD, TYPE_UDP_ACK, max_devices)
{
    // Nothing else to initialize.
}

ProtoConfig::ProtoConfig(
        satcat5::cfg::ConfigBusMmap* cfg,
        satcat5::net::Dispatch* iface,
        const Type& cmd,
        const Type& ack,
        unsigned max_devices)
    : satcat5::net::Protocol(cmd)
    , m_cfg(cfg)
    , m_iface(iface)
    , m_acktype(ack)
    , m_max_devices(max_devices)
{
    m_iface->add(this);
}

#if SATCAT5_ALLOW_DELETION
ProtoConfig::~ProtoConfig()
{
    m_iface->remove(this);
}
#endif

void ProtoConfig::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // Sanity check for the main header.
    if (src.get_read_ready() < 8) {
        log::Log(log::ERROR, "ProtoConfig: Invalid command");
        return;
    }

    // Read header contents.
    u8  opcode  = src.read_u8();
    u8  len8    = src.read_u8();
    u8  seq     = src.read_u8();
    u8  rsvd    = src.read_u8();
    u32 addr    = src.read_u32();

    u8 cmd  = opcode & OPMASK_CMD;
    u8 wren = opcode & OPMASK_WREN;
    unsigned cmd_len = 1 + (unsigned)len8;

    // Diagnostics mimic the format used in "cfgbus_remote.cc".
    if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "ProtoConfig: Received command")
            .write(opcode).write(addr).write((u16)cmd_len);
    }

    // Predict reply-length.
    unsigned reply_bytes = 8;
    if (cmd == OPCODE_READ0 || cmd == OPCODE_READ1) {
        reply_bytes += 4*cmd_len + 1;
    }

    // Attempt to open reply packet.
    satcat5::io::Writeable* dst = m_iface->open_reply(m_acktype, reply_bytes);
    if (!dst) {
        log::Log(log::WARNING, "ProtoConfig: Reply error");
        return;
    }

    // Start writing reply header.
    dst->write_u8(opcode);
    dst->write_u8(len8);
    dst->write_u8(seq);
    dst->write_u8(rsvd);
    dst->write_u32(addr);

    // Get the read/write pointer.
    volatile u32* regptr = m_cfg->get_register_mmap(addr);
    u32 devaddr = (addr / REGS_PER_DEVICE);
    u32 regaddr = (addr % REGS_PER_DEVICE);

    // Execute selected opcode:
    const char* errmsg = 0;
    if (cmd == OPCODE_NOOP) {
        // No-op, send reply but take no other action.
    } else if (devaddr >= m_max_devices
            || regaddr >= REGS_PER_DEVICE
            || regaddr + cmd_len > REGS_PER_DEVICE) {
        errmsg = "Bad address";
    } else if ((cmd == OPCODE_WRITE0 || cmd == OPCODE_WRITE1) && wren) {
        // Sanity check on length, then execute writes.
        if (src.get_read_ready() < 4*cmd_len) {
            errmsg = "Bad length";
        } else if (SATCAT5_PROTOCFG_SUPPORT_WRMASK && wren < OPMASK_WREN) {
            for (unsigned a = 0 ; a < cmd_len ; ++a) {  // Partial writes
                write_mask(regptr, src.read_u32(), wren);
                if (cmd == OPCODE_WRITE1) ++regptr;
            }
        } else {
            for (unsigned a = 0 ; a < cmd_len ; ++a) {  // Full-word writes
                *regptr = src.read_u32();
                if (cmd == OPCODE_WRITE1) ++regptr;
            }
        }
    } else if ((cmd == OPCODE_READ0 || cmd == OPCODE_READ1) && !wren) {
        // Execute reads and add each result to reply.
        for (unsigned a = 0 ; a < cmd_len ; ++a) {
            dst->write_u32(*regptr);
            if (cmd == OPCODE_READ1) ++regptr;
        }
        // Read-error flag is always zero (not supported).
        dst->write_u8(0);
    } else {
        errmsg = "Bad opcode";
    }

    // Attempt to send reply?
    if (errmsg) {
        dst->write_abort();
    } else {
        bool ok = dst->write_finalize();
        if (ok && DEBUG_VERBOSE > 1) {
            log::Log(log::DEBUG, "ProtoConfig: Sent response")
                .write(opcode).write(addr).write((u16)cmd_len);
        }
        if (!ok) errmsg = "Reply error";
    }

    // Log any errors that occur.
    if (errmsg) log::Log(log::ERROR, "ProtoConfig: ").write(errmsg);
}
