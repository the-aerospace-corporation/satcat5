--------------------------------------------------------------------------
-- Copyright 2020, 2021, 2023 The Aerospace Corporation
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
-- Testbench for the asynchronous priority FIFO
--
-- This testbench verifies correct operation of the priority FIFO under
-- a variety of flow-control conditions.  To simplify the tests, it does
-- not cover cases that are already well-covered by "fifo_packet_tb",
-- such as packet-drop on overflow.
--
-- The test sequence takes 6.1 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity fifo_priority_tb is
    generic (
    INPUT_BYTES     : positive := 1;
    OUTPUT_BYTES    : positive := 1;
    BUFF_HI_KBYTES  : positive := 1;
    BUFF_LO_KBYTES  : positive := 1;
    BUFF_FAILOVER   : boolean := true;
    MAX_PACKETS     : positive := 64;
    MIN_PKT_BYTES   : positive := 1;
    MAX_PKT_BYTES   : positive := 64);
    -- No I/O ports
end fifo_priority_tb;

architecture tb of fifo_priority_tb is

-- Define convenience types
subtype in_nlast_t is integer range 0 to INPUT_BYTES;
subtype in_word_t is std_logic_vector(8*INPUT_BYTES-1 downto 0);
subtype out_word_t is std_logic_vector(8*OUTPUT_BYTES-1 downto 0);

-- Calculate maximum data-rate of input and output streams.
constant INPUT_MAXBPS   : real := real(8*INPUT_BYTES) * real(100_000_000);
constant OUTPUT_MAXBPS  : real := real(8*INPUT_BYTES) * real(104_000_000);

-- Shared PRNG functions
constant INIT_SEED1_A   : positive := 15871507;
constant INIT_SEED2_A   : positive := 51708945;
constant INIT_SEED1_B   : positive := 83217413;
constant INIT_SEED2_B   : positive := 68710730;

procedure rand_len(
    variable seed1, seed2   : inout positive;
    variable bcount         : inout natural)
is
    constant DELTA : natural := MAX_PKT_BYTES - MIN_PKT_BYTES;
    variable rand : real;
begin
    uniform(seed1, seed2, rand);
    bcount := MIN_PKT_BYTES + integer(floor(rand * real(DELTA)));
end procedure;

procedure rand_byte(
    variable seed1, seed2   : inout positive;
    variable bcount         : inout natural;
    variable result         : inout out_word_t)
is
    variable rand : real;
begin
    if (bcount > 0) then
        bcount := bcount - 1;
        for n in result'range loop
            uniform(seed1, seed2, rand);
            result(n) := bool2bit(rand < 0.5);
        end loop;
    else
        result := (others => '0');
    end if;
end procedure;

-- Convert remaining-bytes counter to NLAST field.
function get_nlast(rem_bytes : natural) return in_nlast_t is
begin
    if (rem_bytes > INPUT_BYTES) then
        return 0;           -- Frame continues...
    else
        return rem_bytes;   -- End-of-frame at Nth byte.
    end if;
end function;

-- Clock and reset
signal in_clk       : std_logic := '0';
signal out_clk      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Raw and reference streams
signal raw0_data    : in_word_t := (others => '0');
signal raw0_nlast   : in_nlast_t := 0;
signal raw0_ready   : std_logic := '0';
signal raw1_data    : in_word_t := (others => '0');
signal raw1_nlast   : in_nlast_t := 0;
signal raw1_ready   : std_logic := '0';
signal ref0_data    : out_word_t := (others => '0');
signal ref0_last    : std_logic := '0';
signal ref0_ready   : std_logic := '0';
signal ref1_data    : out_word_t := (others => '0');
signal ref1_last    : std_logic := '0';
signal ref1_ready   : std_logic := '0';

-- Combined input stream
signal in_data      : in_word_t := (others => '0');
signal in_nlast     : in_nlast_t := 0;
signal in_hipri     : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_precommit : std_logic;

-- Unit under test
signal in_overflow  : std_logic;
signal out_data     : out_word_t;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_hipri    : std_logic;
signal out_rcvd     : natural := 0;

-- High-level test control
signal test_index   : integer := 0;
signal hi_frac      : real := 0.0;
signal in_rate      : real := 0.0;
signal out_rate     : real := 0.0;
signal expect_ovr   : std_logic := '0';

begin

-- Clock and reset.
in_clk  <= not in_clk after 5.0 ns;     -- 1 / (2*5.0 ns) = 100 MHz
out_clk <= not out_clk after 4.8 ns;    -- 1 / (2*4.8 ns) = 104 MHz

-- Raw and reference streams:
-- Generate Raw0/Ref0 and Raw1/Ref1 as mirror-images of each other.
p_raw : process(in_clk)
    variable temp_byte : out_word_t;
    variable raw0_count, raw1_count : natural := 0;
    variable raw0_seed1, raw1_seed1 : positive := 1;
    variable raw0_seed2, raw1_seed2 : positive := 1;
begin
    if rising_edge(in_clk) then
        -- On reset, resync all the initial seeds.
        if (reset_p = '1') then
            raw0_count  := 0;
            raw1_count  := 0;
            raw0_seed1  := INIT_SEED1_A;
            raw0_seed2  := INIT_SEED2_A;
            raw1_seed1  := INIT_SEED1_B;
            raw1_seed2  := INIT_SEED2_B;
        end if;

        -- If we've reached end-of-packet, randomize new length.
        if (raw0_count = 0) then
            rand_len(raw0_seed1, raw0_seed2, raw0_count);
        end if;
        if (raw1_count = 0) then
            rand_len(raw1_seed1, raw1_seed2, raw1_count);
        end if;

        -- On demand, generate new bytes.
        if (reset_p = '1' or raw0_ready = '1') then
            raw0_nlast <= get_nlast(raw0_count);
            for n in INPUT_BYTES-1 downto 0 loop    -- MSB-first
                rand_byte(raw0_seed1, raw0_seed2, raw0_count, temp_byte);
                raw0_data(8*n+7 downto 8*n) <= temp_byte;
            end loop;
        end if;
        if (reset_p = '1' or raw1_ready = '1') then
            raw1_nlast <= get_nlast(raw1_count);
            for n in INPUT_BYTES-1 downto 0 loop    -- MSB-first
                rand_byte(raw1_seed1, raw1_seed2, raw1_count, temp_byte);
                raw1_data(8*n+7 downto 8*n) <= temp_byte;
            end loop;
        end if;
    end if;
end process;

p_ref : process(out_clk)
    variable temp_byte : out_word_t;
    variable ref0_count, ref1_count : natural := 0;
    variable ref0_seed1, ref1_seed1 : positive := 1;
    variable ref0_seed2, ref1_seed2 : positive := 1;
begin
    if rising_edge(out_clk) then
        -- On reset, resync all the initial seeds.
        if (reset_p = '1') then
            ref0_count  := 0;
            ref1_count  := 0;
            ref0_seed1  := INIT_SEED1_A;
            ref0_seed2  := INIT_SEED2_A;
            ref1_seed1  := INIT_SEED1_B;
            ref1_seed2  := INIT_SEED2_B;
        end if;

        -- If we've reached end-of-packet, randomize new length.
        if (ref0_count = 0) then
            rand_len(ref0_seed1, ref0_seed2, ref0_count);
        end if;
        if (ref1_count = 0) then
            rand_len(ref1_seed1, ref1_seed2, ref1_count);
        end if;

        -- On demand, generate new bytes.
        if (reset_p = '1' or ref0_ready = '1') then
            for n in OUTPUT_BYTES-1 downto 0 loop   -- MSB-first
                rand_byte(ref0_seed1, ref0_seed2, ref0_count, temp_byte);
                ref0_data(8*n+7 downto 8*n) <= temp_byte;
            end loop;
            ref0_last <= bool2bit(ref0_count = 0);
        end if;
        if (reset_p = '1' or ref1_ready = '1') then
            for n in OUTPUT_BYTES-1 downto 0 loop   -- MSB-first
                rand_byte(ref1_seed1, ref1_seed2, ref1_count, temp_byte);
                ref1_data(8*n+7 downto 8*n) <= temp_byte;
            end loop;
            ref1_last <= bool2bit(ref1_count = 0);
        end if;
    end if;
end process;

-- Combined input stream:
p_input : process(in_clk)
    variable seed1  : positive := 575166810;
    variable seed2  : positive := 216546471;
    variable rand   : real := 0.0;
    variable hipri  : std_logic := '0';
begin
    if rising_edge(in_clk) then
        -- Copy selected input.
        if (raw0_ready = '1') then
            in_data     <= raw0_data;
            in_nlast    <= raw0_nlast;
            in_hipri    <= '0';
            in_write    <= '1';
        elsif (raw1_ready = '1') then
            in_data     <= raw1_data;
            in_nlast    <= raw1_nlast;
            in_hipri    <= '1';
            in_write    <= '1';
        else
            in_data     <= (others => '0');
            in_nlast    <= 0;
            in_write    <= '0';
        end if;

        -- Randomize hi/lo sources between packets.
        if ((raw0_nlast > 0 and raw0_ready = '1') or
            (raw1_nlast > 0 and raw1_ready = '1') or
            (reset_p = '1')) then
            uniform(seed1, seed2, rand);
            hipri := bool2bit(rand < hi_frac);
        end if;

        -- Randomize input flow-control.
        uniform(seed1, seed2, rand);
        raw0_ready <= bool2bit(rand < in_rate and hipri = '0' and reset_p = '0');
        raw1_ready <= bool2bit(rand < in_rate and hipri = '1' and reset_p = '0');

        -- Sanity-check: Input should only overflow during specific tests.
        assert (in_overflow = '0' or expect_ovr = '1')
            report "Unexpected FIFO overflow." severity error;
    end if;
end process;

-- Safe to enable pre-commit / cut-through mode?
in_precommit <= bool2bit(in_rate * INPUT_MAXBPS >= 2.0 * out_rate * OUTPUT_MAXBPS);

-- Unit under test.
uut : entity work.fifo_priority
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    BUFF_HI_KBYTES  => BUFF_HI_KBYTES,
    BUFF_LO_KBYTES  => BUFF_LO_KBYTES,
    BUFF_FAILOVER   => BUFF_FAILOVER,
    MAX_PACKETS     => MAX_PACKETS,
    MAX_PKT_BYTES   => MAX_PKT_BYTES)
    port map(
    in_clk          => in_clk,
    in_data         => in_data,
    in_nlast        => in_nlast,
    in_precommit    => in_precommit,
    in_last_keep    => '1',     -- Not tested
    in_last_hipri   => in_hipri,
    in_write        => in_write,
    in_overflow     => in_overflow,
    out_clk         => out_clk,
    out_data        => out_data,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    out_hipri       => out_hipri,
    async_pause     => '0',     -- Not tested
    reset_p         => reset_p);

-- Output checking.
-- Note: Overflow / failover may cause outputs to be received out-of-order.
--       e.g., Nearly-full FIFO may cause failover of a long packet but
--       later accept a shorter packet.  We simply stop checking data after
--       we reach the earliest possible failover point.
ref0_ready <= out_valid and out_ready and bool2bit(out_hipri = '0');
ref1_ready <= out_valid and out_ready and bool2bit(out_hipri = '1');

p_output : process(out_clk)
    constant OVR_THRESH : integer := 1024 * BUFF_HI_KBYTES - MAX_PKT_BYTES;
    variable check  : std_logic := '0';
    variable seed1  : positive := 879165462;
    variable seed2  : positive := 984346546;
    variable rand   : real := 0.0;
    variable prevhi : std_logic := '0';
    variable newfrm : std_logic := '1';
begin
    if rising_edge(out_clk) then
        -- Count received bytes since start of test.
        if (reset_p = '1') then
            out_rcvd <= 0;
        elsif (out_valid = '1' and out_ready = '1') then
            out_rcvd <= out_rcvd + 1;
        end if;

        -- Continue checking output stream? (See note above).
        if (expect_ovr = '0') then
            check := '1';
        else
            check := bool2bit(out_rcvd < OVR_THRESH);
        end if;

        -- Check each output word...
        if (reset_p = '1') then
            -- Reset -> Next output is start of frame.
            newfrm := '1';
        elsif (out_valid = '1' and out_ready = '1' and check = '1') then
            -- Confirm stream only changes at end-of-frame.
            assert (newfrm = '1' or out_hipri = prevhi)
                report "Unexpected stream change!" severity error;
            newfrm := out_last;
            prevhi := out_hipri;
            -- Check each output byte against the selected reference.
            if (out_hipri = '0') then   -- Stream 0
                assert (out_data = ref0_data and out_last = ref0_last)
                    report "Strm0 mismatch!" severity error;
            else                        -- Stream 1
                assert (out_data = ref1_data and out_last = ref1_last)
                    report "Strm1 mismatch!" severity error;
            end if;
        end if;

        -- Randomize output flow control.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < out_rate);
    end if;
end process;

-- High-level test control
p_test : process
    -- Generic start-of-test setup.
    procedure test_start(rf:real; ovr:std_logic) is
    begin
        -- Brief reset at the start of each test.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        expect_ovr  <= ovr;
        reset_p     <= '1';
        hi_frac     <= rf;
        in_rate     <= 0.0;
        out_rate    <= 0.0;
        wait for 1 us;
        reset_p     <= '0';
        wait for 1 us;
    end procedure;

    -- Calculate effective buffer size for the "run_ovr" test, in bytes.
    function effective_buffer return positive is
    begin
        if BUFF_FAILOVER then
            return 1024 * (BUFF_HI_KBYTES + BUFF_LO_KBYTES);
        else
            return 1024 * BUFF_LO_KBYTES;
        end if;
    end function;

    -- Special test for overflow failover:
    --  Hi-priority should failover to lo-priority, then overflow.
    procedure run_ovr is
        constant EXPECTED   : positive := effective_buffer / INPUT_BYTES;
        variable elapsed    : natural := 0;
    begin
        -- Pre-test reset.
        test_start(1.0, '1');

        -- Halt the output and run hi-priority input until we overflow.
        in_rate <= 1.0;
        while (in_overflow = '0' and elapsed < 3*EXPECTED) loop
            wait until rising_edge(in_clk);
            elapsed := elapsed + 1;
        end loop;
        in_rate <= 0.0;

        -- Compare elapsed time to expected total.
        assert (3*EXPECTED < 4*elapsed and 4*elapsed < 5*EXPECTED)
            report "Mismatched time to overflow @" &
                integer'image(elapsed) & " / " & integer'image(EXPECTED)
            severity error;

        -- Flush output and confirm contents.
        out_rate <= 1.0;
        wait until falling_edge(out_valid);
        wait for 1 us;
    end procedure;

    -- General purpose test with specified conditions:
    --  high-priority fraction (rf), input rate (ri), and output rate (ro)
    procedure run_one(rf, ri, ro : real) is
    begin
        -- Pre-test reset.
        test_start(rf, '0');

        -- Sanity-check flow-control conditions.
        -- (This test can't recover from overflow conditions.)
        assert (ri < 0.85 * ro)
            report "Potential overflow" severity warning;

        -- Start inputs and let the test run.
        in_rate  <= ri;
        out_rate <= ro;
        wait for 1 ms;
    end procedure;
begin
    run_ovr;
    run_one(0.5, 0.1, 1.0);
    run_one(0.2, 0.8, 1.0);
    run_one(0.8, 0.8, 1.0);
    run_one(0.8, 0.4, 0.5);
    run_one(0.5, 0.4, 0.5);
    run_one(0.2, 0.4, 0.5);
    report "All tests completed!";
    wait;
end process;

end tb;
