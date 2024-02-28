--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
