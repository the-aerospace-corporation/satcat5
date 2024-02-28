//////////////////////////////////////////////////////////////////////////
// Copyright 2021 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// Override specific built-in functions for dramatic code-size reduction.

#define SATCAT5_BUSYWAIT_FOREVER {while(1);}

// Set default configuration:
#ifndef SATCAT5_HAL_UBLAZE_EXCEPTIONS
#define SATCAT5_HAL_UBLAZE_EXCEPTIONS 1
#endif

#ifndef SATCAT5_HAL_UBLAZE_MEMALLOC
#define SATCAT5_HAL_UBLAZE_MEMALLOC 0
#endif

// Optionally override selected Xilinx exception-handling functions,
// to prevent dependency bloat and reduce code size.
// (Default C++ exception handlers import more than 100 kB of code!)
#if SATCAT5_HAL_UBLAZE_EXCEPTIONS

extern "C" {
    // Override built-in pure-virtual-method handler.
    // See also: https://embdev.net/topic/220434#3940619
    void __cxa_pure_virtual()   SATCAT5_BUSYWAIT_FOREVER;

    // Override built-in "exit", which cannot be reached.
    void __call_exitprocs()     SATCAT5_BUSYWAIT_FOREVER;

    // Override built-in "demangle" used in exception-handler.
    // See also: https://elegantinvention.com/blog/information/smaller-binary-size-with-c-on-baremetal-g/
    void __cxa_demangle()       SATCAT5_BUSYWAIT_FOREVER;
}

namespace __gnu_cxx {
    // Override termination handler, which can add ~10+ kB of bloat.
    void __verbose_terminate_handler() SATCAT5_BUSYWAIT_FOREVER;
}

#endif  // SATCAT5_HAL_UBLAZE_EXCEPTIONS

// Optionally override memory allocation to prevent dependency bloat
// due to exception handling.  (Use defaults unless flag is set.)
#if SATCAT5_HAL_UBLAZE_MEMALLOC

#include <malloc.h>
#include <new>

void* operator new(std::size_t size)
    {return malloc(size);}
void* operator new[](std::size_t size)
    {return malloc(size);}
void operator delete(void* ptr)
    {free(ptr);}
void operator delete[](void* ptr)
    {free(ptr);}

#endif  // SATCAT5_HAL_UBLAZE_MEMALLOC
