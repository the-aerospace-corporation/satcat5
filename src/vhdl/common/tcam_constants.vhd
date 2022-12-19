--------------------------------------------------------------------------
-- Copyright 2021, 2022 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
-- Small package to define TCAM configuration constants.

package tcam_constants is
    -- Set policy for evicting cache entries:
    type repl_policy is (
        TCAM_REPL_NONE,     -- None (No writes once full)
        TCAM_REPL_WRAP,     -- Wraparound (First-in / First-out)
        TCAM_REPL_NRU2,     -- Not-recently-used w/ 2-bit counters
        TCAM_REPL_PLRU);    -- Pseudo least-recently used

    -- Set policy for enforcing unique addresses:
    type write_policy is (
        TCAM_MODE_SIMPLE,   -- CAM mode, no safety check
        TCAM_MODE_CONFIRM,  -- CAM mode, discard duplicates
        TCAM_MODE_MAXLEN);  -- TCAM mode, max-length-prefix

    -- Enumerate all possible TCAM search-types:
    type search_type is (
        TCAM_SEARCH_NONE,   -- Idle / don't-care
        TCAM_SEARCH_USER,   -- Input from user (IN port)
        TCAM_SEARCH_DUPL,   -- Duplicate check (CFG port)
        TCAM_SEARCH_SCAN);  -- Table readback (SCAN port)
end package;
