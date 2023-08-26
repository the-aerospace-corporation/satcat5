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
-- Testbench for the asynchronous packet FIFO
--
-- This testbench is a unit test for the asynchronous packet FIFO, verifying
-- correct operation in a variety of input/output configurations, under a
-- variety of flow-control conditions.
--
-- To mimic expected operation and facilitate testing, the tests uses pairs
-- of FIFO blocks, each back-to-back with another.
--
-- A single top-level module instantiates individual helper modules to test
-- each configuration.  The test will run indefinitely, with adequate coverage
-- taking about 10 milliseconds.
--

---------------------------------------------------------------------
----------------------------- HELPER MODULE -------------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity fifo_packet_tb_single is
    generic (
    OUTER_BYTES     : natural;          -- Width of input/output ports
    INNER_BYTES     : natural;          -- Width of inter-FIFO port
    OUTER_CLOCK_MHZ : natural;          -- Rate of input/output ports
    INNER_CLOCK_MHZ : natural;          -- Rate of inter-FIFO ports
    BUFFER_KBYTES   : natural;          -- Buffer size (kilobytes)
    META_WIDTH      : natural := 0;     -- Metadata width (optional)
    MIN_PKT_BYTES   : natural := 1;     -- Minimum packet size (bytes)
    MAX_PKT_BYTES   : natural := 250);  -- Maximum packet size (bytes)
    -- No I/O ports
end fifo_packet_tb_single;

architecture single of fifo_packet_tb_single is

constant MIN_PKT_WORDS : integer := (MIN_PKT_BYTES + OUTER_BYTES - 1) / OUTER_BYTES;
constant MAX_PKT_WORDS : integer := (MAX_PKT_BYTES + OUTER_BYTES - 1) / OUTER_BYTES;
constant MAX_PACKETS   : integer := 64;

subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);

-- Clock generation.
constant OUTER_PERIOD : time := 1 us / OUTER_CLOCK_MHZ;
constant INNER_PERIOD : time := 1 us / INNER_CLOCK_MHZ;
constant OUTER_MAXBPS : real := real(8 * OUTER_BYTES) * real(OUTER_CLOCK_MHZ);
constant INNER_MAXBPS : real := real(8 * INNER_BYTES) * real(INNER_CLOCK_MHZ);
signal inner_clk    : std_logic := '0';
signal outer_clk    : std_logic := '0';

-- Input to the first FIFO.
signal in_index     : natural := 0; -- Packet index
signal in_xfer      : natural := 0; -- Cumulative byte-index
signal in_drop_en   : std_logic := '0';
signal in_data      : std_logic_vector(8*OUTER_BYTES-1 downto 0) := (others => '0');
signal in_meta      : meta_t := (others => '0');
signal in_last_com  : std_logic := '0';
signal in_last_rev  : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic := '0';
signal in_write     : std_logic;
signal in_overflow  : std_logic;
signal in_hfull     : std_logic;

-- Transfer from first FIFO to second FIFO.
signal mid_xfer     : natural := 0; -- Cumulative byte-index
signal mid_data     : std_logic_vector(8*INNER_BYTES-1 downto 0);
signal mid_nlast    : integer range 0 to INNER_BYTES;
signal mid_meta     : meta_t := (others => '0');
signal mid_precom   : std_logic;
signal mid_last     : std_logic;
signal mid_valid    : std_logic;
signal mid_ready    : std_logic := '0';
signal mid_write    : std_logic;
signal mid_overflow : std_logic;

-- Output from second FIFO.
signal out_index    : natural := 0; -- Packet index
signal out_xfer     : natural := 0; -- Cumulative byte-index
signal out_total    : integer := 0;
signal out_ref      : std_logic_vector(8*OUTER_BYTES-1 downto 0) := (others => '0');
signal out_data     : std_logic_vector(8*OUTER_BYTES-1 downto 0);
signal out_meta     : meta_t := (others => '0');
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_pause    : std_logic := '0';
signal out_overflow : std_logic;
signal out_hfull    : std_logic;

-- Overall test control
constant revert_rate : real := 0.1;
signal test_idx     : integer := 0;
signal in_bps       : real := 0.0;
signal mid_bps      : real := 0.0;
signal out_bps      : real := 0.0;
signal in_rate      : real := 0.0;
signal mid_rate     : real := 0.0;
signal out_rate     : real := 0.0;
signal in_ovr_ok    : std_logic := '0';
signal mid_ovr_ok   : std_logic := '0';
signal reset_p      : std_logic := '1';

begin

-- Clock and reset generation.
inner_clk <= not inner_clk after INNER_PERIOD/2;
outer_clk <= not outer_clk after OUTER_PERIOD/2;

-- Flow control and packet-drop randomization.
p_flow_outer : process(outer_clk)
    constant RESET_DELAY : integer := 63;
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable delay  : integer := RESET_DELAY;
    variable pause  : integer := 0;
begin
    if rising_edge(outer_clk) then
        if (reset_p = '1') then
            -- Short delay to account for reset logic inside first FIFO.
            delay       := RESET_DELAY;
            pause       := 0;
            in_ready    <= '0';
            out_ready   <= '0';
            in_drop_en  <= '0';
        elsif (delay > 0) then
            -- Countdown during startup delay.
            delay       := delay - 1;
            pause       := 0;
            in_ready    <= '0';
            out_ready   <= '0';
            in_drop_en  <= '0';
        else
            -- Normal flow-control randomization.
            uniform(seed1, seed2, rand);
            in_ready <= bool2bit(rand < in_rate);
            uniform(seed1, seed2, rand);
            out_ready <= bool2bit(rand < out_rate);
            if (in_write = '1' and (in_last_com = '1' or in_last_rev = '1')) then
                uniform(seed1, seed2, rand);
                in_drop_en <= bool2bit(rand < revert_rate);
            end if;
            -- At rare intervals, assert "pause" for 100-200 clocks.
            uniform(seed1, seed2, rand);
            if (pause > 0) then
                pause := pause - 1;
            elsif (rand < 0.001) then
                uniform(seed1, seed2, rand);
                pause := 100 + integer(floor(rand * 100.0));
            end if;
        end if;
        out_pause <= bool2bit(pause > 0);
    end if;
end process;

p_flow_inner : process(inner_clk)
    variable seed1  : positive := 5678;
    variable seed2  : positive := 1234;
    variable rand   : real := 0.0;
begin
    if rising_edge(inner_clk) then
        uniform(seed1, seed2, rand);
        mid_ready <= bool2bit(rand < mid_rate);
    end if;
end process;

in_write    <= in_valid and in_ready;
mid_write   <= mid_valid and mid_ready;

-- Safe to enable pre-commit / cut-through mode?
-- (Leave plenty of margin to avoid statistical underflows.)
in_bps      <= OUTER_MAXBPS * in_rate;
mid_bps     <= INNER_MAXBPS * mid_rate;
out_bps     <= OUTER_MAXBPS * out_rate;
mid_precom  <= bool2bit(mid_bps > 2.0*out_bps);

-- Input sequence generation.
p_input : process(outer_clk)
    variable seed1, seed2   : positive := 1;
    variable rand           : real := 0.0;
    variable len, count     : integer := 0;
    variable seed_temp      : integer := 0;
    variable meta           : meta_t := (others => '0');
    variable in_revert      : natural := 0;
    variable in_commit_d    : std_logic := '0';
    variable in_revert_d    : std_logic := '0';
begin
    if rising_edge(outer_clk) then
        -- Check for start of new packet.
        if (reset_p = '1') then
            in_data <= (others => '0');
            len     := 0;
            count   := 0;
            meta    := (others => '0');
        elsif (in_valid = '0' or in_ready = '1') then
            -- Generate next output word...
            if (count >= len) then
                -- First word in each packet is the packet index.
                if (OUTER_BYTES < 4) then
                    seed_temp := in_index mod 2**(8*OUTER_BYTES);
                else
                    seed_temp := in_index;
                end if;
                in_data <= i2s(seed_temp, 8*OUTER_BYTES);
                -- Re-seed PRNG based on packet index.
                seed1 := seed_temp + 1;
                seed2 := 9999 - seed1;
                for n in 1 to 10000 loop
                    uniform(seed1, seed2, rand);
                end loop;
                -- Select packet length/metadata and reset word-count.
                uniform(seed1, seed2, rand);
                len := MIN_PKT_WORDS + integer(floor(
                    rand * real(MAX_PKT_WORDS - MIN_PKT_WORDS)));
                for n in meta'range loop
                    uniform(seed1, seed2, rand);
                    meta(n) := bool2bit(rand < 0.5);
                end loop;
                count := 0;
            else
                -- The rest is random, seeded by packet index.
                for n in in_data'range loop
                    uniform(seed1, seed2, rand);
                    in_data(n) <= bool2bit(rand < 0.5);
                end loop;
                count := count + 1;
            end if;
        end if;

        -- Drive the last-word strobes.
        -- (Metadata is latched concurrently.)
        if (len = 0 or count < len) then
            in_meta     <= (others => 'X');
            in_last_com <= '0';
            in_last_rev <= '0';
        else
            in_meta     <= meta;
            in_last_com <= not in_drop_en;
            in_last_rev <= in_drop_en;
        end if;

        -- Update the cumulative byte-counter.
        if (reset_p = '1') then
            in_xfer <= 0;
        elsif (in_overflow = '1' or in_revert_d = '1') then
            in_xfer <= in_revert + u2i(in_write) * OUTER_BYTES;
        else
            in_xfer <= in_xfer + u2i(in_write) * OUTER_BYTES;
        end if;

        -- Update byte-index of the last accepted frame.
        if (reset_p = '1') then
            in_revert := 0;
        elsif (in_overflow = '0' and in_commit_d = '1') then
            in_revert := in_xfer;
        end if;
        in_commit_d := in_write and in_last_com;
        in_revert_d := in_write and in_last_rev;

        -- Update the packet index.
        if (reset_p = '1') then
            in_index <= 0;
        elsif (in_write = '1' and (in_last_com = '1' or in_last_rev = '1')) then
            in_index <= in_index + 1;
        end if;

        in_valid <= not reset_p;
    end if;
end process;

-- First unit under test.
uut1 : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => OUTER_BYTES,
    OUTPUT_BYTES    => INNER_BYTES,
    BUFFER_KBYTES   => BUFFER_KBYTES,
    META_WIDTH      => META_WIDTH,
    MAX_PACKETS     => MAX_PACKETS,
    MAX_PKT_BYTES   => MAX_PKT_BYTES)
    port map(
    in_clk          => outer_clk,
    in_data         => in_data,
    in_pkt_meta     => in_meta,
    in_last_commit  => in_last_com,
    in_last_revert  => in_last_rev,
    in_write        => in_write,
    in_overflow     => in_overflow,
    in_hfull        => in_hfull,
    out_clk         => inner_clk,
    out_data        => mid_data,
    out_nlast       => mid_nlast,
    out_pkt_meta    => mid_meta,
    out_last        => mid_last,
    out_valid       => mid_valid,
    out_ready       => mid_ready,
    out_overflow    => open,
    reset_p         => reset_p);

-- Count bytes in the middle segment.
p_mid : process(inner_clk)
    variable mid_commit_d : std_logic := '0';
    variable mid_revert   : natural := 0;
begin
    if rising_edge(inner_clk) then
        -- Update cumulative byte-counter.
        if (reset_p = '1') then
            mid_xfer <= 0;
        elsif (mid_overflow = '1') then
            mid_xfer <= mid_revert + u2i(mid_write) * INNER_BYTES;
        else
            mid_xfer <= mid_xfer + u2i(mid_write) * INNER_BYTES;
        end if;

        -- Update byte-index of the last accepted frame.
        if (reset_p = '1') then
            mid_revert := 0;
        elsif (mid_overflow = '0' and mid_commit_d = '1') then
            mid_revert := mid_xfer;
        end if;
        mid_commit_d := mid_write and mid_last;
    end if;
end process;

-- Second unit under test.
uut2 : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INNER_BYTES,
    OUTPUT_BYTES    => OUTER_BYTES,
    BUFFER_KBYTES   => BUFFER_KBYTES,
    META_WIDTH      => META_WIDTH,
    MAX_PACKETS     => MAX_PACKETS,
    MAX_PKT_BYTES   => MAX_PKT_BYTES)
    port map(
    in_clk          => inner_clk,
    in_data         => mid_data,
    in_nlast        => mid_nlast,
    in_pkt_meta     => mid_meta,
    in_precommit    => mid_precom,
    in_last_commit  => mid_last,
    in_last_revert  => '0',
    in_write        => mid_write,
    in_overflow     => mid_overflow,
    out_clk         => outer_clk,
    out_data        => out_data,
    out_pkt_meta    => out_meta,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    out_pause       => out_pause,
    out_overflow    => out_overflow,
    out_hfull       => out_hfull,
    reset_p         => reset_p);

-- Output checking.
p_check : process(outer_clk)
    variable seed1, seed2   : positive := 1;
    variable rand           : real := 0.0;
    variable ref_len, count : integer := 0;
    variable ref_meta       : meta_t := (others => '0');
    variable got_packet     : std_logic := '0';
    variable pause_count    : integer := 0;
begin
    if rising_edge(outer_clk) then
        -- Check each output word as it's received...
        if (reset_p = '1') then
            out_index   <= 0;
            ref_len     := 0;
            count       := 0;
            ref_meta    := (others => '0');
            got_packet  := '0';
        elsif (out_valid = '1' and out_ready = '1') then
            -- Is this the start of a new packet?
            if (got_packet = '0') then
                -- First word in each packet is the packet index.
                out_index <= u2i(out_data);
                -- Re-seed PRNG based on packet index.
                seed1 := u2i(out_data) + 1;
                seed2 := 9999 - seed1;
                for n in 1 to 10000 loop
                    uniform(seed1, seed2, rand);
                end loop;
                -- Predict expected length, metadata, and reset state.
                uniform(seed1, seed2, rand);
                ref_len := MIN_PKT_WORDS + integer(floor(
                    rand * real(MAX_PKT_WORDS - MIN_PKT_WORDS)));
                for n in ref_meta'range loop
                    uniform(seed1, seed2, rand);
                    ref_meta(n) := bool2bit(rand < 0.5);
                end loop;
                got_packet := '1';
                -- Warning if we should be in pause mode.
                -- (Give a little leeway due to final FIFO.)
                assert (pause_count < 40)
                    report "Pause violation: " & integer'image(pause_count) severity error;
            elsif (count <= ref_len) then
                -- Check each expected output word.
                assert (out_data = out_ref)
                    report "Output data mismatch @" & integer'image(out_xfer) severity error;
                assert (out_meta = ref_meta)
                    report "Output metadata mismatch @" & integer'image(out_xfer) severity error;
            else
                report "Output exceeded expected length @" & integer'image(out_xfer) severity error;
            end if;
            -- Confirm "last" flag arrives at expected time.
            if (count = ref_len) then
                assert (out_last = '1')
                    report "Missing out_last strobe @" & integer'image(out_xfer) severity error;
            else
                assert (out_last = '0')
                    report "Unexpected out_last strobe" & integer'image(out_xfer) severity error;
            end if;
            -- Generate the next expected data word.
            for n in out_ref'range loop
                uniform(seed1, seed2, rand);
                out_ref(n) <= bool2bit(rand < 0.5);
            end loop;
            -- Reset after end of packet marker.
            if (out_last = '1') then
                got_packet := '0';
                count := 0;
            else
                count := count + 1;
            end if;
        end if;

        -- Count consecutive cycles that pause has been asserted.
        if (reset_p = '1' or out_pause = '0') then
            pause_count := 0;
        elsif (out_valid = '1' and out_ready = '1') then
            pause_count := pause_count + 1;
        end if;

        -- Count total received words
        if (reset_p = '1') then
            out_total <= 0;
            out_xfer  <= 0;
        elsif (out_valid = '1' and out_ready = '1') then
            out_total <= out_total + 1;
            out_xfer  <= out_xfer + OUTER_BYTES;
        end if;

        -- Check for unexpected overflow flags.
        assert (in_overflow = '0' or in_ovr_ok = '1' or reset_p = '1')
            report "Unexpected 1st input overflow." severity error;
        assert (mid_overflow = '0' or mid_ovr_ok = '1' or reset_p = '1')
            report "Unexpected 2nd input overflow." severity error;
    end if;
end process;

-- Overall test control.
p_test : process
    variable seed1  : positive := 617890;
    variable seed2  : positive := 102835;
    variable rand1, rand2, rand3 : real := 0.0;

    procedure run_test(ri, rm, ro: real) is
        variable bps_in  : real := ri * real(OUTER_BYTES * OUTER_CLOCK_MHZ);
        variable bps_mid : real := rm * real(INNER_BYTES * INNER_CLOCK_MHZ);
        variable bps_out : real := ro * real(OUTER_BYTES * OUTER_CLOCK_MHZ);
        variable bps_net : real := realmin(bps_in, bps_mid);
    begin
        -- Set test conditions.
        report "Starting test #" & integer'image(test_idx+1);
        test_idx <= test_idx + 1;
        in_rate  <= ri;
        mid_rate <= rm;
        out_rate <= ro;

        -- Check if we expect overflows at these rates.
        in_ovr_ok  <= bool2bit(bps_in > 0.85 * bps_mid);
        mid_ovr_ok <= bool2bit(bps_net > 0.85 * bps_out);

        -- Clear FIFO contents.
        reset_p <= '1';
        wait for 1 us;

        -- Allow test to run for one full millisecond.
        reset_p <= '0';
        wait for 999 us;

        -- Sanity check: Must receive at least a few packets.
        assert (out_total > 0)
            report "No data at output." severity error;

        -- Sanity check: "Half-full" indicators for each FIFO.
        if (bps_in > 1.25 * bps_mid) then
            assert (in_hfull = '1')
                report "Missing input half-full." severity error;
        elsif (bps_in < 0.75 * bps_mid) then
            assert (in_hfull = '0')
                report "Unexpected input half-full." severity error;
        end if;

        if (bps_net > 1.25 * bps_out) then
            assert (out_hfull = '1')
                report "Missing output half-full." severity error;
        elsif (bps_net < 0.75 * bps_out) then
            assert (out_hfull = '0')
                report "Unexpected output half-full." severity error;
        end if;
    end procedure;
begin
    -- Cover various corner cases.
    run_test(1.0, 0.2, 0.2);
    run_test(0.2, 1.0, 0.2);
    run_test(0.2, 0.2, 1.0);

    -- Keep running forever with randomized parameters.
    loop
        uniform(seed1, seed2, rand1);
        rand1 := 0.1 + 0.9 * rand1;
        uniform(seed1, seed2, rand2);
        rand2 := 0.1 + 0.9 * rand2;
        uniform(seed1, seed2, rand3);
        rand3 := 0.1 + 0.9 * rand3;
        run_test(rand1, rand2, rand3);
    end loop;
end process;

end single;



---------------------------------------------------------------------
----------------------------- TOP LEVEL TESTBENCH -------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity fifo_packet_tb is
    -- Unit testbench top level, no I/O ports
end fifo_packet_tb;

architecture tb of fifo_packet_tb is

begin

-- Instantiate each test configuration.
u1 : entity work.fifo_packet_tb_single
    generic map(
    OUTER_BYTES     => 1,
    INNER_BYTES     => 1,
    META_WIDTH      => 8,
    OUTER_CLOCK_MHZ => 50,
    INNER_CLOCK_MHZ => 50,
    BUFFER_KBYTES   => 2);

u2 : entity work.fifo_packet_tb_single
    generic map(
    OUTER_BYTES     => 1,
    INNER_BYTES     => 4,
    OUTER_CLOCK_MHZ => 50,
    INNER_CLOCK_MHZ => 125,
    BUFFER_KBYTES   => 2);

u3 : entity work.fifo_packet_tb_single
    generic map(
    OUTER_BYTES     => 2,
    INNER_BYTES     => 1,
    OUTER_CLOCK_MHZ => 50,
    INNER_CLOCK_MHZ => 50,
    BUFFER_KBYTES   => 2);

u4 : entity work.fifo_packet_tb_single
    generic map(
    OUTER_BYTES     => 4,
    INNER_BYTES     => 2,
    OUTER_CLOCK_MHZ => 99,
    INNER_CLOCK_MHZ => 100,
    BUFFER_KBYTES   => 4);

end tb;
