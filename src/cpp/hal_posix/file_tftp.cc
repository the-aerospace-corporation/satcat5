//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/file_tftp.h>
#include <hal_posix/posix_utils.h>
#include <vector>

// Additional includes for specific platforms:
#if SATCAT5_WIN32
    static const char* PATH_SEP = "\\";
#else
    static const char* PATH_SEP = "/";
#endif

// Shortcuts for commonly used names.
using satcat5::udp::TftpClientPosix;
using satcat5::udp::TftpServerPosix;

TftpClientPosix::TftpClientPosix(satcat5::udp::Dispatch* iface)
    : m_dst(0, true)    // Close on finalize
    , m_src(0, true)    // Close on finalize
    , m_tftp(iface)
{
    // No other initialization required.
}

TftpClientPosix::~TftpClientPosix()
{
    m_dst.close();
    m_src.close();
}

void TftpClientPosix::begin_download(
    const satcat5::ip::Addr& server,
    const char* filename_local,
    const char* filename_remote)
{
    m_dst.open(filename_local);
    m_tftp.begin_download(&m_dst, server, filename_remote);
}

void TftpClientPosix::begin_upload(
    const satcat5::ip::Addr& server,
    const char* filename_local,
    const char* filename_remote)
{
    m_src.open(filename_local);
    if (m_src.get_read_ready() > 0)
        m_tftp.begin_upload(&m_src, server, filename_remote);
    else
        log::Log(log::ERROR, "TftpClient: File not found", filename_local);
}

TftpServerPosix::TftpServerPosix(
    satcat5::udp::Dispatch* iface,
    const char* work_folder)
    : satcat5::udp::TftpServerCore(iface)
    , m_work_folder(std::string(work_folder) + PATH_SEP)
    , m_dst(0, true)    // Close on finalize
    , m_src(0, true)    // Close on finalize
{
    // No other initialization required.
}

TftpServerPosix::~TftpServerPosix()
{
    m_dst.close();
    m_src.close();
}

std::string TftpServerPosix::check_path(const char* filename)
{
    // Sanity check: There must be a defined working folder,
    // and it must not contain the ".." token.
    if (!filename) return std::string();
    std::string filename2(filename);
    if (filename2.find("..") != std::string::npos) return std::string();
    return m_work_folder + filename2;
}

satcat5::io::Readable* TftpServerPosix::read(const char* filename)
{
    // Check filename is inside the working folder.
    std::string safe_path = check_path(filename);
    if (safe_path.empty()) {
        log::Log(log::INFO, "TftpServer: Rejected read", filename);
        return 0;
    } else {
        m_src.open(safe_path.c_str());
        if (m_src.get_read_ready() > 0) {
            log::Log(log::INFO, "TftpServer: Reading", safe_path.c_str())
                .write(", length").write10(m_src.get_read_ready());
            return &m_src;
        } else {
            log::Log(log::INFO, "TftpServer: File not found", filename);
            return 0;
        }
    }
}

satcat5::io::Writeable* TftpServerPosix::write(const char* filename)
{
    // Check filename is inside the working folder.
    std::string safe_path = check_path(filename);
    if (safe_path.empty()) {
        log::Log(log::INFO, "TftpServer: Rejected write", filename);
        return 0;
    } else {
        m_dst.open(safe_path.c_str());
        if (m_dst.get_write_space() > 0) {
            log::Log(log::INFO, "TftpServer: Writing", safe_path.c_str());
            return &m_dst;
        } else {
            log::Log(log::WARNING, "TftpServer: Unable to open", safe_path.c_str());
            return 0;
        }
    }
}
