//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/port_adapter.h>

using satcat5::eth::SwitchCore;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::log::DEBUG;
using satcat5::log::Log;
using satcat5::port::MailAdapter;
using satcat5::port::NullAdapter;
using satcat5::port::SlipAdapter;
using satcat5::port::VlanAdapter;

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

VlanAdapter::VlanAdapter(SwitchCore* sw, Writeable* vdst)
    : SwitchPort(sw)
    , m_vdst(vdst)
    , m_vhdr(false)
{
    m_egress.set_callback(this);
}

// This method is called whenever this port has pending output data.
// We need to read the original contents, modify the VLAN tag, then
// copy the modified data to the designated Writeable sink.  If the
// sink cannot accept the entire packet at once, resume work when
// data_rcvd() is called again during the next polling interval.
void VlanAdapter::data_rcvd(satcat5::io::Readable* src)
{
    if (DEBUG_VERBOSE > 0) Log(DEBUG, "VlanAdapter::data_rcvd");

    // Start of frame only: Read and modify the packet header.
    if (!m_vhdr) {
        // Proceed only if we can read/modify/write the entire frame header.
        const unsigned MAX_HDR = 18;    // Dst + Src + Vtag + Etype
        if (m_vdst->get_write_space() < MAX_HDR) return;
        satcat5::eth::Header hdr;
        if (!m_egress.read_obj(hdr)) return;
        // Set VTAG fields based on incoming tag plus port defaults.
        // Note: All tags have DEI and PCP fields, but VID is optional.
        u32 dst_pol = m_vlan_cfg.policy();
        u16 dst_vid = hdr.vtag.vid() ? hdr.vtag.vid() : m_vlan_cfg.vtag().vid();
        u16 dst_dei = hdr.vtag.any() ? hdr.vtag.dei() : m_vlan_cfg.vtag().dei();
        u16 dst_pcp = hdr.vtag.any() ? hdr.vtag.pcp() : m_vlan_cfg.vtag().pcp();
        // Does the destination port require a tag? Format accordingly.
        // (See definition of each mode in "switch_cfg.h".)
        if (dst_pol == satcat5::eth::VTAG_PRIORITY) {
            // VTAG_PRIORITY emits tagged frames DEI and PCP only.
            hdr.vtag.set(0, dst_dei, dst_pcp);
        } else if (dst_pol == satcat5::eth::VTAG_MANDATORY) {
            // VTAG_MANDATORY emits tagged frames with all fields.
            hdr.vtag.set(dst_vid, dst_dei, dst_pcp);
        } else {
            // Other modes never emit tagged frames.
            hdr.vtag.set(0, 0, 0);
        }
        // Write the modified header and set once-per-frame flag.
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "VlanAdapter::data_rcvd::hdr");
        m_vdst->write_obj(hdr);
        m_vhdr = true;
    }

    // Everything after the Eth+VLAN header is a one-for-one copy.
    // Once finished, call finalize and get ready for the next frame.
    if (m_egress.copy_to(m_vdst)) {
        if (DEBUG_VERBOSE > 1) Log(DEBUG, "VlanAdapter::data_rcvd::fin");
        m_egress.read_finalize();
        m_vdst->write_finalize();
        m_vhdr = false;
    }
}

MailAdapter::MailAdapter(SwitchCore* sw, Readable* src, Writeable* dst)
    : VlanAdapter(sw, dst)
    , m_rx_copy(src, this)
{
    // Nothing else to initialize.
}

SlipAdapter::SlipAdapter(SwitchCore* sw, Readable* src, Writeable* dst)
    : VlanAdapter(sw, &m_tx_fcs)
    , m_rx_copy(src, &m_rx_slip)
    , m_rx_slip(&m_rx_fcs)
    , m_rx_fcs(this)
    , m_tx_fcs(&m_tx_slip)
    , m_tx_slip(dst)
{
    // Nothing else to initialize.
}

NullAdapter::NullAdapter(SwitchCore* sw)
    : SwitchPort(sw)
    , ReadableRedirect(&m_egress)
{
    // Nothing else to initialize.
}
