--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation
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
-- Virtual-LAN rate limiting
--
-- This block applies rate-controls to each Virtual-LAN.  Traffic for each
-- VLAN identifier (VID) is tracked using the "token bucket" algorithm:
--  https://en.wikipedia.org/wiki/Token_bucket
--
-- Each "bucket" of tokens counts the number of available credits for
-- a specific VID.  On reset, all buckets default to the "unlimited" mode.
-- If rate-control is enabled, then tokens begin accumulating at a fixed rate
-- (i.e., N tokens per millisecond) up to a designated maximum.  The cost of
-- sending a given packet is proportional to its length; if there are not
-- enough tokens, the packet is instead dropped or reduced in priority.
--
-- Mode, token counter, rate, and maximum values for each VID are stored in
-- BRAM as fixed-width variables.  At the default width of 16 bits for each
-- counter, total BRAM consumption is 26 kiB.
--
-- The token counter value for a given bucket is decremented for each incoming
-- packet, and incremented on a regular schedule.  To allow the use of ordinary
-- dual-port memory, the increment phase is applied during idle periods between
-- packets.
--
-- To maximize useful dynamic range, each VID sets the scale of its tokens.
-- Scale can be set to one token for every 1 or 256 bytes.  At the default
-- limit of 16 bits per counter, this allows fine throughput adjustment:
--  * 1x scale --> Up to 524 Mbps (resolution 8 kbps)
--  * 256x scale --> Up to 134 Gbps (resolution 2 Mbps)
--
-- The increment-when-idle method requires 4,096 idle cycles every millisecond.
-- The only corner case that violates this assumption is a switch pipeline that
-- handles a minimum-length packet every clock cycle with duty cycle >97% for
-- extended periods.  In this extreme case, the rate-limiter may false-alarm
-- until the overload condition is relieved.
--
-- Rate controls are configured through a single ConfigBus register:
--  * REGADDR: Command shift-register (writes required, reads optional)
--      Configuration of each VID requires several consecutive writes:
--      1st write: Set accumulator rate (tokens per millisecond)
--      2nd write: Set accumulator maximum
--      3rd write: Load new settings
--          Bits 31-28: Set mode
--              0x8 = Unlimited: Token-bucket counters ignored (default)
--              0x9 = Demote: Excess packets are low-priority
--              0xA = Strict: Excess packets are dropped
--              0xB = Auto: Demote or Strict mode based on DEI flag
--              All other values reserved
--          Bits 27-24: Token scaling factor
--              0x0 = 1x scaling (1 token = 1 byte)
--              0x8 = 256x scaling (1 token = 256 bytes)
--              All other values reserved
--          Bits 23-12: Reserved (write zeros)
--          Bits 11-00: VID to be configured
--      Reading from this register reports build-time parameters:
--          Bits 31-08: Reserved
--          Bits 07-00: ACCUM_WIDTH (Width of each accumulator)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.dpram;
use     work.eth_frame_common.all;

entity mac_vlan_rate is
    generic (
    DEV_ADDR    : integer;              -- ConfigBus device address
    REG_ADDR    : integer;              -- ConfigBus register address
    IO_BYTES    : positive;             -- Width of main data ports
    PORT_COUNT  : positive;             -- Number of Ethernet ports
    CORE_CLK_HZ : positive;             -- Core clock frequency (Hz)
    ACCUM_WIDTH : positive := 16;       -- Width of all internal counters
    SIM_STRICT  : boolean := false);    -- Enable strict simulation mode?
    port (
    -- Main input stream (metadata only)
    in_vtag     : in  vlan_hdr_t;
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic;

    -- Port-mask and priority results
    out_pmask   : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_himask  : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Diagnostic indicators, not used in normal operation.
    debug_scan  : out std_logic;

    -- Configuration interface (write required, read optional)
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end mac_vlan_rate;

architecture mac_vlan_rate of mac_vlan_rate is

-- All internal counters use the same fixed width.
constant PARAM_WIDTH : positive := 2*ACCUM_WIDTH + 3;
subtype accum_u is unsigned(ACCUM_WIDTH-1 downto 0);
subtype accum_v is std_logic_vector(ACCUM_WIDTH-1 downto 0);
subtype param_v is std_logic_vector(PARAM_WIDTH-1 downto 0);

-- Rate-control modes.
subtype mode_t is std_logic_vector(1 downto 0);
constant MODE_UNLIM     : mode_t := "00";
constant MODE_DEMOTE    : mode_t := "01";
constant MODE_STRICT    : mode_t := "10";
constant MODE_AUTO      : mode_t := "11";
subtype scale_t is std_logic_vector(0 downto 0);

-- Query types for the read-modify-write pipeline.
type query_t is (
    QUERY_NONE,     -- Idle
    QUERY_INCR,     -- Add tokens to bucket
    QUERY_DECR);    -- Remove tokens from bucket

-- Once per millisecond, distribute new tokens to all VIDs.
constant SCAN_TIMER_MAX : natural := div_ceil(CORE_CLK_HZ, 1000) - 1;
subtype scan_timer_t is integer range 0 to SCAN_TIMER_MAX;

-- Query control logic.
signal query_type   : query_t := QUERY_NONE;
signal query_vtag   : vlan_hdr_t := VHDR_NONE;
signal query_len    : accum_u := (others => '0');
signal query_sof    : std_logic := '1';
signal scan_req     : std_logic := '0';
signal scan_next    : std_logic;
signal scan_addr    : vlan_vid_t := (others => '0');
signal scan_timer   : scan_timer_t := SCAN_TIMER_MAX;

-- Dual-port BRAM for parameter lookup.
signal query0_addr  : vlan_vid_t;
signal query1_addr  : vlan_vid_t;
signal query0_en    : std_logic;
signal query1_en    : std_logic;

signal read_type    : query_t := QUERY_NONE;
signal read_vtag    : vlan_hdr_t := VHDR_NONE;
signal read_params  : param_v;
signal read_cmax    : accum_u;
signal read_len     : accum_u := (others => '0');
signal read_incr    : accum_u;
signal read_count   : accum_v;
signal read_mode    : mode_t;
signal read_scale   : scale_t;

-- Read-modify-write pipeline.
signal pre_type     : query_t := QUERY_NONE;
signal pre_vtag     : vlan_hdr_t := VHDR_NONE;
signal pre_addr     : vlan_vid_t;
signal pre_decr     : accum_u := (others => '0');
signal pre_cmax     : accum_u := (others => '0');
signal pre_cmin     : accum_u := (others => '0');
signal pre_mode     : mode_t := (others => '0');
signal pre_index    : integer range 0 to 2 := 0;
signal pre_count    : accum_u;
signal mod_mode     : mode_t := (others => '0');
signal mod_type     : query_t := QUERY_NONE;
signal mod_vtag     : vlan_hdr_t := VHDR_NONE;
signal mod_addr     : vlan_vid_t;
signal mod_dei      : vlan_dei_t;
signal mod_count    : accum_u := (others => '0');
signal mod_write    : std_logic := '0';

-- Policy decisions and output FIFO.
signal fin_count    : accum_u := (others => '0');
signal fin_keep     : std_logic := '0';
signal fin_himask   : std_logic := '0';
signal fin_write    : std_logic := '0';
signal out_keep_i   : std_logic;

-- ConfigBus interface.
signal cfg_sreg     : std_logic_vector(95 downto 0) := (others => '0');
signal cfg_write    : std_logic := '0';
signal cfg_paddr    : vlan_vid_t;
signal cfg_param    : param_v;
signal cfg_rdval    : cfgbus_word;

begin

-- Make internal flags visible for unit-testing purposes.
debug_scan <= scan_req;

-- While scan_req = '1', insert a QUERY_INCR event during any cycle
-- that doesn't contain an end-of-frame event.
scan_next <= scan_req and bool2bit(in_write = '0' or in_nlast = 0);

-- Query control logic.
p_query : process(clk)
    constant VID_MAX : vlan_vid_t := (others => '1');

    function incr_bytes(nlast : natural) return accum_u is
    begin
        if (nlast > 0) then
            return to_unsigned(nlast, ACCUM_WIDTH);     -- End of frame
        else
            return to_unsigned(IO_BYTES, ACCUM_WIDTH);  -- Middle of frame
        end if;
    end function;
begin
    if rising_edge(clk) then
        -- Determine the query type for each clock cycle:
        if (reset_p = '1') then
            query_type <= QUERY_NONE;   -- System reset
            query_vtag <= VHDR_NONE;
        elsif (in_write = '1' and in_nlast > 0) then
            query_type <= QUERY_DECR;   -- Incoming packet
            query_vtag <= in_vtag;
        elsif (scan_next = '1') then
            query_type <= QUERY_INCR;   -- Add new tokens
            query_vtag <= vlan_get_hdr(PCP_NONE, DEI_NONE, scan_addr);
        else
            query_type <= QUERY_NONE;   -- Idle
            query_vtag <= VHDR_NONE;
        end if;

        -- Calculate the length of each input frame.
        if (reset_p = '1') then         -- System reset
            query_len <= (others => '0');
            query_sof <= '1';
        elsif (in_write = '0') then     -- No change
            null;
        elsif (query_sof = '1') then    -- Start of new frame
            query_len <= incr_bytes(in_nlast);
            query_sof <= bool2bit(in_nlast > 0);
        else                            -- Continue counting
            query_len <= query_len + incr_bytes(in_nlast);
            query_sof <= bool2bit(in_nlast > 0);
        end if;

        -- Scan control for the token-distribution process.
        -- (Increment the address whenever there's a QUERY_INCR.)
        if (reset_p = '1' or scan_req = '0') then
            scan_addr <= (others => '0');
        elsif (scan_next = '1') then
            scan_addr <= scan_addr + 1;
        end if;

        -- Request token-distribution at regular intervals.
        if (reset_p = '1') then
            scan_req    <= '0';         -- System reset
            scan_timer  <= SCAN_TIMER_MAX;
        elsif (scan_timer = 0) then
            scan_req    <= '1';         -- Countdown reached zero
            scan_timer  <= SCAN_TIMER_MAX;
        elsif (scan_next = '1' and scan_addr = VID_MAX) then
            scan_req    <= '0';         -- Scan completed
            scan_timer  <= scan_timer - 1;
        else
            scan_req    <= scan_req;    -- Continue countdown
            scan_timer  <= scan_timer - 1;
        end if;
    end if;
end process;

-- Extract the VID/address for various pipeline stages.
query0_en   <= bool2bit(query_type /= QUERY_NONE);
query1_en   <= bool2bit(read_type /= QUERY_NONE);
query0_addr <= vlan_get_vid(query_vtag);
query1_addr <= vlan_get_vid(read_vtag);
pre_addr    <= vlan_get_vid(pre_vtag);
mod_addr    <= vlan_get_vid(mod_vtag);
mod_dei     <= vlan_get_dei(mod_vtag);

-- Dual-port BRAM for parameter lookup:
--  * Parameter BRAM operates in core and ConfigBus clock domains.
--  * Counter BRAM operates entirely in the core clock domain.
--  * Reads are staggerred to allow precompute of fixed parameters.
u_bram_param : dpram
    generic map(
    AWIDTH  => VLAN_VID_WIDTH,
    DWIDTH  => PARAM_WIDTH,
    SIMTEST => SIM_STRICT)
    port map(
    wr_clk  => cfg_cmd.clk,
    wr_addr => cfg_paddr,
    wr_en   => cfg_write,
    wr_val  => cfg_param,
    rd_clk  => clk,
    rd_addr => query0_addr,
    rd_en   => query0_en,
    rd_val  => read_params);

u_bram_count : dpram
    generic map(
    AWIDTH  => VLAN_VID_WIDTH,
    DWIDTH  => ACCUM_WIDTH,
    SIMTEST => SIM_STRICT)
    port map(
    wr_clk  => clk,
    wr_addr => mod_addr,
    wr_en   => mod_write,
    wr_val  => std_logic_vector(mod_count),
    rd_clk  => clk,
    rd_addr => query1_addr,
    rd_en   => query1_en,
    rd_val  => read_count);

-- Convert raw std_logic_vector to individual fields.
read_mode   <= read_params(2*ACCUM_WIDTH+2 downto 2*ACCUM_WIDTH+1);
read_scale  <= read_params(2*ACCUM_WIDTH downto 2*ACCUM_WIDTH);
read_cmax   <= unsigned(read_params(2*ACCUM_WIDTH-1 downto ACCUM_WIDTH));
read_incr   <= unsigned(read_params(ACCUM_WIDTH-1 downto 0));

-- Pipeline bypass: Overlapping updates to the same address need to bypass
-- the normal read-modify-write cycle, to avoid stale or undefined data.
pre_count <= unsigned(read_count) when pre_index = 0
        else mod_count when pre_index = 1
        else fin_count when pre_index = 2
        else (others => 'X');

-- Read-modify-write pipeline.
p_pipeline : process(clk)
    -- Cost(tokens) = PacketLen(bytes) / 2^scale, rounded up.
    function len2cost(len: unsigned; scale: natural) return accum_u is
    begin
        return shift_right(len - 1, scale) + 1;
    end function;

    variable pre_write : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Pipeline stage 3: Policy decision (allow / demote / drop)
        -- Note: For packet queries (mode = QUERY_DECR), the "mod_write"
        -- signal indicates that there were enough tokens in the bucket.
        fin_count   <= mod_count;
        fin_write   <= bool2bit(mod_type = QUERY_DECR);
        if (mod_mode = MODE_UNLIM) then
            -- Unlimited mode completely ignores tokens.
            fin_keep    <= '1';
            fin_himask  <= '1';
        elsif ((mod_mode = MODE_STRICT) or (mod_mode = MODE_AUTO and mod_dei = '1')) then
            -- Strict drops the packet if out of tokens.
            -- Auto + DEI is the same as strict mode.
            fin_keep    <= mod_write;
            fin_himask  <= mod_write;
        else
            -- Demote reduces priority if out of tokens.
            -- Auto - DEI is the same as demote mode.
            fin_keep    <= '1';
            fin_himask  <= mod_write;
        end if;

        -- Pipeline stage 2: Increment or decrement within limits.
        mod_mode <= pre_mode;
        mod_type <= pre_type;
        mod_vtag <= pre_vtag;
        if (pre_type = QUERY_INCR and pre_count >= pre_cmin) then
            mod_count <= pre_cmax;
            pre_write := '1';   -- Increment to max
        elsif (pre_type = QUERY_INCR) then
            mod_count <= pre_count - pre_decr;
            pre_write := '1';   -- Normal increment
        elsif (pre_type = QUERY_DECR and pre_count >= pre_cmin) then
            mod_count <= pre_count - pre_decr;
            pre_write := '1';   -- Normal decrement
        else
            mod_count <= (others => 'X');
            pre_write := '0';   -- No change
        end if;
        mod_write <= pre_write;

        -- Pipeline stage 1: Precalculate various control parameters,
        -- including selection for the pipeline bypass MUX (see above).
        pre_type <= read_type;
        pre_vtag <= read_vtag;
        pre_mode <= read_mode;
        pre_cmax <= read_cmax;

        if (read_type = QUERY_INCR) then
            pre_decr <= not read_incr + 1;
            pre_cmin <= read_cmax - read_incr;
        elsif (read_type = QUERY_DECR and read_scale = "1") then
            pre_decr <= len2cost(read_len, 8);
            pre_cmin <= len2cost(read_len, 8);
        elsif (read_type = QUERY_DECR) then
            pre_decr <= len2cost(read_len, 0);
            pre_cmin <= len2cost(read_len, 0);
        else
            pre_decr <= (others => 'X');
            pre_cmin <= (others => 'X');
        end if;

        if (query1_addr = pre_addr and pre_write = '1') then
            pre_index <= 1; -- Shortcut from MOD stage
        elsif (query1_addr = mod_addr and mod_write = '1') then
            pre_index <= 2; -- Shortcut from FIN stage
        else
            pre_index <= 0; -- Normal operation
        end if;

        -- Pipeline stage 0: Matched delay for the first query.
        read_type   <= query_type;
        read_vtag   <= query_vtag;
        read_len    <= query_len;
    end if;
end process;

-- Small FIFO stores query results for each packet.
u_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 1)
    port map(
    in_data(0)  => fin_keep,
    in_last     => fin_himask,
    in_write    => fin_write,
    out_data(0) => out_keep_i,
    out_last    => out_himask,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

out_pmask <= (others => out_keep_i);

-- ConfigBus interface.
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Update the shift register. Only the final write has MSB = '1'.
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_ADDR)) then
            cfg_write   <= cfg_cmd.wdata(31);
            cfg_sreg    <= cfg_sreg(63 downto 0) & cfg_cmd.wdata;
        else
            cfg_write   <= '0';
        end if;
    end if;
end process;

cfg_paddr <= unsigned(cfg_sreg(11 downto 0));       -- VID      (3rd write)
cfg_param <= cfg_sreg(29 downto 28)                 -- Mode     (3rd write)
           & cfg_sreg(27 downto 27)                 -- Scale    (3rd write)
           & cfg_sreg(31+ACCUM_WIDTH downto 32)     -- Max      (2nd write)
           & cfg_sreg(63+ACCUM_WIDTH downto 64);    -- Incr     (1st write)
cfg_rdval <= i2s(0, 24) & i2s(ACCUM_WIDTH, 8);

u_cfg : cfgbus_readonly
    generic map(
    DEVADDR => DEV_ADDR,
    REGADDR => REG_ADDR)
    port map(
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_ack,
    reg_val => cfg_rdval);

end mac_vlan_rate;
