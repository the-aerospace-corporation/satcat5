--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PTP cross-clock counter system (gen + sync)
--
-- This unit test connects a Vernier-clock counter-generator to a counter-
-- synchronizer, runs for a few milliseconds, and confirms that the result
-- converges with sub-nanosecond accuracy.
--
-- Note: If you encounter a SIGFPE "Floating point exception" when running
-- this testbench, set simulation timestep to 1 picosecond or finer.
--  * In Modelsim: "vsim ptp_counter_tb -t ps"
--
-- The complete test takes 40 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity ptp_counter_tb_single is
    generic (
    VREF_HZ     : positive;
    USER_HZ     : positive;
    USER_PPM    : integer;
    FILTER_EN   : boolean := false);
end ptp_counter_tb_single;

architecture single of ptp_counter_tb_single is

-- Vernier clock parameters:
--  * Calculate picosecond increment first, with rounding.
--    (This is the *actual* frequency due to simulation constraints.)
--  * Recalculate apparent frequency to minimize cumulative error.
constant VNOMINAL   : vernier_config := create_vernier_config(VREF_HZ);
constant VCLKA_PSI  : positive := integer(round(0.5e12 / VNOMINAL.vclka_hz));
constant VCLKB_PSI  : positive := integer(round(0.5e12 / VNOMINAL.vclkb_hz));
constant VCLKA_HZ   : real := 0.5e12 / real(VCLKA_PSI);
constant VCLKB_HZ   : real := 0.5e12 / real(VCLKB_PSI);
constant VACTUAL    : vernier_config :=
    (VREF_HZ, VCLKA_HZ, VCLKB_HZ, 4.0, FILTER_EN, true, (others => 0.0));

-- Offset actual user clock from the nominal rate.
-- As above, recalculate the apparent frequency to match simulation constraints.
constant USER_RATIO : real := 1.0 + real(USER_PPM) * 1.0e-6;
constant USER_REF   : tfreq_t := tfreq_mult(TFREQ_FAST_1PPM, USER_PPM);
constant USER_HZO   : real := real(USER_HZ) * USER_RATIO;
constant USER_PSI   : positive := integer(round(0.5e12 / USER_HZO));
constant USER_HZA   : real := 0.5e12 / real(USER_PSI);

-- Finally, recalculate the nominal frequency to achieve requested offset.
-- (Otherwise, the previous step may introduce 100+ ppm of unrequested error.)
constant USER_HZN   : positive := integer(round(USER_HZA / USER_RATIO));

-- Clock and reset generation.
signal uclk         : std_logic := '0';
signal vclka        : std_logic := '0';
signal vclkb        : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Units under test.
signal ref_time     : port_timeref;
signal ref_tstamp   : tstamp_t := (others => '0');
signal ref_simtime  : integer := 0;
signal sync_time    : tstamp_t;
signal sync_freq    : tfreq_t;
signal sync_lock    : std_logic;

-- Test measurement and control.
signal sync_ref     : tstamp_t := (others => '0');
signal sync_check   : std_logic := '0';
signal sync_delta   : real := 0.0;
signal sync_dfreq   : real := 0.0;
signal delta_mean   : real := 0.0;
signal delta_std    : real := 0.0;

begin

-- Vernier clock generation
uclk  <= not uclk after USER_PSI * 1 ps;
vclka <= not vclka after VCLKA_PSI * 1 ps;
vclkb <= not vclkb after VCLKB_PSI * 1 ps;

-- Unit under test: Generator
uut_gen : entity work.ptp_counter_gen
    generic map(VCONFIG => VACTUAL)
    port map(
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => reset_p,
    ref_time    => ref_time);

-- Note reference time for later comparison.
p_ref : process(ref_time.vclka)
    constant ONE_CYCLE : tstamp_t := get_tstamp_incr(VCLKA_HZ);
begin
    if rising_edge(ref_time.vclka) then
        assert (1 ps > 0 ps)
            report "Insufficient time resolution. Decrease simulation timestep to 1 ps."
            severity failure;
        if (ref_time.tnext = '1') then
            ref_tstamp  <= ref_time.tstamp + ONE_CYCLE + ONE_CYCLE;
            ref_simtime <= integer(now / 1 ps);
        end if;
    end if;
end process;

-- Unit under test: Synchronizer
uut_sync : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VACTUAL,
    USER_CLK_HZ => USER_HZN,
    LOCK_SETTLE => 3.0,
    WAIT_LOCKED => false)
    port map(
    ref_time    => ref_time,
    user_clk    => uclk,
    user_ctr    => sync_time,
    user_freq   => sync_freq,
    user_lock   => sync_lock,
    user_rst_p  => reset_p);

-- Measure error in synchronized counter (UCLK domain).
p_user : process(uclk)
    constant TOL_NSEC : real := 0.3;
    variable delta_ns, sumdd, sumsq, count : real := 0.0;
    variable cooldown, coolfreq : natural := 0;
begin
    if rising_edge(uclk) then
        -- Synthesize current time from reference.
        -- (Always compute time-difference from "now" to prevent overflows.)
        delta_ns    := 0.001 * real(integer(now / 1 ps) - ref_simtime);
        sync_ref    <= ref_tstamp + get_tstamp_nsec(delta_ns);

        -- Calculate difference and convert to nanoseconds.
        sync_delta  <= get_time_nsec(sync_time - sync_ref);
        sync_dfreq  <= get_freq_ppm(tfreq_diff(sync_freq, USER_REF));

        -- Is difference above threshold?
        if (sync_check = '0') then
            -- Ignore difference until check flag is asserted.
            cooldown := 0;
        elsif (abs(sync_delta) > 2.0*TOL_NSEC) then
            -- Always report gross errors.
            report "Counter mismatch: " & real'image(sync_delta) severity error;
        elsif (cooldown > 0) then
            -- Waiting period after each minor error report.
            cooldown := cooldown - 1;
        elsif (abs(sync_delta) > TOL_NSEC) then
            -- Print a warning and reset cooldown timer.
            report "Counter mismatch: " & real'image(sync_delta) severity warning;
            cooldown := 1000;
        end if;

        if (sync_check = '0') then
            -- Ignore difference until check flag is asserted.
            coolfreq := 0;
        elsif (coolfreq > 0) then
            -- Waiting period after each minor error report.
            coolfreq := coolfreq - 1;
        elsif (sync_dfreq > 1.0) then
            -- Print a warning and reset cooldown timer.
            report "Frequency mismatch: " & real'image(sync_dfreq) severity warning;
            coolfreq := 1000;
        end if;

        -- Once we reach the "check" phase, lock should be asserted.
        if (sync_check = '1' and sync_lock = '0' and cooldown = 0) then
            report "Missing LOCK flag." severity error;
            cooldown := 1000;
        end if;

        -- Running sum for mean and standard deviation of error.
        -- Note: Variance = Std**2 = E[x^2] - E[x]^2
        if (sync_check = '1') then
            sumdd := sumdd + sync_delta;
            sumsq := sumsq + sync_delta * sync_delta;
            count := count + 1.0;
            delta_mean  <= sumdd / count;
            delta_std   <= sqrt((sumsq / count) - (sumdd / count) * (sumdd / count));
        end if;
    end if;
end process;

-- Overall test control
p_test : process
begin
    reset_p <= '1'; wait for 1 us;          -- Reset at start of test
    reset_p <= '0'; wait for 39 ms;         -- Run a few milliseconds
    sync_check <= '1'; wait for 990 us;     -- Start checking once converged
    report "Steady-state time offset: "
        & real'image(delta_mean) & " +/- "
        & real'image(delta_std) & " (ns)";
    report "All tests completed."; wait;
end process;

end single;

--------------------------------------------------------------------------

entity ptp_counter_tb is
    -- Testbench --> No I/O ports
end ptp_counter_tb;

architecture tb of ptp_counter_tb is

begin

-- Demonstrate tolerance of reference frequency errors.
uut0 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 25_000_000, USER_HZ => 125_000_000, USER_PPM => 0);
uut1 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 25_000_000, USER_HZ => 125_000_000, USER_PPM => 250);
uut2 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 25_000_000, USER_HZ => 125_000_000, USER_PPM => -250);

-- Demonstrate operation at various reference and user frequencies.
uut3 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 20_000_000,  USER_HZ => 100_000_000, USER_PPM => 0);
uut4 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 50_000_000,  USER_HZ => 150_000_000, USER_PPM => 0);
uut5 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 100_000_000, USER_HZ =>  50_000_000, USER_PPM => 0);
uut6 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 125_000_000, USER_HZ => 200_000_000, USER_PPM => 0);

-- Demonstrate operation of the auxiliary IIR filter.
uut7 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 25_000_000, USER_HZ => 125_000_000, USER_PPM => 250, FILTER_EN => true);
uut8 : entity work.ptp_counter_tb_single
    generic map(VREF_HZ => 25_000_000, USER_HZ => 125_000_000, USER_PPM => -250, FILTER_EN => true);

end tb;
