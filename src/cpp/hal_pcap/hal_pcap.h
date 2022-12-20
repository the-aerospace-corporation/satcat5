//////////////////////////////////////////////////////////////////////////
// Copyright 2021, 2022 The Aerospace Corporation
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
// Wrapper for PCAP / NPCAP socket library and supporting functions
//
// PCAP is a cross-platform API for sending and receiving raw Ethernet frames.
// To use these utilities, install the library for your host operating system:
//  * Linux: libpcap-dev
//      e.g., "apt-get install libpcap-dev" or equivalent
//  * Windows: NPCAP + NPCAP-SDK
//      https://nmap.org/npcap/#download
//
// This file defines a class that converts a PCAP Layer-2 socket to a SatCat5
// Writeable/Readable stream, which can be used to send and receive Ethernet
// frames.  It also defines functions for listing and selecting an interface
// from the list provided by the PCAP API.
//
// Note: Use of these tools may require root/admin privileges.
//

#pragma once

#include <deque>
#include <string>
#include <satcat5/ethernet.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace pcap {
        // Prototype for an internal helper object.
        struct Device;

        // Adapter for a PCAP Layer-2 socket.
        class Socket
            : public satcat5::io::BufferedIO
            , protected satcat5::poll::Always
        {
        public:
            // Open the specified interface by name.
            // Listens for all EtherTypes by default, specify value
            // value to filter for a specific incoming EtherType.
            explicit Socket(
                const char* ifname,
                unsigned bsize=65536,
                satcat5::eth::MacType filter = satcat5::eth::ETYPE_NONE);
            virtual ~Socket();

            // Is the socket in a usable state?
            bool ok() const;

            // Other useful info.
            const char* name() const;
            const char* desc() const;

        protected:
            void data_rcvd() override;
            void poll_always() override;

            satcat5::pcap::Device* const m_device;
        };

        // Structure for holding a device-name and user-readable description.
        // The "name" field can be passed to the Socket constructor.
        struct Descriptor {
            Descriptor(const char* n, const char* d);

            std::string name;
            std::string desc;
        };
        typedef std::deque<satcat5::pcap::Descriptor> DescriptorList;

        // Fetch a list of Ethernet device descriptors.
        satcat5::pcap::DescriptorList list_all_devices();

        // Check if a given name is on the list from "list_all_devices".
        bool is_device(const char* ifname);

        // Print a list of Ethernet devices, and select by index.
        // Returns the "name" field from the selected Descriptor.
        std::string prompt_for_ifname();
    }
}
