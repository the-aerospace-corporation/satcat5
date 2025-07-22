//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Wrapper for PCAP / NPCAP socket library and supporting functions.
//!
//!\details
//! PCAP is a cross-platform API for sending and receiving raw Ethernet frames.
//! To use these utilities, install the library for your host operating system:
//!  * Linux: libpcap-dev
//!      e.g., "apt-get install libpcap-dev" or equivalent
//!  * Windows: NPCAP + NPCAP-SDK
//!      https://nmap.org/npcap/#download
//!
//! This file defines a class that converts a PCAP Layer-2 socket to a SatCat5
//! Writeable/Readable stream, which can be used to send and receive Ethernet
//! frames.  It also defines functions for listing and selecting an interface
//! from the list provided by the PCAP API.
//!
//! Note: Use of these tools may require root/admin privileges.

#pragma once

#include <deque>
#include <string>
#include <satcat5/ethernet.h>
#include <satcat5/io_buffer.h>
#include <satcat5/polling.h>

namespace satcat5 {
    namespace pcap {
        //! Helper object for pcap::Device. Internal use only.
        struct Device;

        //! Adapter for a PCAP Layer-2 socket. \see hal_pcap.h
        class Socket
            : public satcat5::io::BufferedIO
            , protected satcat5::poll::Always
        {
        public:
            //! Open the specified interface by name.
            //! Interface name format varies by platform.  Most users should
            //! choose a name using `list_all_devices` or `prompt_for_ifname`.
            //! This interface listens for all EtherTypes by default. If only
            //! one EtherType is desired, set the `filter` argument.
            //! \param ifname Interface name (OS-specific).
            //! \param bsize Buffer size, in bytes.
            //! \param filter Optional filter for incoming packets.
            explicit Socket(
                const char* ifname,
                unsigned bsize=65536,
                satcat5::eth::MacType filter = satcat5::eth::ETYPE_NONE);
            virtual ~Socket();

            //! Is the socket in a usable state?
            bool ok() const;

            // Other useful info.
            const char* name() const;   //!< Unique interface ID.
            const char* desc() const;   //!< Human-readable name.

        protected:
            void data_rcvd(satcat5::io::Readable* src) override;
            void poll_always() override;

            satcat5::pcap::Device* const m_device;
        };

        //! Structure for holding a device-name and user-readable description.
        //! The "name" field can be passed to the Socket constructor.
        struct Descriptor {
            Descriptor(const char* n, const char* d);

            std::string name;   //!< Unique interface ID.
            std::string desc;   //!< Human-readable name.
        };
        typedef std::deque<satcat5::pcap::Descriptor> DescriptorList;

        //! Fetch a list of Ethernet device descriptors.
        //! \see hal_pcap.h, pcap::Socket, prompt_for_ifname
        satcat5::pcap::DescriptorList list_all_devices();

        //! Check if a given name is on the list from `list_all_devices`.
        bool is_device(const char* ifname);

        //! Print a list of Ethernet devices, and select by index.
        //! Returns the "name" field from the selected Descriptor.
        //! \see hal_pcap.h, pcap::Socket, list_all_devices
        std::string prompt_for_ifname();
    }
}
