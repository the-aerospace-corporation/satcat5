//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <satcat5/log.h>
#include <satcat5/udp_tftp.h>
#include <satcat5/utils.h>

// Shortcuts for commonly used names.
using satcat5::io::ArrayWrite;
using satcat5::net::Type;
using satcat5::udp::PORT_TFTP_SERVER;
using satcat5::udp::TftpClient;
using satcat5::udp::TftpServerCore;
using satcat5::udp::TftpServerSimple;
using satcat5::udp::TftpTransfer;
using satcat5::util::clr_mask_u16;
using satcat5::util::min_unsigned;
using satcat5::util::set_mask_u16;
using satcat5::util::write_be_u16;

// Set verbosity level for debugging (0/1/2).
static constexpr unsigned DEBUG_VERBOSE = 0;

// Define the type-filter for incoming server requests.
static constexpr Type TYPE_TFTP_SERVER = Type(PORT_TFTP_SERVER.value);

// Define TFTP opcodes (RFC 1350, Section 5)
static constexpr u16 OPCODE_RRQ     = 1;    // Read request
static constexpr u16 OPCODE_WRQ     = 2;    // Write request
static constexpr u16 OPCODE_DATA    = 3;    // Data
static constexpr u16 OPCODE_ACK     = 4;    // Acknowledgement
static constexpr u16 OPCODE_ERROR   = 5;    // Error

// Define TFTP error codes (RFC 1350, Appendix I)
// (Additional codes exist, but these are the ones we use.)
static constexpr u16 ERROR_TIMEOUT  = 0;    // Timeout (using code 0)
static constexpr u16 ERROR_NOFILE   = 1;    // File not found
static constexpr u16 ERROR_PROTOCOL = 4;    // Illegal TFTP operation

// Internal options and status flags.
static constexpr u16 FLAG_BUSY      = 0x0001;   // Transfer in progress
static constexpr u16 FLAG_EOF       = 0x0002;   // Transfer completed
static constexpr u16 FLAG_FIRST     = 0x0004;   // Waiting for first response

// TFTP should only be used on a LAN, so set an aggressive timeout
// for the first timeout and double on every subsequent attempt.
static constexpr unsigned RETRY_MAX = 3;
static constexpr unsigned RETRY_MSEC = 100;

// Convert TFTP error-code to a user-readable error string.
inline const char* error_lookup(u16 errcode) {
    switch (errcode) {
    case ERROR_TIMEOUT:     return "Timeout";
    case ERROR_NOFILE:      return "File not found";
    case ERROR_PROTOCOL:    return "Illegal TFTP operation";
    default:                return "Unknown error";
    }
}

TftpTransfer::TftpTransfer(satcat5::udp::Dispatch* iface)
    : satcat5::net::Protocol(satcat5::net::TYPE_NONE)
    , m_addr(iface)
    , m_src(0)
    , m_dst(0)
    , m_xfer_bytes(0)
    , m_block_id(0)
    , m_flags(0)
    , m_retry_count(0)
    , m_retry_len(0)
{
    // Register for incoming UDP packets based on "m_filter",
    // which we will adjust on the fly.
    m_addr.m_iface->add(this);
}

TftpTransfer::~TftpTransfer()
{
    m_addr.m_iface->remove(this);
}

void TftpTransfer::reset(const char* msg)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "TftpTransfer::reset", msg);

    // Always clean up the source.
    if (m_src) m_src->read_finalize();

    // Did we just complete a transfer?
    if ((m_flags & FLAG_BUSY) && (m_flags & FLAG_EOF)) {
        // Successful transfer requires no further cleanup.
        log::Log(log::INFO, "TFTP", msg)
            .write(m_src ? " Sent" : " Rcvd").write10(m_xfer_bytes);
    } else {
        // Failed transfer should revert if possible.
        log::Log(log::WARNING, "TFTP", msg);
        if (m_dst) m_dst->write_abort();
    }

    // Force all internal state to idle.
    m_addr.close();
    m_filter = satcat5::net::TYPE_NONE;
    m_src = 0;
    m_dst = 0;
    m_block_id = 0;
    m_flags = 0;
    m_xfer_bytes = 0;
    m_retry_count = 0;
    m_retry_len = 0;
    timer_stop();
}

void TftpTransfer::request(
    const satcat5::ip::Addr& dstaddr,
    u16 opcode, const char* filename)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "TftpTransfer::request");

    // Open UDP socket on the next available source port.
    // (This will usually issue an ARP request for MAC lookup.)
    satcat5::udp::Port srcport = m_addr.m_iface->next_free_port();
    m_addr.connect(dstaddr, PORT_TFTP_SERVER, srcport);
    m_filter = Type(srcport.value);

    // Write out the request packet (Section 5).
    ArrayWrite pkt(m_retry_buff, sizeof(m_retry_buff));
    pkt.write_u16(opcode);
    pkt.write_str(filename);
    pkt.write_u8(0);
    pkt.write_str("octet");
    pkt.write_u8(0);
    pkt.write_finalize();

    // Queue outgoing packet, sent after receiving ARP response.
    send_packet(pkt.written_len(), 0);
}

void TftpTransfer::accept()
{
    // Open UDP socket on the next available source port.
    satcat5::udp::Port dstport = m_addr.m_iface->reply_src();
    satcat5::udp::Port srcport = m_addr.m_iface->next_free_port();
    m_addr.connect(
        m_addr.m_iface->reply_ip(),
        m_addr.m_iface->reply_mac(),
        dstport, srcport);

    // Update the filter for incoming packets.
    m_filter = Type(dstport.value, srcport.value);

    // Log the new connection.
    log::Log(log::INFO, "TFTP: Connected to client")
        .write(m_addr.m_iface->reply_ip())
        .write(dstport.value).write(srcport.value);
}

void TftpTransfer::file_send(satcat5::io::Readable* src, bool now)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "TftpTransfer::file_send");

    // Reset transfer state.
    m_src = src;
    m_dst = 0;
    m_block_id = 0;
    m_flags = FLAG_BUSY;

    // Send the first data packet immediately?
    if (now) {
        // Server to client: Server immediately sends first data block.
        send_data(1);
    } else {
        // Client to server: Client waits for ACK-0 confirmation.
        set_mask_u16(m_flags, FLAG_FIRST);
    }
}

void TftpTransfer::file_recv(satcat5::io::Writeable* dst, bool now)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "TftpTransfer::file_recv");

    // Reset transfer state.
    m_src = 0;
    m_dst = dst;
    m_block_id = 0;
    m_flags = FLAG_BUSY;

    // Send the first acknowledge packet immediately?
    if (now) {
        // Client to server: Server immediately sends ACK-0.
        send_ack(0);
    } else {
        // Server to client: Client waits for first data block.
        set_mask_u16(m_flags, FLAG_FIRST);
    }
}

void TftpTransfer::frame_rcvd(satcat5::io::LimitedRead& src)
{
    // All valid TFTP packets start with the opcode.
    u16 opcode = src.read_u16();
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::frame_rcvd").write(opcode);

    // Ignore anything that's not from the expected IP address.
    if (m_addr.m_iface->reply_ip() != m_addr.dstaddr()) return;

    // If FIRST flag is set, lock in the sender's source port.
    // (i.e., This is how the client learns the UDP destination port.)
    if (m_flags & FLAG_FIRST) {
        clr_mask_u16(m_flags, FLAG_FIRST);
        // Update the destination for outgoing packets.
        satcat5::udp::Port dstport = m_addr.m_iface->reply_src();
        satcat5::udp::Port srcport = m_addr.srcport();
        m_addr.connect(
            m_addr.m_iface->reply_ip(),
            m_addr.m_iface->reply_mac(),
            dstport, srcport);
        // Update the filter for incoming packets.
        m_filter = Type(dstport.value, srcport.value);
        // Log the new connection.
        log::Log(log::INFO, "TFTP: Connected to server")
            .write(m_addr.m_iface->reply_ip())
            .write(dstport.value).write(srcport.value);
    }

    // Take further action based on the opcode:
    if (opcode == OPCODE_ERROR) {
        // Received ERROR, abort transfer immediately.
        read_error(src);
        reset("Connection reset by peer.");
    } else if (m_dst && opcode == OPCODE_DATA) {
        // Received DATA, read it if applicable and send ACK.
        u16 block_id = src.read_u16();
        read_data(block_id, src);
        send_ack(block_id);
    } else if (m_src && opcode == OPCODE_ACK) {
        // Received ACK, send next DATA packet if applicable.
        u16 block_id = src.read_u16();
        send_data(block_id + 1);
    } else {
        // Any other opcode is an error.
        send_error(ERROR_PROTOCOL);
    }
}

void TftpTransfer::timer_event()
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::timer_event").write10((u32)m_retry_count);

    // Timeout waiting for remote response...
    if (m_flags & FLAG_EOF) {
        // Normal termination (RFC 1350, Section 6)
        reset("Transfer completed.");
    } else if (m_retry_count <= RETRY_MAX) {
        // Retry last packet up to N times.
        send_packet(m_retry_len, m_retry_count+1);
    } else {
        // Abort transfer.
        send_error(ERROR_TIMEOUT);
    }
}

void TftpTransfer::read_data(u16 block_id, satcat5::io::LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::read_data").write(block_id);

    // If we've already got end-of-file, ignore all subsequent data.
    if (m_flags & FLAG_EOF) return;

    // Read contents only for the next expected block.
    u16 predicted = u16(m_block_id & 0xFFFF) + 1;
    if (block_id == predicted) {
        // Update block counter.
        ++m_block_id;
        // Copy the newly-received data.
        unsigned len = src.get_read_ready();
        m_xfer_bytes += len;
        if (len > 0) src.copy_to(m_dst);
        // Last block in file?
        if (len < 512) {
            m_dst->write_finalize();
            set_mask_u16(m_flags, FLAG_EOF);
        }
    }
}

void TftpTransfer::read_error(satcat5::io::LimitedRead& src)
{
    // Unpack the error string into the internal buffer.
    // (We're about to close the connection, so it's OK to overwrite.)
    u16 errcode = src.read_u16();
    char* errstr = (char*)m_retry_buff;
    src.read_str(sizeof(m_retry_buff), errstr);

    // Log the error and abort connection.
    log::Log(log::WARNING, "TFTP: Remote error")
        .write(errcode).write(": ").write(errstr);
}

void TftpTransfer::send_ack(u16 block_id)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::send_ack").write(block_id);

    // Compare 16 LSBs of received block to expected value.
    // (Careful arithmetic here allows for wraparound.)
    s16 diff = s16(block_id - u16(m_block_id & 0xFFFF));
    if (diff < 0) {
        // Ignore stale DATA packets, no ACK needed.
    } else if (diff == 0) {
        // Write out the ACK packet (Section 5).
        ArrayWrite pkt(m_retry_buff, sizeof(m_retry_buff));
        pkt.write_u16(OPCODE_ACK);
        pkt.write_u16(block_id);
        pkt.write_finalize();
        // Send the ACK packet.
        send_packet(pkt.written_len(), 0);
    } else {
        // Out-of-sequence block ID from incoming DATA packet.
        send_error(ERROR_PROTOCOL);
    }
}

void TftpTransfer::send_data(u16 block_id)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::send_data").write(block_id);

    // Compare 16 LSBs of received block to expected value.
    // (Careful arithmetic here allows for wraparound.)
    s16 diff = s16(block_id - u16(m_block_id & 0xFFFF));
    if (diff < 0) {
        // Ignore stale requests.
    } else if (diff == 0) {
        // Request for the previous packet.
        send_packet(m_retry_len, 0);
    } else if (m_flags & FLAG_EOF) {
        // Transfer completed, nothing left to send.
        reset("Transfer completed.");
    } else if (diff == 1) {
        // Write the packet header.
        write_be_u16(m_retry_buff + 0, OPCODE_DATA);
        write_be_u16(m_retry_buff + 2, block_id);
        // Copy the next block of data (max 512 bytes).
        ++m_block_id;
        unsigned len = min_unsigned(512, m_src->get_read_ready());
        m_xfer_bytes += len;
        if (len > 0) m_src->read_bytes(len, m_retry_buff + 4);
        if (len < 512) set_mask_u16(m_flags, FLAG_EOF);
        // Send the DATA packet.
        send_packet(len + 4, 0);
    } else {
        // Invalid block ID from incoming ACK packet.
        send_error(ERROR_PROTOCOL);
    }
}

void TftpTransfer::send_error(u16 errcode)
{
    if (DEBUG_VERBOSE > 1)
        log::Log(log::DEBUG, "TftpTransfer::send_error").write(errcode);

    // Lookup the human-readable error message.
    const char* errstr = error_lookup(errcode);

    // Write out the ERROR packet (Section 5).
    ArrayWrite pkt(m_retry_buff, sizeof(m_retry_buff));
    pkt.write_u16(OPCODE_ERROR);
    pkt.write_u16(errcode);
    pkt.write_str(errstr);
    pkt.write_u8(0);
    pkt.write_finalize();

    // Send the error packet and reset connection.
    send_packet(pkt.written_len(), 0);
    reset(errstr);
}

void TftpTransfer::send_packet(unsigned len, u16 retry)
{
    if (DEBUG_VERBOSE > 1) {
        u16 opcode = satcat5::util::extract_be_u16(m_retry_buff);
        log::Log(log::DEBUG, "TftpTransfer::send_packet").write(opcode);
    }

    // Sanity check on input length.
    if (len > sizeof(m_retry_buff)) return;

    // Exponential timeout doubles after each failed attempt.
    m_retry_len   = (u16)len;
    m_retry_count = retry;
    timer_once(RETRY_MSEC * (1u << retry));

    // Attempt to send the packet.
    auto wr = m_addr.open_write(len);
    if (wr) {
        wr->write_bytes(len, m_retry_buff);
        wr->write_finalize();
    } else if (DEBUG_VERBOSE > 1) {
        log::Log(log::DEBUG, "TftpTransfer: Transmission delayed...");
    }
}

TftpClient::TftpClient(satcat5::udp::Dispatch* iface)
    : m_xfer(iface)
{
    // No other initialization required.
}

void TftpClient::begin_download(
    satcat5::io::Writeable* dst,
    const satcat5::ip::Addr& server,
    const char* filename)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "TftpClient::begin_download");
    m_xfer.request(server, OPCODE_RRQ, filename);
    m_xfer.file_recv(dst, false);   // Wait for DATA1
}

void TftpClient::begin_upload(
    satcat5::io::Readable* src,
    const satcat5::ip::Addr& server,
    const char* filename)
{
    if (DEBUG_VERBOSE > 0) log::Log(log::DEBUG, "TftpClient::begin_upload");
    m_xfer.request(server, OPCODE_WRQ, filename);
    m_xfer.file_send(src, false);   // Wait for ACK0
}

TftpServerCore::TftpServerCore(satcat5::udp::Dispatch* iface)
    : satcat5::net::Protocol(TYPE_TFTP_SERVER)
    , m_iface(iface)
    , m_xfer(iface)
{
    // Register for incoming packets on the TFTP server port.
    m_iface->add(this);
}

TftpServerCore::~TftpServerCore()
{
    m_iface->remove(this);
}

void TftpServerCore::frame_rcvd(satcat5::io::LimitedRead& src)
{
    if (DEBUG_VERBOSE > 1) log::Log(log::DEBUG, "TftpServer::frame_rcvd");

    // Only respond to read-requests and write-requests.
    char filename[256];
    u16 opcode = src.read_u16();
    if (opcode == OPCODE_RRQ) {
        // Read filename and get I/O object.
        src.read_str(sizeof(filename), filename);
        auto file_src = read(filename);
        // Begin read transfer (server to client)
        m_xfer.accept();
        if (file_src) {
            m_xfer.file_send(file_src, true);
        } else {
            m_xfer.send_error(ERROR_NOFILE);
        }
    } else if (opcode == OPCODE_WRQ) {
        // Read filename and get I/O object.
        src.read_str(sizeof(filename), filename);
        auto file_dst = write(filename);
        // Begin write transfer (client to server)
        m_xfer.accept();
        if (file_dst) {
            m_xfer.file_recv(file_dst, true);
        } else {
            m_xfer.send_error(ERROR_NOFILE);
        }
    }
}

TftpServerSimple::TftpServerSimple(
        satcat5::udp::Dispatch* iface,
        satcat5::io::Readable* src,
        satcat5::io::Writeable* dst)
    : TftpServerCore(iface)
    , m_src(src)
    , m_dst(dst)
{
    // Nothing else to initialize.
}

satcat5::io::Readable* TftpServerSimple::read(const char* filename)
    { return m_src; }

satcat5::io::Writeable* TftpServerSimple::write(const char* filename)
    { return m_dst; }
