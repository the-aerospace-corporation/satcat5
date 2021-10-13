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

#include "hal_pcap.h"
#include <cstdio>
#include <pcap.h>
#include <satcat5/log.h>

#ifdef _WIN32
#include <tchar.h>
#else
#include <arpa/inet.h>
#endif

namespace log   = satcat5::log;
namespace pcap  = satcat5::pcap;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Maximum frame size (TODO: Jumbo frames?)
static const unsigned MAX_ETH_FRAME = 1536;

// Global PCAP state
static pcap_if_t* g_pcap_alldevs = 0;

// Define the PCAP data structures required for a Socket.
struct pcap::Device {
    explicit Device(const char* ifname);

    const char* name() const {return m_descr->name;}

    bool m_ok;
    pcap_if_t* m_descr;
    pcap_t* m_device;
};

// First-time PCAP initialization.
bool pcap_init()
{
#ifdef _WIN32
    // Windows only: Load the Npcap DLL.
    _TCHAR npcap_dir[512];
    UINT len;
    len = GetSystemDirectory(npcap_dir, 480);
    if (!len) {
        log::Log(log::ERROR, "GetSystemDirectory").write((u32)GetLastError());
        return false;
    }

    _tcscat_s(npcap_dir, 512, _T("\\Npcap"));
    if (SetDllDirectory(npcap_dir) == 0) {
        log::Log(log::ERROR, "SetDllDirectory").write((u32)GetLastError());
        return false;
    }
#endif

    // Get the list of Ethernet devices.
    char errbuf[PCAP_ERRBUF_SIZE];
    if (pcap_findalldevs(&g_pcap_alldevs, errbuf) < 0) {
        log::Log(log::ERROR, "pcap_findalldevs = ").write(errbuf);
        return false;
    }

    // Ready to use PCAP!
    return true;
}

// Is the designated device an Ethernet interface?
bool is_ethernet_device(const char* ifname)
{
    // Attempt to open designated interface.
    char errbuf[PCAP_ERRBUF_SIZE];
    pcap_t* dev = pcap_open_live(ifname, 0, 0, 0, errbuf);

    // If successful, check type before closing.
    if (dev) {
        int type = pcap_datalink(dev);
        pcap_close(dev);
        return (type == DLT_EN10MB);
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::WARNING, ifname).write("Can't open, ").write(errbuf);
    }
    return false;
}

pcap::Descriptor::Descriptor(const char* n, const char* d)
    : name(n), desc(d)
{
    // Nothing else to initialize.
}

pcap::DescriptorList pcap::list_all_devices()
{
    pcap::DescriptorList list;

    // First-time PCAP initialization.
    if (!g_pcap_alldevs) pcap_init();

    // Scan the global list for Ethernet devices (PCAP also handles USB).
    for (pcap_if_t* dev = g_pcap_alldevs ; dev ; dev = dev->next) {
        if (is_ethernet_device(dev->name)) {
            list.push_back(pcap::Descriptor(dev->name, dev->description));
        }
    }

    return list;
}

pcap::Device::Device(const char* ifname)
    : m_ok(false)
    , m_descr(0)
    , m_device(0)
{
    // First-time setup for Pcap.
    if (!g_pcap_alldevs) pcap_init();

    // Scan list of device-descriptors for a matching name.
    for (m_descr = g_pcap_alldevs ; m_descr ; m_descr = m_descr->next) {
        if (strstr(ifname, m_descr->name)) break;
    }

    if (!m_descr) {       // Success?
        log::Log(log::ERROR, ifname).write("No matching Ethernet device.");
        return;
    }

    // Open matching device.
    char errbuf[PCAP_ERRBUF_SIZE];
    m_device = pcap_open_live(
        m_descr->name,  // Device to open
        MAX_ETH_FRAME,  // Maximum capture size
        1,              // Request promiscuous mode
        1,              // Read timeout = 1 msec
        errbuf);        // Buffer for error string

    if (!m_device) {
        log::Log(log::ERROR, ifname).write("Could not open: ").write(errbuf);
        return;
    }

    // Set non-blocking mode.
    if (pcap_setnonblock(m_device, 1, errbuf) == PCAP_ERROR) {
        log::Log(log::ERROR, ifname).write("Could not set mode: ").write(errbuf);
        return;
    }

    // Success!
    m_ok = true;
}

pcap::Socket::Socket(const char* ifname, unsigned bsize)
    : satcat5::io::BufferedIO(
        new u8[bsize], bsize, bsize/64,
        new u8[bsize], bsize, bsize/64)
    , m_device(new pcap::Device(ifname))
{
    // Nothing else to initialize.
}

pcap::Socket::~Socket()
{
    // Close down the socket.
    if (m_device) pcap_close(m_device->m_device);

    // Deallocate child objects.
    delete[] m_tx.get_buff_dtor();
    delete[] m_rx.get_buff_dtor();
    delete m_device;
}

bool pcap::Socket::ok() const
{
    return (m_device) && (m_device->m_ok);
}

void pcap::Socket::data_rcvd()
{
    // New data ready for transmission?
    unsigned nread = m_tx.get_read_ready();
    if (nread > MAX_ETH_FRAME) {
        log::Log(log::ERROR, m_device->name()).write("Tx frame too long.").write(nread);
    } else if (nread) {
        // Copy outgoing data to a working buffer...
        u8 temp[MAX_ETH_FRAME];
        m_tx.read_bytes(nread, temp);
        // ...then write to the PCAP socket.
        int result = pcap_sendpacket(m_device->m_device, temp, nread);
        if (result <= 0)
            log::Log(log::WARNING, m_device->name()).write("Tx failed.");
    }

    // Cleanup for the next packet, if any.
    m_tx.read_finalize();
}

void pcap::Socket::poll()
{
    struct pcap_pkthdr* pkt_header;
    const u_char *pkt_data;

    // Attempt to read next frame from PCAP socket...
    int result = pcap_next_ex(m_device->m_device, &pkt_header, &pkt_data);
    if (result > 0) {
        m_rx.write_bytes(pkt_header->len, pkt_data);
        m_rx.write_finalize();
    } else if (result < 0 && DEBUG_VERBOSE > 0) {
        log::Log(log::WARNING, m_device->name()).write("Rx error.");
    }
}
