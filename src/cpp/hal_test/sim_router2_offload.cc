//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Test cases for the router's hardware-accelerated offload interface

#include <hal_test/catch.hpp>
#include <hal_test/sim_router2_offload.h>

using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::test::MockOffload;
using satcat5::udp::PORT_CBOR_TLM;

// Define register map (see "router2_common.vhd")
static const unsigned REG_TXRX_DAT  = 0;
static const unsigned REG_PORT_SHDN = 494;
static const unsigned REG_TX_MASK   = 499;
static const unsigned REG_TBL_SIZE  = 508;
static const unsigned REG_TX_CTRL   = 500;
static const unsigned REG_RX_IRQ    = 510;
static const unsigned REG_RX_CTRL   = 511;

// Simulate the offload port's memory-mapped interface.
MockOffload::MockOffload(unsigned devaddr)
    : m_dev(m_regs + devaddr * satcat5::cfg::REGS_PER_DEVICE)
{
    m_dev[REG_TX_CTRL] = 0;                 // Initial state = idle
    m_dev[REG_TBL_SIZE] = 0;                // Count hardware ports
    m_dev[REG_PORT_SHDN] = 0;               // All ports are active
}

MockOffload::~MockOffload() {
    for (auto a = m_ports.begin() ; a != m_ports.end() ; ++a) {
        delete *a;                          // Cleanup of port objects
    }
}

void MockOffload::add_port(Writeable* dst, Readable* src) {
    unsigned index = m_ports.size();
    m_ports.push_back(new Port(index, this, dst, src));
    m_dev[REG_TBL_SIZE] = m_ports.size();   // Update port count
}

void MockOffload::port_shdn(u32 mask_shdn) {
    u32 mask_all = (1u << m_ports.size()) - 1;
    m_dev[REG_PORT_SHDN] = mask_shdn & mask_all;
}

void MockOffload::poll_always() {
    const u8* tx_src = (const u8*)(m_dev + REG_TXRX_DAT);
    u32 tx_len  = m_dev[REG_TX_CTRL];       // Any outgoing data?
    u32 tx_mask = m_dev[REG_TX_MASK];       // Copy to each matching port.
    if (tx_len && tx_mask) {
        for (auto a = m_ports.begin() ; a != m_ports.end() ; ++a) {
            Port* const port = *a;          // Copy to each matching port.
            if (tx_mask & port->port_mask()) {
                port->m_dst->write_bytes(tx_len, tx_src);
                CHECK(port->m_dst->write_finalize());
            }
        }
    }
    m_dev[REG_TX_CTRL] = 0;                 // Frame consumed, clear length.
}

bool MockOffload::copy_to_hwbuf(unsigned idx, Readable* src) {
    if (m_dev[REG_RX_CTRL]) return false;   // Still occupied?
    unsigned len = src->get_read_ready();   // Read incoming data
    src->read_bytes(len, m_dev + REG_TXRX_DAT);
    m_dev[REG_RX_CTRL] = u32(len + 65536*idx);
    m_dev[REG_RX_IRQ] = -1;                 // Interrupt ready for service
    irq_event();                            // Notify interrupt handler
    m_dev[REG_RX_IRQ] = 0;                  // Revert to idle
    return true;                            // Success
}

MockOffload::Port::Port(unsigned index, MockOffload* parent, Writeable* dst, Readable* src)
    : m_index(index), m_parent(parent), m_dst(dst), m_src(src)
{
    m_src->set_callback(this);          // Register data_rcvd callback.
}

MockOffload::Port::~Port() {
    if (m_src) m_src->set_callback(0);  // Unregister callback (our end).
}

void MockOffload::Port::data_rcvd(Readable* src) {
    if (m_parent->copy_to_hwbuf(m_index, src))
        src->read_finalize();           // Copy OK, consume packet.
}

void MockOffload::Port::data_unlink(Readable* src) {
    m_src = 0;                          // Unregister callback (far end).
}
