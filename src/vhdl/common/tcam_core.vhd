--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ternary Content Addressable Memory: Core module
--
-- This module implements a variant of the scalable CAM/TCAM described by:
--      Jiang, Weirong. "Scalable ternary content addressable memory
--      implementation using FPGAs." Architectures for Networking and
--      Communications Systems. IEEE, 2013.
--
-- The core functionality is to maintain an indexed array whose contents
-- can be searched in a single clock cycle.  Search terms can be exact
-- (CAM) or optionally allow wildcards in specific bits (TCAM).  Search
-- latency depends on build options, but is always fixed, and a new
-- search can be executed on each clock cycle.  The returned value is
-- the index of the search term, if found.
--
-- The flexible search function can then be used for MAC-address lookup,
-- next-hop lookup for IP-routing, packet-priority lookup, etc.
--
-- Lookup table parameters should be chosen to match primitives on the
-- FPGA platform.  Defaults are set in the "common_primitives" package
-- but may be overridden for special designs.  Recommended parameters:
--  * Microsemi Polarfire:  LUT_WRBIT = 0, LUT_WIDTH = 6 (uSRAM)
--  * Xilinx 7-series:      LUT_WRBIT = 1, LUT_WIDTH = 6 (LUTRAM)
--
-- A separate management interface is used to add new table entries.
-- Writes follow AXI-style flow control.  Single-cycle writes are possible
-- only in simple configurations, most others require many clock cycles to
-- write each table entry and may rely on idle cycles between input queries.
--  * LUT_WRBIT = 1: Fixed at 2^LUT_WIDTH clocks.
--                   (i.e., 64 cycles if LUT_WIDTH = 6).
--  * LUT_WRBIT = 0: At least 4 * 2^LUT_WIDTH clocks, using idle cycles.
--                   (i.e., At least 256 cycles if LUT_WIDTH = 6).
-- Since most applications do not update IP-address or MAC-address tables
-- frequently, and have at least some idle time, this is usually a non-issue.
-- Queries to columns where an update is in progress will not return a match.
--
-- The user specifies the index where each new item should be written.  This
-- block provides a *recommended* next-write index depending on the specified
-- cache replacement policy (see below).  If TCAM_REPL_NONE is set, then the
-- write index *must* be looped back from the recommended index.  Otherwise,
-- users may use or disregard the recommended index at their discretion.  For
-- example, overrides are essential for coordinating table contents in multiple
-- CAM/TCAM blocks, or in lookup tables for additional metadata.
--
-- The cache-replacement policy is set at build-time (TCAM_REPL):
--  * None (TCAM_REPL_NONE)
--      * New entries must be written in ascending order.
--      * Once full, no new entries can be written.
--      + Non-wildcard writes can be executed in a single clock cycle.
--      + Lowest resource utilization.  Good choice for fixed-size tables.
--      - Eviction of stale entries is not possible.
--      - User cannot override write index.
--  * Wraparound / circular-buffer (TCAM_REPL_WRAP)
--      * New entries should be written or rewritten in ascending order,
--        wrapping around to the oldest entry once full.  However, it is
--        safe to ignore the suggested order.
--      + This mode is recommended when indexing is controlled externally.
--      + Low complexity
--      - Poor cache performance due to first-in / first-out ordering.
--  * Other caching algorithms (TCAM_REPL_NRU2, TCAM_REPL_PLRU)
--      * Any time a match is found, a cache-controller updates a data
--        structure that predicts which other element is least likely to
--        be used again soon.  See each "tcam_cache_*" block for details.
--      * New entries can be written or rewritten in any order.
--        (i.e., The cache-controller gives hints, not orders.)
--      + These methods give superior caching performance in most cases.
--      - Higher resource utilization.
--
-- Policy for writing new entries is also set at build-time (TCAM_MODE):
--  * Simple mode
--      * CAM mode, addresses must match exactly.
--      * Writes directly to specified CAM index, no safety checks.
--      * Upstream controller must ensure each address is unique.
--  * Confirm mode
--      * CAM mode, addresses must match exactly.
--      * Check if new address is already in table before writing.
--        (Must wait for idle time; increased time per write.)
--      * Duplicates are discarded without writing.
--  * Max-length-prefix mode
--      * TCAM mode, matching follows longest-prefix rules (e.g., IPv4 CIDR):
--          * Each table entry stores an address and a prefix length N.
--          * A "match" is any entry where all N MSBs match the search term.
--          * If there is more than one match, keep the one with largest N.
--          * Special case N = 0 is used to erase the table entry.
--      * Upstream controller must avoid writing identical entries.
--        (i.e., Never write the same address and prefix length twice.)
--
-- In any mode, unexpected duplicates will assert an error flag; upstream
-- error-handling must reset the table to restore a known-good state.
--
-- An optional scan interface can read the current table contents.  Each
-- scan request queries the table several times to infer the address-range
-- associated with a specific table entry, reporting the base address and
-- a mask of fixed bits.  Requests are accepted using AXI VALID/READY flow
-- control; the results are ready on the cycle when READY is asserted.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.tcam_constants.all;

entity tcam_core is
    generic (
    INPUT_WIDTH : positive;         -- Width of the search term
    TABLE_SIZE  : positive;         -- Max stored table entries
    REPL_MODE   : repl_policy;      -- Replacement mode (see above)
    TCAM_MODE   : write_policy;     -- Enable wildcard searches?
    META_WIDTH  : natural := 0;     -- Metadata width (optional)
    LUT_WIDTH   : positive := PREFER_DPRAM_AWIDTH;
    LUT_WRBIT   : boolean := PREFER_DPRAM_ONEBIT);
    port (
    -- Search input
    in_data     : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_next     : in  std_logic;

    -- Search result
    out_index   : out integer range 0 to TABLE_SIZE-1;
    out_found   : out std_logic;
    out_next    : out std_logic;
    out_error   : out std_logic;

    -- Matched-delay for original input and metadata (optional)
    out_data    : out std_logic_vector(INPUT_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);

    -- Management interface is used to write new table entries.
    -- (Note: Prefix length "plen" is used only in TCAM_MODE_MAXLEN.)
    -- (Note: "Reject" strobe is only asserted in TCAM_MODE_CONFIRM.)
    -- (Note: Optional "Done" flag is mainly used for unit testing.)
    cfg_clear   : in  std_logic := '0';
    cfg_suggest : out integer range 0 to TABLE_SIZE-1;
    cfg_index   : in  integer range 0 to TABLE_SIZE-1;
    cfg_data    : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    cfg_plen    : in  integer range 0 to INPUT_WIDTH := INPUT_WIDTH;
    cfg_valid   : in  std_logic;    -- AXI flow-control
    cfg_ready   : out std_logic;    -- AXI flow-control
    cfg_reject  : out std_logic;    -- Address already in table
    cfg_done    : out std_logic;    -- Done/idle indicator

    -- Scan interface is used to read table contents (optional).
    scan_index  : in  integer range 0 to TABLE_SIZE-1 := 0;
    scan_valid  : in  std_logic := '0';
    scan_ready  : out std_logic;
    scan_found  : out std_logic;
    scan_data   : out std_logic_vector(INPUT_WIDTH-1 downto 0);
    scan_mask   : out std_logic_vector(INPUT_WIDTH-1 downto 0);

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end tcam_core;

architecture tcam_core of tcam_core is

-- Can we enable single-cycle writes?
constant SIMPLE_WRITE : boolean :=
    (REPL_MODE = TCAM_REPL_NONE) and (TCAM_MODE /= TCAM_MODE_MAXLEN);

-- Divide search lookup into N smaller segments.
-- N = 6 (64x1) is best for Xilinx 7-series, adjust for other platforms.
constant LUT_COUNT : positive := (INPUT_WIDTH + LUT_WIDTH - 1) / LUT_WIDTH;
constant EXT_WIDTH : positive := LUT_COUNT * LUT_WIDTH;

-- Define various convenience types.
subtype search_t is std_logic_vector(INPUT_WIDTH-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype table_idx_t is integer range 0 to TABLE_SIZE-1;
subtype ext_addr_t is unsigned(EXT_WIDTH-1 downto 0);
subtype sub_addr_t is unsigned(LUT_WIDTH-1 downto 0);
subtype sub_mask_t is std_logic_vector(LUT_COUNT-1 downto 0);
subtype cam_mask_t is std_logic_vector(TABLE_SIZE-1 downto 0);
type cam_mask_array is array(0 to LUT_COUNT-1) of cam_mask_t;
constant SUBADDR_FINAL : sub_addr_t := (others => '1');

-- Get the Nth address segment for a given LUTRAM.
function get_subaddr(addr:search_t ; n:natural) return sub_addr_t is
    variable ext : ext_addr_t := resize(unsigned(addr), EXT_WIDTH);
    variable sub : sub_addr_t := ext((n+1)*LUT_WIDTH-1 downto n*LUT_WIDTH);
begin
    return sub;
end function;

-- Convert table-index to a one-hot bit mask.
function create_mask(n : table_idx_t) return cam_mask_t is
    variable mask : cam_mask_t := (others => '0');
begin
    mask(n) := '1'; -- Write to the selected column
    return mask;
end function;

-- Determine which matching units match the given wildcard address.
function create_tvec(addr, mask : search_t; erase: std_logic; wridx : sub_addr_t) return sub_mask_t is
    variable subaddr, submask : sub_addr_t;
    variable tvec : sub_mask_t;
begin
    -- For each matching unit...
    for n in tvec'range loop
        subaddr := get_subaddr(addr, n);
        submask := get_subaddr(mask, n);
        if (erase = '1') then
            -- Erase mode writes all zeros to the matching unit.
            tvec(n) := '0';
        elsif (TCAM_MODE = TCAM_MODE_MAXLEN) then
            -- Check wildcard range for each matching unit...
            tvec(n) := bool2bit((subaddr and submask) = (wridx and submask));
        else
            -- No wildcards, just check for an exact match.
            tvec(n) := bool2bit(subaddr = wridx);
        end if;
    end loop;
    return tvec;
end function;

-- Given an array of bit-masks, AND them together to form a single mask.
function and_reduce(
    x : cam_mask_array;
    y : cam_mask_t := (others => '1'))
    return cam_mask_t
is
    variable tmp : cam_mask_t := y;
begin
    for n in x'range loop
        tmp := tmp and x(n);
    end loop;
    return tmp;
end function;

-- Given a bit-mask, return an error if more than one bit is set.
function one_hot_error(x : cam_mask_t) return std_logic is
    variable tmp : std_logic := '0';
begin
    for n in x'range loop
        if (x(n) = '1' and tmp = '1') then
            report "Invalid one-hot input!" severity error;
            return '1';
        end if;
        tmp := tmp or x(n);
    end loop;
    return '0';
end function;

-- Match-unit control signals.
signal camrd_masks  : cam_mask_array := (others => (others => '0'));
signal camrd_type   : search_type := TCAM_SEARCH_NONE;
signal camwr_addr   : sub_addr_t := (others => '0');
signal camwr_mask   : cam_mask_t := (others => '1');
signal camwr_tval   : sub_mask_t := (others => '0');

-- Search result pipeline.
signal reduce_data  : search_t := (others => '0');
signal reduce_meta  : meta_t := (others => '0');
signal reduce_mask  : cam_mask_t := (others => '0');
signal reduce_type  : search_type := TCAM_SEARCH_NONE;
signal match_data   : search_t := (others => '0');
signal match_meta   : meta_t := (others => '0');
signal match_index  : table_idx_t := 0;
signal match_found  : std_logic := '0';
signal match_type   : search_type := TCAM_SEARCH_NONE;
signal match_aux    : std_logic := '0';
signal match_error  : std_logic := '0';
signal match_reject : std_logic;
signal match_start  : std_logic;

-- Cache replacement and CAM-update state machine.
type ctrl_state_t is (
    CTRL_INIT,      -- Clear tables on startup
    CTRL_IDLE,      -- Ready to receive new command
    CTRL_FULL,      -- No longer accepting new writes
    CTRL_CHECK,     -- Checking for duplicates before write
    CTRL_WAIT,      -- Waiting to start read/modify/write
    CTRL_READ,      -- 1st phase of read/modify/write
    CTRL_MODIFY,    -- 2nd phase of read/modify/write
    CTRL_WRITE);    -- 3rd phase of read/modify/write
signal ctrl_state   : ctrl_state_t := CTRL_INIT;
signal ctrl_pmask   : search_t := (others => '1');
signal ctrl_erase   : std_logic := '0';
signal ctrl_error   : std_logic := '0';
signal repl_index   : table_idx_t := 0; -- Recommended write column
signal cfg_exec     : std_logic;        -- Column contents updated
signal cfg_ready_i  : std_logic;        -- Accept command (AXI flow-control)
signal cfg_write    : std_logic;        -- Any write to lookup table
signal cfg_reset    : std_logic;

-- Scan logic for table readback.
signal scan_addr    : sub_addr_t := (others => '0');
signal scan_match   : sub_mask_t := (others => '0');
signal scan_min     : ext_addr_t := (others => '0');
signal scan_max     : ext_addr_t := (others => '0');
signal scan_retry   : std_logic := '0';
signal scan_wait    : std_logic := '0';
signal scan_done    : std_logic := '0';
signal scan_next    : std_logic;

begin

-- Drive top-level outputs.
out_data    <= match_data;
out_meta    <= match_meta;
out_index   <= match_index;
out_found   <= match_found;
out_next    <= bool2bit(match_type = TCAM_SEARCH_USER);
out_error   <= match_error or ctrl_error;
cfg_suggest <= repl_index;
cfg_ready   <= cfg_ready_i;
cfg_reject  <= match_reject;
cfg_done    <= bool2bit(ctrl_state = CTRL_IDLE) and not cfg_valid;
scan_ready  <= scan_done;
scan_found  <= and_reduce(scan_match);
scan_data   <= std_logic_vector(resize(scan_min, INPUT_WIDTH));
scan_mask   <= std_logic_vector(resize(scan_min xnor scan_max, INPUT_WIDTH));

-- The "start" strobe initiates a read/modify/write cycle in all modes.
-- The "reject" strobe only applies in TCAM_MODE_CONFIRM.
match_start  <= cfg_valid and bool2bit(ctrl_state = CTRL_IDLE);
match_reject <= match_found
            and bool2bit(ctrl_state = CTRL_CHECK)
            and bool2bit(match_type = TCAM_SEARCH_CTRL)
            and bool2bit(TCAM_MODE = TCAM_MODE_CONFIRM);

-- Attempt next scan query whenever there is an active user request.
-- (May be overridden by main-input or duplicate-check, if applicable.)
scan_next   <= scan_valid and not scan_wait;

-- Separation of reset signals ensures we can clear table while operating.
cfg_reset   <= cfg_clear or reset_p;

-- Instantiate each of the first-stage matching units.
-- Each LUTRAM bank contains 2**LUT_WIDTH words with TABLE_SIZE bits.
-- The entire bank uses the same read and write address.
gen_cam_word : for n in 0 to LUT_COUNT-1 generate
    local : block
        signal wr_addr, rd_addr : sub_addr_t := (others => '0');
        signal wr_mask   : cam_mask_t := (others => '0');
        signal rd_enable : std_logic := '0';
    begin
        -- Read address selection, in descending priority:
        p_read : process(clk)
        begin
            if rising_edge(clk) then
                if (in_next = '1') then
                    rd_addr <= get_subaddr(in_data, n);
                elsif (match_start = '1') then
                    rd_addr <= get_subaddr(cfg_data, n);
                elsif (cfg_valid = '1') then
                    rd_addr <= camwr_addr;
                elsif (scan_next = '1') then
                    rd_addr <= scan_addr;
                else
                    rd_addr <= (others => 'X');     -- Don't care
                end if;
                rd_enable <= in_next or cfg_valid or scan_next;
            end if;
        end process;

        -- Write address depends on build-time configuration only:
        wr_addr <= get_subaddr(cfg_data, n)
              when (SIMPLE_WRITE and ctrl_state /= CTRL_INIT)
              else camwr_addr;

        -- Bit-at-a-time mode uses separate write-enables for each column.
        -- (i.e., Instantiate separate DPRAM blocks for each bit/column.)
        gen_bits : if LUT_WRBIT generate
            gen_cam_bit : for b in 0 to TABLE_SIZE-1 generate
                u_column : dpram
                    generic map(
                    AWIDTH      => LUT_WIDTH,
                    DWIDTH      => 1)
                    port map(
                    wr_clk      => clk,
                    wr_addr     => wr_addr,
                    wr_en       => camwr_mask(b),
                    wr_val(0)   => camwr_tval(n),
                    rd_clk      => clk,
                    rd_addr     => rd_addr,
                    rd_en       => rd_enable,
                    rd_val(0)   => camrd_masks(n)(b));
            end generate;
        end generate;

        -- Word-at-a-time mode uses a read-modify-write cycle to update columns.
        -- (i.e., Instantiate a single DPRAM block containing all columns.)
        gen_word : if not LUT_WRBIT generate
            p_modify : process(clk)
            begin
                if rising_edge(clk) then
                    for b in wr_mask'range loop
                        if (camwr_mask(b) = '1') then
                            wr_mask(b) <= camwr_tval(n);
                        elsif (camrd_type = TCAM_SEARCH_CTRL) then
                            wr_mask(b) <= camrd_masks(n)(b);
                        end if;
                    end loop;
                end if;
            end process;

            -- Instantiate a single lookup table for this bank.
            u_table : dpram
                generic map(
                AWIDTH      => LUT_WIDTH,
                DWIDTH      => TABLE_SIZE)
                port map(
                wr_clk      => clk,
                wr_addr     => wr_addr,
                wr_en       => cfg_write,
                wr_val      => wr_mask,
                rd_clk      => clk,
                rd_addr     => rd_addr,
                rd_en       => rd_enable,
                rd_val      => camrd_masks(n));
        end generate;
    end block;
end generate;

-- Search result pipeline.
p_search : process(clk)
    variable prerd_type : search_type := TCAM_SEARCH_NONE;
    variable prerd_data : search_t := (others => '0');
    variable prerd_meta : meta_t := (others => '0');
    variable prerd_safe : cam_mask_t := (others => '0');
    variable camrd_data : search_t := (others => '0');
    variable camrd_meta : meta_t := (others => '0');
    variable camrd_safe : cam_mask_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Pipeline stage 2: AND-reduce the resulting LUTRAM masks.
        -- Each '1' bit in a mask represents a partial match.
        -- AND all the partials together to check for a complete match.
        reduce_data <= camrd_data;
        reduce_meta <= camrd_meta;
        reduce_mask <= and_reduce(camrd_masks, camrd_safe);
        if (reset_p = '1') then
            reduce_type <= TCAM_SEARCH_NONE;
        else
            reduce_type <= camrd_type;
        end if;

        -- Pipeline stage 1: Matched delay for LUTRAM lookup.
        -- (Make the type available one cycle early for scan logic, below.)
        camrd_type  <= prerd_type;
        camrd_data  := prerd_data;
        camrd_meta  := prerd_meta;
        camrd_safe  := prerd_safe;

        -- Pipeline stage 0: Matched delay for Sub-address selection.
        -- If duplicate-checking is enabled, search on the first idle cycle.
        if (reset_p = '1') then
            prerd_type := TCAM_SEARCH_NONE;     -- Global reset
        elsif (in_next = '1') then
            prerd_type := TCAM_SEARCH_USER;     -- Normal query
        elsif (cfg_valid = '1') then
            prerd_type := TCAM_SEARCH_CTRL;     -- Internal control
        elsif (scan_next = '1') then
            prerd_type := TCAM_SEARCH_SCAN;     -- Table readback
        else
            prerd_type := TCAM_SEARCH_NONE;     -- Idle
        end if;
        prerd_data  := in_data;         -- Store for later reference
        prerd_meta  := in_meta;         -- Store for later reference
        prerd_safe  := not camwr_mask;  -- Ignore columns being overwritten
    end if;
end process;

gen_tcam1 : if (TCAM_MODE = TCAM_MODE_MAXLEN) generate
    -- TCAM mode requires a "max-length prefix" (MLP) matching system.
    u_mlp : entity work.tcam_maxlen
        generic map(
        INPUT_WIDTH => INPUT_WIDTH,
        META_WIDTH  => META_WIDTH,
        TABLE_SIZE  => TABLE_SIZE)
        port map(
        in_data     => reduce_data,
        in_meta     => reduce_meta,
        in_mask     => reduce_mask,
        in_type     => reduce_type,
        out_data    => match_data,
        out_meta    => match_meta,
        out_index   => match_index,
        out_found   => match_found,
        out_type    => match_type,
        out_error   => match_error,
        cfg_clear   => cfg_clear,
        cfg_index   => cfg_index,
        cfg_plen    => cfg_plen,
        cfg_write   => cfg_exec,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_tcam0 : if (TCAM_MODE /= TCAM_MODE_MAXLEN) generate
    -- Without wildcards, CAM output stage is a one-hot decoder.
    p_decode : process(clk)
        constant ADDR_BITS : positive := log2_ceil(TABLE_SIZE);
    begin
        if rising_edge(clk) then
            match_data  <= reduce_data;
            match_meta  <= reduce_meta;
            match_index <= to_integer(one_hot_decode(reduce_mask, ADDR_BITS));
            match_found <= or_reduce(reduce_mask);
            match_error <= one_hot_error(reduce_mask);
            if (reset_p = '1') then
                match_type <= TCAM_SEARCH_NONE;
            else
                match_type <= reduce_type;
            end if;
        end if;
    end process;
end generate;

-- Cache replacement policy.
gen_cache_plru : if (REPL_MODE = TCAM_REPL_PLRU) generate
    local : block
        signal cache_index  : table_idx_t;
        signal cache_read   : std_logic;
        signal repl_hold    : std_logic;
    begin
        -- Combined cache-access stream for updating the state.
        cache_index <= cfg_index when (cfg_exec = '1') else match_index;
        cache_read  <= bool2bit(match_type = TCAM_SEARCH_USER);

        -- Freeze the eviction index during a write transaction.
        repl_hold   <= cfg_valid and not cfg_ready_i;

        -- Psuedo-LRU cache controller block.
        u_lru : entity work.tcam_cache_plru
            generic map(TABLE_SIZE => TABLE_SIZE)
            port map(
            in_index    => cache_index,
            in_read     => cache_read,
            in_write    => cfg_exec,
            out_index   => repl_index,
            out_hold    => repl_hold,
            clk         => clk,
            reset_p     => cfg_reset);
    end block;
end generate;

gen_cache_nru2 : if (REPL_MODE = TCAM_REPL_NRU2) generate
    local : block
        signal cache_index  : table_idx_t;
        signal cache_read   : std_logic;
        signal repl_hold    : std_logic;
    begin
        -- Combined cache-access stream for updating the state.
        cache_index <= cfg_index when (cfg_exec = '1') else match_index;
        cache_read  <= bool2bit(match_type = TCAM_SEARCH_USER);

        -- Freeze the eviction index during a write transaction.
        repl_hold   <= cfg_valid and not cfg_ready_i;

        -- Not-recently-used cache controller block.
        u_lru : entity work.tcam_cache_nru2
            generic map(TABLE_SIZE => TABLE_SIZE)
            port map(
            in_index    => cache_index,
            in_read     => cache_read,
            in_write    => cfg_exec,
            out_index   => repl_index,
            out_hold    => repl_hold,
            clk         => clk,
            reset_p     => cfg_reset);
    end block;
end generate;

gen_cache_simple : if (REPL_MODE = TCAM_REPL_NONE or REPL_MODE = TCAM_REPL_WRAP) generate
    -- In all other modes, the suggested index is just a counter.
    p_count : process(clk)
    begin
        if rising_edge(clk) then
            -- Counter with wraparound
            if (cfg_reset = '1') then
                repl_index <= 0;
            elsif (cfg_exec = '1') then
                repl_index <= (repl_index + 1) mod TABLE_SIZE;
            end if;
        end if;
    end process;
end generate;

-- CAM-reset and CAM-update state machine.
gen_ctrl_simple : if SIMPLE_WRITE generate
    -- Simplified controller for simple-write mode:
    --  * On startup, clear entire table.
    --  * After startup, address lines are connected directly to cfg_data.
    --  * TCAM_MODE_SIMPLE: Wait for readback, then execute write.
    --  * TCAM_MODE_CONFIRM: Wait for readback, then execute or discard.
    cfg_ready_i <= bool2bit(ctrl_state = CTRL_WRITE);
    cfg_exec    <= (cfg_valid and cfg_ready_i)
               and bool2bit(TCAM_MODE = TCAM_MODE_SIMPLE or match_found = '0');
    cfg_write   <= bool2bit(ctrl_state = CTRL_WRITE or ctrl_state = CTRL_INIT);

    -- Clear on startup, then all subsequent writes set a single column.
    camwr_tval  <= (others => bool2bit(ctrl_state /= CTRL_INIT));

    -- Control state machine:
    p_ctrl : process(clk)
    begin
        if rising_edge(clk) then
            -- Rules sanity-check:
            if (cfg_exec = '1' and cfg_index /= repl_index) then
                ctrl_error <= '1';
                report "Illegal write-index." severity warning;
            elsif (cfg_exec = '1' and cfg_plen /= INPUT_WIDTH) then
                ctrl_error <= '1';
                report "Illegal prefix-length." severity warning;
            else
                ctrl_error <= '0';
            end if;

            -- Sweep through addresses during startup.
            -- After initialization, this signal is unused.
            if (cfg_reset = '1') then
                camwr_addr <= (others => '0');
            elsif (ctrl_state = CTRL_INIT) then
                camwr_addr <= camwr_addr + 1;
            end if;

            -- Update controller state.
            if (cfg_reset = '1') then
                -- Begin clearing lookup tables.
                ctrl_state <= CTRL_INIT;
                camwr_mask <= (others => '1');
            elsif (ctrl_state = CTRL_INIT) then
                -- Stop sweep after the last address.
                if (camwr_addr = SUBADDR_FINAL) then
                    ctrl_state <= CTRL_IDLE;
                    camwr_mask <= (others => '0');
                end if;
            elsif (ctrl_state = CTRL_IDLE and cfg_valid = '1') then
                -- User has requested an update to the table.
                -- (Depending on configuration, readback may be required.)
                if (LUT_WRBIT and TCAM_MODE = TCAM_MODE_SIMPLE) then
                    ctrl_state <= CTRL_WRITE;   -- Start immediately.
                    camwr_mask <= create_mask(repl_index);
                elsif (LUT_WRBIT and in_next = '0') then
                    ctrl_state <= CTRL_READ;    -- Wait for an idle cycle.
                elsif (in_next = '0') then
                    ctrl_state <= CTRL_READ;    -- Wait for an idle cycle.
                    camwr_mask <= create_mask(repl_index);
                end if;
            elsif (ctrl_state = CTRL_READ) then
                -- Continue the read/modify/write cycle...
                ctrl_state <= CTRL_MODIFY;
            elsif (ctrl_state = CTRL_MODIFY) then
                -- Continue the read/modify/write cycle...
                ctrl_state <= CTRL_WRITE;
                camwr_mask <= create_mask(repl_index);
            elsif (ctrl_state = CTRL_WRITE) then
                -- Complete the write or read/modify/write cycle.
                if (cfg_exec = '1' and repl_index = TABLE_SIZE-1) then
                    ctrl_state <= CTRL_FULL;    -- Last write, table is full.
                    camwr_mask <= (others => '0');
                else
                    ctrl_state <= CTRL_IDLE;    -- Otherwise, ready for another.
                    camwr_mask <= (others => '0');
                end if;
            end if;
        end if;
    end process;
end generate;

gen_ctrl_normal : if not SIMPLE_WRITE generate
    -- The "normal" controller scans through all addresses on each write:
    --  * Clear entire table on startup.
    --  * If TCAM_MODE_CONFIRM, wait for confirmation before starting.
    --  * 1st scan clears all bits in the selected column.
    --  * 2nd scan sets selected bits based on the address and prefix.

    -- Accept write commands when they are completed or rejected.
    cfg_exec    <= bool2bit(ctrl_state = CTRL_WRITE and camwr_addr = SUBADDR_FINAL);
    cfg_ready_i <= (cfg_exec) or (match_reject and bool2bit(ctrl_state = CTRL_CHECK));
    cfg_write   <= bool2bit(ctrl_state = CTRL_WRITE or ctrl_state = CTRL_INIT);

    -- Combinational logic for individual matching flags.
    camwr_tval  <= (others => '0') when (ctrl_state = CTRL_INIT)
              else create_tvec(cfg_data, ctrl_pmask, ctrl_erase, camwr_addr);

    -- Control state machine:
    p_ctrl : process(clk)
    begin
        if rising_edge(clk) then
            -- Convert prefix-length to a bit-mask, when applicable.
            if (cfg_valid = '1' and cfg_plen = 0) then
                ctrl_error <= '0';  -- Erase this table entry.
                ctrl_erase <= '1';
                ctrl_pmask <= (others => '1');
            elsif (cfg_valid = '1' and TCAM_MODE = TCAM_MODE_MAXLEN) then
                ctrl_error <= '0';  -- Normal entry with wildcards.
                ctrl_erase <= '0';
                for n in ctrl_pmask'range loop
                    ctrl_pmask(n) <= bool2bit(n >= INPUT_WIDTH - cfg_plen);
                end loop;
            elsif (cfg_valid = '1' and cfg_plen /= INPUT_WIDTH) then
                ctrl_error <= '1';  -- Wildcards not supported.
                ctrl_erase <= '0';
                report "Illegal prefix-length." severity warning;
            else
                ctrl_error <= '0';  -- Idle or normal entry.
                ctrl_erase <= '0';
            end if;

            -- Address scanning control.
            if (cfg_reset = '1' or ctrl_state = CTRL_IDLE) then
                camwr_addr <= (others => '0');
            elsif (ctrl_state = CTRL_INIT or ctrl_state = CTRL_WRITE) then
                camwr_addr <= camwr_addr + 1;
            end if;

            -- Update control state.
            if (cfg_reset = '1') then
                -- Global reset.
                ctrl_state  <= CTRL_INIT;           -- Start clearing tables.
                camwr_mask  <= (others => '1');     -- (Write all columns)
            elsif (ctrl_state = CTRL_INIT) then
                -- Continue clearing tables until we reach the last address.
                if (camwr_addr = SUBADDR_FINAL) then
                    ctrl_state  <= CTRL_IDLE;       -- Ready for commands
                    camwr_mask  <= (others => '0'); -- (Stop writing)
                end if;
            elsif (ctrl_state = CTRL_IDLE and cfg_valid = '1') then
                -- Write command received.  Do we need a readback step?
                if (TCAM_MODE = TCAM_MODE_CONFIRM and in_next = '1') then
                    camwr_mask <= (others => '0');  -- Waiting for an idle moment...
                elsif (TCAM_MODE = TCAM_MODE_CONFIRM) then
                    ctrl_state <= CTRL_CHECK;       -- Query start, wait for result.
                    camwr_mask <= (others => '0');  -- (No writes yet)
                elsif (LUT_WRBIT) then
                    ctrl_state <= CTRL_WRITE;       -- Start first write immediately.
                    camwr_mask <= create_mask(cfg_index);
                else
                    ctrl_state <= CTRL_WAIT;        -- Start first read/modify/write.
                    camwr_mask <= create_mask(cfg_index);
                end if;
            elsif (ctrl_state = CTRL_CHECK and match_type = TCAM_SEARCH_CTRL) then
                -- Search completed. Should we continue or abort?
                if (match_found = '1') then
                    ctrl_state <= CTRL_IDLE;        -- Abort and return to idle.
                elsif (LUT_WRBIT) then
                    ctrl_state <= CTRL_WRITE;       -- Start first write immediately.
                    camwr_mask <= create_mask(cfg_index);
                else
                    ctrl_state <= CTRL_WAIT;        -- Start first read/modify/write.
                    camwr_mask <= create_mask(cfg_index);
                end if;
            elsif (ctrl_state = CTRL_WAIT and in_next = '0') then
                -- Wait for an idle cycle to start the read/modify/write cycle.
                ctrl_state <= CTRL_READ;
            elsif (ctrl_state = CTRL_READ) then
                -- Continue the read/modify/write cycle...
                ctrl_state <= CTRL_MODIFY;
            elsif (ctrl_state = CTRL_MODIFY) then
                -- Continue the read/modify/write cycle...
                ctrl_state <= CTRL_WRITE;
            elsif (ctrl_state = CTRL_WRITE) then
                -- Complete the write or read/modify/write cycle.
                if (camwr_addr = SUBADDR_FINAL) then
                    ctrl_state <= CTRL_IDLE;        -- Done, revert to idle.
                    camwr_mask <= (others => '0');  -- (Stop writing)
                elsif (LUT_WRBIT) then
                    ctrl_state <= CTRL_WRITE;       -- Start next write immediately.
                else
                    ctrl_state <= CTRL_WAIT;        -- Start next read/modify/write.
                end if;
            end if;
        end if;
    end process;
end generate;

-- Scan logic for table readback.
p_scan : process(clk)
    constant ADDR_MIN : sub_addr_t := (others => '0');
    constant ADDR_MAX : sub_addr_t := (others => '1');
    variable addr_d1  : sub_addr_t := (others => '0');
    variable addr_d2  : sub_addr_t := (others => '0');
    variable addr_d3  : sub_addr_t := (others => '0');
    variable mask_d3  : sub_mask_t := (others => '0');
    variable read_d3  : std_logic := '0';
    variable done_d3  : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Pipeline stage 4: Accumulate scan results.
        if (read_d3 = '1' and addr_d3 = ADDR_MIN) then
            -- Start of a new scan.
            scan_min    <= (others => '0');
            scan_max    <= (others => '0');
            scan_match  <= mask_d3;
        elsif (read_d3 = '1') then
            -- Set the "match" flag if any sub-address query matches this column.
            scan_match <= scan_match or mask_d3;
            -- Update running min and max for each matching LUTRAM bank.
            for b in mask_d3'range loop
                if (scan_match(b) = '0') then   -- Min = First match in scan
                    scan_min(LUT_WIDTH*(b+1)-1 downto LUT_WIDTH*b) <= addr_d3;
                end if;
                if (mask_d3(b) = '1') then      -- Max = Last match in scan
                    scan_max(LUT_WIDTH*(b+1)-1 downto LUT_WIDTH*b) <= addr_d3;
                end if;
            end loop;
        end if;
        scan_done <= done_d3;

        -- Pipeline stage 3: Extract the table column of interest.
        -- Assert the DONE strobe just as we read the last sub-address.
        for b in mask_d3'range loop
            mask_d3(b) := camrd_masks(b)(scan_index);
        end loop;

        if (camrd_type = TCAM_SEARCH_SCAN) then
            read_d3 := '1';
            done_d3 := bool2bit(addr_d2 = ADDR_MAX) and not scan_retry;
        else
            read_d3 := '0';
            done_d3 := '0';
        end if;

        addr_d3 := addr_d2;

        -- Pipeline stage 2: Matched delay + Restart if LUTRAM contents change.
        scan_retry <= camwr_mask(scan_index) or cfg_reset;
        addr_d2 := addr_d1;

        -- Pipeline stage 1: Matched delay for the LUTRAM query.
        addr_d1 := scan_addr;

        -- Pipeline stage 0: Scan over all sub-addresses.
        if (scan_done = '1' or scan_retry = '1' or scan_valid = '0') then
            -- Idle state or start of a new scan. (Including auto-retry.)
            scan_addr <= (others => '0');
            scan_wait <= '0';
        elsif (in_next = '1' or cfg_valid = '1') then
            null;   -- Waiting for our turn to issue a query...
        elsif (scan_wait = '0') then
            -- Once we start a scan, increment over the whole range and then stop.
            scan_addr <= scan_addr + 1;
            scan_wait <= bool2bit(scan_addr = ADDR_MAX);
        end if;
    end if;
end process;

-- Simulation-only error checking:
-- Confirm that none of the cfg_** signals change after VALID is asserted.
-- (We rely on upstream blocks to uphold this portion of the AXI standard.)
p_simcheck : process(clk)
    variable dly_index  : integer range 0 to TABLE_SIZE-1 := 0;
    variable dly_data   : std_logic_vector(INPUT_WIDTH-1 downto 0) := (others => '0');
    variable dly_plen   : integer range 0 to INPUT_WIDTH := INPUT_WIDTH;
    variable dly_check  : std_logic := '0';
begin
    if rising_edge(clk) then
        if (dly_check = '1' and match_reject = '0') then
            -- Change during CONFIRM process is necessary to support
            -- synchronized table updates (e.g., for "mac_lookup.vhd").
            assert (dly_index = cfg_index)
                report "Unexpected change in cfg_index" severity error;
        end if;
        if (dly_check = '1') then
            assert (dly_data = cfg_data)
                report "Unexpected change in cfg_data" severity error;
            assert (dly_plen = cfg_plen)
                report "Unexpected change in cfg_plen" severity error;
            assert (cfg_valid = '1')
                report "Unexpected change in cfg_valid" severity error;
        end if;

        dly_index   := cfg_index;
        dly_data    := cfg_data;
        dly_plen    := cfg_plen;
        dly_check   := cfg_valid and not (cfg_ready_i or reset_p);
    end if;
end process;

end tcam_core;
