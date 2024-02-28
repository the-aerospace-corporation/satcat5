//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2024 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include "posix_utils.h"
#include <satcat5/ethernet.h>
#include <satcat5/ip_core.h>
#include <satcat5/polling.h>
#include <satcat5/utils.h>
#include <cstdio>
#include <ctime>
#include <iomanip>
#include <sstream>

#if SATCAT5_WIN32
    #include <conio.h>      // For kbhit(), getch()
    #include <windows.h>    // All-in-one for Win32 API
    #undef ERROR            // Deconflict Windows "ERROR" macro
#else
    #include <sys/ioctl.h>  // For ioctl()
    #include <termios.h>    // For getchar(), tcgetattr(), etc
    #include <unistd.h>     // For usleep()
#endif

using satcat5::io::BufferedWriter;
using satcat5::io::BufferedWriterHeap;
using satcat5::io::KeyboardStream;
using satcat5::io::PacketBuffer;
using satcat5::io::PacketBufferHeap;
using satcat5::io::Readable;
using satcat5::io::Writeable;
using satcat5::log::ToConsole;
using satcat5::poll::timekeeper;
using satcat5::util::PosixTimer;
using satcat5::util::PosixTimekeeper;
using satcat5::util::write_be_u32;

std::string satcat5::io::read_str(Readable* src)
{
    std::string tmp;
    while (src->get_read_ready())
        tmp.push_back(src->read_u8());
    src->read_finalize();
    return tmp;
}

BufferedWriterHeap::BufferedWriterHeap(Writeable* dst, unsigned nbytes)
    : BufferedWriter(dst, new u8[nbytes], nbytes, nbytes/64)
{
    // Nothing else to initialize.
}

BufferedWriterHeap::~BufferedWriterHeap()
{
    delete[] m_buff.get_buff_dtor();
}

KeyboardStream::KeyboardStream(Writeable* dst, bool line_buffer)
    : m_dst(dst)
    , m_line_buffer(line_buffer)
{
#ifdef _WIN32
    // No initial setup for Windows (yet).
#else
    // Initial setup for POSIX:
    tcflush(0, TCIFLUSH);
    termios term;
    tcgetattr(0, &term);
    term.c_lflag &= ~(ICANON | ECHO);
    tcsetattr(0, TCSANOW, &term);
#endif
}

KeyboardStream::~KeyboardStream()
{
#ifdef _WIN32
    // No cleanup for Windows (yet).
#else
    // Cleanup for POSIX:
    tcflush(0, TCIFLUSH);
    termios term;
    tcgetattr(0, &term);
    term.c_lflag |= ICANON | ECHO;
    tcsetattr(0, TCSANOW, &term);
#endif
}

void KeyboardStream::poll_always()
{
    // If there's any characters in the queue, copy them.
#ifdef _WIN32
    while (_kbhit()) {
        write_key(_getch());
    }
#else
    int byteswaiting;
    while (1) {
        ioctl(0, FIONREAD, &byteswaiting);
        if (byteswaiting < 1) break;
        write_key(getchar());
    }
#endif
}

void KeyboardStream::write_key(int ch)
{
    if (m_line_buffer && (ch == '\r' || ch == '\n')) {
        m_dst->write_finalize();    // EOL flushes input
    } else if (0 < ch && ch < 128) {
        m_dst->write_u8(ch);        // Forward "normal" keys
        if (!m_line_buffer) m_dst->write_finalize();
    }
}

ToConsole::ToConsole(s8 threshold)
    : m_threshold(threshold)
    , m_last_msg()
    , m_tref(m_timer.now())
{
    // Nothing else to initialize.
}

bool ToConsole::contains(const char* msg)
{
    return (m_last_msg.find(msg) != std::string::npos);
}

void ToConsole::suppress(const char* msg)
{
    if (msg) {
        m_suppress.push_back(std::string(msg));
    } else {
        m_suppress.clear();
    }
}

void ToConsole::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    // Always store the most recent log-message.
    m_last_msg = std::string(msg, msg+nbytes);

    // Don't display anything below designated priority threshold.
    if (priority < m_threshold) return;

    // Don't display the message if it matches any saved filter.
    for (auto filter = m_suppress.begin() ; filter != m_suppress.end() ; ++filter) {
        if (m_last_msg.find(*filter) != std::string::npos) return;
    }

    // Timestamp = Milliseconds since creation of this object.
    u32 now = (m_timer.elapsed_usec(m_tref) / 1000) % 10000;

    // Print human-readable message to either STDERR or STDOUT.
    if (priority >= satcat5::log::ERROR) {
        fprintf(stderr, "Log (ERROR) @%04u: %s\n", now, msg);
    } else if (priority >= satcat5::log::WARNING) {
        fprintf(stdout, "Log (WARN)  @%04u: %s\n", now, msg);
    } else if (priority >= satcat5::log::INFO) {
        fprintf(stdout, "Log (INFO)  @%04u: %s\n", now, msg);
    } else {
        fprintf(stdout, "Log (DEBUG) @%04u: %s\n", now, msg);
    }
}

PacketBufferHeap::PacketBufferHeap(unsigned nbytes)
    : PacketBuffer(new u8[nbytes], nbytes, nbytes/64)
{
    // Nothing else to initialize
}

PacketBufferHeap::~PacketBufferHeap()
{
    delete[] get_buff_dtor();
}

PosixTimer::PosixTimer()
    : satcat5::util::GenericTimer(1)    // 1 tick = 1 usec
{
    // Nothing else to initialize.
}

u32 PosixTimer::now()
{
    struct timespec tv;
    int errcode = clock_gettime(CLOCK_MONOTONIC, &tv);
    if (errcode) {
        // Fallback to clock() function, usually millisecond resolution.
        const unsigned SCALE = 1000000 / CLOCKS_PER_SEC;
        return (u32)(clock() * SCALE);
    } else {
        // Higher resolution using clock_gettime(), if available.
        u32 usec1 = (u32)(tv.tv_sec * 1000000);
        u32 usec2 = (u32)(tv.tv_nsec / 1000);
        return usec1 + usec2;
    }
}

s64 PosixTimer::gps() const
{
    // Get the POSIX timestamp (sorta-kinda-UTC).
    // See also: http://www.madore.org/~david/computers/unix-leap-seconds.html
    struct timespec tv;
    int errcode = clock_gettime(CLOCK_REALTIME, &tv);
    if (errcode) return 0;
    s64 msec1 = s64(tv.tv_sec) * 1000;
    s64 msec2 = s64(tv.tv_nsec) / 1000000;
    // Assume this code is being run 2017 or later, so the number of
    // cumulative leap-seconds is fixed for the foreseeable future.
    // TODO: Keep this up-to-date if/when leap-seconds resume.
    // See also: https://stackoverflow.com/questions/16539436/
    // See also: https://stackoverflow.com/questions/20521750/
    constexpr s64 GPS_EPOCH = (1000LL) * (315964800 - 18);
    return msec1 + msec2 - GPS_EPOCH;
}

PosixTimekeeper::PosixTimekeeper()
    : m_timer()
    , m_adapter(&timekeeper, &m_timer)
{
    timekeeper.set_clock(&m_timer);
}

PosixTimekeeper::~PosixTimekeeper()
{
    timekeeper.set_clock(0);
}

void satcat5::util::sleep_msec(unsigned msec)
{
#ifdef _WIN32
    Sleep(msec);
#else
    usleep(msec * 1000);
#endif
}

void satcat5::util::service_msec(unsigned total_msec, unsigned msec_per_iter)
{
    PosixTimer timer;
    u32 usec = 1000 * total_msec;
    u32 tref = timer.now();
    while (1) {
        poll::service_all();
        if (timer.elapsed_test(tref, usec)) break;
        satcat5::util::sleep_msec(msec_per_iter);
    }
}

std::string satcat5::log::format(const satcat5::eth::MacAddr& addr)
{
    char tmp[32];
    snprintf(tmp, sizeof(tmp),
        "%02X:%02X:%02X:%02X:%02X:%02X",
        addr.addr[0], addr.addr[1], addr.addr[2],
        addr.addr[3], addr.addr[4], addr.addr[5]);
    return std::string(tmp);
}

std::string satcat5::log::format(const satcat5::ip::Addr& addr)
{
    // Extract individual byte fields from IPv4 address.
    u8 addr_bytes[4];
    write_be_u32(addr_bytes, addr.value);
    // Format using conventional format (e.g., "127.0.0.1")
    std::stringstream tmp;
    tmp << (unsigned)addr_bytes[0] << "."
        << (unsigned)addr_bytes[1] << "."
        << (unsigned)addr_bytes[2] << "."
        << (unsigned)addr_bytes[3];
    return tmp.str();
}
