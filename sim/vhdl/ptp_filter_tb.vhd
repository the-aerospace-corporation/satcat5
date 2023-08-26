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
-- Testbench for the PTP secondary filter
--
-- This unit test connects the secondary filter to a simulated timestamp
-- counter, with added noise and randomized phase and frequency offsets.
-- The result should track the ideal sequence with sub-LSB precision.
--
-- The complete test takes 4.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_filter_tb is
    generic (
    LOOP_TAU    : real := 3000.0;
    USER_CLK_HZ : positive := 125_000_000);
end ptp_filter_tb;

architecture tb of ptp_filter_tb is

-- Clock generation.
constant USER_TCLK  : time := 500_000_000 ns / USER_CLK_HZ;
constant USER_INCR  : real := real(2**TSTAMP_SCALE) * real(1e9) / real(USER_CLK_HZ);
signal user_clk     : std_logic := '0';

-- Unit under test.
signal ref_tstamp   : tstamp_t := (others => '0');
signal in_locked    : std_logic := '0';
signal in_noise     : tstamp_t := (others => '0');
signal in_tstamp    : tstamp_t;
signal out_tstamp   : tstamp_t;
signal out_delta    : tstamp_t;

-- High-level control.
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal test_noise   : real := 0.0;
signal test_thresh  : integer := 0;
signal test_check   : std_logic := '0';
signal test_run     : std_logic := '0';

begin

-- Clock generation.
user_clk <= not user_clk after USER_TCLK;

-- Input and reference signals.
p_input : process(user_clk)
    variable seed1 : positive := 123456;
    variable seed2 : positive := 789012;
    variable rand  : real := 0.0;
    variable accum : real := 0.0;
    variable noise_tmp : integer := 0;
    variable lock_ctr  : natural := 0;
begin
    if rising_edge(user_clk) then
        -- Countdown from rising edgte of "run" to rising edge of "lock.
        if (test_run = '0') then
            lock_ctr := 10;
        elsif (lock_ctr > 0) then
            lock_ctr := lock_ctr - 1;
        end if;
        in_locked <= bool2bit(lock_ctr = 0);

        -- Generate the ideal timestamp reference.
        if (test_run = '0') then
            -- Randomize initial phase.
            accum := 0.0;
            for n in ref_tstamp'range loop
                uniform(seed1, seed2, rand);
                ref_tstamp(n) <= bool2bit(rand < 0.5);
            end loop;
        else
            -- Increment phase, including sub-LSB accumulator.
            accum := accum + test_rate;
            ref_tstamp <= ref_tstamp + integer(floor(accum));
            accum := accum mod 1.0;
        end if;

        -- Generate uniform-distributed noise over +/-X LSBs.
        uniform(seed1, seed2, rand);
        noise_tmp := integer(round(2.0 * test_noise * (rand - 0.5)));
        in_noise <= unsigned(to_signed(noise_tmp, TSTAMP_WIDTH));
    end if;
end process;


-- Unit under test.
in_tstamp <= ref_tstamp + in_noise;
out_delta <= unsigned(abs(signed(out_tstamp - ref_tstamp)));

uut : entity work.ptp_filter
    generic map(
    LOOP_TAU    => LOOP_TAU,
    USER_CLK_HZ => USER_CLK_HZ)
    port map(
    in_locked   => in_locked,
    in_tstamp   => in_tstamp,
    out_tstamp  => out_tstamp,
    user_clk    => user_clk);

-- Check output against reference.
p_check : process(user_clk)
begin
    if rising_edge(user_clk) then
        if (test_check = '1') then
            assert (out_delta <= test_thresh) report "Output mismatch: "
                & integer'image(to_integer(out_delta));
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure run_test(offset_ppm, noise_lsb: real; thresh_lsb: positive) is
    begin
        -- Set test conditions.
        report "Starting test #" & integer'image(test_index+1);
        test_rate   <= USER_INCR * (1.0 + 0.000001 * offset_ppm);
        test_noise  <= noise_lsb;
        test_thresh <= thresh_lsb;
        test_check  <= '0';
        test_run    <= '0';
        test_index  <= test_index + 1;
        -- Begin test after a fixed delay.
        wait for 1 us;
        test_run    <= '1';
        -- Allow time to converge...
        wait for 990 us;
        -- Inspect output until end of test.
        test_check  <= '1';
        wait for 9 us;
        test_run    <= '0';
        test_check  <= '0';
    end procedure;
begin
    run_test(  0.0,   0.0,  2);
    run_test( 10.0,  10.0,  2);
    run_test( 20.0,  30.0,  2);
    run_test(-42.0, 100.0,  3);
    report("All tests completed!");
    wait;
end process;

end tb;
