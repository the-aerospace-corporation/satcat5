//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// AeroCube File Transfer Protocol (AeroFTP) receiver
//
// This file implements the receive-only counterpart for the transmitter
// defined in "satcat5/net_aeroftp.h".  See that file for more information
// regarding the file-transfer protocol.
//
// The receiver (server) requires read/write access to a working folder.
// This allows data and metadata to persist across multiple communication
// contacts. Files are created, renamed, and removed as data is received:
//  * "file_########.data"  = Received file-data, ready for use.
//  * "file_########.part"  = In-progress file-data.
//  * "file_########.rcvd"  = In-progress meta-data.
//

#pragma once

#include <hal_posix/file_io.h>
#include <satcat5/net_aeroftp.h>
#include <climits>
#include <cstdio>
#include <map>
#include <string>
#include <vector>

namespace satcat5 {
    namespace net {
        // Helper class representing a saving data to a particular file.
        class AeroFtpFile {
        public:
            // Create a new file object.
            //  * If the complete file already exists, no action is taken.
            //  * If the partial file already exists, download is resumed.
            //  * Otherwise, this creates a new partial file.
            AeroFtpFile(
                const char* work_folder,    // Path to working folder
                u32 file_id, u32 file_len,  // New file parameters
                bool resume);               // Resume or force-restart?
            ~AeroFtpFile();

            // Handler for each received packet relating to this file.
            void frame_rcvd(
                u32 file_id, u32 file_len, u32 offset, u32 rxlen,
                satcat5::io::LimitedRead& data);

            // Get a stream of missing blocks for this file.
            satcat5::io::Readable* missing_blocks();

            // Has the complete file been received successfully?
            inline bool done() const    { return m_pcount == 0; }
            inline bool error() const   { return m_pcount == UINT_MAX; }

        protected:
            void cleanup();                 // Close open file handles
            void log(s8 level, const char* msg);

            const std::string m_name_data;  // Filenames (see top)
            const std::string m_name_meta;
            const std::string m_name_part;
            const u32 m_file_id;            // Numeric File-ID
            const u32 m_file_len;           // Length of file (words)
            const u32 m_bcount;             // Total block count
            unsigned m_pcount;              // Number of pending blocks
            FILE* m_data;                   // In-progress file-data
            FILE* m_meta;                   // In-progress meta-data
            u8* m_pending;                  // Flag each pending block
            satcat5::io::ArrayRead m_status;
        };

        // Receive file(s) using AeroFTP.
        class AeroFtpServer : public satcat5::net::Protocol {
        public:
            // Get a stream of missing blocks for the designated file-ID.
            // (Format mimics the "aux" argument to net::AeroFtpClient.)
            satcat5::io::Readable* missing_blocks(u32 file_id);

            // Has the complete file been received successfully?
            bool done(u32 file_id) const;

            // Allow server to resume transfers in progress?
            inline void resume(bool allow) {m_resume = allow;}

        protected:
            // Constructor is only available to child classes, such as
            // satcat5::eth::AeroFtpServer and satcat5::udp::AeroFtpServer.
            AeroFtpServer(
                const char* work_folder,            // Working folder
                satcat5::net::Dispatch* iface,      // Network interface
                const satcat5::net::Type& typ);     // Packet type/port/etc.
            ~AeroFtpServer();

            // Callback for incoming packets.
            void frame_rcvd(satcat5::io::LimitedRead& src) override;

            // Internal state.
            const std::string m_work_folder;
            satcat5::net::Dispatch* const m_iface;
            bool m_resume;
            std::map<u32, satcat5::net::AeroFtpFile*> m_files;
        };
    }

    // Thin wrappers for commonly used protocols:
    namespace eth {
        class AeroFtpServer final : public satcat5::net::AeroFtpServer
        {
        public:
            AeroFtpServer(
                const char* work_folder,
                satcat5::eth::Dispatch* eth,
                const satcat5::eth::MacType& type = satcat5::eth::ETYPE_AEROFTP);
        };
    }

    namespace udp {
        class AeroFtpServer final : public satcat5::net::AeroFtpServer
        {
        public:
            AeroFtpServer(
                const char* work_folder,
                satcat5::udp::Dispatch* udp,
                const satcat5::udp::Port& port = satcat5::udp::PORT_AEROFTP);
        };
    }
}
