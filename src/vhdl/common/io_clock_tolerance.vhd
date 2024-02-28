--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock frequency-tolerance tester
--
-- This module accepts two input clocks: a known-good reference and a
-- test clock that may be running erratically, intermittently, or with
-- degraded accuracy. By counting cycles of the test clock over a known
-- interval, this block can report whether the test clock is running
-- at the expected frequency with a designated tolerance.
--
-- This block is a more precise test than the simpler "io_clock_detect"
-- block, which merely checks whether the test clock is running at all.
--
-- The test begins when "ref_reset_p" is released, continues for the
-- specified duration, then asserts "out_done" and the pass/fail flag.
-- All output signals operate in the "ref_clk" domain.
--
-- Note: For best results, ensure that:
--  TST_CLK_HZ * LEN_MSEC * TOL_PPM > 1e11
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.common_primitives.sync_reset;

entity io_clock_tolerance is
    generic (
    REF_CLK_HZ  : positive;             -- Frequency of ref_clk
    TST_CLK_HZ  : positive;             -- Frequency of tst_clk
    LEN_MSEC    : positive := 1;        -- Test duration (msec)
    TOL_PPM     : positive := 1000);    -- Max error tolerance
    port (
    reset_p     : in  std_logic;        -- Reset / start of test
    ref_clk     : in  std_logic;        -- Known-good reference clock
    tst_clk     : in  std_logic;        -- Clock under test
    out_pass    : out std_logic;        -- Test pass/fail
    out_done    : out std_logic;        -- Test completed
    out_wait    : out std_logic);       -- Inverse of out_done
end io_clock_tolerance;

architecture io_clock_tolerance of io_clock_tolerance is

-- Calculate the duration while avoiding overflow.
function get_count(clk_hz: positive; ppm: integer) return positive is
    constant scale : real := real(1_000_000 + ppm) / real(1_000_000_000);
begin
    return positive(real(clk_hz) * real(LEN_MSEC) * scale);
end function;

-- Calculate nominal/min/max test duration in various clock domains.
constant COUNT_REF  : positive := get_count(REF_CLK_HZ, 0);
constant COUNT_TMIN : positive := get_count(TST_CLK_HZ, -TOL_PPM);
constant COUNT_TMAX : positive := get_count(TST_CLK_HZ, TOL_PPM);

-- Set counter width to allow significant variation in frequency.
constant COUNT_BITS : positive := 1 + log2_ceil(COUNT_TMAX);

-- Control delay includes main test run plus settling time.
constant DELAY_WAIT : positive := 32;
constant DELAY_MAX  : positive := COUNT_REF + DELAY_WAIT;

-- Signals in the reference clock domain:
signal ref_count    : integer range 0 to DELAY_MAX := DELAY_MAX;
signal ref_reset_p  : std_logic;
signal ref_lo       : std_logic := '0';
signal ref_hi       : std_logic := '0';
signal ref_run      : std_logic := '0';
signal ref_done     : std_logic := '0';
signal ref_pass     : std_logic := '0';

-- Signals in the test clock domain:
signal tst_count    : unsigned(COUNT_BITS-1 downto 0) := (others => '0');
signal tst_run      : std_logic := '0';
signal tst_run_d    : std_logic := '0';

begin

-- Sanity-check on requested frequency tolerance.
assert (COUNT_TMAX >= COUNT_TMIN + 100)
    report "Test duration is too short for requested accuracy." severity warning;

-- Drive top-level outputs.
out_pass <= ref_pass;
out_done <= ref_done;
out_wait <= not ref_done;

-- Synchronize the reset signal.
u_reset : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => ref_reset_p,
    out_clk     => ref_clk);

-- Control state machine operates in the ref_clk domain:
--  * Wait for release of upstream reset.
--  * Assert "ref_run" and count down from COUNT_REF.
--  * Wait a few cycles for cross-clock signals to settle.
--  * Assert "ref_done" and inspect counter value.
p_control : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        -- Simple countdown.
        if (ref_reset_p = '1') then
            ref_count <= DELAY_MAX;
        elsif (ref_count > 0) then
            ref_count <= ref_count - 1;
        end if;

        -- Drive the "run", "done", and "pass" strobes.
        -- Freeze all outputs once "done" is asserted.
        if (ref_reset_p = '1') then
            ref_run  <= '0';
            ref_done <= '0';
            ref_pass <= '0';
        elsif (ref_done = '0') then
            ref_run  <= bool2bit(ref_count >= DELAY_WAIT);
            ref_done <= bool2bit(ref_count = 0);
            ref_pass <= bool2bit(ref_count = 0) and ref_lo and ref_hi;
        end if;

        -- Compare test-clock counter to min/max thresholds.
        -- (Trustworthy once cross-clock signals are stable.)
        ref_lo <= bool2bit(tst_count >= COUNT_TMIN);
        ref_hi <= bool2bit(tst_count <= COUNT_TMAX);
    end if;
end process;

-- Clock-domain transition.
u_run : sync_buffer
    port map(
    in_flag     => ref_run,
    out_flag    => tst_run,
    out_clk     => tst_clk);

-- Counter state machine operates in the tst_clk domain:
--  * Rising edge of "tst_run" resets counter.
--  * Increment counter as long as "tst_run_d" is asserted.
--  * Hold the counter stable for cross-clock transition.
p_count : process(tst_clk)
begin
    if rising_edge(tst_clk) then
        if (tst_run_d = '0' and tst_run = '1') then
            tst_count <= (others => '0');
        elsif (tst_run_d = '1') then
            tst_count <= tst_count + 1;
        end if;
        tst_run_d <= tst_run;
    end if;
end process;

end io_clock_tolerance;
