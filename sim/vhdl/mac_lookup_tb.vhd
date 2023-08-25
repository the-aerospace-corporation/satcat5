--------------------------------------------------------------------------
-- Copyright 2019, 2020, 2021, 2022, 2023 The Aerospace Corporation
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
-- Testbench for the MAC-address lookup system.
--
-- This testbench generates test sequences for the MAC-lookup table,
-- including the following test cases:
--      * Delivery of a broadcast packet
--      * Delivery to a discovered address
--      * Broadcast or drop of an undiscovered address
--      * Fill address table, then overwrite oldest
--      * Randomized traffic
--
-- To ensure predictable cache-overwrite events, we use the WRAP mode
-- only for this test.  Other modes are tested in "tcam_test_tb".
--
-- A single top-level module instantiates individual helper modules to
-- test each configuration.  The test will run indefinitely, with
-- adequate coverage taking about 1.5 msec.
--

---------------------------------------------------------------------
----------------------------- HELPER MODULE -------------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.tcam_constants.all;

entity mac_lookup_tb_single is
    generic (
    UUT_LABEL       : string;           -- Human-readable label
    ALLOW_RUNT      : boolean;          -- Allow undersize frames?
    IO_BYTES        : positive;         -- Width of main data port
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    TABLE_SIZE      : positive;         -- Max stored MAC addresses
    MISS_BCAST      : std_logic;        -- Broadcast or drop unknown MAC?
    MAX_PACKETS     : positive := 2000; -- Declare "done" after N packets
    VERBOSITY       : natural := 0;     -- Verbosity level (0/1/2)
    MAX_LATENCY     : natural := 16);   -- Maximum allowed latency
    port (
    got_stats       : out std_logic;
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_tb_single;

architecture single of mac_lookup_tb_single is

-- Define convenience types.
constant INPUT_WIDTH : positive := 8 * IO_BYTES;
subtype port_idx_t is integer range 0 to PORT_COUNT-1;
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- Overall source state
signal in_rate      : real := 0.0;
signal out_rate     : real := 0.0;
signal pkt_count    : natural := 0;
signal pkt_delay    : natural := 0;
signal pkt_mode     : natural := 0;
signal cfg_delay    : natural := 0;

-- Queued reference data
signal in_pdst      : port_mask_t := (others => '0');
signal mac_final    : std_logic := '0';
signal ref_pdst     : port_mask_t;
signal ref_rd       : std_logic;
signal ref_valid    : std_logic;

-- Elapsed-time measurement
signal in_time      : unsigned(15 downto 0) := (others => '0');
signal ref_time     : std_logic_vector(15 downto 0);

-- Unit under test
signal in_psrc      : port_idx_t := 0;
signal in_wcount    : mac_bcount_t := 0;
signal in_data      : std_logic_vector(INPUT_WIDTH-1 downto 0) := (others => 'X');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal out_pdst     : port_mask_t;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal scrub_busy   : std_logic := '0';
signal cfg_prmask   : port_mask_t := (others => '0');
signal error_change : std_logic := '0';     -- MAC address changed ports
signal error_table  : std_logic := '0';     -- Table integrity check failed
signal read_index   : integer range 0 to TABLE_SIZE-1 := 0;
signal read_valid   : std_logic := '0';
signal read_ready   : std_logic;
signal read_addr    : mac_addr_t;
signal read_psrc    : port_idx_t;
signal read_found   : std_logic;
signal write_addr   : mac_addr_t := (others => '0');
signal write_psrc   : integer range 0 to PORT_COUNT-1 := 0;
signal write_valid  : std_logic := '0';
signal write_ready  : std_logic;

-- Overall test state
signal got_packet   : std_logic := '0';
signal got_result   : std_logic := '0';

-- Diagnostic functions.
impure function pkt_str return string is
begin
    return UUT_LABEL
        & "_" & integer'image(pkt_mode)
        & "." & integer'image(pkt_count);
end function;

begin

-- Generate time counter for latency measurement.
p_time : process(clk)
begin
    if rising_edge(clk) then
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
    function mac2port(mac: unsigned) return natural is
        variable mac_int : natural := to_integer(mac);
    begin
        if (mac_int = 255) then
            -- Special case for broadcast packets.
            return 255;
        else
            -- Normal mode, port index distributed evenly.
            return mac_int mod PORT_COUNT;
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

    function make_mac(idx: natural) return unsigned is
    begin
        return to_unsigned(idx mod 256, 8);
    end function;

    impure function should_print(idx: natural) return boolean is
    begin
        if (VERBOSITY = 2) then     -- Always
            return true;
        elsif (VERBOSITY = 1) then  -- Sometimes
            return (idx < 10) or (idx mod 100) = 0;
        elsif (VERBOSITY = 0) then  -- Rarely
            return (got_result = '0') and (idx mod 1000) = 0;
        end if;
    end function;

    -- Minimum delay to ensure TCAM has time to update.
    constant TCAM_DELAY : positive := 128;

    -- Packet generator state
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;
    variable temp_dst   : natural := 0;
    variable temp_src   : natural := 0;
    variable temp_last  : std_logic := '0';
    variable temp_write : std_logic := '0';
    variable bnext      : unsigned(7 downto 0) := (others => '0');
    variable bcount     : natural := 0;
    variable pkt_dst    : unsigned(7 downto 0) := (others => '0');
    variable pkt_src    : unsigned(7 downto 0) := (others => '0');
    variable pkt_len    : natural := 0; -- Packet length in bytes
    variable pkt_dly    : natural := 0; -- Post-packet delay, in clocks
    variable cfg_change : std_logic := '0';
    variable mac_known  : std_logic_vector(255 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Set defaults
        in_data     <= (others => 'X');
        mac_final   <= '0';
        cfg_change  := '0';
        temp_last   := '0';
        temp_write  := '0';
        -- Flow control randomization
        uniform(seed1, seed2, rand);
        -- Main state machine:
        if (reset_p = '1') then
            -- Reset packet generation.
            in_pdst     <= (others => '0'); -- Mask
            in_psrc     <= 0;               -- Index
            pkt_count   <= 0;
            pkt_mode    <= 0;
            bcount      := 0;
            pkt_len     := 0;
            mac_known   := (others => '0');
        elsif (rand < in_rate) then
            -- If we're starting a new packet, select parameters.
            if (bcount >= pkt_len) then
                -- Depending on verbosity, periodically report start of new packet.
                if should_print(pkt_count) then
                    report "Starting packet " & pkt_str;
                end if;
                -- Reset generator state.
                bcount  := 0;
                pkt_dly := 0;
                -- Select source and destination based on test mode.
                if (pkt_mode = 0) then
                    -- First few packets are fixed source/destination:
                    if (pkt_count = 0) then
                        -- Broadcast from address x04.
                        pkt_dst := make_mac(255);
                        pkt_src := make_mac(4);
                        pkt_dly := TCAM_DELAY;  -- Delay before next packet
                    elsif (pkt_count = 1) then
                        -- From address x05 to x04 (should match learned address)
                        pkt_dst := make_mac(4);
                        pkt_src := make_mac(5);
                        pkt_dly := TCAM_DELAY;
                    elsif (pkt_count = 2) then
                        -- From address x04 to x06 (should miss)
                        pkt_dst := make_mac(6);
                        pkt_src := make_mac(4);
                        pkt_dly := TCAM_DELAY;
                        -- Note: At the end of this packet, manually write x06 to the MAC table.
                    else
                        -- From address x04 to x06 (should match manual address)
                        pkt_dst := make_mac(6);
                        pkt_src := make_mac(4);
                        pkt_dly := TCAM_DELAY;
                    end if;
                elsif (pkt_mode = 1) then
                    -- Fill the address table (already have x04, x05, x06)
                    -- (Leave a pause after each one to update the table.)
                    pkt_dst := make_mac(pkt_count + 5);
                    pkt_src := make_mac(pkt_count + 6);
                    pkt_dly := TCAM_DELAY;
                elsif (pkt_mode = 2) then
                    -- Rapid-fire sequential packets in range 4-N.
                    temp_dst := pkt_count mod TABLE_SIZE;
                    pkt_dst := make_mac(temp_dst + 4);
                    pkt_src := make_mac(temp_dst + 4);
                elsif (pkt_mode = 3) then
                    -- Overwrite oldest table element.
                    if (pkt_count = 0) then
                        -- From x05 to x03, should miss.
                        pkt_dst := x"03";
                        pkt_src := x"05";
                    elsif (pkt_count = 1) then
                        -- Broadcast from x03, should overwrite oldest = x04
                        pkt_dst := x"FF";
                        pkt_src := x"03";
                        pkt_dly := TCAM_DELAY;
                        mac_known(4) := '0';
                    elsif (pkt_count = 2) then
                        -- From address x03 to x04 (should miss)
                        pkt_dst := x"04";
                        pkt_src := x"03";
                    else
                        -- From address x03 to x05 (should hit)
                        pkt_dst := x"05";
                        pkt_src := x"03";
                    end if;
                else
                    -- Random traffic from ports 5-N.
                    uniform(seed1, seed2, rand);
                    if (rand < 0.1) then
                        temp_dst := 255;  -- Broadcast
                    else
                        uniform(seed1, seed2, rand);
                        temp_dst := 5 + integer(floor(rand * real(TABLE_SIZE-1)));
                    end if;
                    uniform(seed1, seed2, rand);
                    temp_src := 5 + integer(floor(rand * real(TABLE_SIZE-1)));
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
                elsif (MISS_BCAST = '1') then
                    -- Unknown packet -> Broadcast
                    in_pdst <= make_dstmask(cfg_prmask, temp_src, -1);
                else
                    -- Unknown packet -> Drop
                    in_pdst <= (others => '0');
                end if;
                -- Update the known-port mask by inspecting source address.
                mac_known(to_integer(pkt_src)) := '1';
                -- Randomize packet length (bytes including header)
                uniform(seed1, seed2, rand);
                if ALLOW_RUNT then
                    pkt_len := 18 + integer(floor(rand * 32.0));
                else
                    pkt_len := 64 + integer(floor(rand * 32.0));
                end if;
            end if;
            -- Generate the next data word, one byte at a time.
            in_data <= (others => '0');
            in_wcount <= int_min(bcount / IO_BYTES, IP_HDR_MAX);
            for b in IO_BYTES downto 1 loop  -- MSW first
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
                -- (Note: Only destination MAC is required to generate output.)
                if (bcount = 6) then
                    mac_final <= '1';
                end if;
            end loop;
            -- Assert the LAST and VALID flags appropriately.
            temp_last   := bool2bit(bcount >= pkt_len);
            temp_write  := '1';
            -- After end of packet, increment generator state.
            if (bcount < pkt_len) then
                null;  -- Waiting for end of packet.
            elsif (pkt_mode = 0 and pkt_count = 3) then
                -- Finished initial tests.
                pkt_count <= 0;
                pkt_mode  <= pkt_mode + 1;
            elsif (pkt_mode = 1 and pkt_count + 3 = TABLE_SIZE) then
                -- Finished filling address table.
                -- Note: If this block doesn't scrub, skip ahead.
                pkt_count <= 0;
                pkt_mode  <= pkt_mode + 1;
            elsif (pkt_mode = 2 and pkt_count = 3 * TABLE_SIZE) then
                -- This phase can run indefinitely; cutoff is arbitrary.
                pkt_count <= 0;
                pkt_mode  <= pkt_mode + 1;
            elsif (pkt_mode = 3 and pkt_count = 3) then
                -- Finished confirmation of stale-address overwrite.
                pkt_count <= 0;
                pkt_mode  <= pkt_mode + 1;
            elsif (pkt_mode > 3 and pkt_count = 500) then
                -- Configuration change every N frames.
                pkt_count <= 0;
                pkt_mode  <= pkt_mode + 1;
                cfg_change := '1';
            else
                -- All other conditions.
                pkt_count <= pkt_count + 1;
            end if;
        elsif (in_last = '1') then
            -- As part of test, clear PSRC immediately after end-of-frame.
            in_psrc <= 0;
        end if;

        -- Drive the "real" last and write strobes.
        in_last  <= temp_last;
        in_write <= temp_write;

        -- Drive manual "write" interface at selected times.
        if (reset_p = '1' or write_ready = '1') then
            write_addr  <= (others => '0');
            write_psrc  <= 0;
            write_valid <= '0';
        elsif (pkt_mode = 0 and pkt_count = 2 and temp_last = '1' and temp_write = '1') then
            write_addr  <= x"060606060606";
            write_psrc  <= mac2port(x"06");
            write_valid <= '1';
            mac_known(6) := '1';
        end if;

        -- Compare manual "read" results against expected status.
        if (read_valid = '1' and read_ready = '1') then
            if (pkt_mode = 0 and read_index > 2) then
                assert (read_found = '0' and read_addr = MAC_ADDR_BROADCAST)
                    report "Table entry should be empty." severity error;
            elsif (pkt_mode = 2 or pkt_mode = 4) then
                bnext := unsigned(read_addr(7 downto 0));
                assert (read_found = '1' and read_addr /= MAC_ADDR_BROADCAST)
                    report "Table entry should be filled." severity error;
                assert (read_psrc = mac2port(bnext))
                    report "Table read mismatch: Got " & integer'image(read_psrc)
                        & " expected " & integer'image(mac2port(bnext))
                    severity error;
            end if;
        end if;

        -- Issue manual "read" commands whenever the table is quiet.
        if (reset_p = '1') then
            read_valid  <= '0';         -- Global reset
            read_index  <= 0;
        elsif (read_valid = '0' or read_ready = '1') then
            if (pkt_mode = 0 or pkt_mode = 2 or pkt_mode = 4) then
                read_valid <= '1';      -- Start of new read
                uniform(seed1, seed2, rand);
                read_index <= integer(floor(rand * real(TABLE_SIZE)));
            else
                read_valid <= '0';      -- Idle
            end if;
        end if;

        -- Update post-packet delay countdown, if requested.
        if (reset_p = '1') then
            pkt_delay <= 0;
        elsif (temp_last = '1') then
            pkt_delay <= pkt_dly;
        elsif (pkt_delay > 0) then
            pkt_delay <= pkt_delay - 1;
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
        out_ready <= bool2bit(rand < out_rate) and not reset_p;
    end if;
end process;

-- Select the input and output flow-control rates.
in_rate <= 0.0 when (pkt_delay > 0)     -- Wait before sending packet
      else 0.0 when (cfg_delay > 0)     -- Wait after configuration change
      else 0.8 when (pkt_mode < 5)      -- 80% for Modes 0-4
      else 1.0;                         -- 100% for random traffic gen.

out_rate <= 0.7 when IO_BYTES < 18 else 0.95;

-- A small FIFO for reference data (including timing).
-- Note: Includes first word fall-through.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => PORT_COUNT,
    META_WIDTH  => 16)
    port map(
    in_data     => in_pdst,
    in_meta     => std_logic_vector(in_time),
    in_write    => mac_final,
    out_data    => ref_pdst,
    out_meta    => ref_time,
    out_valid   => ref_valid,
    out_read    => ref_rd,
    reset_p     => reset_p,
    clk         => clk);

ref_rd <= out_valid and out_ready;

-- Unit under test. (One of several configurations.)
uut : entity work.mac_lookup
    generic map(
    ALLOW_RUNT      => ALLOW_RUNT,
    IO_BYTES        => IO_BYTES,
    PORT_COUNT      => PORT_COUNT,
    TABLE_SIZE      => TABLE_SIZE,
    CACHE_POLICY    => TCAM_REPL_WRAP)
    port map(
    in_psrc         => in_psrc,
    in_wcount       => in_wcount,
    in_data         => in_data,
    in_last         => in_last,
    in_write        => in_write,
    out_psrc        => open,    -- Not tested
    out_pmask       => out_pdst,
    out_valid       => out_valid,
    out_ready       => out_ready,
    cfg_mbmask      => (others => MISS_BCAST),
    cfg_prmask      => cfg_prmask,
    error_change    => error_change,
    error_table     => error_table,
    read_index      => read_index,
    read_valid      => read_valid,
    read_ready      => read_ready,
    read_addr       => read_addr,
    read_psrc       => read_psrc,
    read_found      => read_found,
    write_addr      => write_addr,
    write_psrc      => write_psrc,
    write_valid     => write_valid,
    write_ready     => write_ready,
    clk             => clk,
    reset_p         => reset_p);

-- Confirm expected outputs.
got_stats <= got_result;

p_check : process(clk)
    variable elapsed, time_cnt, time_min, time_max, time_sum : natural := 0;
begin
    if rising_edge(clk) then
        -- Check the two error strobes.
        if (reset_p = '0') then
            assert (error_table = '0')
                report "Unexpected table integrity error near " & pkt_str
                severity error;
            assert (error_change = '0')
                report "Unexpected table change error near " & pkt_str
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
            if (time_cnt = MAX_PACKETS) then
                report "Timing statistics: " & UUT_LABEL
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
signal got_stats    : std_logic_vector(3 downto 0);

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

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
uut0 : entity work.mac_lookup_tb_single
    generic map(
    UUT_LABEL       => "Unit0",
    ALLOW_RUNT      => true,
    IO_BYTES        => 1,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 12,
    MISS_BCAST      => '1',
    MAX_PACKETS     => 300)
    port map(
    got_stats       => got_stats(0),
    clk             => clk_100,
    reset_p         => reset_p);

uut1 : entity work.mac_lookup_tb_single
    generic map(
    UUT_LABEL       => "Unit1",
    ALLOW_RUNT      => true,
    IO_BYTES        => 6,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 16,
    MISS_BCAST      => '1')
    port map(
    got_stats       => got_stats(1),
    clk             => clk_100,
    reset_p         => reset_p);

uut2 : entity work.mac_lookup_tb_single
    generic map(
    UUT_LABEL       => "Unit2",
    ALLOW_RUNT      => false,
    IO_BYTES        => 12,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 32,
    MISS_BCAST      => '1')
    port map(
    got_stats       => got_stats(2),
    clk             => clk_100,
    reset_p         => reset_p);

uut3 : entity work.mac_lookup_tb_single
    generic map(
    UUT_LABEL       => "Unit3",
    ALLOW_RUNT      => true,
    IO_BYTES        => 18,
    PORT_COUNT      => 12,
    TABLE_SIZE      => 32,
    MISS_BCAST      => '1')
    port map(
    got_stats       => got_stats(3),
    clk             => clk_100,
    reset_p         => reset_p);

end tb;
