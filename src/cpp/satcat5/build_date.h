//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2025 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
//!\file
//! Build-date reporting
//!
//!\details
//! Use preprocessor macros to obtain and manipulate the build timestamp.
//!
//! To ensure fresh results, the associated .o file should always be deleted
//! and rebuilt by the build script before compiling any other changes.
//! Keeping these functions separate minimizes the resulting time overhead.

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    //! Calculate software build date as a 32-bit integer, 0xYYMMDDHH.
    u32 get_sw_build_code();

    //! Return a pointer to the ISO8601 date and time constructed at build time.
    //! Build date is local time, no time-zone identifier given.
    const char* get_sw_build_string();
}
