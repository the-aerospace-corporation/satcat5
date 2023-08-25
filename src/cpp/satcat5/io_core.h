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
