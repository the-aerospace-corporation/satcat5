--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock-synthesis unit using cross-clock counter
--
-- This block synthesizes a square-wave "clock" from a SatCat5 timestamp
-- counter. (See also: ptp_counter_gen, ptp_counter_sync)  This is not
-- required for PTP directly, but can be useful for observation and
-- verification purposes.  (e.g., To measure the precision of time
-- alignment in various clock domains on an oscilloscope.)
--
-- The reference time "par_tstamp" may be a free-running counter (modulo 2^48,
-- REF_MOD_HZ = 0) or the combined nanoseconds + subnanoseconds field from
-- a real-time clock (modulo 1e9, REF_MOD_HZ = 1).  Higher values of
-- REF_MOD_HZ are unusual except to facilitate accelerated testing.
--
-- The parallel output is usually connected to a SERDES accepting multiple
-- samples per clock.  Higher sampling rates significantly improve the
-- fidelity of the output signal, as the sample period directly sets the
-- effective jitter and resolution of the discrete-time signal.
--
-- When REF_MOD_HZ = 0, the reference interval (2^48 clock cycles) is
-- typically not a multiple of the synthesized output period.  In such
-- cases, this block should always be released from reset within ~2 seconds
-- of reference counter startup.  Otherwise, it may introduce a psuedorandom
-- phase offset.  For similar reasons, when REF_MOD_HZ > 0 the output
-- frequency must be a multiple of the modulo frequency.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_clksynth is
    generic (
    SYNTH_HZ    : positive;         -- Desired output frequency
    PAR_CLK_HZ  : positive;         -- Rate of the parallel clock
    PAR_COUNT   : positive;         -- Number of samples per clock
    REF_MOD_HZ  : natural := 0;     -- Reference modulo (1/N) seconds?
    DITHER_EN   : boolean := true;  -- Enable dither on output?
    MSB_FIRST   : boolean := true); -- Parallel bit order
    port (
    par_clk     : in  std_logic;    -- Parallel clock
    par_tstamp  : in  tstamp_t;     -- Timestamp (from ptp_counter_sync)
    par_out     : out std_logic_vector(PAR_COUNT-1 downto 0);
    reset_p     : in  std_logic);
end ptp_clksynth;

architecture ptp_clksynth of ptp_clksynth is

-- Useful constants.
-- (Note: If REF_MOD_HZ is zero, then REF_MODULO is also zero.)
constant OUT_TSAMP  : real := 1.0 / (real(PAR_COUNT) * real(PAR_CLK_HZ));
constant DITHER_MAX : tstamp_t := get_tstamp_sec(OUT_TSAMP);
constant REF_MODULO : tstamp_t := get_tstamp_incr(REF_MOD_HZ);
constant SYNTH_ONE  : tstamp_t := get_tstamp_incr(SYNTH_HZ);
constant SYNTH_TWO  : tstamp_t := shift_left(SYNTH_ONE, 1);
constant SYNTH_HALF : tstamp_t := shift_right(SYNTH_ONE, 1);

-- Counter initial value compensates for pipeline delay in "p_mod".
function CTR_DELAY return real is
begin
    if (DITHER_EN) then
        return 4.0 / real(PAR_CLK_HZ);
    else
        return 3.0 / real(PAR_CLK_HZ);
    end if;
end function;

constant CTR_INIT   : tstamp_t := REF_MODULO + get_tstamp_sec(-CTR_DELAY);

-- Modulo-time calculation.
signal mod_offset   : tstamp_t := ctr_init;
signal mod_time     : tstamp_t := (others => '0');
signal mod_dither   : tstamp_t := (others => '0');
signal par_out_i    : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');

-- For debugging, apply KEEP constraint to certain signals.
attribute KEEP : string;
attribute KEEP of mod_offset, mod_time : signal is "true";

begin

-- Drive top-level output.
par_out <= flip_vector(par_out_i) when MSB_FIRST else par_out_i;

-- Sanity check that we can keep up with requested frequency.
assert (10*SYNTH_HZ < 9*PAR_CLK_HZ)
    report "Requested synth frequency too high." severity error;
assert (10*REF_MOD_HZ < SYNTH_HZ)
    report "Requested modulo frequency is too high." severity error;
assert (REF_MOD_HZ = 0 or (SYNTH_HZ mod REF_MOD_HZ) = 0)
    report "Reference period must be a multiple of synth period." severity error;

-- Iterative modulo block.  Increment a running counter until the
-- difference is smaller than the desired output period.
-- (This state machine is far smaller than a true modulo operator.)
p_mod : process(par_clk)
    constant MOD_HALF   : tstamp_t := shift_right(REF_MODULO, 1);
    constant MOD_LIMIT  : tstamp_t := REF_MODULO - SYNTH_ONE;
    variable delta : tstamp_t := (others => '0');
begin
    if rising_edge(par_clk) then
        -- Sanity check on output.
        assert (mod_time < SYNTH_ONE) severity error;

        -- Calculate instantaneous offset.
        if (REF_MODULO > 0 and par_tstamp - mod_offset + REF_MODULO < MOD_HALF) then
            delta := par_tstamp - mod_offset + REF_MODULO;
        else
            delta := par_tstamp - mod_offset;
        end if;

        -- "Locked" if result doesn't need to wrap more than once.
        if (delta < SYNTH_ONE) then
            mod_time <= delta;                  -- Ordinary case
        elsif (delta < SYNTH_TWO) then
            mod_time <= delta - SYNTH_ONE;      -- Simple wraparound
        else
            mod_time <= (others => '0');        -- Suppress out-of-range
        end if;

        -- Update the offset counter to stay within desired range.
        if (reset_p = '1') then
            mod_offset <= ctr_init;
        elsif (signed(delta) >= signed(SYNTH_ONE)) then
            -- Increment if we're behind by one full cycle.
            if (REF_MODULO > 0 and mod_offset >= MOD_LIMIT) then
                mod_offset <= mod_offset - MOD_LIMIT;
            else
                mod_offset <= mod_offset + SYNTH_ONE;
            end if;
        elsif (signed(delta) < 0) then
            -- Decrement if we're ahead by any amount.
            if (REF_MODULO > 0 and mod_offset < SYNTH_ONE) then
                mod_offset <= mod_offset + MOD_LIMIT;
            else
                mod_offset <= mod_offset - SYNTH_ONE;
            end if;
        end if;
    end if;
end process;

-- Optionally add dither to the parallel timestamps.
gen_dither1 : if DITHER_EN generate
    u_dither : entity work.ptp_dither
        port map(
        in_tstamp   => mod_time,
        in_tmax     => DITHER_MAX,
        out_dither  => mod_dither,
        clk         => par_clk,
        reset_p     => reset_p);
end generate;

gen_dither0 : if not DITHER_EN generate
    mod_dither <= mod_time;
end generate;

-- Comparator for each parallel output bit:
gen_cmp : for n in 0 to PAR_COUNT-1 generate
    p_cmp : process(par_clk)
        constant OFFSET : tstamp_t := get_tstamp_sec(real(n) * OUT_TSAMP);
        constant OFFMOD : tstamp_t := SYNTH_ONE - OFFSET;
        variable tlocal : tstamp_t := (others => '0');
    begin
        if rising_edge(par_clk) then
            -- Output '1' in first half of each cycle.
            par_out_i(n) <= bool2bit(tlocal < SYNTH_HALF);

            -- Calculate local modulo (never more than one wraparound).
            if (mod_dither < OFFMOD) then
                tlocal := mod_dither + OFFSET;
            else
                tlocal := mod_dither - OFFMOD;
            end if;
        end if;
    end process;
end generate;

end ptp_clksynth;
