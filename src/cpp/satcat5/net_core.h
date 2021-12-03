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
// Generic network Dispatch API
//
// The reason to provide this generic API is so that some Protocols can work
// with either raw-Ethernet or UDP mode, with no required code changes.
// See "net_cfgbus.h" for an example of this usage.
//
// Most Dispatch implementations, including eth::Dispatch and ip::Dispatch,
// further provide a means for Protocols to send messages to an arbitrary
// address.  However, this requires protocol-specific arguments that cannot
// be provided in the generic API.
//

#pragma once

#include <satcat5/io_core.h>
#include <satcat5/list.h>
#include <satcat5/types.h>

namespace satcat5 {
    namespace net {
        // Each Protocol object is required to contain a Type that designates
        // the type or identity of streams it can accept, or the corresponding
        // field-values for outgoing frames.
        //
        // The formatting depends on the associated Dispatch, but is usually
        // one-to-one with EtherType, UDP port #, etc. for that network layer.
        // The size is chosen to fit any of the above without duress.
        //
        // Note: Dispatch implementations SHOULD provide public accessors
        //       for creating Type objects from EtherType, Port#, etc.
        struct Type {
        public:
            explicit constexpr Type(u8 val)   : m_value(val) {}
            explicit constexpr Type(u16 val)  : m_value(val) {}
            explicit constexpr Type(u32 val)  : m_value(val) {}
            explicit constexpr Type(u16 val1, u16 val2)
                : m_value(65536ul * val1 + val2) {}

            inline u8  as_u8()  const {return (u8) m_value;}
            inline u16 as_u16() const {return (u16)m_value;}
            inline u32 as_u32() const {return (u32)m_value;}

            inline void as_u8(u8& a) const {a = as_u8();}
            inline void as_u16(u16& a) const {a = as_u16();}
            inline void as_u32(u32& a) const {a = as_u32();}
            inline void as_pair(u16& a, u16& b) const
                {a = (u16)(m_value >> 16); b = (u16)(m_value & 0xFFFF);}

            inline bool bound() const {return (m_value != 0);}

        private:
            friend satcat5::net::Dispatch;
            u32 m_value;
        };

        constexpr satcat5::net::Type TYPE_NONE = Type((u32)0);

        // Network "Dispatch" objects:
        //  * Know their own address, and any other required parameters.
        //  * Allow registration of one or more Protocols, each tied to a
        //    specific traffic stream (e.g., an EtherType or UDP port).
        //  * Allow construction of Filters that designate
        //  * Accept incoming frames and read header information.
        //  * Apply filtering as needed for invalid frame headers.
        //  * Route the remaining data to one of several Protocol objects,
        //    comparing header field(s) until a suitable match is found.
        //  * Allow Protocol objects to send simple replies.
        class Dispatch {
        public:
            // Open a reply to the sender of the most recent message, by
            // writing frame header(s) and returning a stream where the
            // caller should write frame data, then call write_finalize().
            //
            // The length argument is the number of bytes that will be written
            // by the caller. (IPv4 and UDP require this information up-front.)
            //
            // Returns zero if sending a reply is not currently possible.
            //
            // Child MUST implement this method.
            // Child SHOULD also provide an equivalent open_write(...) method
            //  for sending messages to other recipients, when practical.
            // Child MAY ignore the "type" argument at its discretion.
            virtual satcat5::io::Writeable* open_reply(
                const satcat5::net::Type& type, unsigned len) = 0;

            // Register or unregister a Protocol object.
            inline void add(satcat5::net::Protocol* proto)
                {m_list.add(proto);}
            inline void remove(satcat5::net::Protocol* proto)
                {m_list.remove(proto);}

            // Check if a given Type has a matching Protocol.
            bool bound(const satcat5::net::Type& type) const;

        protected:
            // Constructor and destructor access restricted to children.
            Dispatch() {}
            ~Dispatch() {}

            // Deliver current message by calling Protocol::frame_rcvd(...).
            // Returns true if a matching Protocol is found.
            // Note: Caller is responsible for read_finalize(), if required.
            bool deliver(
                const satcat5::net::Type& type,
                satcat5::io::Readable* src, unsigned len);

            // Linked list of protocol objects.
            satcat5::util::List<satcat5::net::Protocol> m_list;
        };

        // Each Address object wraps a particular Dispatch + Address + Type,
        // to provide an open_write(...) method for generic Protocols.
        // Every Dispatch implementation SHOULD provide an Address wrapper.
        class Address {
        public:
            // Fetch a pointer to the underlying interface.
            // Child MUST override this method.
            virtual satcat5::net::Dispatch* iface() const = 0;

            // Open a new frame to the designated address and type.
            // Returns zero if sending a frame is not currently possible.
            // Child MUST override this method.
            virtual satcat5::io::Writeable* open_write(unsigned len) const = 0;

            // Close any open connections and revert to idle.
            // Child MUST override this method.
            virtual void close() = 0;

            // Is this address object ready for use?
            // Child MUST override this method.
            virtual bool ready() const = 0;
        };

        // Each Protocol handles a particular data stream (see above).
        class Protocol {
        public:
            // Dispatch calls frame_rcvd(...) for each incoming frame with
            // with a matching Type value.  The child class SHOULD read
            // the frame contents from the provided "src" object, which
            // is only valid until the function returns.
            //
            // To send a reply:
            //  * Call m_iface->open_reply() to obtain a Writable object.
            //    (This also writes out any applicable frame headers.)
            //  * Write frame contents, then call write_finalize().
            //
            // The child class MUST override this method.
            virtual void frame_rcvd(satcat5::io::LimitedRead& src) = 0;

        protected:
            // Constructor and destructor access restricted to children.
            // Note: Child MUST call Dispatch::add and Dispatch::remove.
            Protocol(const satcat5::net::Type& type)
                : m_filter(type), m_next(0) {}
            ~Protocol() {}

            satcat5::net::Type m_filter;        // Incoming packet filter

        private:
            // Required objects for net::Dispatch.
            friend satcat5::net::Dispatch;
            friend satcat5::util::ListCore;
            satcat5::net::Protocol* m_next;     // Linked list of Protocols
        };
    }
}
