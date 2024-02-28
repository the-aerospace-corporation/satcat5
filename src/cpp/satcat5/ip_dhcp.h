//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Dynamic Host Configuration Protocol (DHCP) client and server
//
// Dynamic Host Configuration Protocol is used to automatically assign
// or request IP addresses for hosts on an IPv4 subnet.  DHCP servers
// maintain a pool of free and assigned addresses; DHCP clients contact
// the server to request an address.
//
// To use the DHCP client:
//  * Initialize the UDP-dispatch or IP-stack object with ip::ADDR_NONE.
//  * Create an ip::DhcpClient object linked to the UDP-dispatch object.
//  * Client will automatically issue a DHCP request after a short delay.
//
// To use the DHCP server:
//  * Initialize the UDP-dispatch or IP-stack object.
//    The assigned IP-address should be outside the DHCP range.
//  * Allocate an ip::DhcpPool object (usually DhcpPoolStatic).
//  * Create an ip::DhcpServer object, providing pointers to the
//    UDP-dispatch object and the DHCP-pool object.
//
// See also: IETF RFC2131: https://www.rfc-editor.org/rfc/rfc2131
//

#pragma once

#include <satcat5/eth_arp.h>
#include <satcat5/net_core.h>
#include <satcat5/ip_core.h>
#include <satcat5/polling.h>
#include <satcat5/udp_core.h>

// Set default for maximum client-ID length (range 1 - 254).
#ifndef SATCAT5_DHCP_MAX_ID_LEN
#define SATCAT5_DHCP_MAX_ID_LEN 62
#endif

namespace satcat5 {
    namespace ip {
        // A unique client-identifier.
        struct DhcpId {
            u8 id_len;      // Number of bytes in "id"
            u8 type;        // Type code (RFC2132 Section 9.14)
            u8 id[SATCAT5_DHCP_MAX_ID_LEN];
        };

        // Client states match the ones in RFC2131 Figure 5, except that
        // we've added a few new internal wait states (e.g., ARP queries).
        enum class DhcpState {
            INIT,       // Initial state
            SELECTING,  // DISCOVER sent, waiting for OFFER
            TESTING,    // ARP sent, waiting for reply
            REQUESTING, // REQUEST sent, waiting for ACK
            BOUND,      // Successfully bound
            RENEWING,   // Normal unicast renew
            REBINDING,  // Fallback broadcast renew
            INFORMING,  // INFORM pending or sent; waiting for ACK
            STOPPED,    // Manually halted
        };

        // DHCP Client for leasing an IP address from a server.
        class DhcpClient final
            : public satcat5::eth::ArpListener
            , public satcat5::net::Protocol
            , public satcat5::poll::Timer
        {
        public:
            // Attach this DHCP client to a UDP-dispatch object.
            DhcpClient(satcat5::udp::Dispatch* iface);
            ~DhcpClient() SATCAT5_OPTIONAL_DTOR;

            // Set a static IP and fetch other parameters from the server.
            void inform(const satcat5::ip::Addr& new_addr);

            // Relinquish the currently held lease, if one exists.
            // Halts automatic requests until renew() is called.
            // If an address is provided, set the new static IP address.
            void release(const satcat5::ip::Addr& new_addr = satcat5::ip::ADDR_NONE);

            // Request extension of current lease if held, otherwise
            // request a new lease.  Resumes automatic requests.
            void renew();

            // Report current lease state.
            inline satcat5::ip::DhcpState state() const
                { return m_state; }

            // Report remaining lease time, or zero if none is held.
            u32 status() const;

            // Set an explicit client identifier (RFC2132 Section 9.14).
            // This is not normally required, but can help ensure continuity
            // when switching between network adapters (e.g., wired/wireless).
            inline void set_client_id(const satcat5::ip::DhcpId* id)
                { m_client_id = id; }

        private:
            // Event handler methods.
            void arp_event(
                const satcat5::eth::MacAddr& mac,
                const satcat5::ip::Addr& ip) override;
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            // Internal methods.
            void next_timer();
            void send_message(u8 opcode);

            // Internal state.
            satcat5::udp::Dispatch* const m_iface;
            const satcat5::ip::DhcpId* m_client_id;
            satcat5::udp::Address m_server; // Server IP+MAC address
            satcat5::ip::DhcpState m_state; // Client state
            satcat5::ip::Addr m_ipaddr;     // Assigned IP address, if any
            u16 m_seconds;                  // Seconds since start of process
            u32 m_server_id;                // Server-ID (may not match IP-addr)
            u32 m_timeout;                  // Time to next action, in seconds
            u32 m_xid;                      // Client/server transaction-ID
        };

        // One address in the pool allocated to a DhcpServer.
        struct DhcpAddress {
            u32 client;                     // Hash of client-ID
            u32 timeout;                    // Lease expiration time
        };

        // Generic container for a group of DhcpAddress objects.
        // Most users should use DhcpPoolStatic, but more complex use cases
        // such as non-contiguous ranges may need a custom implementation.
        class DhcpPool {
        public:
            // Find index associated with the given IP address.
            // If none is found, return any out-of-bounds index.
            // Child classes MUST override this method.
            virtual unsigned addr2idx(const satcat5::ip::Addr& addr) const = 0;

            // Fetch IP-address for Nth object in the pool, or
            // return ip::ADDR_NONE if the index is out of bounds.
            // Child classes MUST override this method.
            virtual satcat5::ip::Addr idx2addr(unsigned idx) const = 0;

            // Fetch metadata for Nth object in the pool, or
            // return NULL if the index is out of bounds.
            // Child classes MUST override this method.
            virtual satcat5::ip::DhcpAddress* idx2meta(unsigned idx) = 0;

            // Does this pool contain the designated address?
            inline bool contains(const satcat5::ip::Addr& addr)
                { return idx2addr(addr2idx(addr)).value > 0; }

            // Two-step lookup of metadata from address.
            inline satcat5::ip::DhcpAddress* addr2meta(const satcat5::ip::Addr& addr)
                { return idx2meta(addr2idx(addr)); }
        };

        // The simplest possible implementation of DhcpPool, supporting
        // a contiguous range of IP-addresses from BASE to BASE+SIZE-1.
        template <unsigned SIZE> class DhcpPoolStatic final
            : public satcat5::ip::DhcpPool
        {
        public:
            DhcpPoolStatic(const satcat5::ip::Addr& base) : m_base(base) {}

            unsigned addr2idx(const satcat5::ip::Addr& addr) const override
                { return (unsigned)(addr.value - m_base.value); }

            satcat5::ip::Addr idx2addr(unsigned idx) const override
                { return (idx < SIZE) ? (m_base + idx) : ADDR_NONE; }

            satcat5::ip::DhcpAddress* idx2meta(unsigned idx) override
                { return (idx < SIZE) ? (m_array + idx) : 0; }

        private:
            const satcat5::ip::Addr m_base;
            satcat5::ip::DhcpAddress m_array[SIZE];
        };

        // DHCP Server for managing leases to other clients.
        class DhcpServer final
            : public satcat5::net::Protocol
            , public satcat5::poll::Timer
        {
        public:
            // Attach this DHCP server to a UDP-dispatch object and address pool.
            DhcpServer(
                satcat5::udp::Dispatch* iface,
                satcat5::ip::DhcpPool* pool);
            ~DhcpServer() SATCAT5_OPTIONAL_DTOR;

            // Report the number of active or open leases.
            void count_leases(unsigned& free, unsigned& taken) const;

            // Manually request/reserve an IP address for the next N seconds.
            // Request a specific address or ADDR_NONE for the first available.
            satcat5::ip::Addr request(u32 lease_seconds,
                const satcat5::ip::Addr& addr = satcat5::ip::ADDR_NONE);

            // Set various optional fields.
            inline void set_dns(const satcat5::ip::Addr& addr)
                { m_dns = addr; }
            inline void set_domain(const char* name)
                { m_domain = name; }
            inline void set_gateway(const satcat5::ip::Subnet& gateway)
                { m_gateway = gateway; }

            // Other controls, mostly used for testing.
            inline void max_lease(u32 seconds)
                { m_max_lease = seconds; }

        private:
            // Event handler methods.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            // Internal methods.
            satcat5::ip::Addr offer(
                u32 client_id, u32 req_ipaddr, u32 req_lease);
            satcat5::ip::Addr reserve(
                u32 client_id, u32 req_ipaddr, u32 req_lease);

            // Pointers to helper objects.
            satcat5::udp::Dispatch* const m_iface;
            satcat5::ip::DhcpPool* const m_pool;

            // Current reference time.
            u32 m_time;
            u32 m_max_lease;

            // Round-robin indexing into the lease pool.
            unsigned m_next_lease;          // Next lease request
            unsigned m_next_timer;          // Next timer event

            // Parameters relayed to new clients.
            satcat5::ip::Addr m_dns;        // DNS server, if one is available
            const char* m_domain;           // Domain name (human-readable)
            satcat5::ip::Subnet m_gateway;  // Default gateway and subnet mask
        };
    }
}
