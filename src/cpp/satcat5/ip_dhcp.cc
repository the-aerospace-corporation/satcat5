//////////////////////////////////////////////////////////////////////////
// Copyright 2023-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/ip_dhcp.h>
#include <satcat5/eth_checksum.h>
#include <satcat5/log.h>
#include <satcat5/timer.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

using satcat5::eth::crc32;
using satcat5::eth::MacAddr;
using satcat5::eth::MACADDR_BROADCAST;
using satcat5::io::ArrayWrite;
using satcat5::io::LimitedRead;
using satcat5::io::Writeable;
using satcat5::ip::Addr;
using satcat5::ip::ADDR_BROADCAST;
using satcat5::ip::ADDR_NONE;
using satcat5::ip::DEFAULT_ROUTE;
using satcat5::ip::DhcpAddress;
using satcat5::ip::DhcpClient;
using satcat5::ip::DhcpPool;
using satcat5::ip::DhcpServer;
using satcat5::ip::DhcpState;
using satcat5::net::Type;
using satcat5::udp::PORT_DHCP_CLIENT;
using satcat5::udp::PORT_DHCP_SERVER;
using satcat5::util::min_u32;
namespace log = satcat5::log;

// Enable additional logs for debugging? (Verbosity = 0/1/2)
static constexpr unsigned DEBUG_VERBOSE = 0;

// Dispatch type codes.
static constexpr Type TYPE_CLIENT = Type(PORT_DHCP_CLIENT.value);
static constexpr Type TYPE_SERVER = Type(PORT_DHCP_SERVER.value);

// Opcodes for the legacy "OP" field from BOOTP.
static constexpr u8 OP_REQUEST          = 1;
static constexpr u8 OP_REPLY            = 2;

// DHCP "magic cookie" identifier.
static constexpr u32 DHCP_MAGIC         = 0x63825363;

// Request bits in the FLAGS header.
static constexpr u16 FLAG_BROADCAST     = 0x8000;

// Field lengths in the DHCP_HEADER
static constexpr unsigned MACADDR_LEN   = 6;
static constexpr unsigned CHADDR_LEN    = 16;
static constexpr unsigned LEGACY_BYTES  = 192;
static constexpr unsigned LEGACY_WORDS  = LEGACY_BYTES / 4;

// DHCP message types for use with OPTION_MSG_TYPE (Section 3.1.2)
static constexpr u8 DHCP_DISCOVER       = 1;    // Client to server
static constexpr u8 DHCP_OFFER          = 2;    // Server to client
static constexpr u8 DHCP_REQUEST        = 3;    // Client to server
static constexpr u8 DHCP_DECLINE        = 4;    // Client to server
static constexpr u8 DHCP_ACK            = 5;    // Server to client
static constexpr u8 DHCP_NAK            = 6;    // Server to client
static constexpr u8 DHCP_RELEASE        = 7;    // Client to server
static constexpr u8 DHCP_INFORM         = 8;    // Client to server

// Minimal subset of DHCP option codes.  Type/length/value except as noted.
// See also: IETF RFC 2132: https://www.rfc-editor.org/rfc/rfc2132.html
static constexpr u8 OPTION_PAD          = 0;    // No length
static constexpr u8 OPTION_SUBNET_MASK  = 1;
static constexpr u8 OPTION_ROUTER       = 3;
static constexpr u8 OPTION_DNS_SERVER   = 6;
static constexpr u8 OPTION_DOMAIN_NAME  = 15;
static constexpr u8 OPTION_REQUEST_IP   = 50;
static constexpr u8 OPTION_LEASE_TIME   = 51;
static constexpr u8 OPTION_MSG_TYPE     = 53;
static constexpr u8 OPTION_SERVER_IP    = 54;
static constexpr u8 OPTION_CLIENT_ID    = 61;
static constexpr u8 OPTION_END          = 255;  // No length

// Various time-related constants, always in seconds.
static constexpr u32 TIME_INIT_FIRST    = 3;
static constexpr u32 TIME_INIT_RETRY    = 5;
static constexpr u32 TIME_LEASE_DEFAULT = 24 * 60 * 60;
static constexpr u32 TIME_LEASE_OFFER   = 30;
static constexpr u32 TIME_WAIT_ARP      = 3;
static constexpr u32 TIME_WAIT_OFFER    = 5;
static constexpr u32 TIME_WAIT_RENEW    = 30;
static constexpr u32 TIME_WAIT_REBIND   = 30;
static constexpr u32 TIME_WAIT_REQUEST  = 5;

// Reserved client-IDs.
static constexpr u32 CLIENT_NONE        = 0;
static constexpr u32 CLIENT_RSVD        = 1;

// Shortcut for expired or inactive leases.
static constexpr DhcpAddress LEASE_NONE = {CLIENT_NONE, 0};

// Is a given lease expired or otherwise available?
inline bool lease_expired(DhcpAddress* meta, u32 tref)
{
    // If no Client-ID exists, then the lease is ready for use.
    // Otherwise, check remaining time.  (Difference of two u32
    // timestamps is guaranteed to wrap correctly.)
    if (meta->client != CLIENT_NONE) {
        s32 rem = (s32)(meta->timeout - tref);
        return rem < 0;     // Timeout elapsed?
    } else {
        return true;        // Empty lease ignores time
    }
}

DhcpClient::DhcpClient(satcat5::udp::Dispatch* iface)
    : satcat5::net::Protocol(TYPE_CLIENT)
    , m_iface(iface)
    , m_client_id(0)
    , m_server(iface)
    // Does the interface have a static IP-address?
    , m_state(iface->ipaddr().value ? DhcpState::STOPPED : DhcpState::INIT)
    , m_ipaddr(ADDR_NONE)
    , m_server_id(0)
    // Wait a few seconds before first DHCP_DISCOVER attempt.
    , m_timeout(TIME_INIT_FIRST)
    // RFC2131 requires XID to be "random".  Local MAC address should
    // be unique, so use CRC32 as a crude psuedorandom hash.
    , m_xid(crc32(MACADDR_LEN, iface->macaddr().addr))
{
    // Additional entropy for XID.
    m_xid += m_iface->iface()->m_timer->now();

    // Call frame_rcvd() for incoming packets.
    m_iface->add(this);

    // Call timer_event() once per second.
    timer_every(1000);
}

#if SATCAT5_ALLOW_DELETION
DhcpClient::~DhcpClient()
{
    // Unlink incoming message handler.
    m_iface->remove(this);

    // Release the currently-held lease, if any.
    send_message(DHCP_RELEASE);
}
#endif

void DhcpClient::inform(const Addr& new_addr)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "User inform");

    // Release lease if held, and set the new address.
    send_message(DHCP_RELEASE);
    m_iface->iface()->set_addr(new_addr);

    // If possible, request subnet parameters after a short delay.
    if (new_addr != ADDR_NONE) {
        m_state = DhcpState::INFORMING;
        m_timeout = 1;
    }
}

void DhcpClient::release(const Addr& new_addr)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "User release");

    send_message(DHCP_RELEASE);
    m_iface->iface()->set_addr(new_addr);
}

void DhcpClient::renew()
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "User renew");

    // Do we currently hold a lease?
    if (status() > 0) {
        // Lease held -> Send REQUEST and attempt reuse.
        send_message(DHCP_REQUEST);
    } else {
        // No lease or tentative lease -> Start over.
        send_message(DHCP_DISCOVER);
    }
}

u32 DhcpClient::status() const
{
    // Do we currently hold a lease?
    if (m_state == DhcpState::BOUND) {
        return m_timeout + TIME_WAIT_REBIND + TIME_WAIT_RENEW;
    } else if (m_state == DhcpState::RENEWING) {
        return m_timeout + TIME_WAIT_REBIND;
    } else if (m_state == DhcpState::REBINDING) {
        return m_timeout;
    } else {
        return 0;
    }
}

void DhcpClient::arp_event(const MacAddr& mac, const Addr& ip)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "arp_event");

    // When we get a tentative IP through DHCPOFFER, send an ARP request to
    // test if it's already taken.  If there's a response, decline the offer.
    if (ip == m_ipaddr && mac != m_iface->macaddr()) {
        // Unregister ARP callbacks and notify server.
        log::Log(log::WARNING, "DHCP client", "Address already claimed");
        m_iface->arp()->remove(this);
        send_message(DHCP_DECLINE);
    }
}

void DhcpClient::frame_rcvd(LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "frame_rcvd");

    // Shortcut if we're not listening for DHCP messages.
    if (m_state != DhcpState::SELECTING &&
        m_state != DhcpState::REQUESTING &&
        m_state != DhcpState::RENEWING &&
        m_state != DhcpState::REBINDING &&
        m_state != DhcpState::INFORMING) return;

    // Read the BOOTP/DHCP message header.
    u8 op       = src.read_u8();
    u8 htype    = src.read_u8();
    u8 hlen     = src.read_u8();
    src.read_u8();  // hops
    u32 xid     = src.read_u32();
    src.read_u16(); // secs
    src.read_u16(); // flags
    src.read_u32(); // ciaddr
    u32 yiaddr  = src.read_u32();
    src.read_u32(); // siaddr
    src.read_u32(); // giaddr
    src.read_consume(CHADDR_LEN);
    src.read_consume(LEGACY_BYTES);
    u32 magic   = src.read_u32();

    // Sanity check before proceeding.
    if (!src.get_read_ready()) return;      // Incomplete header
    if (op != OP_REPLY) return;             // Not a server-to-client message
    if (htype != 1 || hlen != 6) return;    // Not an IPv4 / Ethernet request
    if (xid != m_xid) return;               // Transaction-ID mismatch
    if (magic != DHCP_MAGIC) return;        // Invalid "magic cookie" value

    // Scan through options for information of interest.
    // (Options in any order, so we need to parse the whole thing.)
    // TODO: Do something with DNS server and domain name options?
    u8 opcode = 0;
    u32 lease_time = 0;
    u32 server = 0;
    u32 subnet = 0;
    u32 router = 0;
    while (src.get_read_ready()) {
        // Read option type and handle no-length options.
        u8 typ = src.read_u8();
        if (typ == OPTION_PAD) continue;
        if (typ == OPTION_END) break;
        // Read option length and contents.
        u8 len = src.read_u8();
        if (typ == OPTION_SUBNET_MASK && len == 4) {
            subnet = src.read_u32();
        } else if (typ == OPTION_ROUTER && len == 4) {
            router = src.read_u32();
        } else if (typ == OPTION_LEASE_TIME && len == 4) {
            lease_time = src.read_u32();
        } else if (typ == OPTION_MSG_TYPE && len == 1) {
            opcode = src.read_u8();
        } else if (typ == OPTION_SERVER_IP && len == 4) {
            server = src.read_u32();
        } else {
            src.read_consume(len);  // Discard unsupported options
        }
    }

    // Log this event if applicable.
    if (DEBUG_VERBOSE > 0)
        log::Log(log::DEBUG, "DHCP client", "Received").write(opcode);

    // Update internal state and take further action.
    if (opcode == DHCP_OFFER && m_state == DhcpState::SELECTING) {
        // In the SELECTING state, tentatively accept the first OFFER.
        // Test if assigned IP is occupied before setting up the IP stack.
        log::Log(log::INFO, "DHCP client", "Offer received").write(yiaddr);
        m_iface->iface()->set_addr(ADDR_NONE);
        m_ipaddr = Addr(yiaddr);
        m_state = DhcpState::TESTING;
        m_timeout = TIME_WAIT_ARP;
        // Register for callbacks and send an ARP probe (RFC5227)
        m_iface->arp()->add(this);
        m_iface->arp()->send_probe(yiaddr);
    } else if (opcode == DHCP_ACK && m_state == DhcpState::INFORMING) {
        // Information only, set up the local IP stack.
        log::Log(log::INFO, "DHCP client", "Information").write(yiaddr);
        m_state = DhcpState::STOPPED;
        m_timeout = 0;
        if (router && subnet)
            m_iface->iface()->route_simple(Addr(router), Addr(subnet));
    } else if (opcode == DHCP_ACK && server == m_server_id) {
        // Lease granted.  Can we accept it?
        if (lease_time > TIME_WAIT_RENEW + TIME_WAIT_REBIND
            && yiaddr == m_ipaddr.value && m_ipaddr.is_unicast()) {
            log::Log(log::INFO, "DHCP client", "Lease granted").write(yiaddr);
            // Move to the BOUND state.
            m_state = DhcpState::BOUND;
            m_timeout = lease_time - TIME_WAIT_RENEW - TIME_WAIT_REBIND;
            // Set up the local IP stack.
            m_iface->iface()->set_addr(m_ipaddr);
            if (router && subnet)
                m_iface->iface()->route_simple(Addr(router), Addr(subnet));
        } else {
            // Reject the assigned lease.
            log::Log(log::INFO, "DHCP client", "Lease invalid").write(yiaddr);
            send_message(DHCP_RELEASE);
        }
    } else if (opcode == DHCP_NAK && server == m_server_id) {
        // Lease denied -> Shut down and start over.
        log::Log(log::WARNING, "DHCP client", "Request refused").write(yiaddr);
        m_ipaddr = ADDR_NONE;
        m_state = DhcpState::INIT;
        m_timeout = TIME_INIT_RETRY;
        m_iface->iface()->set_addr(ADDR_NONE);
    }

    // Bind the server address for later messages?
    if (m_state == DhcpState::BOUND || m_state == DhcpState::TESTING) {
        m_server_id = server;
        m_server.connect(
            m_iface->reply_ip(), m_iface->reply_mac(),
            PORT_DHCP_SERVER, PORT_DHCP_CLIENT);
    }
}

void DhcpClient::timer_event()
{
    ++m_seconds;
    if (m_timeout == 1) {
        // Execute next scheduled action.
        --m_timeout;
        next_timer();
    } else if (m_timeout > 0) {
        // Countdown to next scheduled action.
        --m_timeout;
    }
}

void DhcpClient::next_timer()
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "next_timer");

    switch (m_state) {
        case DhcpState::INIT:       // Initial state, ready for operation.
        case DhcpState::SELECTING:  // Timeout waiting for DHCPOFFER, start over.
        case DhcpState::REBINDING:  // Timeout waiting for DHCPOFFER, start over.
        case DhcpState::REQUESTING: // Timeout waiting for DHCPACK, start over.
            // Send a DISCOVER message and wait for OFFER.
            send_message(DHCP_DISCOVER);
            break;
        case DhcpState::TESTING:    // Timeout waiting for ARP reply.
            // Proceed with REQUEST and wait for ACK or NAK.
            m_iface->arp()->remove(this);
            send_message(DHCP_REQUEST);
            break;
        case DhcpState::BOUND:      // Lease expiring soon, attempt unicast renew.
        case DhcpState::RENEWING:   // Unable to unicast renew, attempt broadcast renew.
            // Send a REQUEST message and wait for ACK or NAK.
            send_message(DHCP_REQUEST);
            break;
        case DhcpState::INFORMING:  // Timeout waiting for DHCPACK, retry.
            send_message(DHCP_INFORM);
            break;
        default: break;             // LCOV_EXCL_LINE (Unreachable but harmless.)
    }
}

void DhcpClient::send_message(u8 opcode)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP client", "Sending opcode").write(opcode);

    // How does sending this message change the current state?
    if (opcode == DHCP_DISCOVER) {
        m_state   = DhcpState::SELECTING;
        m_timeout = TIME_WAIT_OFFER;
    } else if (opcode == DHCP_REQUEST && m_state == DhcpState::TESTING) {
        m_state   = DhcpState::REQUESTING;
        m_timeout = TIME_WAIT_REQUEST;
    } else if (opcode == DHCP_REQUEST && m_state == DhcpState::BOUND) {
        m_state   = DhcpState::RENEWING;
        m_timeout = TIME_WAIT_RENEW;
    } else if (opcode == DHCP_REQUEST) {
        m_state   = DhcpState::REBINDING;
        m_timeout = TIME_WAIT_REBIND;
    } else if (opcode == DHCP_DECLINE) {
        m_state   = DhcpState::INIT;
        m_timeout = TIME_INIT_RETRY;
    } else if (opcode == DHCP_RELEASE) {
        m_state   = DhcpState::STOPPED;
        m_timeout = 0;
    } else if (opcode == DHCP_INFORM) {
        m_state   = DhcpState::INFORMING;
        m_timeout = TIME_INIT_RETRY;
    } else if (DEBUG_VERBOSE > 0) {
        log::Log(log::ERROR, "DHCP client", "Unexpected command");
    }

    // Restart the elapsed-time counter?  (Table 5)
    if (opcode == DHCP_DISCOVER || opcode == DHCP_INFORM ||
        opcode == DHCP_DECLINE || opcode == DHCP_RELEASE)
        m_seconds = 0;

    // Release commands without a lease are ignored.
    if (opcode == DHCP_RELEASE && m_ipaddr == ADDR_NONE) return;

    // Should this message be a broadcast?
    bool bcast = !m_server.ready();
    if (opcode == DHCP_REQUEST && !status())
        bcast = true;   // Initial bindings are always broadcast
    if (opcode == DHCP_DISCOVER || opcode == DHCP_INFORM)
        bcast = true;   // Certain opcodes are always broadcast
    if (m_state == DhcpState::REBINDING)
        bcast = true;   // Unicast renew failed, try broadcast
    if (bcast) {
        m_server.connect(
            ADDR_BROADCAST, MACADDR_BROADCAST,
            PORT_DHCP_SERVER, PORT_DHCP_CLIENT);
    }

    // Client hardware address.
    MacAddr macaddr = m_iface->macaddr();
    u8 chaddr[CHADDR_LEN];
    for (unsigned a = 0 ; a < CHADDR_LEN ; ++a)
        chaddr[a] = (a < MACADDR_LEN) ? macaddr.addr[a] : 0;

    // Put IP address in ciaddr or an option? (Never both.)
    // See RFC2131 Table 5 for MUST/MAY/MUST-NOT rules.
    u32 ciaddr = 0, reqaddr = 0;
    if ((opcode == DHCP_RELEASE) || (opcode == DHCP_REQUEST && status() > 0)) {
        // Client holds a valid lease.
        ciaddr  = m_ipaddr.value;
        reqaddr = 0;
    } else if (opcode == DHCP_INFORM) {
        // Client holds a static address.
        ciaddr  = m_iface->ipaddr().value;
        reqaddr = 0;
    } else {
        // No lease or tentative lease.
        ciaddr  = 0;
        reqaddr = m_ipaddr.value;
    }

    // Include server address field?
    u32 server = 0;
    if (opcode == DHCP_REQUEST && m_state == DhcpState::REQUESTING)
        server = m_server_id;   // Required per RFC2131 Table 5, Col 2
    else if (opcode == DHCP_DECLINE || opcode == DHCP_RELEASE)
        server = m_server_id;   // Required per RFC2131 Table 5, Col 3

    // Write out options to determine total length.
    // See RFC2131 Table 5 for MUST/MAY/MUST-NOT rules.
    u8 buffer[64 + SATCAT5_DHCP_MAX_ID_LEN];
    ArrayWrite opt(buffer, sizeof(buffer));
    // Message type is always required.
    opt.write_u8(OPTION_MSG_TYPE);
    opt.write_u8(1);
    opt.write_u8(opcode);
    // Requested IP address.
    if (reqaddr) {
        opt.write_u8(OPTION_REQUEST_IP);
        opt.write_u8(4);
        opt.write_u32(reqaddr);
    }
    // Requested lease time.
    if (opcode == DHCP_DISCOVER || opcode == DHCP_REQUEST) {
        opt.write_u8(OPTION_LEASE_TIME);
        opt.write_u8(4);
        opt.write_u32(TIME_LEASE_DEFAULT);
    }
    // Server identifier.
    if (server) {
        opt.write_u8(OPTION_SERVER_IP);
        opt.write_u8(4);
        opt.write_u32(server);
    }
    // Client identifier.
    if (SATCAT5_DHCP_MAX_ID_LEN >= 1 &&
        SATCAT5_DHCP_MAX_ID_LEN <= 254 &&
        m_client_id && m_client_id->id_len &&
        m_client_id->id_len <= SATCAT5_DHCP_MAX_ID_LEN) {
        opt.write_u8(OPTION_CLIENT_ID);
        opt.write_u8(m_client_id->id_len + 1);
        opt.write_u8(m_client_id->type);
        opt.write_bytes(m_client_id->id_len, m_client_id->id);
    }

    // End-of-options marker.
    opt.write_u8(OPTION_END);
    opt.write_finalize();

    // Prepare to send a new UDP packet...
    unsigned msg_len = 240 + opt.written_len();
    Writeable* dst = m_server.open_write(msg_len);
    if (dst) {
        // Write the basic DHCP message header.
        dst->write_u32(0x01010600); // OP, HTYPE, HLEN, HOPS
        dst->write_u32(m_xid);      // xid
        dst->write_u16(m_seconds);  // secs
        dst->write_u16(0);          // flags = 0
        dst->write_u32(ciaddr);     // ciaddr (see above)
        dst->write_u32(0);          // yiaddr = 0
        dst->write_u32(0);          // siaddr = 0
        dst->write_u32(0);          // giaddr = 0
        dst->write_bytes(CHADDR_LEN, chaddr);
        for (unsigned a = 0 ; a < LEGACY_WORDS ; ++a)
            dst->write_u32(0);      // 192 bytes of zeros
        dst->write_u32(DHCP_MAGIC); // Magic cookie
        // Write options and send the message.
        dst->write_bytes(opt.written_len(), buffer);
        dst->write_finalize();
    }
}

DhcpServer::DhcpServer(satcat5::udp::Dispatch* iface, DhcpPool* pool)
    : satcat5::net::Protocol(TYPE_SERVER)
    , m_iface(iface)
    , m_pool(pool)
    , m_time(0)
    , m_max_lease(TIME_LEASE_DEFAULT)
    , m_next_lease(0)
    , m_next_timer(0)
    , m_dns(ADDR_NONE)
    , m_domain(0)
    , m_gateway(DEFAULT_ROUTE)
{
    // Mark the entire lease pool as available.
    unsigned idx = 0;
    while (1) {
        DhcpAddress* next = m_pool->idx2meta(idx++);
        if (next) *next = LEASE_NONE;
        else break;
    }

    // Call frame_rcvd() for incoming packets.
    m_iface->add(this);

    // Call timer_event() once per second.
    timer_every(1000);
}

#if SATCAT5_ALLOW_DELETION
DhcpServer::~DhcpServer()
{
    // Unlink incoming message handler.
    m_iface->remove(this);
}
#endif

void DhcpServer::count_leases(unsigned& free, unsigned& taken) const
{
    // Reset output counters.
    free = 0; taken = 0;

    // Iterate over the entire lease pool.
    unsigned idx = 0;
    while (1) {
        DhcpAddress* next = m_pool->idx2meta(idx++);
        if (!next)
            return;         // Reached end of list
        else if (next->timeout > 0)
            ++taken;        // Lease has been claimed
        else
            ++free;         // Lease is available
    }
}

Addr DhcpServer::request(u32 lease_seconds, const Addr& addr)
{
    log::Log(log::INFO, "DHCP server", "Local request").write(addr.value);
    if (addr == ADDR_NONE)  // First available
        return offer(CLIENT_RSVD, addr.value, lease_seconds);
    else                    // Specific address
        return reserve(CLIENT_RSVD, addr.value, lease_seconds);
}

void DhcpServer::frame_rcvd(LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP server", "frame_rcvd");

    // Define some working buffers for later use...
    static constexpr unsigned MAX_OPTION = 255;
    u8 chaddr[CHADDR_LEN];  // Header field CHADDR
    u8 buffer[MAX_OPTION];  // Temp buffer for one option

    // Read the BOOTP/DHCP message header.
    u8 op       = src.read_u8();
    u8 htype    = src.read_u8();
    u8 hlen     = src.read_u8();
    src.read_u8();  // hops
    u32 xid     = src.read_u32();
    src.read_u16(); // secs
    u16 flags   = src.read_u16();
    u32 ciaddr  = src.read_u32();
    src.read_u32(); // yiaddr
    src.read_u32(); // siaddr
    u32 giaddr  = src.read_u32();
    src.read_bytes(CHADDR_LEN, chaddr);
    src.read_consume(LEGACY_BYTES);
    u32 magic   = src.read_u32();

    // Sanity check before proceeding.
    if (!src.get_read_ready()) return;      // Incomplete header
    if (op != OP_REQUEST) return;           // Not a client-to-server message
    if (htype != 1 || hlen != 6) return;    // Not an IPv4 / Ethernet request
    if (magic != DHCP_MAGIC) return;        // Invalid "magic cookie" value

    // To save memory, we use a hash to identify clients.  Calculate
    // a hash of CHADDR now; replace it later if Client-ID is provided.
    // (Likelihood and consequence of a collision are both low, and even a
    // CRC32 hash is hardly the weakest link in DHCP's security.)
    u32 client = crc32(CHADDR_LEN, chaddr);

    // Scan through options for information of interest.
    // (Options in any order, so we need to parse the whole thing.)
    bool opt_complete = false;
    u8 opcode = 0;
    u32 lease_time = TIME_LEASE_DEFAULT;
    while (src.get_read_ready()) {
        // Read option type and handle no-length options.
        u8 typ = src.read_u8();
        if (typ == OPTION_PAD) continue;
        if (typ == OPTION_END) {opt_complete = true; break;}
        // Read option length and confirm it is valid.
        u8 len = src.read_u8();
        if (src.get_read_ready() < len) break;
        // Read option contents.
        if (typ == OPTION_REQUEST_IP && len == 4) {
            // Client has a specific IP they'd like to reuse.
            ciaddr = src.read_u32();
        } else if (typ == OPTION_LEASE_TIME && len == 4) {
            // Update the requested lease duration.
            lease_time = min_u32(src.read_u32(), m_max_lease);
        } else if (typ == OPTION_MSG_TYPE && len == 1) {
            // Message type (required, but not necessarily first option).
            opcode = src.read_u8();
        } else if (typ == OPTION_CLIENT_ID) {
            // Update client hash using Client-ID field.
            src.read_bytes(len, buffer);
            client = crc32(len, buffer);
        } else {
            // Unsupported options are discarded.
            src.read_consume(len);
        }
    }

    // Silently discard messages with an incomplete options field.
    if (!opt_complete) return;

    // Optional diagnostic logging.
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP server", "Received opcode").write(opcode);

    // Force client hash out of the reserved range.
    if (client == CLIENT_NONE || client == CLIENT_RSVD) client = ~client;

    // Update internal state and decide how to reply.
    const char* log_msg = "Message ignored";
    s8 log_typ = log::INFO;
    u8 reply_type = 0;
    Addr reply_addr(0), yiaddr(ciaddr);
    if (opcode == DHCP_DISCOVER) {
        // If we have an open slot, grant a tentative lease.
        log_msg = "Discover";
        yiaddr = offer(client, ciaddr, TIME_LEASE_OFFER);
        if (yiaddr != ADDR_NONE) reply_type = DHCP_OFFER;
    } else if (opcode == DHCP_REQUEST) {
        // Request from client -> Accept, reject, or ignore?
        yiaddr = reserve(client, ciaddr, lease_time);
        if (yiaddr != ADDR_NONE) {
            log_msg = "Request granted";
            reply_addr = yiaddr;
            reply_type = DHCP_ACK;
        } else if (m_pool->contains(ciaddr)) {
            log_msg = "Request refused";
            log_typ = log::WARNING;
            reply_addr = m_iface->reply_ip();
            reply_type = DHCP_NAK;
        }
    } else if (opcode == DHCP_DECLINE) {
        // We assigned client an IP, but it's already taken!?
        // If it's one of ours, mark it so we don't reassign it.
        if (m_pool->contains(ciaddr)) {
            log_msg = "Lease declined";
            log_typ = log::WARNING;
            reserve(CLIENT_RSVD, ciaddr, m_max_lease);
        }
    } else if (opcode == DHCP_RELEASE) {
        // Client is giving up an assigned lease.
        DhcpAddress* meta = m_pool->addr2meta(ciaddr);
        if (meta && client == meta->client) {
            log_msg = "Release granted";
            *meta = LEASE_NONE;
        }
    } else if (opcode == DHCP_INFORM) {
        // Client has an address but needs gateway, etc.
        log_msg = "Information request";
        reply_addr = m_iface->reply_ip();
        reply_type = DHCP_ACK;
    }

    // Always write something to the event log.
    log::Log(log_typ, "DHCP server", log_msg)
        .write(ciaddr | yiaddr.value).write(client);

    // Skip the rest if no reply is needed.
    if (reply_type == 0) return;
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "DHCP server", "Sending opcode").write(reply_type);

    // Write outgoing options into the working buffer.
    // (Do this up front to ensure an accurate length estimate.)
    ArrayWrite opt(buffer, MAX_OPTION);
    // Message type is always required.
    opt.write_u8(OPTION_MSG_TYPE);
    opt.write_u8(1);
    opt.write_u8(reply_type);
    // Include setup and lease parameters?
    if (reply_type == DHCP_OFFER || reply_type == DHCP_ACK) {
        // Option: Gateway and subnet mask and gateway
        if (m_gateway != DEFAULT_ROUTE) {
            opt.write_u8(OPTION_SUBNET_MASK);
            opt.write_u8(4);
            opt.write_u32(m_gateway.mask.value);
            opt.write_u8(OPTION_ROUTER);
            opt.write_u8(4);
            opt.write_u32(m_gateway.addr.value);
        }
        // Option: DNS server
        if (m_dns.value) {
            opt.write_u8(OPTION_DNS_SERVER);
            opt.write_u8(4);
            opt.write_u32(m_dns.value);
        }
        // Option: Domain name.
        if (m_domain) {
            u8 dlen = (u8)min_u32(32, strlen(m_domain));
            opt.write_u8(OPTION_DOMAIN_NAME);
            opt.write_u8(dlen);
            opt.write_bytes(dlen, m_domain);
        }
        // Option: Lease time
        opt.write_u8(OPTION_LEASE_TIME);
        opt.write_u8(4);
        opt.write_u32(lease_time);
    }
    // Option: DHCP server IP
    opt.write_u8(OPTION_SERVER_IP);
    opt.write_u8(4);
    opt.write_u32(m_iface->ipaddr().value);
    // End-of-options marker.
    opt.write_u8(OPTION_END);
    opt.write_finalize();

    // Unicast or broadcast reply? (RFC2131 Section 4.1)
    satcat5::udp::Address dstaddr(m_iface);
    dstaddr.connect(
        (flags & FLAG_BROADCAST) ? ADDR_BROADCAST : reply_addr,
        (flags & FLAG_BROADCAST) ? MACADDR_BROADCAST : m_iface->reply_mac(),
        PORT_DHCP_CLIENT, PORT_DHCP_SERVER);

    // Calculate reply length and formulate response.
    // See also: RFC2131 Table 3
    unsigned reply_len = 240 + opt.written_len();
    satcat5::io::Writeable* dst = dstaddr.open_write(reply_len);
    if (dst) {
        // Write the basic DHCP message header.
        dst->write_u32(0x02010600);     // OP, HTYPE, HLEN, HOPS
        dst->write_u32(xid);            // xid = Echo
        dst->write_u16(0);              // secs = 0
        dst->write_u16(flags);          // flags = Echo
        dst->write_u32(0);              // ciaddr = 0
        dst->write_u32(yiaddr.value);   // Offered address (see above)
        dst->write_u32(0);              // siaddr = None
        dst->write_u32(giaddr);         // giaddr = Echo
        dst->write_bytes(CHADDR_LEN, chaddr); // chaddr = Echo
        for (unsigned a = 0 ; a < LEGACY_WORDS ; ++a)
            dst->write_u32(0);          // 192 bytes of zeros
        dst->write_u32(DHCP_MAGIC);     // Magic cookie
        // Write options and send the message.
        dst->write_bytes(opt.written_len(), buffer);
        dst->write_finalize();
    }
}

void DhcpServer::timer_event()
{
    // Increment the reference time.
    ++m_time;

    // Check ONE address to see if its lease has expired.
    // No need to check the entire pool; as long as we touch everything
    // within 2^31 seconds then we'll avoid overflow/wraparound glitches.
    DhcpAddress* meta = m_pool->idx2meta(m_next_timer++);
    if (meta) {
        // Has this lease expired?  If so, reset it.
        if (lease_expired(meta, m_time))
            *meta = LEASE_NONE;
    } else {
        // End of pool, wrap around to the beginning.
        m_next_timer = 0;
    }
}

// Reuse an existing address, or find the next free address.
Addr DhcpServer::offer(u32 client_id, u32 req_ipaddr, u32 req_lease)
{
    // Did the client request a preferred IP address?
    if (req_ipaddr) {
        // Claim the address if it's available (reuse or expired).
        Addr tmp = reserve(client_id, req_ipaddr, req_lease);
        if (tmp != ADDR_NONE) return tmp;
    }

    // Confirm we're starting from a valid initial index.
    // (Certain edge-cases can leave it out-of-bounds.)
    if (!m_pool->idx2meta(m_next_lease)) m_next_lease = 0;

    // Find the next open address...
    unsigned wrap = m_next_lease;
    do {
        // Check the next address in the pool...
        DhcpAddress* meta = m_pool->idx2meta(m_next_lease);
        if (!meta) {
            // Reached end of pool -> Wrap to beginning.
            m_next_lease = 0;
        } else if (lease_expired(meta, m_time)) {
            // Found an open lease -> Assign it.
            *meta = {client_id, m_time + req_lease};
            return m_pool->idx2addr(m_next_lease++);
        } else {
            // Try the next address in the pool.
            ++m_next_lease;
        }
    } while (m_next_lease != wrap);

    // If we've reached this point, there are no vacancies.
    return ADDR_NONE;
}

// Attempt to reserve the designated address for the designated client.
Addr DhcpServer::reserve(u32 client_id, u32 req_ipaddr, u32 req_lease)
{
    // Lookup the requested address.
    DhcpAddress* meta = m_pool->addr2meta(req_ipaddr);

    // If it's the same client or unclaimed, assign it.
    if (!meta) {
        return ADDR_NONE;           // No such address
    } else if (client_id == CLIENT_RSVD) {
        *meta = {client_id, m_time + req_lease};
        return Addr(req_ipaddr);    // Forced-reserve
    } else if (client_id == meta->client || lease_expired(meta, m_time)) {
        *meta = {client_id, m_time + req_lease};
        return Addr(req_ipaddr);    // Requested IP is OK!
    } else {
        return ADDR_NONE;           // Already in use
    }
}
