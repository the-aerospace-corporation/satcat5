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

#include <satcat5/cfgbus_remote.h>
#include <satcat5/ip_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/timer.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

namespace cfg   = satcat5::cfg;
namespace util  = satcat5::util;
using satcat5::cfg::ConfigBusRemote;
using satcat5::net::Type;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Define command opcodes
static const u8 OPCODE_WRITE0   = 0x2F;     // Write no-increment
static const u8 OPCODE_WRITE1   = 0x3F;     // Write auto-increment
static const u8 OPCODE_READ0    = 0x40;     // Read no-increment
static const u8 OPCODE_READ1    = 0x50;     // Read auto-increment

// Internal software flags (m_status)
static const u32 STATUS_PENDING = (1u << 0);
static const u32 STATUS_BUSY    = (1u << 1);

// Define Type codes for each supported protocol.
static const Type TYPE_ETH_ACK =
    Type(satcat5::eth::ETYPE_CFGBUS_ACK.value);
static const Type TYPE_UDP_ACK =
    Type(satcat5::udp::PORT_CFGBUS_ACK.value);

satcat5::eth::ConfigBus::ConfigBus(
        satcat5::eth::Dispatch* iface,          // Network interface
        satcat5::util::GenericTimer* timer)     // Reference for timeouts
    : satcat5::eth::AddressContainer(iface)
    , ConfigBusRemote(&m_addr, TYPE_ETH_ACK, timer)
{
    // Nothing else to initialize
}

void satcat5::eth::ConfigBus::connect(
    const satcat5::eth::MacAddr& dst)
{
    m_addr.connect(dst, satcat5::eth::ETYPE_CFGBUS_CMD);
}

satcat5::udp::ConfigBus::ConfigBus(
        satcat5::udp::Dispatch* udp)            // UDP interface
    : satcat5::udp::AddressContainer(udp)
    , ConfigBusRemote(&m_addr, TYPE_UDP_ACK, udp->iface()->m_timer)
{
    // Nothing else to initialize
}

void satcat5::udp::ConfigBus::connect(
    const satcat5::ip::Addr& dstaddr,           // Remote address
    const satcat5::ip::Addr& gateway)           // Next-hop address
{
    m_addr.connect(
        dstaddr, gateway,                       // New IP address
        satcat5::udp::PORT_CFGBUS_CMD,          // Dst = Cmd port
        satcat5::udp::PORT_CFGBUS_ACK);         // Src = Ack port
}

ConfigBusRemote::ConfigBusRemote(
        satcat5::net::Address* dst,             // Remote iface + address
        const satcat5::net::Type& ack,          // Ack type parameter
        util::GenericTimer* timer)              // Reference for timeouts
    : satcat5::cfg::ConfigBus()
    , satcat5::net::Protocol(ack)
    , m_dst(dst)
    , m_timer(timer)
    , m_timeout_rd(100000)  // Default = 100 msec
    , m_timeout_wr(0)       // Default = Non-blocking
    , m_status(0)
    , m_response_opcode(0)
    , m_response_ptr(0)
    , m_response_len(0)
    , m_response_status(cfg::IOSTATUS_OK)
{
    // Register to receive traffic.
    m_dst->iface()->add(this);
}

#if SATCAT5_ALLOW_DELETION
ConfigBusRemote::~ConfigBusRemote()
{
    m_dst->iface()->remove(this);
}
#endif

cfg::IoStatus ConfigBusRemote::read(unsigned regaddr, u32& rdval)
{
    return send_and_wait(OPCODE_READ1, regaddr, 1, &rdval, m_timeout_rd);
}

cfg::IoStatus ConfigBusRemote::write(unsigned regaddr, u32 wrval)
{
    return send_and_wait(OPCODE_WRITE1, regaddr, 1, &wrval, m_timeout_wr);
}

cfg::IoStatus ConfigBusRemote::read_array(
    unsigned regaddr, unsigned count, u32* result)
{
    return send_and_wait(OPCODE_READ1, regaddr, count, result, m_timeout_rd);
}

cfg::IoStatus ConfigBusRemote::read_repeat(
    unsigned regaddr, unsigned count, u32* result)
{
    return send_and_wait(OPCODE_READ0, regaddr, count, result, m_timeout_rd);
}

cfg::IoStatus ConfigBusRemote::write_array(
    unsigned regaddr, unsigned count, const u32* data)
{
    return send_and_wait(OPCODE_WRITE1, regaddr, count, data, m_timeout_wr);
}

cfg::IoStatus ConfigBusRemote::write_repeat(
    unsigned regaddr, unsigned count, const u32* data)
{
    return send_and_wait(OPCODE_WRITE0, regaddr, count, data, m_timeout_wr);
}

void ConfigBusRemote::frame_rcvd(satcat5::io::LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "CfgRemote: frame_rcvd");

    // Ignore everything if the PENDING flag isn't set.
    if (!(m_status & STATUS_PENDING)) return;

    // Sanity check on the header length.
    if (src.get_read_ready() < 8) {
        log::Log(log::ERROR, "CfgRemote: Invalid response");
        return;     // Ignore bad packet, keep waiting...
    }

    // Read the response opcode.  Discard any that don't match.
    // (Frequently WRITE commands don't wait for the response, so there
    //  may be a number of queued responses before we get to a READ.)
    u8 opcode = src.read_u8();
    if (opcode != m_response_opcode && DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "CfgRemote: Response ignored").write(opcode);
        return;     // Ignore mismatched opcode. (With debug log)
    } else if (opcode != m_response_opcode) {
        return;     // Ignore mismatched opcode. (Normal)
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "CfgRemote: Response received").write(opcode);
    }

    // Read and discard the rest of the reply header.
    // TODO: Is there any point in error-checking this?
    src.read_consume(7);    // Len, Rsvd, Addr

    // If applicable, store the read-response.
    unsigned rdbytes = 4 * m_response_len + 1;
    if ((m_response_ptr) && (src.get_read_ready() >= rdbytes)) {
        for (unsigned a = 0 ; a < m_response_len ; ++a)
            m_response_ptr[a] = src.read_u32();
        u8 errflag = src.read_u8();
        if (errflag) {
            log::Log(log::WARNING, "CfgRemote: Read error");
            m_response_status = cfg::IOSTATUS_BUSERROR;
        }
    } else if (m_response_ptr) {
        log::Log msg(log::ERROR, "CfgRemote: Invalid response");
        m_response_status = cfg::IOSTATUS_CMDERROR;
        if (DEBUG_VERBOSE > 1) {
            msg.write((u16)src.get_read_ready());
            msg.write(", expected").write((u16)rdbytes);
        }
        return; // Ignore bad packet, keep waiting...
    }

    // Signal wait_response() that operation is complete.
    util::clr_mask_u32(m_status, STATUS_PENDING);
}

cfg::IoStatus ConfigBusRemote::send_and_wait(
    u8 opcode, unsigned addr, unsigned len, const u32* ptr, unsigned timeout)
{
    // Attempt to send the read command.
    bool ok = send_command(opcode, addr, len, ptr);

    // Wait for response?
    if (!ok) {
        return cfg::IOSTATUS_CMDERROR;
    } else if (timeout) {
        return wait_response(timeout);
    } else {
        return cfg::IOSTATUS_OK;
    }
}

bool ConfigBusRemote::send_command(
    u8 opcode, unsigned addr, unsigned len, const u32* ptr)
{
    // Sanity check: Never allow overlapping command/response.
    if (m_status & STATUS_BUSY) {
        log::Log(log::ERROR, "CfgRemote: Already busy");
        return false;   // Failed to send
    }

    // Sanity check: Bulk read/write cannot exceed 256 items.
    if (len > 256) {
        log::Log(log::ERROR, "CfgRemote: Bad length");
        return false;   // Failed to send
    }

    // Predict command length.
    unsigned cmd_bytes = 8;
    if ((opcode == OPCODE_WRITE0) || (opcode == OPCODE_WRITE1))
        cmd_bytes += 4 * len;

    // Attempt to open connection.  (Also writes Eth/UDP headers.)
    io::Writeable* dst = m_dst->open_write(cmd_bytes);
    if (!dst) {                     // Unable to proceed?
        log::Log(log::ERROR, "CfgRemote: Connection error");
        return false;
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::DEBUG, "CfgRemote: Sending command")
            .write(opcode).write((u8)len);
    }

    // Write frame contents (see cfgbus_host_eth.vhd)
    m_response_opcode   = opcode;   // Updated expected response...
    m_response_len      = len;
    dst->write_u8(opcode);          // Opcode
    dst->write_u8(len-1);           // Length
    dst->write_u16(0);              // Reserved
    dst->write_u32(addr);           // Combined address
    if ((opcode == OPCODE_WRITE0) || (opcode == OPCODE_WRITE1)) {
        for (unsigned a = 0 ; a < len ; ++a)
            dst->write_u32(ptr[a]);
        m_response_ptr = 0;         // No read-response
    } else {
        m_response_ptr = (u32*)ptr; // Store response at PTR
    }

    // Send the packet!
    return dst->write_finalize();
}

cfg::IoStatus ConfigBusRemote::wait_response(unsigned timeout)
{
    m_response_status = IOSTATUS_OK;

    // Set the busy and response-pending flag.
    util::set_mask_u32(m_status, STATUS_BUSY | STATUS_PENDING);

    // Keep polling until we get a response or timeout.
    u32 tref = m_timer->now();
    while (1) {
        satcat5::poll::service();   // Yield to other SatCat5 tasks
        if (!(m_status & STATUS_PENDING)) {
            break;                  // Response received
        } else if (m_timer->elapsed_usec(tref) > timeout) {
            log::Log(log::ERROR, "CfgRemote: Timeout");
            m_response_status = cfg::IOSTATUS_TIMEOUT;
            break;                  // Timeout
        }
    }

    // Clear status flags before returning.
    util::clr_mask_u32(m_status, STATUS_BUSY | STATUS_PENDING);
    return m_response_status;
}
