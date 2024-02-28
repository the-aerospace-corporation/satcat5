//////////////////////////////////////////////////////////////////////////
// Copyright 2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/file_aeroftp.h>
#include <satcat5/eth_dispatch.h>
#include <satcat5/log.h>
#include <satcat5/udp_dispatch.h>
#include <satcat5/utils.h>

// Set verbosity level (0/1/2)
constexpr unsigned DEBUG_VERBOSE = 0;

// Define the transport-layer wrappers first.
using satcat5::net::Type;

satcat5::eth::AeroFtpServer::AeroFtpServer(
    const char* work_folder,
    satcat5::eth::Dispatch* eth,
    const satcat5::eth::MacType& type)
    : satcat5::net::AeroFtpServer(work_folder, eth, Type(type.value))
{
    // Nothing else to initialize.
}

satcat5::udp::AeroFtpServer::AeroFtpServer(
    const char* work_folder,
    satcat5::udp::Dispatch* udp,
    const satcat5::udp::Port& port)
    : satcat5::net::AeroFtpServer(work_folder, udp, Type(port.value))
{
    // Nothing else to initialize.
}

// Begin defining the core functionality.
using satcat5::io::ArrayRead;
using satcat5::io::LimitedRead;
using satcat5::io::Readable;
using satcat5::net::AeroFtpFile;
using satcat5::net::AeroFtpServer;
using satcat5::util::min_u32;

static constexpr unsigned WORDS_PER_BLOCK = 256;

static constexpr unsigned words2blocks(unsigned words)
    { return satcat5::util::div_ceil(words, WORDS_PER_BLOCK); }

inline std::string make_filename(const char* work, unsigned id, const char* typ)
{
    char temp[512];
    snprintf(temp, sizeof(temp), "%s/file_%08u.%s", work, id, typ);
    return std::string(temp);
}

AeroFtpFile::AeroFtpFile(const char* work, unsigned id, unsigned len, bool resume)
    : m_name_data(make_filename(work, id, "data"))
    , m_name_meta(make_filename(work, id, "rcvd"))
    , m_name_part(make_filename(work, id, "part"))
    , m_file_id(id)
    , m_file_len(len)
    , m_bcount(words2blocks(len))
    , m_pcount(0)
    , m_data(0)
    , m_meta(0)
    , m_pending(new u8[m_bcount])
    , m_status(m_pending, 0)
{
    // Does the complete file already exist?
    FILE* temp = fopen(m_name_data.c_str(), "rb");
    bool done = (temp && !ferror(temp));
    if (temp) fclose(temp);
    if (done && resume) {
        log(satcat5::log::INFO, "Already complete");
        return;
    } else if (done) {
        remove(m_name_data.c_str());
    }

    // Open or create the in-progress files.
    m_data = fopen(m_name_part.c_str(), resume ? "ab+" : "wb+");
    m_meta = fopen(m_name_meta.c_str(), resume ? "ab+" : "wb+");

    // Use length of metadata file to indicate previous state...
    unsigned meta_len = (unsigned)ftell(m_meta);
    if (!(m_data && m_meta)) {
        // Couldn't open working files. Permission error?
        log(satcat5::log::ERROR, "File creation error");
        cleanup();
        m_pcount = UINT_MAX;
    } else if (meta_len == 0) {
        // New file -> Initialize to empty all-pending state.
        log(satcat5::log::INFO, done ? "Restart file" : "New file");
        m_pcount = m_bcount;
        memset(m_pending, 1, m_bcount);
        fwrite(m_pending, 1, m_bcount, m_meta);
    } else if (meta_len == m_bcount) {
        // Partial file -> Reload state and count pending blocks.
        log(satcat5::log::INFO, "Continued file");
        fseek(m_meta, 0, SEEK_SET);
        fread(m_pending, 1, m_bcount, m_meta);
        for (unsigned a = 0 ; a < m_bcount ; ++a) {
            if (m_pending[a]) ++m_pcount;
        }
    } else {
        // Mismatched length -> Error, unable to proceed.
        log(satcat5::log::ERROR, "Length mismatch");
        cleanup();
        m_pcount = UINT_MAX;
    }
}

AeroFtpFile::~AeroFtpFile()
{
    cleanup();
    delete[] m_pending;
}

void AeroFtpFile::cleanup()
{
    if (m_data) fclose(m_data);
    if (m_meta) fclose(m_meta);
    m_data = 0;
    m_meta = 0;
}

void AeroFtpFile::log(s8 level, const char* msg)
{
    satcat5::log::Log(level, "AeroFTP", msg)
        .write(", ID").write10(m_file_id)
        .write(", length").write10(4u*m_file_len);
}

void AeroFtpFile::frame_rcvd(
    u32 file_id, u32 file_len, u32 offset, u32 rxlen,
    satcat5::io::LimitedRead& data)
{
    if (DEBUG_VERBOSE > 1) log(satcat5::log::DEBUG, "Frame received");

    // Calculate block number and expected length.
    u32 block = words2blocks(offset);
    u32 expected = min_u32(WORDS_PER_BLOCK, m_file_len - offset);

    // Reject any packets that fail sanity checks.
    if (done() || error()) return;
    if (file_id != m_file_id) return;
    if (file_len != m_file_len) return;
    if (block >= m_bcount) return;
    if (block*WORDS_PER_BLOCK != offset) return;
    if (rxlen != expected) return;
    if (data.get_read_ready() < 4*expected) return;

    // Has this block already been saved?
    if (!m_pending[block]) return;

    // Write the newly-received data.
    u8 temp[4*WORDS_PER_BLOCK];
    data.read_bytes(4*rxlen, temp);
    fseek(m_data, (s64)(4ull*offset), SEEK_SET);
    fwrite(temp, 1, 4*rxlen, m_data);

    // Update the pending-blocks state.
    --m_pcount;
    m_pending[block] = 0;
    fseek(m_meta, (s64)block, SEEK_SET);
    fwrite(m_pending + block, 1, 1, m_meta);

    // Was this the last block in the file?
    if (done()) {
        log(satcat5::log::INFO, "Completed file");
        cleanup();
        rename(m_name_part.c_str(), m_name_data.c_str());
        remove(m_name_meta.c_str());
    } else if (DEBUG_VERBOSE > 0) {
        log(satcat5::log::DEBUG, "Frame accepted");
    }
}

Readable* AeroFtpFile::missing_blocks()
{
    if (error()) return 0;
    m_status.read_reset(m_bcount);
    return &m_status;
}

AeroFtpServer::AeroFtpServer(
    const char* work_folder,
    satcat5::net::Dispatch* iface,
    const satcat5::net::Type& typ)
    : satcat5::net::Protocol(typ)
    , m_work_folder(work_folder)
    , m_iface(iface)
    , m_files()
{
    m_iface->add(this);
}

AeroFtpServer::~AeroFtpServer()
{
    m_iface->remove(this);
    for (auto x = m_files.begin() ; x != m_files.end() ; ++x) {
        delete x->second;
    }
}

Readable* AeroFtpServer::missing_blocks(u32 file_id)
{
    auto x = m_files.find(file_id);
    if (x != m_files.end()) {
        return x->second->missing_blocks();
    } else {
        return 0;
    }
}

bool AeroFtpServer::done(u32 file_id) const
{
    auto x = m_files.find(file_id);
    if (x != m_files.end()) {
        return x->second->done();
    } else {
        return false;
    }
}

void AeroFtpServer::frame_rcvd(LimitedRead& src)
{
    // Read the packet header.
    u32 file_id  = src.read_u32();
    u32 file_len = src.read_u32();
    u32 blk_off  = src.read_u32();
    u32 blk_len  = src.read_u32();

    // Sanity checks before we continue.
    if (file_len == 0) return;
    if (blk_off % WORDS_PER_BLOCK != 0) return;
    if (blk_len > WORDS_PER_BLOCK) return;

    // First time seeing this file?
    if (m_files.find(file_id) == m_files.end()) {
        m_files[file_id] = new AeroFtpFile(
            m_work_folder.c_str(), file_id, file_len, m_resume);
    }

    // Dispatch to the appropriate handler.
    m_files[file_id]->frame_rcvd(file_id, file_len, blk_off, blk_len, src);
}
