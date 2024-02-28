--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Secondary filter for use with "ptp_counter_sync"
--
-- This block implements a digital filter that accepts a noisy counter
-- sequence (i.e., y[t] = m*t + b + noise), and emits an estimate of
-- the underlying sequence (i.e., y'[t] = m*t + b).  Implementation
-- uses a second-order tracking filter with fixed gain coefficients.
-- The filter pipeline is rigged to track the input counter sequence
-- with zero effective delay.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_filter is
    generic (
    LOOP_TAU    : real;             -- Tracking time constant (normalized)
    USER_CLK_HZ : positive;         -- User clock frequency (Hz)
    PHA_SCALE   : natural := 0;     -- Phase scale (0=auto, or 1 nsec = 2^N units)
    TAU_SCALE   : natural := 0);    -- Slope scale (0=auto, or 1 nsec = 2^N units)
    port (
    in_locked   : in  std_logic;
    in_tstamp   : in  tstamp_t;
    out_tstamp  : out tstamp_t;
    user_clk    : in  std_logic);
end ptp_filter;

architecture ptp_filter of ptp_filter is

-- Upper bound on expected slope. Add margin for initial overshoot.
constant USR_MAX_NS : integer := integer(ceil(1.1e9 / real(USER_CLK_HZ)));

-- Calculate normalized loop constants for an underdamped second-order loop.
-- Reference: Stephens & Thomas 1995, "Controlled-root formulation for digital
-- phase-locked loops." https://ieeexplore.ieee.org/abstract/document/366295/
constant TRK_DAMPSQ : real := 0.50;                 -- Damping factor squared
constant TRK_DMOD   : real := 0.25 / TRK_DAMPSQ;    -- Modified damping factor
constant TRK_ALPHA  : real := 4.0 / (MATH_PI * LOOP_TAU * (1.0 + TRK_DMOD));
constant TRK_BETA   : real := TRK_DMOD * TRK_ALPHA * TRK_ALPHA;
constant TRK_ALPHA2 : real := MATH_2_PI * TRK_ALPHA;
constant TRK_BETA2  : real := MATH_2_PI * TRK_BETA;

-- Automatic or manual coefficient scaling?
constant PHA_SCALE2 : natural := auto_scale(TRK_ALPHA2, 0, PHA_SCALE);
constant TAU_SCALE2 : natural := auto_scale(TRK_BETA2, 0, TAU_SCALE);
constant PHA_SCALE3 : positive := PHA_SCALE2 + TSTAMP_SCALE;
constant TAU_SCALE3 : positive := TAU_SCALE2 + TSTAMP_SCALE;
constant PHA_GAIN   : positive := integer(round(TRK_ALPHA2 * 2.0**PHA_SCALE2));
constant TAU_GAIN   : positive := integer(round(TRK_BETA2 * 2.0**TAU_SCALE2));

-- Set width of each accumulator and define shortcuts.
constant PHA_WIDTH  : positive := PHA_SCALE2 + TSTAMP_WIDTH;
constant TAU_WIDTH  : positive := TAU_SCALE3 + log2_ceil(USR_MAX_NS);
constant SUB_WIDTH  : natural := TAU_SCALE2 - PHA_SCALE2;
subtype phase_t is unsigned(PHA_WIDTH-1 downto 0);
subtype slope_t is unsigned(TAU_WIDTH-1 downto 0);
subtype subclk_t is unsigned(SUB_WIDTH-1 downto 0);

-- Initial estimate of slope.
constant PHA_INIT : phase_t :=
    r2u(2.0**PHA_SCALE3 * 1.0e9 / real(USER_CLK_HZ), PHA_WIDTH);
constant TAU_INIT : slope_t :=
    r2u(2.0**TAU_SCALE3 * 1.0e9 / real(USER_CLK_HZ), TAU_WIDTH);

-- Filter pipeline.
signal filt_diff    : signed(TSTAMP_WIDTH-1 downto 0) := (others => '0');
signal filt_alpha   : phase_t := (others => '0');
signal filt_beta    : slope_t := (others => '0');
signal filt_incr    : phase_t := (others => '0');
signal filt_pha     : phase_t := (others => '0');
signal filt_tau     : slope_t := TAU_INIT;
signal filt_sub     : subclk_t := (others => '0');
signal filt_ovr     : std_logic := '0';

begin

-- Sanity check on the configuration parameters:
assert (LOOP_TAU > 100.0)
    report "Time constant too small." severity error;

-- Drive top-level outputs.
out_tstamp <= filt_pha(filt_pha'left downto PHA_SCALE2);

-- Filter pipeline.
p_filter : process(user_clk)
    -- Integer to "accum_t" conversion. (Native arithmetic mangles overflow.)
    function scale_diff(w:positive; g:positive; x:signed) return unsigned is
        variable y : signed(w-1 downto 0) := to_signed(g, w);
        variable z : signed(w-1 downto 0) := resize(x * y, w);
    begin
        return unsigned(z);
    end function;

    -- Scale conversion for the slope accumulator.
    function tau2incr(x: slope_t) return phase_t is
    begin
        return resize(shift_right(x, SUB_WIDTH), PHA_WIDTH);
    end function;

    -- Convert input to initial value of phase accumulator.
    function tstamp2pha(x: tstamp_t) return phase_t is
        variable y : phase_t := resize(x, PHA_WIDTH);
    begin
        return shift_left(y, PHA_SCALE2) + PHA_INIT;
    end function;

    variable next_sub : subclk_t := (others => '0');
begin
    if rising_edge(user_clk) then
        -- Pipeline stage 4: Accumulators.
        -- Accumulate sub-LSB leftovers for full long-term precision; the
        -- main increment term takes MSBs only, +1 each time it overflows.
        next_sub := filt_sub + filt_tau(SUB_WIDTH-1 downto 0);
        if (in_locked = '0') then
            filt_pha <= tstamp2pha(in_tstamp);
            filt_tau <= TAU_INIT;
            filt_sub <= (others => '0');
        else
            filt_pha <= filt_pha + filt_incr;
            filt_tau <= filt_tau + filt_beta;
            filt_sub <= next_sub;
        end if;

        -- Pipeline stage 3: Sum of intermediate terms.
        filt_incr   <= filt_alpha + u2i(filt_ovr) + tau2incr(filt_tau);
        filt_ovr    <= bool2bit(SUB_WIDTH > 0 and next_sub < filt_sub);   -- Wraparound?

        -- Pipeline stage 2: Gain calculation.
        filt_alpha  <= scale_diff(PHA_WIDTH, PHA_GAIN, filt_diff);
        filt_beta   <= scale_diff(TAU_WIDTH, TAU_GAIN, filt_diff);

        -- Pipeline stage 1: Difference signal.
        filt_diff   <= signed(in_tstamp - filt_pha(filt_pha'left downto PHA_SCALE2));
    end if;
end process;

end ptp_filter;
