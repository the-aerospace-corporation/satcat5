//////////////////////////////////////////////////////////////////////////
// Copyright 2024-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/coap_posix.h>
#include <satcat5/udp_dispatch.h>

using satcat5::coap::ManageUdpHeap;
using satcat5::coap::EndpointUdpHeap;

ManageUdpHeap::ManageUdpHeap(satcat5::coap::Endpoint* coap, unsigned size)
    : ManageUdp(coap)
{
    satcat5::udp::Dispatch* udp = (satcat5::udp::Dispatch*)coap->iface();
    for (unsigned a = 0 ; a < size ; ++a)
        m_connections.push_back(new ConnectionUdp(coap, udp));
}

ManageUdpHeap::~ManageUdpHeap() {
    for (auto a = m_connections.begin() ; a != m_connections.end() ; ++a)
        delete *a;
}

EndpointUdpHeap::EndpointUdpHeap(satcat5::udp::Dispatch* udp, unsigned size)
    : Endpoint(udp)
    , ManageUdpHeap(this, size)
{
    // Nothing else to initialize.
}
