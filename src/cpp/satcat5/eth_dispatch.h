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
// Ethernet protocol dispatcher.

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/net_core.h>

namespace satcat5 {
    namespace eth {
        // Implemention of "net::Dispatch" for Ethernet frames.
        class Dispatch final
            : public satcat5::net::Dispatch
            , public satcat5::io::EventListener
        {
        public:
            // Connect to any valid I/O source and sink.
            // (e.g., satcat5::port::MailMap or satcat5::eth::SlipCodec.)
            Dispatch(
                const satcat5::eth::MacAddr& addr,
                satcat5::io::Writeable* dst,
                satcat5::io::Readable* src);
            ~Dispatch() SATCAT5_OPTIONAL_DTOR;

            // Write Ethernet frame header and get Writeable object.
            // Variants for reply (required) and any address (optional)
            satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) override;
            satcat5::io::Writeable* open_write(
                const satcat5::eth::MacAddr& dst,
                const satcat5::eth::MacType& type);

            // Other accessors:
            inline satcat5::eth::MacAddr reply_mac() const
                {return m_reply_macaddr;}

            // MAC address for this interface.
            satcat5::eth::MacAddr const m_addr;

        protected:
            // Event handler for incoming Ethernet frames.
            void data_rcvd() override;

            // Sink and source objects for the Ethernet interface.
            satcat5::io::Writeable* const m_dst;
            satcat5::io::Readable* const m_src;

            // The current reply address.
            satcat5::eth::MacAddr m_reply_macaddr;
        };
    }
}
