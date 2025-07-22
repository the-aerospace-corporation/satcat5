--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Queue-depth estimation
--
-- This block accepts the raw queue depth (i.e., "in_pct_full") of a given
-- queue, then performs various time-averaging and windowing operations to
-- produce a more stable indicator of the sustained congestion severity.
-- The result is a useful input for AQM, ECN, and RED algorithms.
--
-- The estimation algorithm is as follows:
--  * For each fixed time window, calculate the minimum depth.
--    (Default T0 = 10 msec.)
--  * Exponential time-averaging of the intermediate output.
--    (Default T1 = 40 msec, or T1 <= 0 to skip this step.)
--
-- New algorithms and configuration options may be added in future updates.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.round;
use     work.common_functions.all;

entity router2_qdepth is
    generic (
    REFCLK_HZ   : positive;         -- Reference clock rate (Hz)
    T0_MSEC     : real := 10.0;     -- Time window for minimum
    T1_MSEC     : real := 40.0;     -- Time constant for averaging
    SUB_LSB     : boolean := true); -- Enable sub-LSB accumulators?
    port (
    in_qdepth   : in  unsigned(7 downto 0);
    out_qdepth  : out unsigned(7 downto 0);
    out_enable  : in  std_logic := '1';
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_qdepth;

architecture router2_qdepth of router2_qdepth is

-- Additional LSBs for fixed-point arithmetic.
constant SHIFT : positive := 8;

-- Enable the averaging stage?
constant AVG_ENABLE : boolean := (T1_MSEC > 2.0 * T0_MSEC);

-- Filter state.
signal min_write    : std_logic := '0';
signal min_qdepth   : unsigned(7 downto 0) := (others => '0');
signal min_scale    : unsigned(15 downto 0) := (others => '0');
signal avg_accum    : unsigned(15 downto 0) := (others => '0');
signal out_mask     : unsigned(7 downto 0);

begin

-- Minimum over each time window.
p_min : process(clk)
    constant CLKDIV : positive := integer(round(0.001 * T0_MSEC * real(REFCLK_HZ)));
    constant CLKMAX : natural := CLKDIV - 1;
    variable count : integer range 0 to CLKMAX := CLKMAX;
begin
    if rising_edge(clk) then
        -- Running minimum over each time window.
        if (reset_p = '1' or min_write = '1' or in_qdepth < min_qdepth) then
            min_qdepth <= in_qdepth;
        end if;

        -- End-of-window strobe every CLKDIV clock cycles.
        min_write <= bool2bit(count = 0);
        if (reset_p = '1' or count = 0) then
            count := CLKMAX;
        else
            count := count - 1;
        end if;
    end if;
end process;

-- Prescale the minimum to match the accumulator.
min_scale <= shift_left(resize(min_qdepth, min_scale'length), SHIFT);

-- Secondary output stage...
gen_avg1 : if AVG_ENABLE generate
    -- Exponential time-averaging.
    p_avg : process(clk)
        constant SCALE : signed := R2S(real(2**SHIFT) * T0_MSEC / T1_MSEC, SHIFT);
        variable diff : signed(SHIFT+16 downto 0) := (others => '0');
        variable dlsb : unsigned(SHIFT-1 downto 0) := (others => '0');
    begin
        if rising_edge(clk) then
            -- Pipeline stage 2: Accumulate the weighted differences.
            -- Optional sub-LSB accumulator prevents loss-of-precision.
            diff := diff + signed(resize(dlsb, diff'length));
            if (reset_p = '1') then
                avg_accum <= (others => '0');
            else
                avg_accum <= avg_accum + unsigned(resize(shift_right(diff, SHIFT), avg_accum'length));
            end if;

            -- Enable the fractional-LSB accumulator?
            if (reset_p = '1' or not SUB_LSB) then
                dlsb := (others => '0');
            else
                dlsb := unsigned(diff(SHIFT-1 downto 0));
            end if;

            -- Pipeline stage 1: Weighted difference between input and average.
            if (min_write = '1') then
                diff := extend_sub(min_scale, avg_accum) * SCALE;
            else
                diff := (others => '0');
            end if;
        end if;
    end process;
end generate;

gen_avg0 : if not AVG_ENABLE generate
    -- No averaging, simply latch value at the end of each window.
    p_avg : process(clk)
    begin
        if rising_edge(clk) then
            if (reset_p = '1') then
                avg_accum <= (others => '0');
            elsif (min_write = '1') then
                avg_accum <= min_scale;
            end if;
        end if;
    end process;
end generate;

-- Drive the final output.
out_mask   <= (others => out_enable);
out_qdepth <= avg_accum(avg_accum'left downto SHIFT) and out_mask;

end router2_qdepth;
