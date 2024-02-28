//////////////////////////////////////////////////////////////////////////
// Copyright 2021-2023 The Aerospace Corporation.
// This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
//////////////////////////////////////////////////////////////////////////
// I/O interface core definitions
//
// The core of all SatCat5 I/O are the "Writeable" interface (io_writeable.h)
// and "Readable" interface (io_readable.h).  These general-purpose virtual
// interfaces are used by PacketBuffer, generic UARTs, etc. for code reuse.
//
// This file is a redirect for both of the above. New projects should include
// those files directly, but this is included for backwards-compatibility.
//

#pragma once

#include <satcat5/io_readable.h>
#include <satcat5/io_writeable.h>
