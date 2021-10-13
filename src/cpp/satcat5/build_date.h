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
// Build-date reporting
//
// Use preprocessor macros to obtain and manipulate the build timestamp.
//
// To ensure fresh results, the associated .o file should always be deleted
// and rebuilt by the build script before compiling any other changes.
// Keeping these functions separate minimizes the resulting time overhead.

#pragma once

#include <satcat5/types.h>

namespace satcat5 {
    // Calculate software build date as a 32-bit integer, 0xYYMMDDHH.
    u32 get_sw_build_code();

    // Construct ISO8601 date and time and return pointer to result.
    const char* get_sw_build_string();
}
