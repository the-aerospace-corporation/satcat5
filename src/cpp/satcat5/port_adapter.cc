//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
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
using satcat5::port::SwitchAdapter;
using satcat5::port::VlanAdapter;

// Set verbosity level for debugging (0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

VlanAdapter::VlanAdapter(SwitchCore* sw, Writeable* vdst)
    : SwitchPort(sw, vdst)
    , m_vport(this)
{
    // Nothing else to initialize.
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
    : SwitchPort(sw, nullptr)
    , ReadableRedirect(&m_egress)
{
    // Nothing else to initialize.
}

SwitchAdapter::SwitchAdapter(SwitchCore* swa, SwitchCore* swb)
    : m_a2b(swa, &m_b2a)
    , m_b2a(swb, &m_a2b)
{
    // Nothing else to initialize.
}
