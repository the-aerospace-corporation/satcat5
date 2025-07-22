//////////////////////////////////////////////////////////////////////////
// Copyright 2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <climits>
#include <hal_posix/posix_utils.h>
#include <hal_posix/tcp_socket.h>
#include <satcat5/log.h>
#include <satcat5/ip_core.h>
#include <satcat5/utils.h>

// Include files for Windows or Linux?
#if SATCAT5_WIN32
    #include <winsock2.h>
    #include <ws2tcpip.h>
    #define CLOSE_SOCKET(x) {closesocket(x); x = -1;}
    #undef ERROR            // Deconflict Windows "ERROR" macro
#else
    #include <arpa/inet.h>
    #include <fcntl.h>
    #include <netdb.h>
    #include <sys/socket.h>
    #include <sys/types.h>
    #include <unistd.h>
    #define CLOSE_SOCKET(x) {::close(x); x = -1;}
#endif

using satcat5::ip::Addr;
using satcat5::ip::Port;
using satcat5::tcp::SocketPosix;
using satcat5::util::min_unsigned;
using satcat5::util::TimeVal;

// Make a list of sockets with a single item.
static inline fd_set make_fdset(int fd) {
    fd_set tmp;
    FD_ZERO(&tmp);
    FD_SET(fd, &tmp);
    return tmp;
}

// Is the provided socket in a state that can read/write/accept?
static bool can_read(int fd) {
    if (fd < 0) return false;
    auto query = make_fdset(fd);
    timeval right_now = {0, 0};
    int count = select(fd+1, &query, nullptr, nullptr, &right_now);
    return (count > 0);
}

static bool can_write(int fd) {
    if (fd < 0) return false;
    auto query = make_fdset(fd);
    timeval right_now = {0, 0};
    int count = select(fd+1, nullptr, &query, nullptr, &right_now);
    return (count > 0);
}

static bool got_event(int fd) {
    if (fd < 0) return false;
    auto query = make_fdset(fd);
    timeval right_now = {0, 0};
    int count = select(fd+1, nullptr, nullptr, &query, &right_now);
    return (count > 0);
}

// Mark a socket descriptor as non-blocking.
static int set_nonblock(int fd) {
    #if SATCAT5_WIN32
        u_long enable = 1;
        return ioctlsocket(fd, FIONBIO, &enable);
    #else
        int flags = fcntl(fd, F_GETFL, 0);
        return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    #endif
}

// Get the most recent socket-related error code.
static int get_error() {
    #if SATCAT5_WIN32
        return WSAGetLastError();
    #else
        return errno;
    #endif
}

// Is a given error code a "real" error?
// (i.e., Ignore special return codes for non-blocking sockets.)
static bool is_error(int err) {
    if (err >= 0) return false;
    int sub_code = get_error();
    #if SATCAT5_WIN32
        return sub_code != WSAEINPROGRESS
            && sub_code != WSAEWOULDBLOCK;
    #else
        return sub_code != EAGAIN
            && sub_code != EINPROGRESS
            && sub_code != EWOULDBLOCK;
    #endif
}

// Shortcut for printing a network error message.
static void log_socket_error(const char* label) {
    int err_code = get_error();
    const char* err_msg = strerror(err_code);
    satcat5::log::Log(satcat5::log::ERROR, "SocketPosix: ")
        .write(label).write10(err_code).write("\r\n  ").write(err_msg);
}

// Internal status flags:
constexpr u32 FLAG_WSA_CLEANUP = (1u << 0);

SocketPosix::SocketPosix(unsigned txbytes, unsigned rxbytes)
    : BufferedIO(
        new u8[txbytes], txbytes, 0,    // Allocate Tx buffer
        new u8[rxbytes], rxbytes, 0)    // Allocate Rx buffer
    , m_flags(0)
    , m_last_rx(SATCAT5_CLOCK->now())
    , m_last_tx(SATCAT5_CLOCK->now())
    , m_sock_listen(-1)
    , m_sock_data(-1)
    , m_rate_kbps(0)
{
    // Windows only: Perform first-time setup of WinSock API.
    // Request version 2.2, which has been stable from 1996-2024.
    // Note: Microsoft counts how many times each application calls
    // WSAStartup, and last call to WSACleanup turns out the lights.
    #if SATCAT5_WIN32
        WSADATA wsadata;
        int err = WSAStartup(MAKEWORD(2, 2), &wsadata);
        if (err) log_socket_error("ctor");
        else m_flags |= FLAG_WSA_CLEANUP;
    #endif
}

SocketPosix::~SocketPosix() {
    // Close open connections.
    close();

    // Windows only: Additional cleanup required.
    #if SATCAT5_WIN32
        if (m_flags & FLAG_WSA_CLEANUP) WSACleanup();
    #endif

    // Free the I/O working buffers.
    delete[] m_tx.get_buff_dtor();
    delete[] m_rx.get_buff_dtor();
}

void SocketPosix::close() {
    // Close both sockets.
    if (m_sock_listen >= 0) CLOSE_SOCKET(m_sock_listen);
    if (m_sock_data >= 0)   CLOSE_SOCKET(m_sock_data);

    // Reset reference timestamps.
    m_last_rx = SATCAT5_CLOCK->now();
    m_last_tx = SATCAT5_CLOCK->now();

    // Stop timer polling.
    timer_stop();
}

bool SocketPosix::bind(const Port& port) {
    // Sanity checks before we start...
    close();

    // Setup request information.
    struct sockaddr_in request;
    request.sin_family = AF_INET;
    request.sin_addr.s_addr = INADDR_ANY;
    request.sin_port = htons(port.value);

    // Open the socket and mark it as non-blocking.
    m_sock_listen = open_nonblock_socket();
    if (m_sock_listen < 0) return false;

    // Attempt to set the REUSEADDR flag to allow server restarts.
    // This is nonessential, so ignore errors in this operation.
    const int enable = 1;
    setsockopt(m_sock_listen, SOL_SOCKET, SO_REUSEADDR, (const char*)&enable, sizeof(enable));

    // Attempt to bind to the requested port.
    int err = ::bind(m_sock_listen, (const sockaddr*)&request, sizeof(request));
    if (err) {
        log_socket_error("bind");
        close(); return false;
    }

    // Start listening on that port.
    err = listen(m_sock_listen, 1);
    if (err) {
        log_socket_error("listen");
        close(); return false;
    }

    // On success, start the timer.
    timer_every(1);
    return true;
}

bool SocketPosix::connect(const char* hostname, const Port& port) {
    bool ok = true;

    // Setup query for hostname lookup.
    struct addrinfo hints;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_INET;          // Prefer IPv4
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;

    struct addrinfo *result = nullptr;
    int err = getaddrinfo(hostname, nullptr, &hints, &result);
    if (err) {
        log_socket_error("addr");
        ok = false;
    }

    // Extract first IPv4 address from the list of results,
    // then attempt to proceed with connection by address.
    if (ok) {
        struct sockaddr_in* tmp = (struct sockaddr_in*)result->ai_addr;
        Addr addr(ntohl(tmp->sin_addr.s_addr));
        ok = connect(Addr{addr}, port);
    }

    // Cleanup before returning.
    freeaddrinfo(result);
    return ok;
}

bool SocketPosix::connect(const Addr& addr, const Port& port) {
    // Sanity checks before we start...
    close();
    if (!addr.is_unicast()) return false;

    // Setup request information:
    struct sockaddr_in request;
    request.sin_family = AF_INET;
    request.sin_addr.s_addr = htonl(addr.value);
    request.sin_port = htons(port.value);

    // Open the socket and mark it as non-blocking.
    m_sock_data = open_nonblock_socket();
    if (m_sock_data < 0) return false;

    // Attempt connection to the remote server.
    int err = ::connect(m_sock_data, (struct sockaddr*)&request, sizeof(request));
    if (is_error(err)) {
        log_socket_error("connect");
        close(); return false;
    }

    // On success, start the timer.
    timer_every(1);
    return true;
}

bool SocketPosix::ready() {
    return can_write(m_sock_data);
}

void SocketPosix::data_rcvd(satcat5::io::Readable* src) {
    // Copy data from working buffer to the socket.
    if (can_write(m_sock_data)) {
        unsigned limit = rate_limit(m_last_tx);
        while (limit) {
            unsigned len = min_unsigned(limit, m_tx.get_peek_ready());
            const char* tmp = (const char*)m_tx.peek(len);
            int sent = send(m_sock_data, tmp, len, 0);
            if (sent < 0) log_socket_error("send");
            if (sent <= 0) break;
            m_tx.read_consume(unsigned(sent));
            limit -= sent;
            if (unsigned(sent) < len) break;
        }
    }
}

void SocketPosix::timer_event() {
    // Handle events for m_sock_data or m_sock_listen...
    if (can_read(m_sock_data)) {
        // Copy new data to the working buffer.
        unsigned limit = rate_limit(m_last_rx);
        u8 tmp[256];
        while (limit) {
            unsigned rmax = min_unsigned(sizeof(tmp), limit);
            rmax = min_unsigned(rmax, m_rx.get_write_space());
            int rcvd = recv(m_sock_data, (char*)tmp, rmax, 0);
            if (is_error(rcvd)) log_socket_error("recv");
            if (rcvd <= 0) break;
            m_rx.write_bytes(rcvd, tmp);
            limit -= rcvd;
            if (unsigned(rcvd) == rmax) break;
        }
        m_rx.write_finalize();
    } else if (got_event(m_sock_data)) {
        // Error closes current connection.
        log_socket_error("poll");
        CLOSE_SOCKET(m_sock_data);
        // Client reverts to idle, server resumes listening.
        if (m_sock_listen < 0) {
            close();
        } else if (listen(m_sock_listen, 1)) {
            log_socket_error("listen");
            close();
        }
    } else if (m_sock_data < 0 && can_read(m_sock_listen)) {
        // Accept incoming connection.
        m_sock_data = accept(m_sock_listen, nullptr, nullptr);
        if (m_sock_data < 0 || set_nonblock(m_sock_data)) {
            log_socket_error("accept");
            close();
        }
    } else if (got_event(m_sock_listen)) {
        // Other error while listening for connections.
        log_socket_error("server");
        close();
    }
}

int SocketPosix::open_nonblock_socket() {
    // Create a new socket descriptor..
    int sock = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (sock < 0) {
        log_socket_error("socket");
        return sock;
    }

    // Mark it as non-blocking.
    int err = set_nonblock(sock);
    if (err) {
        log_socket_error("nonblk");
        CLOSE_SOCKET(sock);
    }
    return sock;
}

unsigned SocketPosix::rate_limit(TimeVal& tv) {
    // Calculate maximum Tx/Rx bytes based on previous Tx/Rx timestamp.
    unsigned elapsed = min_unsigned(10, tv.increment_msec());
    return m_rate_kbps ? (elapsed * m_rate_kbps / 8) : UINT_MAX;
}
