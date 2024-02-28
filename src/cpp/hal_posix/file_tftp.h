//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//
// TFTP client and server implementation using FileReader and FileWriter
//

#pragma once

#include <hal_posix/file_io.h>
#include <satcat5/udp_tftp.h>
#include <string>

namespace satcat5 {
    namespace udp {
        // A client makes request(s) to a remote server.
        class TftpClientPosix
        {
        public:
            explicit TftpClientPosix(satcat5::udp::Dispatch* iface);
            virtual ~TftpClientPosix();

            // Download a file from server to a Writeable stream.
            void begin_download(
                const satcat5::ip::Addr& server,
                const char* filename_local,
                const char* filename_remote);

            // Upload data from a Readable stream to the server.
            void begin_upload(
                const satcat5::ip::Addr& server,
                const char* filename_local,
                const char* filename_remote);

            // Accessors for the transfer status.
            inline bool active() const
                {return m_tftp.active();}
            inline u32 progress_blocks() const
                {return m_tftp.progress_blocks();}
            inline u32 progress_bytes() const
                {return m_tftp.progress_bytes();}

        protected:
            // Interface objects.
            satcat5::io::FileWriter m_dst;
            satcat5::io::FileReader m_src;
            satcat5::udp::TftpClient m_tftp;
        };

        // A server handles requests from remote clients.
        // For safety reasons, file operations are limited to the
        // designated working folder.  Use "/" at your own risk.
        class TftpServerPosix : public satcat5::udp::TftpServerCore {
        public:
            TftpServerPosix(
                satcat5::udp::Dispatch* iface,
                const char* work_folder);
            virtual ~TftpServerPosix();

        protected:
            // Check a user-supplied path is safe to use.
            std::string check_path(const char* filename);

            // Required overrides from TftpServer.
            satcat5::io::Readable* read(const char* filename) override;
            satcat5::io::Writeable* write(const char* filename) override;

            // Interface objects.
            const std::string m_work_folder;
            satcat5::io::FileWriter m_dst;
            satcat5::io::FileReader m_src;
        };
    }
}
