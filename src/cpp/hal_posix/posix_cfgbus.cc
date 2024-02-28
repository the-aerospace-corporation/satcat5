//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////

#include <hal_posix/posix_cfgbus.h>

// TODO: Implement a Windows equivalent?
#ifndef _WIN32

#include <sys/mman.h>
#include <unistd.h>
#include <fcntl.h>

using satcat5::cfg::ConfigBusPosix;
using satcat5::cfg::ConfigBusMmap;
using satcat5::cfg::IoStatus;

ConfigBusPosix::ConfigBusPosix(void* base_addr, int irq)
    : ConfigBusMmap(base_addr, irq)
{
    m_fd = open("/dev/mem", O_RDWR | O_SYNC);
    m_base_ptr =(u32*) mmap(0, MAX_TOTAL_REGS * 4, PROT_READ | PROT_WRITE, MAP_SHARED, m_fd, (off_t) base_addr);
}

ConfigBusPosix::~ConfigBusPosix()
{
    munmap(0, MAX_TOTAL_REGS * 4);
    close(m_fd);
}

#endif // _WIN32
