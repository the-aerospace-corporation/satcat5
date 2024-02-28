--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Cross-clock counter synchronization for Precision Time Protocol (PTP)
--
-- SatCat5 timestamps are referenced to a global free-running counter.
-- However, the global counter operates in its own time-domain.  This
-- block synthesizes an equivalent free-running counter in the user
-- clock domain, that is asymptotically synchronized to the original
-- with sub-nanosecond precision.  (i.e., It follows exactly the same
-- best-fit line for counter value vs. time.)
--
-- To accomplish this, the global reference distributes two clocks at
-- slightly different frequencies.  This block locks a Vernier PLL to
-- both references, to obtain a precise estimate of the relative phase
-- of the user clock and the two global reference clocks.
--
-- PLL coefficients are derived at build-time based on the time-constant
-- "tau" and the user clock rate.  Typical time-to-first-lock is about
-- 10*tau due to the multi-step acquisition process, including retries.
--
-- Default parameters are tested for user clocks from 50-200 MHz.
-- Internal accumulators use automatic fixed-point scaling to prevent gain
-- coefficients from rounding to zero.  If this causes excess quantization
-- effects, override the default by setting PHA_SCALE (phase accumulator)
-- or TAU_SCALE (slope or frequency accumulator) to a positive value.  In
-- both cases, the internal fixed-point scale is 1 LSB = 2^-N nanoseconds.
--
-- An optional ConfigBus register can be used to add an adjustable time
-- offset to the output counter.  Scale matches PTP format (i.e., one
-- LSB = 1 / 2^16 nanoseconds).
--
-- An optional auxiliary filter can be added to smooth the final output.
-- This mitigates high-frequency jitter in the raw NCO output, at the cost
-- of additional FPGA resources.  Since the jitter magnitude is typically
-- less than one picosecond, the filter is disabled by default.
--
-- A multi-step acquisition process helps to enhance pull-in range and
-- prevent false-lock conditions.  Effective pull-in depends on the
-- Vernier reference parameters, user clock, and final loop bandwidth.
-- Empirically, a 19.979 / 20.021 MHz Vernier pair and a 125 MHz user
-- clock allows total frequency mismatch of up to +/- 1500 ppm.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity ptp_counter_sync is
    generic (
    VCONFIG     : vernier_config;   -- Vernier configuration
    USER_CLK_HZ : positive;         -- User clock frequency (Hz)
    PHA_SCALE   : natural := 0;     -- Phase scale (0=auto, 1+ override)
    TAU_SCALE   : natural := 0;     -- Slope scale (0=auto, 1+ override)
    WAIT_LOCKED : boolean := true;  -- Suppress output until locked?
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Global reference clocks and counter.
    ref_time    : in  port_timeref;
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- Internal diagnostics, not used in normal designs.
    diagnostics : out std_logic_vector(7 downto 0);
    -- User clock and local counter.
    -- (Deassert clock-enable to freeze output if desired.)
    user_clk    : in  std_logic;
    user_cken   : in  std_logic := '1';
    user_ctr    : out tstamp_t;
    user_lock   : out std_logic;
    user_rst_p  : in  std_logic := '0');
end ptp_counter_sync;

architecture ptp_counter_sync of ptp_counter_sync is

-- Threshold for early/late decision.  (See "ctr" function.)
constant CTR_THRESH : integer := integer(
    round(0.5 * real(USER_CLK_HZ) / VCONFIG.vclka_hz));
subtype ped_count_t is integer range 0 to CTR_THRESH;

-- Maximum expected value for each accumulator:
-- * Divide-by-two for VCLKA_HZ means period is doubled.
-- * USER_CLK_HZ adds margin to allow for overshoot during initial transient.
constant PHA_MAX_NS : integer := integer(ceil(2.0e9 / VCONFIG.vclka_hz));
constant USR_MAX_NS : integer := integer(ceil(1.1e9 / real(USER_CLK_HZ)));

-- Effective VPED gain is estimated empirically.
-- TODO: There seems to be a small variation with fsamp.
constant PED_GAIN   : real := 128.0;

-- Calculate normalized loop constants for an underdamped second-order loop.
-- Reference: Stephens & Thomas 1995, "Controlled-root formulation for digital
-- phase-locked loops." https://ieeexplore.ieee.org/abstract/document/366295/
constant TRK_DAMPSQ : real := 0.50;                 -- Damping factor squared
constant TRK_DMOD   : real := 0.25 / TRK_DAMPSQ;    -- Modified damping factor
constant TRK_TAU    : real := (0.001 * VCONFIG.sync_tau_ms) * real(USER_CLK_HZ);
constant TRK_ALPHA  : real := 4.0 / (MATH_PI * TRK_TAU * (1.0 + TRK_DMOD));
constant TRK_BETA   : real := TRK_DMOD * TRK_ALPHA * TRK_ALPHA;

-- Automatic or manual coefficient scaling?
-- (Never use fewer than 2^TSTAMP_SCALE units per nanosecond.)
constant PHA_SCALE2 : positive := auto_scale(PED_GAIN * TRK_ALPHA, TSTAMP_SCALE, PHA_SCALE);
constant TAU_SCALE2 : positive := auto_scale(PED_GAIN * TRK_BETA, TSTAMP_SCALE, TAU_SCALE);

-- Calculate required accumulator width.
-- * PHA_SCALE sets the phase accumulator precision (1 nsec = 2^N units).
-- * TAU_SCALE sets the period accumulator precision (1 nsec = 2^N units).
constant PHA_WIDTH  : integer := PHA_SCALE2 + log2_ceil(PHA_MAX_NS + USR_MAX_NS);
constant TAU_WIDTH  : integer := TAU_SCALE2 + log2_ceil(USR_MAX_NS);
constant SUB_WIDTH  : integer := TAU_SCALE2 - PHA_SCALE2;
subtype phase_t is unsigned(PHA_WIDTH-1 downto 0);
subtype period_t is unsigned(TAU_WIDTH-1 downto 0);
subtype subclk_t is unsigned(SUB_WIDTH-1 downto 0);

-- Convert frequency to accumulator units.
-- (Some care required to avoid VHDL'93 integer overflow.)
function freq2phase(freq_hz: real) return phase_t is
    constant ONE_SEC : real := real(1e9) * (2.0 ** PHA_SCALE2);
begin
    return r2u(ONE_SEC / freq_hz, PHA_WIDTH);
end function;

function freq2period(freq_hz: real) return period_t is
    constant ONE_SEC : real := real(1e9) * (2.0 ** TAU_SCALE2);
begin
    return r2u(ONE_SEC / freq_hz, TAU_WIDTH);
end function;

-- Set lock-detector window to ~0.2 milliseconds. (Nearest power of two.)
function get_lock_window return positive is
    constant LOCK_TIME : positive := div_round(USER_CLK_HZ, 5000);
    constant LOCK_TLOG : positive := log2_floor(LOCK_TIME);
begin
    return 2**LOCK_TLOG - 1;
end function;

-- Calculate gain coefficients to achieve the specified bandwidth.
-- Use of "positive" type ensures a synth error if gain rounds to zero.
-- ("K" parameter scales the user-specified settling time by 1/K.)
function lpt(k : positive) return positive is       -- Loop gain (Period)
    constant TRK_GAIN : real := PED_GAIN * (2.0 ** TAU_SCALE2);
begin
    -- Set the "P" gain for the PLL's proportional-integral control law.
    -- Note: If this rounds to zero, try increasing TAU_SCALE.
    return integer(round(TRK_GAIN * TRK_BETA * real(k*k)));
end function;

function lpp(k : positive) return positive is       -- Loop gain (Phase-sum)
    constant TRK_GAIN : real := PED_GAIN * (2.0 ** PHA_SCALE2);
begin
    -- Set the "I" gain for the PLL's proportional-integral control law.
    -- Note: If this rounds to zero, try increasing PHA_SCALE.
    return integer(round(TRK_GAIN * TRK_ALPHA * real(k)));
end function;

function lpd(k : positive) return positive is       -- Settling time (msec)
    constant MIN_MSEC : positive := 1;
    constant TRK_MSEC : real := 3.0 * VCONFIG.sync_tau_ms / real(k);
begin
    -- Set the minimum expected settling time, in milliseconds.
    if (TRK_MSEC < real(MIN_MSEC)) then
        return MIN_MSEC;
    else    
        return integer(ceil(TRK_MSEC));
    end if;
end function;

-- Record holding a set of loop parameters:
type mode_t is record
    DLY_MSEC    : natural;              -- Time spent in this mode
    PHA_GAIN    : natural;              -- PED gain (phase)
    TAU_GAIN    : natural;              -- PED gain (period)
    LOCK_SUB    : natural;              -- Lock mismatch penalty
    FREQ_MODE   : boolean;              -- Coarse frequency mode?
end record;

-- Set loop bandwidth during each acquisition and tracking mode.
-- Early phases uses a very wide loop bandwidth for the broader frequency
-- pull-in range, then get progressively finer with each stage.
constant MODE_FIRST : integer := 4;     -- Number of acquisition modes
type pll_mode_array is array(MODE_FIRST downto 0) of mode_t;

--       Dly      Pha      Tau  Sub  Freq?
constant PLL_MODES : pll_mode_array := (
    (lpd(16), lpp(16), lpt(16),   2, false),   -- Coarse freq+phase
    (lpd( 8), lpp( 8),  lpt(8),   4, false),   -- Progressively finer
    (lpd( 4), lpp( 4),  lpt(4),   8, false),   -- Progressively finer
    (lpd( 2), lpp( 2),  lpt(2),  16, false),   -- Progressively finer
    (lpd( 1), lpp( 1),  lpt(1),  16, false));  -- Normal operation

-- Calculate accumulator frequency hints and initial values.
-- (Initial values are scaled to match average delay of the DDMTD strobe.)
constant PHA_MOD_A  : phase_t := freq2phase(0.5 * VCONFIG.vclka_hz);
constant PHA_MOD_B  : phase_t := freq2phase(0.5 * VCONFIG.vclkb_hz);
constant PHA_INIT   : phase_t := freq2phase(real(USER_CLK_HZ) / 1.5);
constant PHI_INIT   : phase_t := freq2phase(real(USER_CLK_HZ));
constant TAU_INIT   : period_t := freq2period(real(USER_CLK_HZ));

-- The drift-compensation accumulator mitigates long-term drift caused by
-- rounding errors in PHA_MOD_A and PHA_MOD_B. The error is smaller than
-- a femtosecond, but incurs every VCLKA or VCLKB cycle and accumulates
-- indefinitely, eventually leading to loss of lock unless corrected.
constant CMP_MAX    : integer := 15;        -- Max accumulator value
subtype cmperr_t is integer range -CMP_MAX to CMP_MAX;

-- Generate and resynchronize reference signals.
signal ref_toga     : std_logic := '0';
signal ref_togb     : std_logic := '0';
signal ref_ddmtd    : std_logic := '0';
signal ref_msec     : std_logic;
signal sync_clka    : std_logic;
signal sync_clkb    : std_logic;
signal sync_ddmtd   : std_logic;
signal sync_msec    : std_logic;

-- Vernier PLL state.
subtype pll_state_t is integer range 0 to MODE_FIRST;
subtype pll_delay_t is integer range 0 to lpd(1);
subtype pll_ped_t is integer range -1 to 1;
signal pll_midx     : pll_state_t := MODE_FIRST;    -- PLL mode index
signal pll_mode     : mode_t;                       -- PLL mode parameters
signal pll_dlyct    : pll_delay_t := 0;             -- Remaining duration
signal pll_run      : std_logic := '0';             -- Ready for operation?
signal pll_clka     : std_logic := '1';             -- Estimated RefA
signal pll_clkb     : std_logic := '1';             -- Estimated RefB
signal pll_peda     : pll_ped_t := 0;               -- RefA phase error
signal pll_pedb     : pll_ped_t := 0;               -- RefB phase error
signal pll_pha      : phase_t := PHA_INIT;          -- RefA phase accum
signal pll_phb      : phase_t := PHA_INIT;          -- RefB phase accum
signal pll_phi      : phase_t := PHI_INIT;          -- Next phase increment
signal pll_tau      : period_t := TAU_INIT;         -- User clock period
signal pll_sub      : subclk_t := (others => '0');  -- Sub-LSB accumulator
signal pll_cmp      : cmperr_t := 0;                -- Drift compensation
signal pll_cneg     : std_logic := '0';             -- Drift bias A or B?

-- Lock detection
constant LOCK_SET   : positive := get_lock_window;  -- Accumulator max
constant LOCK_CLR   : natural := 0;                 -- Unlock threshold
signal lock_ctr     : integer range 0 to LOCK_SET := 0;
signal lock_any     : std_logic := '0';             -- Pre-lock (any stage)
signal lock_final   : std_logic := '0';             -- Final stage locked

-- Output counter generation.
signal ctr_rden     : std_logic := '0';
signal ctr_base     : tstamp_t := (others => '0');
signal ctr_incr     : tstamp_t := (others => '0');
signal ctr_phase    : tstamp_t;
signal ctr_offset   : tstamp_t;
signal ctr_total    : tstamp_t;
signal ctr_filter   : tstamp_t := (others => '0');
signal ctr_outreg   : tstamp_t := (others => '0');

-- ConfigBus interface.
signal cfg_offset   : cfgbus_word;

-- Force register duplication for tight routing of critical signals.
attribute async_reg : boolean;
attribute async_reg of ctr_base, ref_ddmtd : signal is true;
attribute dont_touch : boolean;
attribute dont_touch of ctr_base, ref_ddmtd, ref_toga, ref_togb : signal is true;
attribute keep : boolean;
attribute keep of ctr_base, ref_ddmtd, ref_toga, ref_togb : signal is true;

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of ctr_base, ref_ddmtd : signal is true;
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of ref_ddmtd, ref_toga, ref_togb : signal is true;

begin

-- Drive top-level outputs.
user_ctr    <= ctr_outreg;
user_lock   <= lock_final;

-- Sanity check on clock configuration.
assert (VCONFIG.vclka_hz < VCONFIG.vclkb_hz and VCONFIG.vclkb_hz < 1.1*VCONFIG.vclka_hz)
    report "Invalid Vernier clock (A slightly slower than B)." severity error;
assert (real(USER_CLK_HZ) > 2.0*VCONFIG.vclka_hz)
    report "User clock too slow, unsafe operation." severity error;

-- Generate local signals derived from the global references.
-- Duplicating each register ensures they can be placed as close as
-- possible to the buffers below, to minimize routing delay:
--  * Toggle-A is a local divide-by-2 derived from VCLKA.
--    Rising edge must be synchronous to changes in the global timestamp.
--  * Toggle-B is a local divide-by-2 derived from VCLKB.
--    Polarity of this signal is don't-care.
--  * DDMTD signal is a resampled copy of Toggle-B in the VCLKA domain.
--    "Digital Dual Mixer Time Difference" effectively forms a stretched
--    virtual clock by sampling one clock with a slightly slower clock
--    derived from the same source.  See also:
--      http://white-rabbit.web.cern.ch/documents/DDMTD_for_Sub-ns_Synchronization.pdf
--    We use the rising edge of the DDMTD signal to indicate when Toggle-A
--    and Toggle-B are phase-aligned, as an initial guess for our PLL.
p_vclka : process(ref_time.vclka)
begin
    if rising_edge(ref_time.vclka) then
        if (ref_time.tnext = '1') then
            ref_ddmtd <= ref_togb;
        end if;
        ref_toga <= ref_time.tnext;
    end if;
end process;

p_vclkb : process(ref_time.vclkb)
begin
    if rising_edge(ref_time.vclkb) then
        ref_togb <= not ref_togb;
    end if;
end process;

-- Choose a bit from the reference to act as a millisecond timer.
-- (This bit toggles every 2^20 nsec = 1.04 msec.)
ref_msec <= ref_time.tstamp(TSTAMP_SCALE + 20);

-- Resynchronize each reference signal.
u_sync_clka : sync_buffer
    port map(
    in_flag     => ref_toga,
    out_flag    => sync_clka,
    out_clk     => user_clk);
u_sync_clkb : sync_buffer
    port map(
    in_flag     => ref_togb,
    out_flag    => sync_clkb,
    out_clk     => user_clk);
u_sync_ddmtd : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map (
    in_toggle   => ref_ddmtd,
    out_strobe  => sync_ddmtd,
    out_clk     => user_clk);
u_sync_msec : sync_toggle2pulse
    port map (
    in_toggle   => ref_msec,
    out_strobe  => sync_msec,
    out_clk     => user_clk);

-- Select the active set of loop parameters.
pll_mode <= PLL_MODES(pll_midx);

-- Vernier PLL.
p_pll : process(user_clk)
    -- Integer to "accum_t" conversion. (Native arithmetic mangles overflow.)
    function int2phase(w:positive; x:integer) return unsigned is
        variable y : signed(w-1 downto 0) := to_signed(x, w);
    begin
        return unsigned(y);
    end function;

    -- Clip integer input to +/- CMP_MAX.
    function cmp_limit(x: integer) return cmperr_t is
    begin
        if (x < -CMP_MAX) then
            return -CMP_MAX;
        elsif (x < CMP_MAX) THEN
            return x;
        else
            return CMP_MAX;
        end if;
    end function;

    -- Phase accumulator with modulo/wraparound.
    function accum_mod(phase, period : phase_t) return phase_t is
    begin
        if phase >= period then
            return phase - period;
        else
            return phase;
        end if;
    end function;

    -- Phase error detector compares two pseudo-clock signals.  On mismatch,
    -- make an early/late decision based on time since last change.
    function ped(ref, pll : std_logic; ct: ped_count_t) return pll_ped_t is
    begin
        if (ref = pll) then
            return 0;       -- Aligned
        elsif (ct < CTR_THRESH) then
            return -1;      -- PLL leads REF
        else
            return 1;       -- PLL lags REF
        end if;
    end function;

    -- Count cycles since last change in a pseudo-clock signal.
    function ctr(clk, dly : std_logic; ct: ped_count_t) return ped_count_t is
    begin
        if (clk /= dly) then
            return 0;       -- Reset counter on change
        elsif (ct < CTR_THRESH) then
            return ct + 1;  -- Increment up to max
        else
            return CTR_THRESH;
        end if;
    end function;

    variable incr_cmp           : cmperr_t := 0;
    variable incr_tau           : period_t := (others => '0');
    variable next_sub           : subclk_t := (others => '0');
    variable incr_pha, incr_phb : phase_t := (others => '0');
    variable next_pha, next_phb : phase_t := (others => '0');
    variable pll_ctra, pll_ctrb : ped_count_t := 0;
    variable pll_dlya, pll_dlyb : std_logic := '0';
begin
    if rising_edge(user_clk) then
        -- Transition between each startup mode.
        --  * At the start of each phase, wait for DDMTD pulse to proceed.
        --    (This is our main method of preventing false-lock conditions.)
        --  * Run for the designated time interval, measured in msec.
        --  * At the end of the countdown, advance or revert:
        --      * Not locked, first phase: Restart from beginning.
        --      * Not locked, any other phase: Restart from previous phase.
        --      * Locked, except final phase: Start next phase.
        --      * Locked, final phase: Continue operating.
        --        (Keep checking the "lock" flag every millisecond.)
        if (user_rst_p = '1') then
            pll_midx    <= MODE_FIRST;      -- Global reset
            pll_run     <= '0';             -- Wait for sync pulse
            pll_dlyct   <= 0;               -- (Don't-care)
        elsif (pll_run = '0' and sync_ddmtd = '1') then
            pll_run     <= '1';             -- Start next phase
            pll_dlyct   <= pll_mode.DLY_MSEC;
        elsif (pll_run = '1' and sync_msec = '1') then
            if (pll_dlyct > 0) then         -- Countdown to next mode
                pll_dlyct <= pll_dlyct - 1;
            elsif (lock_any = '0' and pll_midx = MODE_FIRST) then
                pll_run   <= '0';           -- Restart from beginning
            elsif (lock_any = '0') then
                pll_run   <= '0';           -- Revert to previous phase
                pll_midx  <= pll_midx + 1;
            elsif (pll_midx > 0) then
                pll_run   <= '0';           -- Transition to next phase.
                pll_midx  <= pll_midx - 1;
            end if;
        end if;

        -- Precalculate the next phase accumulator values.
        next_pha := pll_pha + pll_phi + incr_pha;
        next_phb := pll_phb + pll_phi + incr_phb;

        -- Latch the input counter on rising edge of reconstructed clock.
        -- (Counter changes on rising edge of ref_toga, which leads sync_clka
        --  by 2x user_clk.  Once the PLL is locked, sync_clka and pll_clka
        --  are identical, so it is safe to sample on the PLL rising edge.)
        ctr_rden <= bool2bit(next_pha >= PHA_MOD_A);

        -- Output '1' in the first half of each accumulator cycle.
        pll_clka <= bool2bit(next_pha < PHA_MOD_A / 2 or next_pha >= PHA_MOD_A);
        pll_clkb <= bool2bit(next_phb < PHA_MOD_B / 2 or next_phb >= PHA_MOD_B);

        -- Update accumulators for the jointly-coupled loop filter.
        --  * Frequency accumulator restarts ONLY at the start of the first
        --    phase; otherwise the cumulative estimate carries forward.
        --  * Frequency mode: Coarse frequency loop driven by the DDMTD
        --    strobe, which fires when A/B clocks are near-perfectly aligned.
        --  * Normal operation: Precision second-order phase tracking loop.
        if (pll_run = '0') then
            pll_pha <= PHA_INIT;            -- Updates paused
            pll_phb <= PHA_INIT;
        elsif (pll_mode.FREQ_MODE and sync_ddmtd = '1') then
            pll_pha <= PHA_INIT;            -- Frequency-sync mode
            pll_phb <= PHA_INIT;
        else                                -- Normal operation
            pll_pha <= accum_mod(next_pha, PHA_MOD_A + u2i(pll_cneg));
            pll_phb <= accum_mod(next_phb, PHA_MOD_B + u2i(not pll_cneg));
        end if;

        if (pll_run = '0' and pll_midx = MODE_FIRST) then
            pll_tau <= TAU_INIT;            -- First phase reset
        elsif (pll_run = '1') then
            pll_tau <= pll_tau + incr_tau;  -- Normal operation
        end if;

        -- Tau has higher resolution than the two phase accumulators.
        -- Accumulate sub-LSB leftovers for full long-term precision; the
        -- main increment term takes MSBs only, +1 each time it overflows.
        next_sub := pll_sub + pll_tau(SUB_WIDTH-1 downto 0);
        if (pll_run = '0') then
            pll_phi <= PHI_INIT;                -- Global reset
            pll_sub <= (others => '0');
        elsif (SUB_WIDTH > 0) then
            pll_phi <= resize(pll_tau(TAU_WIDTH-1 downto SUB_WIDTH), PHA_WIDTH)
                     + u2i(next_sub < pll_sub); -- +1 on overflow/wraparound
            pll_sub <= next_sub;                -- Modulo accumulator
        else
            pll_phi <= resize(pll_tau(TAU_WIDTH-1 downto SUB_WIDTH), PHA_WIDTH);
        end if;

        -- Drift compenstation nudges the effective period of PHA_MOD_A or
        -- PHA_MOD_B by 1 LSB, depending on the cumulative error.  This term
        -- is required to mitigate long-term ratiometric drift.
        pll_cneg <= bool2bit(pll_cmp < 0);
        if (pll_run = '0') then
            pll_cmp <= 0;
        else
            pll_cmp <= cmp_limit(pll_cmp + incr_cmp);
        end if;

        -- Adjust loop gain based on active acquisition or tracking mode.
        incr_cmp := pll_peda - pll_pedb;
        incr_pha := int2phase(PHA_WIDTH,
            pll_mode.PHA_GAIN * (pll_peda + pll_pedb));
        incr_phb := int2phase(PHA_WIDTH,
            pll_mode.PHA_GAIN * (pll_peda + pll_pedb));
        incr_tau := int2phase(TAU_WIDTH,
            pll_mode.TAU_GAIN * (pll_peda + pll_pedb));

        -- Early/late phase error detector (PED) for each input.
        -- Note: This PED has a limited pull-in range of about +/- 50 nsec.
        --  Beyond that limit, it will false-lock onto adjacent local minima.
        pll_ctra := ctr(pll_clka, pll_dlya, pll_ctra);
        pll_ctrb := ctr(pll_clkb, pll_dlyb, pll_ctrb);
        pll_peda <= ped(sync_clka, pll_clka, pll_ctra);
        pll_pedb <= ped(sync_clkb, pll_clkb, pll_ctrb);
        pll_dlya := pll_clka;
        pll_dlyb := pll_dlyb;
    end if;
end process;

-- Lock/unlock detection.
-- An accumulator measures the long-term average of the PLL prediction
-- accuracy.  i.e., If sync_clka and pll_clka match most of the time,
-- then the system is probably locked.  The threshold is given by:
--  P(correct) >= LOCK_SUB / (LOCK_SUB + 1)
-- Even when perfectly locked, jitter causes some random variation.
p_lock : process(user_clk)
begin
    if rising_edge(user_clk) then
        -- Threshold with hysteresis for both LOCK flags:
        if (pll_run = '0' or pll_dlyct > 0) then
            lock_any    <= '0';     -- Wait for acquisition
            lock_final  <= '0';
        elsif (pll_mode.FREQ_MODE) then
            lock_any    <= '1';     -- Free pass in frequency mode
            lock_final  <= '0';
        elsif (lock_ctr = LOCK_SET) then
            lock_any    <= '1';     -- Counter reached maximum value
            lock_final  <= bool2bit(pll_midx = 0);
        elsif (lock_ctr <= LOCK_CLR) then
            lock_any    <= '0';     -- Unlock below threshold
            lock_final  <= '0';
        end if;

        -- Increment or decrement the running counter:
        -- On a perfect match, accumulator gets +1, otherwise -N.
        if (pll_run = '0' or pll_dlyct > 0) then
            lock_ctr <= 0;                          -- Wait for acquisition
        elsif (sync_clka = pll_clka and sync_clkb = pll_clkb) then
            if (lock_ctr < LOCK_SET) then           -- Increment up to max
                lock_ctr <= lock_ctr + 1;
            end if;
        elsif (lock_ctr > pll_mode.LOCK_SUB) then   -- Normal decrement
            lock_ctr <= lock_ctr - pll_mode.LOCK_SUB;
        else                                        -- Don't go below zero
            lock_ctr <= 0;
        end if;
    end if;
end process;

-- Additional diagnostics for initial bringup and simulation only.
-- (All associated logic should all be trimmed during synthesis.)
p_sim : process(user_clk)
    variable dtau : signed(TAU_WIDTH-1 downto 0) := (others => '0');
begin
    if rising_edge(user_clk) then
        diagnostics <= lock_any & ctr_rden & sync_ddmtd & sync_msec
            & pll_clka & sync_clka & pll_clkb & sync_clkb;
        dtau := signed(pll_tau - TAU_INIT);
    end if;
end process;

-- Unit conversion: PLL phase indicates the time offset between clocks.
-- This is added to the latched value from the global reference (see below).
ctr_phase   <= resize(shift_right(pll_pha, PHA_SCALE2 - TSTAMP_SCALE), TSTAMP_WIDTH);
ctr_offset  <= unsigned(resize(signed(cfg_offset), TSTAMP_WIDTH));
ctr_total   <= ctr_base + ctr_incr;

-- Output counter generation.
p_ctr : process(user_clk)
    constant FIXED_DELAY : tstamp_t := get_tstamp_incr(USER_CLK_HZ / 3);
begin
    if rising_edge(user_clk) then
        -- Pipeline stage 2: Final output selection.
        if (user_cken = '0') then
            ctr_outreg <= ctr_outreg;           -- Freeze output
        elsif (WAIT_LOCKED and lock_final = '0') then
            ctr_outreg <= TSTAMP_DISABLED;      -- Not locked
        elsif (VCONFIG.sync_aux_en) then
            ctr_outreg <= ctr_filter;           -- Filtered output
        else
            ctr_outreg <= ctr_total;            -- Direct output
        end if;

        -- Pipeline stage 1: Pre-add inputs + Cross-clock latch.
        ctr_incr <= ctr_phase + ctr_offset + FIXED_DELAY;
        if (ctr_rden = '1') then
            ctr_base <= ref_time.tstamp;
        end if;
    end if;
end process;

-- Optional auxiliary filter for high-frequency jitter reduction.
gen_filter : if VCONFIG.sync_aux_en generate
    u_filter : entity work.ptp_filter
        generic map(
        LOOP_TAU    => 0.01 * TRK_TAU,
        USER_CLK_HZ => USER_CLK_HZ,
        PHA_SCALE   => PHA_SCALE,
        TAU_SCALE   => TAU_SCALE)
        port map(
        in_locked   => pll_run,
        in_tstamp   => ctr_total,
        out_tstamp  => ctr_filter,
        user_clk    => user_clk);
end generate;

-- ConfigBus interface sets a fixed time-offset.
-- (Simplifies to constant zero if ConfigBus is disconnected or disabled.)
u_cfg_offset : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    reg_val     => cfg_offset);

end ptp_counter_sync;
