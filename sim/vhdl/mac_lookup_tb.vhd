--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Testbench for all MAC-address lookup variants.
--
-- This testbench generates test sequences for the MAC-lookup table,
-- including the following test cases:
--      * Delivery of a broadcast packet
--      * Delivery to a discovered address
--      * Broadcast of an undiscovered address
--      * Fill address table (no overflow)
--      * Stale-address removal (one)
--      * Address table overflow
--      * Stale-address removal (all)
--      * Randomized traffic
--
-- A single top-level module instantiates individual helper modules to
-- test each implementation variant.  The test will run indefinitely,
-- with adequate coverage taking a different time for each unit (watch
-- for the "timing statistics" report):
--   BINARY:    2.6 msec
--   BRUTE:     0.5 msec
--   LUTRAM:    0.4 msec
--   PARSHIFT:  0.7 msec
--   SIMPLE:    4.0 msec
--   STREAM:    2.0 msec
--

---------------------------------------------------------------------
----------------------------- HELPER MODULE -------------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity mac_lookup_tb_single is
    generic (
    IMPL_TYPE       : string;           -- SIMPLE, PARSHIFT, BINARY, BRUTE
    INPUT_WIDTH     : integer;          -- Width of main data port
    PORT_COUNT      : integer;          -- Number of Ethernet ports
    TABLE_SIZE      : integer;          -- Max stored MAC addresses
    VERBOSITY       : integer := 0;     -- Verbosity level (0/1/2)
    MAX_LATENCY     : integer := 999;   -- Maximum allowed latency
    SCRUB_TIMEOUT   : integer := 7);    -- Timeout for stale entries
    port (
    got_stats       : out std_logic;
    scrub_req       : in  std_logic;
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_tb_single;

architecture single of mac_lookup_tb_single is

-- Does the unit under test support scrubbing?
function scrub_enable_fn return std_logic is
begin
    if (IMPL_TYPE = "BINARY" or
        IMPL_TYPE = "SIMPLE") then
        return '1'; -- Scrubbing supported
    elsif (IMPL_TYPE = "BRUTE" or
        IMPL_TYPE = "LUTRAM" or
        IMPL_TYPE = "PARSHIFT" or
        IMPL_TYPE = "STREAM") then
        return '0'; -- Scrubbing not required.
    else
        report "Unrecognized implementation: " & IMPL_TYPE
            severity failure;
        return '0';
    end if;
end function;

constant SCRUB_ENABLE : std_logic := scrub_enable_fn;

-- Is the unit under test configured for uplink mode?
-- (All ports except zero have only a single MAC address.)
function uplink_mode_fn return std_logic is
begin
    if (IMPL_TYPE = "STREAM") then
        return '1';
    else
        return '0';
    end if;
end function;

constant UPLINK_MODE : std_logic := uplink_mode_fn;

-- How many packets to send during the initial startup phase?
function addr_count_fn return integer is
begin
    if (UPLINK_MODE = '1') then
        return PORT_COUNT;
    else
        return TABLE_SIZE;
    end if;
end function;

constant ADDR_COUNT : integer := addr_count_fn;

-- Define convenience types.
subtype port_idx_t is integer range 0 to PORT_COUNT-1;
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- Overall source state
signal in_rate      : real := 0.0;
signal pkt_count    : integer := 0;
signal pkt_mode     : integer := 0;
signal cfg_delay    : integer := 0;
signal scrub_count  : integer := 0;
signal scrub_rem    : integer := 0;
signal ignore_ovr   : std_logic := '0';

-- Queued reference data
signal in_pdst      : port_mask_t := (others => '0');
signal mac_final    : std_logic := '0';
signal ref_pdst     : port_mask_t;
signal ref_rd       : std_logic;
signal ref_wr       : std_logic;
signal ref_valid    : std_logic;

-- Elapsed-time measurement
signal in_time      : unsigned(15 downto 0) := (others => '0');
signal ref_time     : std_logic_vector(15 downto 0);

-- Unit under test
signal in_psrc      : port_idx_t := 0;
signal in_data      : std_logic_vector(INPUT_WIDTH-1 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal out_pdst     : port_mask_t;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal scrub_busy   : std_logic := '0';
signal scrub_remove : std_logic := '0';
signal cfg_prmask   : port_mask_t := (others => '0');
signal error_full   : std_logic := '0';     -- No room for new address
signal error_table  : std_logic := '0';     -- Table integrity check failed

-- Overall test state
signal got_packet   : std_logic := '0';
signal got_result   : std_logic := '0';

-- Diagnostic functions.
impure function pkt_str return string is
begin
    return integer'image(pkt_mode)
        & "." & integer'image(pkt_count)
        & " (" & IMPL_TYPE & ")";
end function;

begin

-- Count scrub requests and generate time counter.
p_scrub_count : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            scrub_count <= 0;
        elsif (scrub_req = '1') then
            assert (scrub_busy = '0')
                report "Scrub still in progress." severity warning;
            scrub_count <= scrub_count + 1;
        end if;

        if (reset_p = '1') then
            in_time <= (others => '0');
        else
            in_time <= in_time + 1; -- Wraparound OK
        end if;
    end if;
end process;

-- Traffic generation. Ethernet frames contain:
--   * Destination MAC address (6 bytes)
--   * Source MAC address (6 bytes)
--   * Ethertype / length tag (2 bytes)
--   * Payload data (46-1500 bytes)
--   * FCS (4 bytes)
-- For this test, only the two MAC-address fields are used; all others are
-- psuedorandom filler used to guarantee adequate inter-packet spacing.
-- For simplicity, every MAC is a single byte repeated six times.
p_src : process(clk)
    function mac2port(mac: unsigned) return integer is
        variable mac_int : integer := to_integer(mac);
    begin
        if (mac_int = 255) then
            -- Special case for broadcast packets.
            return 255;
        elsif (UPLINK_MODE = '0') then
            -- Normal mode, port index distributed evenly.
            return mac_int mod PORT_COUNT;
        elsif (mac_int < PORT_COUNT) then
            -- Uplink mode, one address per endpoint.
            return mac_int;
        else
            -- Uplink mode, part of extended network.
            return 0;
        end if;
    end function;

    function make_dstmask(pmask : port_mask_t; src, dst: integer) return port_mask_t is
        variable dstmask, srcmask, result : port_mask_t := (others => '0');
    begin
        -- Set the destination mask.
        if (dst < 0) then
            dstmask := (others => '1');         -- Broadcast
        else
            dstmask(dst mod PORT_COUNT) := '1'; -- Single port
        end if;
        -- Set the source mask.
        assert (src >= 0) report "Invalid source" severity error;
        srcmask(src mod PORT_COUNT) := '1';
        -- Set flag for promiscuous ports or designated destination,
        -- but never send a packet back to its source.  (Loops are BAD.)
        result := (pmask or dstmask) and not srcmask;
        return result;
    end function;

    function make_mac(idx: integer) return unsigned is
    begin
        return to_unsigned(idx mod 256, 8);
    end function;

    impure function should_print(idx: integer) return boolean is
    begin
        if (VERBOSITY = 2) then     -- Always
            return true;
        elsif (VERBOSITY = 1) then  -- Sometimes
            return (idx < 10) or (idx mod 100) = 0;
        elsif (VERBOSITY = 0) then  -- Rarely
            return (got_result = '0') and (idx mod 1000) = 0;
        end if;
    end function;

    constant BYTES_PER_CLOCK : integer := INPUT_WIDTH / 8;
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;
    variable temp_dst   : integer := 0;
    variable temp_src   : integer := 0;
    variable bnext      : unsigned(7 downto 0) := (others => '0');
    variable bcount     : integer := 0;
    variable pkt_dst    : unsigned(7 downto 0) := (others => '0');
    variable pkt_src    : unsigned(7 downto 0) := (others => '0');
    variable pkt_len    : integer := 0;
    variable cfg_change : std_logic := '0';
    variable mac_known  : std_logic_vector(255 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        cfg_change := '0';
        if (reset_p = '1') then
            -- Reset packet generation.
            in_pdst     <= (others => '0'); -- Mask
            in_psrc     <= 0;               -- Index
            in_data     <= (others => '0'); -- Data word
            in_last     <= '0';
            in_valid    <= '0';
            pkt_count   <= 0;
            pkt_mode    <= 0;
            ignore_ovr  <= '0';
            bcount      := 0;
            pkt_len     := 0;
            mac_known   := (others => '0');
        elsif (in_valid = '0' or in_ready = '1') then
            -- Input flow-control randomization.
            uniform(seed1, seed2, rand);
            if (rand < in_rate) then
                -- If we're starting a new packet, select parameters.
                if (bcount >= pkt_len) then
                    -- Depending on verbosity, periodically report start of new packet.
                    if should_print(pkt_count) then
                        report "Starting packet " & pkt_str;
                    end if;
                    -- Reset generator state.
                    bcount := 0;
                    ignore_ovr <= '0';
                    -- Select source and destination based on test mode.
                    if (pkt_mode = 0) then
                        -- First few packets are fixed source/destination:
                        if (pkt_count = 0) then
                            -- Broadcast from address x05.
                            pkt_dst := make_mac(255);
                            pkt_src := make_mac(5);
                        elsif (pkt_count = 1) then
                            -- From address x04 to x05 (should match)
                            pkt_dst := make_mac(5);
                            pkt_src := make_mac(4);
                        else
                            -- From address x04 to x06 (should miss)
                            pkt_dst := make_mac(6);
                            pkt_src := make_mac(4);
                        end if;
                    elsif (pkt_mode = 1) then
                        -- Fill the address table (already have x04, x05)
                        pkt_dst := make_mac(pkt_count + 5);
                        pkt_src := make_mac(pkt_count + 6);
                    elsif (pkt_mode = 2) then
                        -- Stale address removal, keep sending all but x04.
                        temp_dst := pkt_count mod (TABLE_SIZE-1);
                        pkt_dst := make_mac(temp_dst + 5);
                        pkt_src := make_mac(temp_dst + 5);
                    elsif (pkt_mode = 3) then
                        -- Confirm stale data was removed from the table.
                        if (pkt_count = 0) then
                            -- Attempt packet to port 4 (should miss)
                            pkt_dst := x"04";
                            pkt_src := x"05";
                        elsif (pkt_count = 1) then
                            -- Broadcast from port 4 (re-learn)
                            pkt_dst := x"FF";
                            pkt_src := x"04";
                        else
                            -- Re-attempt packet to port 4 (should match)
                            pkt_dst := x"04";
                            pkt_src := x"05";
                        end if;
                    elsif (pkt_mode = 4) then
                        -- Intentionally overflow the address table.
                        -- Note: This phase is followed by a very long pause.
                        ignore_ovr <= '1';    -- Ignore overflow messages
                        pkt_dst := make_mac(pkt_count + 5);
                        pkt_src := make_mac(pkt_count + TABLE_SIZE);
                    else
                        -- Random traffic.
                        uniform(seed1, seed2, rand);
                        if (rand < 0.1) then
                            temp_dst := 255;  -- Broadcast
                        else
                            uniform(seed1, seed2, rand);
                            temp_dst := 4 + integer(floor(rand * real(TABLE_SIZE)));
                        end if;
                        uniform(seed1, seed2, rand);
                        temp_src := 4 + integer(floor(rand * real(TABLE_SIZE)));
                        pkt_dst := make_mac(temp_dst);
                        pkt_src := make_mac(temp_src);
                    end if;
                    -- Select source port index.
                    temp_src := mac2port(pkt_src);
                    temp_dst := to_integer(pkt_dst);
                    in_psrc  <= temp_src;
                    -- Generate destination port mask.
                    if (temp_dst = 255) then
                        -- Broadcast packet.
                        in_pdst <= make_dstmask(cfg_prmask, temp_src, -1);
                    elsif (mac_known(temp_dst) = '1') then
                        -- Normal packet to known port.
                        in_pdst <= make_dstmask(cfg_prmask, temp_src, temp_dst);
                    elsif (UPLINK_MODE = '0') then
                        -- Unknown packet / Normal mode --> Broadcast.
                        in_pdst <= make_dstmask(cfg_prmask, temp_src, -1);
                    else
                        -- Unknown packet / Uplink mode --> Port 0 (except loopback).
                        in_pdst <= make_dstmask(cfg_prmask, temp_src, 0);
                    end if;
                    -- Update the known-port mask by inspecting source address.
                    if (UPLINK_MODE = '0' or temp_src /= 0) then
                        mac_known(to_integer(pkt_src)) := '1';
                    end if;
                    -- Randomize packet length (bytes including header)
                    uniform(seed1, seed2, rand);
                    pkt_len := 64 + integer(floor(rand * 64.0));
                end if;
                -- Generate the next data word, one byte at a time.
                in_data     <= (others => '0');
                mac_final   <= '0';
                for b in BYTES_PER_CLOCK downto 1 loop  -- MSW first
                    if (bcount < 6) then
                        -- Destination MAC address (repeat byte six times)
                        bnext := pkt_dst;
                    elsif (bcount < 12) then
                        -- Source MAC address (repeat byte six times)
                        bnext := pkt_src;
                    else
                        -- All others = random filler.
                        uniform(seed1, seed2, rand);
                        bnext := to_unsigned(integer(floor(rand * 256.0)), 8);
                    end if;
                    in_data(8*b-1 downto 8*b-8) <= std_logic_vector(bnext);
                    bcount := bcount + 1;
                    -- Drive the MAC-ready strobe to measure latency.
                    if (bcount = 12) then
                        mac_final <= '1';
                    end if;
                end loop;
                -- Assert the LAST and VALID flags appropriately.
                in_last     <= bool2bit(bcount >= pkt_len);
                in_valid    <= '1';
                -- After end of packet, increment generator state.
                if (bcount < pkt_len) then
                    null;  -- Waiting for end of packet.
                elsif (pkt_mode = 0 and pkt_count = 2) then
                    -- Finished initial tests.
                    pkt_count <= 0;
                    pkt_mode  <= pkt_mode + 1;
                elsif (pkt_mode = 1 and pkt_count + 3 = ADDR_COUNT) then
                    -- Finished filling address table.
                    -- Note: If this block doesn't scrub, skip ahead.
                    pkt_count <= 0;
                    if (SCRUB_ENABLE = '0') then
                        pkt_mode <= 5;
                    else
                        pkt_mode <= pkt_mode + 1;
                    end if;
                elsif (pkt_mode = 2 and scrub_count = SCRUB_TIMEOUT + 2) then
                    -- Finished stale-address removal.
                    pkt_count <= 0;
                    pkt_mode  <= pkt_mode + 1;
                    mac_known(4) := '0';
                elsif (pkt_mode = 3 and pkt_count = 2) then
                    -- Finished confirmation of stale-address removal.
                    pkt_count <= 0;
                    pkt_mode  <= pkt_mode + 1;
                elsif (pkt_mode = 4 and pkt_count = 1) then
                    -- Finished intentional table overflow.
                    pkt_count <= 0;
                    pkt_mode  <= pkt_mode + 1;
                    -- Next phase will clear table (no traffic).
                    mac_known := (others => '0');
                elsif (pkt_mode > 4 and pkt_count = 500) then
                    -- Configuration change every N frames.
                    pkt_count <= 0;
                    pkt_mode  <= pkt_mode + 1;
                    cfg_change := '1';
                else
                    -- All other conditions.
                    pkt_count <= pkt_count + 1;
                end if;
            elsif (in_last = '1') then
                -- Last word consumed, clear all flags.
                in_psrc  <= 0;
                in_last  <= '0';
                in_valid <= '0';
            else
                -- Previous word consumed, clear in_valid only.
                in_valid <= '0';
            end if;
        end if;

        -- Update the test configuration at start of each phase.
        if (reset_p = '1') then
            -- Default configuration.
            cfg_delay   <= 0;
            cfg_prmask  <= (others => '0');
        elsif (cfg_change = '1') then
            -- Configuration change request.
            cfg_delay   <= 32;    -- Pause for N cycles
        elsif (cfg_delay > 0) then
            -- Countdown while pipeline is flushed.
            cfg_delay   <= cfg_delay - 1;
            -- Just before we restart, re-randomize test configuration:
            if (cfg_delay = 1) then
                -- Set/clear the promiscuous-port flags.
                for n in cfg_prmask'range loop
                    uniform(seed1, seed2, rand);
                    cfg_prmask(n) <= bool2bit(rand < 0.05);
                end loop;
            end if;
        end if;

        -- Output flow-control randomization.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < 0.5) and not reset_p;
    end if;
end process;

-- Drive the input rate
in_rate <= 0.8 when (pkt_mode < 5)      -- 80% for Modes 0-4
      else 0.0 when (scrub_rem > 0)     -- Wait until scrubbing completed
      else 0.0 when (cfg_delay > 0)     -- Wait after configuration change
      else 1.0;                         -- 100% for random traffic gen.

p_rate : process(clk)
begin
    if rising_edge(clk) then
        -- If scrubbing is enabled, countdown at start of Mode 5.
        if (SCRUB_ENABLE = '0') then
            scrub_rem <= 0;                     -- Scrub disabled
        elsif (pkt_mode < 5) then
            scrub_rem <= SCRUB_TIMEOUT + 5;     -- Waiting for start
        elsif (scrub_req = '1' and scrub_rem > 0) then
            scrub_rem <= scrub_rem - 1;         -- Countdown to zero
        end if;
    end if;
end process;

-- A small FIFO for reference data (including timing).
-- Note: Includes first word fall-through.
fifo_pdst : entity work.smol_fifo
    generic map(IO_WIDTH => PORT_COUNT)
    port map(
    in_data     => in_pdst,
    in_write    => ref_wr,
    out_data    => ref_pdst,
    out_valid   => open,
    out_read    => ref_rd,
    reset_p     => reset_p,
    clk         => clk);

fifo_time : entity work.smol_fifo
    generic map(IO_WIDTH => 16)
    port map(
    in_data     => std_logic_vector(in_time),
    in_write    => ref_wr,
    out_data    => ref_time,
    out_valid   => ref_valid,
    out_read    => ref_rd,
    reset_p     => reset_p,
    clk         => clk);

ref_wr <= in_valid and in_ready and mac_final;
ref_rd <= out_valid and out_ready;

-- Unit under test. (One of several configurations.)
uut : entity work.mac_lookup_generic
    generic map(
    IMPL_TYPE       => IMPL_TYPE,
    INPUT_WIDTH     => INPUT_WIDTH,
    PORT_COUNT      => PORT_COUNT,
    TABLE_SIZE      => TABLE_SIZE,
    SCRUB_TIMEOUT   => SCRUB_TIMEOUT)
    port map(
    in_psrc         => in_psrc,
    in_data         => in_data,
    in_last         => in_last,
    in_valid        => in_valid,
    in_ready        => in_ready,
    out_pdst        => out_pdst,
    out_valid       => out_valid,
    out_ready       => out_ready,
    scrub_req       => scrub_req,
    scrub_busy      => scrub_busy,
    scrub_remove    => scrub_remove,
    cfg_prmask      => cfg_prmask,
    error_full      => error_full,
    error_table     => error_table,
    clk             => clk,
    reset_p         => reset_p);

-- Confirm expected outputs.
got_stats <= got_result;

p_check : process(clk)
    variable elapsed, time_cnt, time_min, time_max, time_sum : integer := 0;
begin
    if rising_edge(clk) then
        -- Check the two error strobes.
        if (reset_p = '0') then
            assert (error_table = '0')
                report "Unexpected table integrity error near " & pkt_str
                severity error;
            assert (error_full = '0' or ignore_ovr = '1')
                report "Unexpected table overflow error near " & pkt_str
                severity error;
        end if;

        -- Check that destination mask matches expected value.
        if (out_valid = '1' and out_ready = '1') then
            assert (ref_valid = '1')
                report "Output too early (Mask before MAC)"
                severity error;
            assert (out_pdst = ref_pdst)
                report "Destination mask mismatch near " & pkt_str
                severity error;
        end if;

        -- Measure min/avg/max latency.
        elapsed := to_integer(in_time - unsigned(ref_time));
        if (reset_p = '1') then
            got_packet <= '0';
            got_result <= '0';
        elsif (pkt_mode > 4 and out_valid = '1' and got_packet = '0') then
            -- Alarm if elapsed time exceeds threshold.
            assert (elapsed <= MAX_LATENCY)
                report "Exceeded maximum latency near " & pkt_str;
            -- Update statistics.
            if (time_cnt = 0 or elapsed < time_min) then
                time_min := elapsed;
            end if;
            if (time_cnt = 0 or elapsed > time_max) then
                time_max := elapsed;
            end if;
            time_sum := time_sum + elapsed;
            time_cnt := time_cnt + 1;
            -- Don't double-count this packet.
            got_packet <= not out_ready;
            -- Report results after N test packets.
            if (time_cnt = 2000) then
                report "Timing statistics: " & IMPL_TYPE
                    & " Range " & integer'image(time_min)
                    & "-" & integer'image(time_max)
                    & ", Mean " & real'image(real(time_sum) / real(time_cnt));
                got_result <= '1';
            end if;
        elsif (out_valid = '1' and out_ready = '1') then
            -- Result consumed, ready to count results again.
            got_packet <= '0';
        end if;
    end if;
end process;

end single;



---------------------------------------------------------------------
----------------------------- TOP LEVEL TESTBENCH -------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_tb is
    -- Unit testbench top level, no I/O ports
end mac_lookup_tb;

architecture tb of mac_lookup_tb is

signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';
signal scrub_req    : std_logic := '0';
signal got_stats    : std_logic_vector(5 downto 0);

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Scrub request at ~10 kHz.
-- (Abnormally fast, to allow reasonable simulation time.)
p_scrub : process(clk_100)
    constant INTERVAL : integer := 10000;
    variable count : integer := 0;
begin
    if rising_edge(clk_100) then
        if (reset_p = '1') then
            scrub_req <= '0';
            count     := 0;
        elsif (count+1 < INTERVAL) then
            scrub_req <= '0';
            count     := count + 1;
        else
            scrub_req <= '1';
            count     := 0;
        end if;
    end if;
end process;

-- Detect when all instances are done.
p_done : process
begin
    while (and_reduce(got_stats) /= '1') loop
        wait until rising_edge(clk_100);
    end loop;
    report "All tests completed!";
    wait;
end process;

-- Instantiate each test configuration.
u_binary : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "BINARY",
    INPUT_WIDTH     => 32,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 31,
    MAX_LATENCY     => 14)
    port map (
    got_stats       => got_stats(0),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

u_brute : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "BRUTE",
    INPUT_WIDTH     => 32,
    PORT_COUNT      => 9,
    TABLE_SIZE      => 31)
    port map (
    got_stats       => got_stats(1),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

u_lutram : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "LUTRAM",
    INPUT_WIDTH     => 40,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 32)
    port map (
    got_stats       => got_stats(2),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

u_parshift : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "PARSHIFT",
    INPUT_WIDTH     => 24,
    PORT_COUNT      => 11,
    TABLE_SIZE      => 32)
    port map (
    got_stats       => got_stats(3),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

u_simple : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "SIMPLE",
    INPUT_WIDTH     => 8,
    PORT_COUNT      => 8,
    TABLE_SIZE      => 31)
    port map (
    got_stats       => got_stats(4),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

u_stream : entity work.mac_lookup_tb_single
    generic map(
    IMPL_TYPE       => "STREAM",
    INPUT_WIDTH     => 8,   -- "STREAM" = 8-bit only
    PORT_COUNT      => 9,   -- Note: 1 uplink + 8 endpoints
    TABLE_SIZE      => -1)  -- Not applicable
    port map (
    got_stats       => got_stats(5),
    scrub_req       => scrub_req,
    clk             => clk_100,
    reset_p         => reset_p);

end tb;
