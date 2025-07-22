//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! CBOR-encoded network logging
//!
//!\details
//! This file defines a log-to-network system, where each `Log` message is
//! encoded using CBOR (IETF-RFC-8949).  Variations using raw-Ethernet and
//! UDP are provided.  Both default to broadcast mode, but can be changed
//! to unicast by calling the connect(...) method.
//!
//! For more information on the logging system: \see log.h
//!
//! The encoding used here is compatible with the "Diagnostic Logging"
//! message defined in the "Slingshot Payload Manual" (ATR-2022-01270).
//! This manual is included in this repo under "/examples/slingshot".
//!
//! For the simpler encoding used in example designs, see "eth_chat.h".
//! (Especially eth::LogToChat, which implements the same logging API.)

#pragma once

#include <satcat5/ethernet.h>
#include <satcat5/log.h>
#include <satcat5/types.h>
#include <satcat5/udp_core.h>

// Enable this feature? (See types.h)
#if SATCAT5_CBOR_ENABLE

namespace satcat5 {
    namespace log {
        //! Read CBOR-formatted network messages and copy to the local log.
        //!
        //! \link log_cbor.h SatCat5 CBOR log messages. \endlink
        //!
        //! This class is not intended to be used directly.  For a specific
        //! protocol, `satcat5::eth::FromCbor` or `satcat5::udp::FromCbor`.
        class FromCbor : public satcat5::net::Protocol {
        protected:
            //! Only children can safely access constructor/destructor.
            FromCbor(
                satcat5::net::Dispatch* src,        // Incoming message interface
                satcat5::net::Type filter);         // Incoming message type
            ~FromCbor() SATCAT5_OPTIONAL_DTOR;

            //! Event handler for incoming messages.
            //! After parsing and validation, this method calls `log_event`.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            //! Event handler for validated messages.
            //! The built-in handler creates a `log::Log` message object, which
            //! notifies all local `log::EventHandler` instances. Users may
            //! override this method in a child class to add new behavior.
            //! Note: The string argument is NOT null-terminated.
            virtual void log_event(s8 priority, unsigned nbytes, const char* msg);

            //! Pointer to the interface object.
            satcat5::net::Dispatch* const m_src;

        public:
            //! Set the minimum priority for message forwarding.
            //! By default, all messages are forwarded for processing.
            //! After calling this method, messages below the specified
            //! cutoff are ignored.
            void set_min_priority(s8 priority) {m_min_priority = priority;}

        private:
            s8 m_min_priority = satcat5::log::DEBUG;  // default to handle everything
        };

        //! Write local logs to a CBOR-formatted network message.
        //!
        //! \link log_cbor.h SatCat5 CBOR log messages. \endlink
        //!
        //! This class is not intended to be used directly.  For a specific
        //! protocol, `satcat5::eth::ToCbor` or `satcat5::udp::ToCbor`.
        class ToCbor : public satcat5::log::EventHandler {
        protected:
            //! Only children can safely access constructor/destructor.
            //! Constructor sets the destination address and interface.
            explicit ToCbor(satcat5::net::Address* dst);
            ~ToCbor() {}

            // Implement the required "log_event" handler.
            void log_event(s8 priority, unsigned nbytes, const char* msg) override;

            // Destination interface and address.
            satcat5::net::Address* const m_dst;
        public:
            // Set the minimum level (priority). Messages below this level will be ignored.
            void set_min_priority(s8 priority) {m_min_priority = priority;}
        private:
            s8 m_min_priority = satcat5::log::DEBUG;  // default to handle everything
        };
    }

    namespace eth {
        //! Specialization of `satcat5::log::FromCbor` for raw-Ethernet frames.
        class LogFromCbor final
            : public satcat5::log::FromCbor
        {
        public:
            //! Constructor binds to a specific interface and EtherType.
            LogFromCbor(
                satcat5::eth::Dispatch* iface,      // Ethernet interface
                const satcat5::eth::MacType& typ);  // Incoming EtherType
            ~LogFromCbor() {}
        };

        //! Specialization of `satcat5::log::ToCbor` for raw-Ethernet frames.
        class LogToCbor final
            : public satcat5::eth::AddressContainer
            , public satcat5::log::ToCbor
        {
        public:
            //! Constructor binds to a specific interface and EtherType.
            //! The default destination is the broadcast address.  To change
            //! this behavior, call `connect`.
            LogToCbor(
                satcat5::eth::Dispatch* eth,        // Ethernet interface
                const satcat5::eth::MacType& typ);  // Destination EtherType
            ~LogToCbor() {}

            //! Set the destination address.
            inline void connect(
                const satcat5::eth::MacAddr& addr,
                const satcat5::eth::MacType& type)
                { m_addr.connect(addr, type); }

            //! Stop message forwarding.
            inline void close()
                { m_addr.close(); }
        };
    }

    namespace udp {
        //! Specialization of `satcat5::log::FromCbor` for UDP datagrams.
        class LogFromCbor final
            : public satcat5::log::FromCbor
        {
        public:
            //! Constructor binds to a specific incoming UDP port.
            LogFromCbor(
                satcat5::udp::Dispatch* iface,      // UDP interface
                const satcat5::udp::Port& port);    // Incoming UDP port
            ~LogFromCbor() {}
        };

        //! Specialization of `satcat5::log::ToCbor` for UDP datagrams.
        class LogToCbor final
            : public satcat5::udp::AddressContainer
            , public satcat5::log::ToCbor
        {
        public:
            //! Constructor binds to a specific interface and port number.
            //! The default destination is the IPv4 broadcast address.
            //! To change this behavior, call `connect`.
            LogToCbor(
                satcat5::udp::Dispatch* udp,        // UDP interface
                const satcat5::udp::Port& dstport); // Destination port
            ~LogToCbor() {}

            //! Set the destination address.
            inline void connect(
                const satcat5::udp::Addr& dstaddr,
                const satcat5::udp::Port& dstport)
                { m_addr.connect(dstaddr, dstport, 0);}

            //! Stop message forwarding.
            inline void close()
                { m_addr.close(); }
        };
    }
}

#endif // SATCAT5_CBOR_ENABLE
