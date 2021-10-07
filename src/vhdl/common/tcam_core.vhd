--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- A separate management interface is used to add new search entries.
-- Writes follow AXI-style flow control.  Single-cycle writes are
-- possible only in simple configurations, most others require up
-- to 64 clock cycles to write (or overwrite) a table entry.
--
-- The user specifies the index where each new term should be written.
-- This block provies a recommended next-write index depending on the
-- specified replacement policy (see below).  In most cases this can
-- be a simple loopback, but advanced users may need to coordinate
-- multiple CAM/TCAM blocks or synchronize their own metadata tables.
--
-- The replacement policy is set at build-time (TCAM_REPL):
--  * None (TCAM_REPL_NONE)
--      * New entries must be written in ascending order.
--      * Once full, no new entries can be written.
--      + Non-wildcard writes can be executed in a single clock cycle.
--      + Lowest resource utilization.  Good choice for fixed-size tables.
--      - Eviction of stale entries is not possible.
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
--          * Each table entry stores an address and a prefix length.
--          * A "match" is any entry where the N leading bits match the search term.
--          * If there is more than one match, keep the one with largest N.
--      * Upstream controller must avoid writing identical entries.
--        (Never write the same address and prefix length twice.)
--
-- In any mode, unexpected duplicates will assert an error flag; upstream
-- error-handling must reset the table to restore a known-good state.
--

---------------------------------------------------------------------
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
end package;

---------------------------------------------------------------------
-- The main TCAM block

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.tcam_constants.all;

entity tcam_core is
    generic (
    INPUT_WIDTH : positive;         -- Width of the search term
    TABLE_SIZE  : positive;         -- Max stored MAC addresses
    REPL_MODE   : repl_policy;      -- Replacement mode (see above)
    TCAM_MODE   : write_policy;     -- Enable wildcard searches?
    META_WIDTH  : natural := 0);    -- Metadata width (optional)
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

    -- Management interface
    -- (Note: Prefix length "plen" is used only in TCAM_MODE_MAXLEN.)
    -- (Note: "Reject" strobe is only asserted in TCAM_MODE_CONFIRM.)
    cfg_suggest : out integer range 0 to TABLE_SIZE-1;
    cfg_index   : in  integer range 0 to TABLE_SIZE-1;
    cfg_data    : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    cfg_plen    : in  integer range 1 to INPUT_WIDTH := INPUT_WIDTH;
    cfg_valid   : in  std_logic;
    cfg_ready   : out std_logic;
    cfg_reject  : out std_logic;

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
constant LUT_WIDTH : positive := PREFER_DPRAM_AWIDTH;
constant LUT_COUNT : positive := (INPUT_WIDTH + LUT_WIDTH - 1) / LUT_WIDTH;

-- Define various convenience types.
subtype search_t is std_logic_vector(INPUT_WIDTH-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype table_idx_t is integer range 0 to TABLE_SIZE-1;
subtype sub_addr_t is unsigned(LUT_WIDTH-1 downto 0);
subtype sub_mask_t is std_logic_vector(LUT_COUNT-1 downto 0);
subtype cam_mask_t is std_logic_vector(TABLE_SIZE-1 downto 0);
type cam_mask_array is array(0 to LUT_COUNT-1) of cam_mask_t;
constant SUBADDR_FINAL : sub_addr_t := (others => '1');

-- Get the Nth address segment for a given LUTRAM.
function get_subaddr(addr:search_t ; n:natural) return sub_addr_t is
    constant EXT_WIDTH : positive := LUT_COUNT*LUT_WIDTH;
    variable ext : unsigned(EXT_WIDTH-1 downto 0) := resize(unsigned(addr), EXT_WIDTH);
    variable sub : sub_addr_t := ext((n+1)*LUT_WIDTH-1 downto n*LUT_WIDTH);
begin
    return sub;
end function;

-- Determine which matching units match the given wildcard address.
function create_tvec(addr, mask : search_t; wridx : sub_addr_t) return sub_mask_t is
    variable subaddr, submask : sub_addr_t;
    variable tvec : sub_mask_t;
begin
    -- For each matching unit...
    for n in tvec'range loop
        subaddr := get_subaddr(addr, n);
        submask := get_subaddr(mask, n);
        if (TCAM_MODE = TCAM_MODE_MAXLEN) then
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
signal camwr_addr   : sub_addr_t := (others => '0');
signal camwr_mask   : cam_mask_t := (others => '1');
signal camwr_tval   : sub_mask_t := (others => '0');

-- Search result pipeline.
signal reduce_data  : search_t := (others => '0');
signal reduce_meta  : meta_t := (others => '0');
signal reduce_mask  : cam_mask_t := (others => '0');
signal reduce_type  : std_logic := '0';
signal reduce_next  : std_logic := '0';
signal match_data   : search_t := (others => '0');
signal match_meta   : meta_t := (others => '0');
signal match_index  : table_idx_t := 0;
signal match_found  : std_logic := '0';
signal match_type   : std_logic := '0';
signal match_next   : std_logic := '0';
signal match_aux    : std_logic := '0';
signal match_error  : std_logic := '0';
signal match_reject : std_logic;

-- Cache replacement and CAM-update state machine.
type ctrl_state_t is (
    CTRL_INIT,      -- Clear tables on startup
    CTRL_IDLE,      -- Ready to receive new command
    CTRL_FULL,      -- No longer accepting new writes
    CTRL_CHECK,     -- Checking for duplicates before write
    CTRL_WRITE);    -- Clear previous and set new entry
signal ctrl_state   : ctrl_state_t := CTRL_INIT;
signal ctrl_pmask   : search_t := (others => '1');
signal ctrl_error   : std_logic := '0';
signal repl_index   : table_idx_t := 0;
signal cfg_start    : std_logic := '0';
signal cfg_exec     : std_logic := '0';
signal cfg_ready_i  : std_logic := '0';

begin

-- Drive top-level outputs.
out_data    <= match_data;
out_meta    <= match_meta;
out_index   <= match_index;
out_found   <= match_found;
out_next    <= match_next;
out_error   <= match_error or ctrl_error;
cfg_suggest <= match_index when (match_reject = '1') else repl_index;
cfg_ready   <= cfg_ready_i;
cfg_reject  <= match_reject;

-- The "reject" strobe only applies in TCAM_MODE_CONFIRM.
match_reject <= match_type and match_found
            and bool2bit(TCAM_MODE = TCAM_MODE_CONFIRM);

-- Instantiate each of the first-stage matching units.
-- This process should implement as an array of dual-port Nx1 LUTRAM.
gen_cam_word : for n in 0 to LUT_COUNT-1 generate
    local : block
        signal wr_addr, rd_addr : sub_addr_t;
    begin
        -- Each LUTRAM bank (64xN typ.) uses the same read and write addresses.
        rd_addr <= get_subaddr(cfg_data, n)
              when (in_next = '0' and TCAM_MODE = TCAM_MODE_CONFIRM)
              else get_subaddr(in_data, n);
        wr_addr <= get_subaddr(cfg_data, n)
              when (SIMPLE_WRITE and ctrl_state /= CTRL_INIT)
              else camwr_addr;

        -- Instantiate each LUTRAM bit in this bank...
        gen_cam_bit : for b in 0 to TABLE_SIZE-1 generate
            u_lutram : dpram
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
                rd_val(0)   => camrd_masks(n)(b));
        end generate;
    end block;
end generate;

-- Search result pipeline.
p_search : process(clk)
    variable camrd_data : search_t := (others => '0');
    variable camrd_meta : meta_t := (others => '0');
    variable camrd_type, camrd_next : std_logic := '0';
    variable safe_mask : cam_mask_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Pipeline stage 1: AND-reduce the resulting LUTRAM masks.
        -- Each '1' bit in a mask represents a partial match.
        -- AND all the partials together to check for a complete match.
        reduce_data <= camrd_data;
        reduce_meta <= camrd_meta;
        reduce_mask <= and_reduce(camrd_masks, safe_mask);
        reduce_type <= camrd_type and not reset_p;
        reduce_next <= camrd_next and not reset_p;

        -- Pipeline stage 0: Matched delay for LUTRAM lookup.
        -- If duplicate-checking is enabled, search on the first idle cycle.
        if (reset_p = '1') then
            camrd_type := '0';          -- Global reset
            camrd_next := '0';
        elsif (in_next = '1') then
            camrd_type := '0';          -- Normal query
            camrd_next := '1';
        elsif (TCAM_MODE = TCAM_MODE_CONFIRM and ctrl_state = CTRL_IDLE) then
            camrd_type := cfg_valid;    -- Check for duplicates
            camrd_next := '0';
        else
            camrd_type := '0';          -- Idle
            camrd_next := '0';
        end if;
        camrd_data := in_data;
        camrd_meta := in_meta;
        -- Disregard any columns that have writes in progress.
        safe_mask := not camwr_mask;
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
        in_rdy      => reduce_next,
        out_data    => match_data,
        out_meta    => match_meta,
        out_index   => match_index,
        out_found   => match_found,
        out_type    => match_type,
        out_rdy     => match_next,
        out_error   => match_error,
        cfg_index   => cfg_index,
        cfg_plen    => cfg_plen,
        cfg_write   => cfg_start,
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
            match_type  <= reduce_type and not reset_p;
            match_next  <= reduce_next and not reset_p;
            match_error <= one_hot_error(reduce_mask);
        end if;
    end process;
end generate;

-- Cache replacement policy.
gen_cache_plru : if (REPL_MODE = TCAM_REPL_PLRU) generate
    local : block
        signal cache_index  : table_idx_t;
        signal repl_hold    : std_logic;
    begin
        -- Combined cache-access stream for updating the state.
        cache_index <= cfg_index when (cfg_start = '1') else match_index;

        -- Freeze the eviction index during a write transaction.
        repl_hold   <= cfg_valid and not cfg_ready_i;

        -- Psuedo-LRU cache controller block.
        u_lru : entity work.tcam_cache_plru
            generic map(TABLE_SIZE => TABLE_SIZE)
            port map(
            in_index    => cache_index,
            in_read     => match_next,
            in_write    => cfg_start,
            out_index   => repl_index,
            out_hold    => repl_hold,
            clk         => clk,
            reset_p     => reset_p);
    end block;
end generate;

gen_cache_nru2 : if (REPL_MODE = TCAM_REPL_NRU2) generate
    local : block
        signal cache_index  : table_idx_t;
        signal repl_hold    : std_logic;
    begin
        -- Combined cache-access stream for updating the state.
        cache_index <= cfg_index when (cfg_start = '1') else match_index;

        -- Freeze the eviction index during a write transaction.
        repl_hold   <= cfg_valid and not cfg_ready_i;

        -- Not-recently-used cache controller block.
        u_lru : entity work.tcam_cache_nru2
            generic map(TABLE_SIZE => TABLE_SIZE)
            port map(
            in_index    => cache_index,
            in_read     => match_next,
            in_write    => cfg_start,
            out_index   => repl_index,
            out_hold    => repl_hold,
            clk         => clk,
            reset_p     => reset_p);
    end block;
end generate;

gen_cache_simple : if (REPL_MODE = TCAM_REPL_NONE or REPL_MODE = TCAM_REPL_WRAP) generate
    -- In all other modes, the suggested index is just a counter.
    p_count : process(clk)
    begin
        if rising_edge(clk) then
            -- Counter with wraparound
            if (reset_p = '1') then
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
    --  * TCAM_MODE_SIMPLE: Subsequent writes execute immediately.
    --  * TCAM_MODE_CONFIRM: Wait for the search, then execute or discard.
    cfg_ready_i <= match_type when (TCAM_MODE = TCAM_MODE_CONFIRM)
              else bool2bit(ctrl_state = CTRL_IDLE);
    cfg_exec    <= (cfg_valid and cfg_ready_i)
               and (bool2bit(TCAM_MODE = TCAM_MODE_SIMPLE) or not match_found);
    cfg_start   <= cfg_exec;    -- Start and end in same cycle

    -- Clear on startup, then all other writes are to set a bit.
    camwr_tval  <= (others => bool2bit(ctrl_state /= CTRL_INIT));

    -- Choose which bits to write:
    gen_mask : for n in camwr_mask'range generate
        camwr_mask(n) <= '1' when (ctrl_state = CTRL_INIT)
                    else cfg_exec and bool2bit(repl_index = n);
    end generate;

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
            if (reset_p = '1') then
                camwr_addr <= (others => '0');
            elsif (ctrl_state = CTRL_INIT) then
                camwr_addr <= camwr_addr + 1;
            end if;

            -- Update controller state.
            if (reset_p = '1') then
                -- Begin clearing lookup tables.
                ctrl_state <= CTRL_INIT;
            elsif (ctrl_state = CTRL_INIT) then
                -- Stop sweep after the last address.
                if (camwr_addr = SUBADDR_FINAL) then
                    ctrl_state <= CTRL_IDLE;
                end if;
            elsif (cfg_exec = '1' and repl_index = TABLE_SIZE-1) then
                -- Final write, table is full.
                ctrl_state <= CTRL_FULL;
            elsif (TCAM_MODE = TCAM_MODE_CONFIRM) then
                -- Transition to and from the search state.
                if (ctrl_state = CTRL_IDLE and cfg_valid = '1' and in_next = '0') then
                    ctrl_state <= CTRL_CHECK;
                elsif (ctrl_state = CTRL_CHECK and match_type = '1') then
                    ctrl_state <= CTRL_IDLE;
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

    -- Accept input commands at end of write sequence or no-match-found.
    cfg_exec    <= bool2bit(ctrl_state = CTRL_WRITE and camwr_addr = SUBADDR_FINAL);
    cfg_ready_i <= (cfg_exec) or (match_type and match_found);

    -- Combinational logic for individual matching flags.
    camwr_tval  <= (others => '0') when (ctrl_state = CTRL_INIT)
              else create_tvec(cfg_data, ctrl_pmask, camwr_addr);

    -- Control state machine:
    p_ctrl : process(clk)
        function make_mask(n : table_idx_t) return cam_mask_t is
            variable mask : cam_mask_t := (others => '0');
        begin
            mask(n) := '1'; -- Write to the selected column
            return mask;
        end function;
    begin
        if rising_edge(clk) then
            -- Convert prefix-length to a bit-mask, when applicable.
            if (cfg_valid = '1' and TCAM_MODE = TCAM_MODE_MAXLEN) then
                ctrl_error <= '0';
                for n in ctrl_pmask'range loop
                    ctrl_pmask(n) <= bool2bit(n > INPUT_WIDTH - cfg_plen);
                end loop;
            elsif (cfg_valid = '1' and cfg_plen /= INPUT_WIDTH) then
                ctrl_error <= '1';
                report "Illegal prefix-length." severity warning;
            else
                ctrl_error <= '0';
            end if;

            -- Address scanning control.
            if (reset_p = '1' or ctrl_state = CTRL_IDLE or ctrl_state = CTRL_CHECK) then
                camwr_addr <= (others => '0');
            else
                camwr_addr <= camwr_addr + 1;
            end if;

            -- Update control state.
            cfg_start <= '0';                       -- Set default
            if (reset_p = '1') then
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
                -- Write command received...
                if (TCAM_MODE = TCAM_MODE_CONFIRM) then
                    if (in_next = '0') then
                        ctrl_state <= CTRL_CHECK;   -- Query start, wait for result
                    end if;
                elsif (REPL_MODE /= TCAM_REPL_NONE) then
                    ctrl_state <= CTRL_WRITE;       -- Begin writing immediately
                    camwr_mask <= make_mask(cfg_index);
                    cfg_start  <= '1';
                end if;
            elsif (ctrl_state = CTRL_CHECK AND match_type = '1') then
                -- Search completed. Write or discard?
                if (match_found = '0') then
                    ctrl_state <= CTRL_WRITE;       -- Begin writing
                    camwr_mask <= make_mask(cfg_index);
                    cfg_start  <= '1';
                else
                    ctrl_state <= CTRL_IDLE;        -- Discard this write
                end if;
            elsif (ctrl_state = CTRL_WRITE) then
                -- Continue writing until end of frame.
                if (camwr_addr = SUBADDR_FINAL) then
                    ctrl_state <= CTRL_IDLE;        -- Ready for next command
                    camwr_mask <= (others => '0');  -- (Stop writing)
                end if;
            end if;
        end if;
    end process;
end generate;

-- Simulation-only error checking:
-- Confirm that none of the cfg_** signals change after VALID is asserted.
-- (We rely on upstream blocks to uphold this portion of the AXI standard.)
p_simcheck : process(clk)
    variable dly_index  : integer range 0 to TABLE_SIZE-1 := 0;
    variable dly_data   : std_logic_vector(INPUT_WIDTH-1 downto 0) := (others => '0');
    variable dly_plen   : integer range 1 to INPUT_WIDTH := INPUT_WIDTH;
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
