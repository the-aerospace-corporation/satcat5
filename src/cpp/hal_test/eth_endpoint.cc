//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_test/eth_endpoint.h>

using satcat5::test::EthernetEndpoint;
using satcat5::test::SlipEndpoint;

EthernetEndpoint::EthernetEndpoint(
    const satcat5::eth::MacAddr& local_mac,
    const satcat5::ip::Addr& local_ip,
    unsigned rate_bps)
    : ReadableRedirect(&m_txbuff)       // From device to network
    , WriteableRedirect(&m_rxlimit)     // From network to device
    , m_rxbuff()
    , m_txbuff()
    , m_rxlimit(&m_rxbuff, rate_bps)
    , m_txlimit(&m_txbuff, rate_bps)
    , m_ip(local_mac, local_ip, &m_txlimit, &m_rxbuff)
{
    // No other initialization required.
}

void EthernetEndpoint::set_rate(unsigned rate_bps)
{
    m_rxlimit.set_rate(rate_bps);
    m_txlimit.set_rate(rate_bps);
}

SlipEndpoint::SlipEndpoint(
    const satcat5::eth::MacAddr& local_mac,
    const satcat5::ip::Addr& local_ip,
    unsigned rate_bps)
    : ReadableRedirect(&m_slip)     // From device to network
    , WriteableRedirect(&m_slip)    // From network to device
    , m_eth(local_mac, local_ip, rate_bps)
    , m_slip(&m_eth, &m_eth)
{
    // No other initialization required.
}
