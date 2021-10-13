//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation
//
// This file is part of SatCat5.
//
// SatCat5 is free software: you can redistribute it and/or modify it under
// the terms of the GNU Lesser General Public License as published by the
// Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// SatCat5 is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
// License for more details.
//
// You should have received a copy of the GNU Lesser General Public License
// along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
//////////////////////////////////////////////////////////////////////////

#include "posix_utils.h"
#include <satcat5/utils.h>
#include <cstdio>
#include <ctime>

std::string satcat5::io::read_str(satcat5::io::Readable* src)
{
    std::string tmp;
    while (src->get_read_ready())
        tmp.push_back(src->read_u8());
    src->read_finalize();
    return tmp;
}

satcat5::io::BufferedWriterHeap::BufferedWriterHeap(
    satcat5::io::Writeable* dst, unsigned nbytes)
    : satcat5::io::BufferedWriter(dst, new u8[nbytes], nbytes, nbytes/64)
{
    // Nothing else to initialize.
}

satcat5::io::BufferedWriterHeap::~BufferedWriterHeap()
{
    delete[] m_buff.get_buff_dtor();
}

satcat5::log::ToConsole::ToConsole(s8 threshold)
    : m_threshold(threshold)
    , m_last_msg()
    , m_tref(m_timer.now())
{
    satcat5::log::start(this);
}

satcat5::log::ToConsole::~ToConsole()
{
    satcat5::log::start(0);
}

bool satcat5::log::ToConsole::contains(const char* msg)
{
    return (m_last_msg.find(msg) != std::string::npos);
}

void satcat5::log::ToConsole::log_event(s8 priority, unsigned nbytes, const char* msg)
{
    // Always store the most recent log-message.
    m_last_msg = std::string(msg, msg+nbytes);

    // Don't display anything below designated priority threshold.
    if (priority < m_threshold) return;

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

satcat5::io::PacketBufferHeap::PacketBufferHeap(unsigned nbytes)
    : satcat5::io::PacketBuffer(new u8[nbytes], nbytes, nbytes/64)
{
    // Nothing else to initialize
}

satcat5::io::PacketBufferHeap::~PacketBufferHeap()
{
    delete[] get_buff_dtor();
}

satcat5::util::PosixTimer::PosixTimer()
    : satcat5::util::GenericTimer(1)    // 1 tick = 1 usec
{
    // Nothing else to initialize.
}

u32 satcat5::util::PosixTimer::now() {
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
