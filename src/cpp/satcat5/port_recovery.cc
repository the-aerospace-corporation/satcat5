//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/port_recovery.h>

using satcat5::eth::PluginPacket;
using satcat5::eth::SwitchCore;
using satcat5::eth::SwitchPort;
using satcat5::port::RecoveryIngress;
using satcat5::port::RecoveryEgress;
using satcat5::log::DEBUG;
using satcat5::log::Log;

// Set Verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

RecoveryIngress::RecoveryIngress(SwitchCore* sw)
    : PluginCore(sw)
    , m_recov_in_buff(m_raw_buff_in, SATCAT5_RECOVERY_SWITCH_BUFFER_SIZE)
{
    // Nothing else to initialize.
}

void RecoveryIngress::query(PluginPacket& packet) {
    // If this is a recovery packet: copy the data onto the buffer, call
    // free_packet, and let the parent know we've consumed the packet.
    if (packet.hdr.type == satcat5::eth::ETYPE_RECOVERY) {
        // Discard frame header and note remaining length.
        satcat5::io::MultiPacket::Reader rd(packet.pkt);
        rd.read_consume(packet.hlen);
        unsigned length = rd.get_read_ready();

        // If there is enough space, copy the rest of the packet.
        if (m_recov_in_buff.get_write_space() >= length) {
            rd.copy_to(&m_recov_in_buff);
            m_recov_in_buff.write_finalize();
        } else if (DEBUG_VERBOSE > 1) {
            Log(DEBUG, "RecoveryIngress::query: Overflow.");
        }

        // Signal to the parent that we've consumed this packet.
        m_switch->free_packet(packet.pkt);
        packet.divert();
    }
}

RecoveryEgress::RecoveryEgress(SwitchPort* port)
    : MultiWriter(port->get_switch())
    , m_egress(port->get_egress())
{
    // Nothing else to initialize.
}

bool RecoveryEgress::write_finalize() {
    // Instead of MultiWriter::write_finalize, we want to call write_bypass()
    // to directly write to port. See Multiwriter::write_bypass()
    set_priority(9999);

    if (DEBUG_VERBOSE > 1) {
        Log(DEBUG, "RecoveryEgress::write_finalize");
    }
    return write_bypass(m_egress);
}