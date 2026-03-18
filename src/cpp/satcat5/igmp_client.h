//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Client-side implementation of the Internet Group Management Protocol (IGMP)
//!
//!\details
//! Any IPv4 packet sent to 224.0.0.0/8 (i.e., 224.*.*.*) is a "multicast"
//! packet. Routers should send multicast packets to interested recipients,
//! including routers with downstream recipients, but avoid sending them
//! to uninterested hosts.  IGMP is the protocol that routers to determine
//! which next-hop interface(s) have members subscribed to a given multicast
//! address (i.e., a "group"), so it can forward only to those port(s).
//!
//! This file implements the "host" (i.e., client/endpoint) side of IGMP:
//! * ip::IgmpAddress represents a client subscription to a multicast group.
//! * ip::IgmpClient is the host endpoint that responds to IGMP queries.
//!
//! As required by IETF, the client defaults to IGMPv3, but is fully backwards
//! compatible with IGMPv1 and IGMPv2, and will downgrade as needed to support
//! networks with legacy routers.  However, SatCat5 does not currently support
//! the source-address filtering features of IGMPv3, always responding as if
//! the end-user has requested an exclude-none policy.
//!
//! IGMPv1 is defined by [IETF RFC-1112](https://www.rfc-editor.org/rfc/rfc1112).
//! IGMPv2 is defined by [IETF RFC-2236](https://www.rfc-editor.org/rfc/rfc2236).
//! IGMPv3 is defined by [IETF RFC-9776](https://www.rfc-editor.org/rfc/rfc9776).

#pragma once

#include <satcat5/ip_core.h>
#include <satcat5/list.h>
#include <satcat5/net_protocol.h>
#include <satcat5/polling.h>

// Enable support for IPv4 multicast and IGMP?
// For memory-constrained projects that do not need to receive multicast
// packets, dropping IGMP support can reduce code size by about 3 kB.
// For GCC/G++: compiler flag "-DSATCAT5_IGMP_ENABLE=0" to disable.
#ifndef SATCAT5_IGMP_ENABLE
#define SATCAT5_IGMP_ENABLE 1
#endif

namespace satcat5 {
    namespace igmp {
        // Destination addresses for IGMP broadcasts:
        constexpr satcat5::ip::Addr
            DST_ALL_SYSTEMS(224, 0, 0, 1),      //!< All endpoints on subnet.
            DST_ALL_ROUTERS(224, 0, 0, 2),      //!< All routers on subnet.
            DST_IGMPV3_REPORT(224, 0, 0, 22);   //!< Group for IGMPv3 reports.

        //! Set upper and lower bounds for the length of an IGMP message.
        //!@{
        constexpr unsigned
            MIN_LEN_SHORTS  = 4,
            MIN_LEN_BYTES   = 2 * MIN_LEN_SHORTS,
            MAX_LEN_SHORTS  = 730,
            MAX_LEN_BYTES   = 2 * MAX_LEN_SHORTS,
            MAX_V3_RECORDS  = (MAX_LEN_SHORTS - 4) / 4;
        //!@}

        // Protocol constants:
        constexpr u16
            MASK_TYPE           = 0xFF00,   //!< Bit-mask "type" from first header word
            MASK_MAXLEN         = 0x00FF,   //!< Bit-mask "length" from first header word
            TYPE_QUERY          = 0x1100,   //!< IGMP query (all versions)
            TYPE_REPORT_V1      = 0x1200,   //!< Reply to IGMPv1 query
            TYPE_REPORT_V2      = 0x1600,   //!< Reply to IGMPv2 query
            TYPE_LEAVE_V2       = 0x1700,   //!< Leaving group (v2 / v3)
            TYPE_REPORT_V3      = 0x2200,   //!< Reply to IGMPv3 query
            RECORD_MODE_INCL    = 0x0100,   //!< Record type: Include mode
            RECORD_MODE_EXCL    = 0x0200,   //!< Record type: Exclude mode
            RECORD_CHANGE_INCL  = 0x0300,   //!< Record type: Change to INCL mode
            RECORD_CHANGE_EXCL  = 0x0400,   //!< Record type: Change to EXCL mode
            RECORD_ALLOW_NEW    = 0x0500,   //!< Record type: Append to allow list
            RECORD_BLOCK_OLD    = 0x0600;   //!< Record type: Append to block list

        //! Given IGMP message contents, write Eth/IP headers and send packet.
        //! This helper function is used by igmp::Client and igmp::Server.
        bool igmp_send(
            satcat5::ip::Dispatch* iface,
            const satcat5::ip::Addr& dst,
            const unsigned wcount, u16* data);

        //! Given the first word of the IGMP query header, decode max delay.
        //! The overall message length allows the IGMP version to be inferred.
        //! \returns Maximum delay in milliseconds.
        u32 decode_maxdly(u16 hdr, bool v3);

        //! Host/Client for the Internet Group Management Protocol (IGMP).
        //!
        //! This class implements the client ("host") side of IGMP.  It sends
        //! messages when the local endpoint joins or leaves a group, and
        //! responds to group membership queries from the server ("querier"),
        //! which is usually an IGMP-capable IPv4 router.
        //!
        //! This client supports IGMPv1, IGMPv2, and IGMPv3 queries, though
        //! SatCat5 endpoints do not currently support the source-address
        //! filtering features of IGMPv3.
        //!
        //! \see igmp_client.h, igmp::Address, igmp::Server.
        class Client final
            #if SATCAT5_IGMP_ENABLE
            : protected satcat5::net::Protocol
            , protected satcat5::poll::Timer
            #endif
        {
        public:
            //! Link this handler to an IPv4 network interface.
            explicit Client(satcat5::ip::Dispatch* iface);
            ~Client();

            //! Join a multicast group. \see igmp::Address::join.
            //! \param obj Endpoint object to be modified.
            //! \param addr Multicast address/group to be joined.
            //! The multicast address must be from the 224.0.0.0/48 block.
            //! This method has no effect if SATCAT5_IGMP_ENABLE=0.
            void join(satcat5::igmp::Address& obj, const satcat5::ip::Addr& addr);

            //! Leave a multicast group. \see igmp::Address::leave.
            //! This method has no effect if SATCAT5_IGMP_ENABLE=0.
            void leave(satcat5::igmp::Address& obj);

        protected:
            #if SATCAT5_IGMP_ENABLE
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;
            satcat5::igmp::Address* find_match(const satcat5::ip::Addr& group) const;
            void send_leave(const satcat5::ip::Addr& group);
            void send_report(const satcat5::ip::Addr& group);
            void set_timer(u32& timer, u32 max_msec);

            satcat5::ip::Dispatch* const m_iface;
            satcat5::util::List<satcat5::igmp::Address> m_groups;
            u32 m_reply_timer;
            u8 m_version;
            #endif
        };

        //! Client state for an IGMP multicast subscription.
        //! Classes such as ip::Address and ptp::Client instantiate this
        //! object to manage IGMP subscriptions for a specific group address.
        //! \see igmp_client.h, ip::Address, igmp::Client.
        struct Address {
        public:
            //! Constructor for an address placeholder.
            //! Child is responsible for registering with IgmpClient
            //! when it wishes to join or leave a multicast group.
            constexpr Address()
                #if SATCAT5_IGMP_ENABLE
                : m_igmp_group(0), m_igmp_timer(0), m_next(nullptr)
                #endif
                {}  // Empty stub if IGMP is disabled.

            //! Join a multicast group.
            //! This is a thin wrapper for igmp::Client::join. The two have
            //! the same effect; use whichever method is more convenient.
            //! \param igmp Local IGMP client. \see ip::Stack::igmp.
            //! \param addr Multicast address/group to be joined.
            //! The multicast address must be from the 224.0.0.0/8 block.
            inline void join(satcat5::igmp::Client* igmp, const satcat5::ip::Addr& addr)
                { igmp->join(*this, addr); }

            //! Leave a multicast group.
            //! This is a thin wrapper for igmp::Client::leave. The two have
            //! the same effect; use whichever method is more convenient.
            inline void leave(satcat5::igmp::Client* igmp)
                { igmp->leave(*this); }

        protected:
            #if SATCAT5_IGMP_ENABLE
            // Required state for the IGMP protocol.
            friend satcat5::igmp::Client;
            satcat5::ip::Addr m_igmp_group;
            u32 m_igmp_timer;

            // Linked list to the next IgmpAddress object.
            friend satcat5::util::ListCore;
            satcat5::igmp::Address* m_next;
            #endif
        };
    }
}
