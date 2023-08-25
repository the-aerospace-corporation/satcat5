
//////////////////////////////////////////////////////////////////////////
// Copyright 2023 The Aerospace Corporation
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
//

#include <hal_posix/posix_cfgbus.h>
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
