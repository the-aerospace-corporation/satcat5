//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022, 2023 The Aerospace Corporation
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

#include "hal_pcap/hal_pcap.h"
#include <cstdio>
#include <cstring>
#include <iostream>
#include <satcat5/log.h>

// PCAP must be included last due to name conflicts on some platforms.
#include <pcap.h>

// Platform-specific includes
#ifdef _WIN32
    #include <tchar.h>
    #undef ERROR            // Deconflict Windows "ERROR" macro
#else
    #include <arpa/inet.h>
#endif

namespace eth   = satcat5::eth;
namespace log   = satcat5::log;
namespace spcap = satcat5::pcap;

// Set verbosity level (0/1/2)
static const unsigned DEBUG_VERBOSE = 0;

// Maximum frame size (TODO: Jumbo frames?)
static const unsigned MAX_ETH_FRAME = 1536;

// Global PCAP state
static pcap_if_t* g_pcap_alldevs = 0;

// Define the PCAP data structures required for a Socket.
struct spcap::Device {
    explicit Device(const char* ifname, u16 filter);

    const char* name() const {return m_descr->name;}
    const char* desc() const {return m_descr->description;}

    bool m_ok;
    pcap_if_t* m_descr;
    pcap_t* m_device;
    struct bpf_program m_filter;
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
        log::Log(log::ERROR, "pcap_findalldevs", errbuf);
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
        log::Log(log::WARNING, ifname, "Can't open, ").write(errbuf);
    }
    return false;
}

spcap::Descriptor::Descriptor(const char* n, const char* d)
    : name(n), desc(d ? d : n)
{
    // Nothing else to initialize.
}

spcap::DescriptorList spcap::list_all_devices()
{
    spcap::DescriptorList list;

    // First-time PCAP initialization.
    if (!g_pcap_alldevs) pcap_init();

    // Scan the global list for Ethernet devices (PCAP also handles USB).
    for (pcap_if_t* dev = g_pcap_alldevs ; dev ; dev = dev->next) {
        if (is_ethernet_device(dev->name)) {
            list.push_back(spcap::Descriptor(dev->name, dev->description));
        }
    }

    return list;
}

bool spcap::is_device(const char* ifname)
{
    // First-time setup for Pcap.
    if (!g_pcap_alldevs) pcap_init();

    // Scan list of device-descriptors for a matching name.
    for (pcap_if_t* dev = g_pcap_alldevs ; dev ; dev = dev->next) {
        if (strstr(ifname, dev->name)) return true;
    }

    return false;   // No match
}

std::string spcap::prompt_for_ifname()
{
    // Sanity check: Only one option? No options at all?
    spcap::DescriptorList devs = spcap::list_all_devices();
    if (devs.size() == 1) return devs[0].name;
    if (devs.size() == 0) {
        std::cerr << "No valid PCAP devices." << std::endl;
        return "";
    }

    // Otherwise print a menu of options.
    std::cout << "Please select a device from the list:" << std::endl;
    for (unsigned a = 0 ; a < devs.size() ; ++a) {
        std::cout << "  " << a << ":\t" << devs[a].desc << std::endl;
    }
    std::cout << "  (Any other number to cancel)" << std::endl;

    // Return selected index, if valid.
    int sel = -1;
    std::cin >> sel;
    if (sel < 0 || sel >= (int)devs.size())
        return "";
    else
        return devs[sel].name;
}

spcap::Device::Device(const char* ifname, u16 filter)
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
        log::Log(log::ERROR, ifname, "No matching Ethernet device.");
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
        log::Log(log::ERROR, ifname, "Could not open: ").write(errbuf);
        return;
    }

    // Set non-blocking mode.
    if (pcap_setnonblock(m_device, 1, errbuf) == PCAP_ERROR) {
        log::Log(log::ERROR, ifname, "Could not set mode: ").write(errbuf);
        return;
    }

    // Enable a filter for incoming packets?
    if (filter) {
        char filter_str[128];
        snprintf(filter_str, sizeof(filter_str), "ether proto 0x%04X", filter);
        if (pcap_compile(m_device, &m_filter, filter_str, 1, PCAP_NETMASK_UNKNOWN) < 0) return;
        if (pcap_setfilter(m_device, &m_filter) < 0) return;
    }

    // Success!
    m_ok = true;
}

spcap::Socket::Socket(const char* ifname, unsigned bsize, eth::MacType filter)
    : satcat5::io::BufferedIO(
        new u8[bsize], bsize, bsize/64,
        new u8[bsize], bsize, bsize/64)
    , m_device(new spcap::Device(ifname, filter.value))
{
    // Nothing else to initialize.
}

spcap::Socket::~Socket()
{
    // Close down the socket.
    if (m_device) pcap_close(m_device->m_device);

    // Deallocate child objects.
    delete[] m_tx.get_buff_dtor();
    delete[] m_rx.get_buff_dtor();
    delete m_device;
}

bool spcap::Socket::ok() const
{
    return (m_device) && (m_device->m_ok);
}

const char* spcap::Socket::name() const
{
    return m_device ? m_device->name() : "";
}

const char* spcap::Socket::desc() const
{
    return m_device ? m_device->desc() : "";
}

void spcap::Socket::data_rcvd()
{
    // New data ready for transmission?
    unsigned nread = m_tx.get_read_ready();
    if (nread > MAX_ETH_FRAME) {
        log::Log(log::ERROR, m_device->name(), "Tx frame too long.").write(nread);
    } else if (nread && ok()) {
        // Copy outgoing data to a working buffer...
        u8 temp[MAX_ETH_FRAME];
        m_tx.read_bytes(nread, temp);
        // ...then write to the PCAP socket.
        int result = pcap_sendpacket(m_device->m_device, temp, nread);
        if (result < 0)
            log::Log(log::WARNING, m_device->name(), "Tx failed:\n")
                .write(pcap_geterr(m_device->m_device));
    }

    // Cleanup for the next packet, if any.
    m_tx.read_finalize();
}

void spcap::Socket::poll_always()
{
    struct pcap_pkthdr* pkt_header;
    const u_char *pkt_data;

    // Sanity check before polling...
    if (!ok()) return;

    // Attempt to read next frame from PCAP socket...
    int result = pcap_next_ex(m_device->m_device, &pkt_header, &pkt_data);
    if (result > 0) {
        m_rx.write_bytes(pkt_header->len, pkt_data);
        m_rx.write_finalize();
    } else if (result < 0 && DEBUG_VERBOSE > 0) {
        log::Log(log::WARNING, m_device->name(), "Rx error:\n")
            .write(pcap_geterr(m_device->m_device));
    }
}
