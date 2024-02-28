//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// Client and server for the Trivial File Transfer Protocol (TFTP)
//
// Trivial File Transfer Protocol (TFTP) is a simple lockstep file transfer
// protocol that allows a client to upload or download a file from a remote
// host over UDP.  It prioritizes simplicity over performance or security.
//
// The client defined in this file conforms to IETF RFC 1350:
//  https://datatracker.ietf.org/doc/html/rfc1350
//
// The server conforms to RFC 1350 with the following exceptions:
//  * Only binary/octet mode is supported.
//  * Only one client may connect at a time.
//

#pragma once

#include <satcat5/udp_socket.h>

namespace satcat5 {
    namespace udp {
        // Transfer objects are used by both client and server.
        // Users should not typically use this object directly.
        class TftpTransfer
            : public satcat5::net::Protocol
            , public satcat5::poll::Timer
        {
        public:
            // Create an idle connection object.
            explicit TftpTransfer(satcat5::udp::Dispatch* iface);
            ~TftpTransfer();

            // Is there a transfer in progress?
            inline bool active() const
                {return m_flags > 0;}

            // Transfer progress, measured in 512-byte blocks or in bytes.
            inline u32 progress_blocks() const
                {return m_block_id;}
            inline u32 progress_bytes() const
                {return m_xfer_bytes;}

            // Immediately revert to the idle state.
            void reset(const char* msg);

            // Issue a write-request or read-request.
            void request(
                const satcat5::ip::Addr& dstaddr,
                u16 opcode, const char* filename);

            // Accept remote connection and note reply address.
            // (Host should next call file_send() or file_recv().)
            void accept();

            // Begin transfer of a single file (DATA-ACK-DATA-ACK).
            // Once activated, the transfer proceeds unless cancelled.
            void file_send(satcat5::io::Readable* src, bool now);
            void file_recv(satcat5::io::Writeable* dst, bool now);

            // Send an error message.
            void send_error(u16 errcode);

        protected:
            friend satcat5::test::TftpClient;
            friend satcat5::test::TftpServer;

            // Inherited event handlers:
            void frame_rcvd(satcat5::io::LimitedRead& src) override;
            void timer_event() override;

            // Internal event handlers:
            void read_data(u16 block_id, satcat5::io::LimitedRead& src);
            void read_error(satcat5::io::LimitedRead& src);
            void send_ack(u16 block_id);
            void send_data(u16 block_id);
            void send_packet(unsigned len, u16 retry);

            // Interface objects.
            satcat5::udp::Address m_addr;
            satcat5::io::Readable* m_src;
            satcat5::io::Writeable* m_dst;

            // Transfer state uses soft-matching against an extended
            // 32-bit Block-ID to allow files larger than 32 MiB.
            u32 m_xfer_bytes;
            u32 m_block_id;
            u16 m_flags;

            // Internal buffer allows retransmission of lost packets.
            // (Max 4-byte header + 512 bytes data = 516 bytes.)
            u16 m_retry_count;
            u16 m_retry_len;
            u8 m_retry_buff[516];
        };

        // A client makes request(s) to a remote server.
        // This implementation uses user-provided stream objects for I/O.
        // For file I/O, see TftpClientPosix (hal_posix/file_tftp.h).
        class TftpClient
        {
        public:
            explicit TftpClient(satcat5::udp::Dispatch* iface);
            ~TftpClient() {}

            // Download a file from server to a Writeable stream.
            void begin_download(
                satcat5::io::Writeable* dst,
                const satcat5::ip::Addr& server,
                const char* filename);

            // Upload data from a Readable stream to the server.
            void begin_upload(
                satcat5::io::Readable* src,
                const satcat5::ip::Addr& server,
                const char* filename);

            // Accessors for the transfer status.
            inline bool active() const
                {return m_xfer.active();}
            inline u32 progress_blocks() const
                {return m_xfer.progress_blocks();}
            inline u32 progress_bytes() const
                {return m_xfer.progress_bytes();}

        protected:
            friend satcat5::test::TftpClient;

            // Upload or download state.
            satcat5::udp::TftpTransfer m_xfer;
        };

        // ServerCore is the base class that handles TFTP network functions.
        // However, it depends on children to define the I/O functions.
        // See also: TftpServerSimple (below)
        // See also: TftpServerPosix (hal_posix/file_tftp.h)
        class TftpServerCore : public satcat5::net::Protocol
        {
        protected:
            // Users cannot instantiate this class directly.
            // See "TftpServerSimple" for an example implementation.
            explicit TftpServerCore(satcat5::udp::Dispatch* iface);
            ~TftpServerCore();

            // Child class MUST override these methods.
            virtual satcat5::io::Readable* read(const char* filename) = 0;
            virtual satcat5::io::Writeable* write(const char* filename) = 0;

            // Inherited event handler for handling incoming packets.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Connection to client (one at a time).
            satcat5::udp::Dispatch* const m_iface;
            satcat5::udp::TftpTransfer m_xfer;
        };

        // TFTP server with a simple streaming source and sink.
        //  * Client-provided filenames are ignored.
        //  * Fixed Readable source is used for each read/download.
        //    Note: Use "ArrayRead" to repeatedly serve the same file.
        //  * Fixed Writeable destination is used for each write/upload.
        //  * If either is null, requests of that type are disabled.
        class TftpServerSimple : public satcat5::udp::TftpServerCore {
        public:
            TftpServerSimple(
                satcat5::udp::Dispatch* iface,
                satcat5::io::Readable* src,
                satcat5::io::Writeable* dst);
            ~TftpServerSimple() {}

        protected:
            friend satcat5::test::TftpServer;

            // Required overrides from TftpServer.
            satcat5::io::Readable* read(const char* filename) override;
            satcat5::io::Writeable* write(const char* filename) override;

            // Interface objects.
            satcat5::io::Readable* const m_src;
            satcat5::io::Writeable* const m_dst;
        };
    }
}
