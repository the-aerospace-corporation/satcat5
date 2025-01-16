--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Pulse-per-second (PPS) output derived from PTP timestamp
--
-- This block generates a square-wave pulse-per-second (PPS) output,
-- deriving its phase and frequency from a PTP time reference (e.g.,
-- the "rtc_time" signal from port_mailmap).
--
-- This block is similar in function to "ptp_clksynth", but operates
-- from an RTC input (ptp_time_t) instead of a VERDACT timestamp
-- (tstamp_t) and can only be used to synthesize a 1 Hz output.  Both
-- factors simplify required timestamp-modulo logic.
--
-- The output signal can be an ordinary single-bit output, or it can be
-- a parallel word with PAR_COUNT samples per parallel clock.  The user
-- must separately provide any required SERDES logic.
--
-- The optional ConfigBus interface uses a single register:
--  * Write: Set polarity and phase offset.
--      * Two consecutive writes: bits 63-32, then bits 31-00.
--      * Bit 63: Select active edge, '1' for rising or '0' for falling.
--      * Bit 62-48: Reserved (write zeros)
--      * Bit 47-00: Signed phase offset in subnanoseconds
--                   Positive values shift the output later.
--                   Do not set this larger than +/- 999 msec.
--  * Read: Latch the new configuration.  (i.e., Write twice, then read.)
--      * Bit 31-00: Reserved
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_pps_out is
    generic (
    PAR_CLK_HZ  : positive;         -- Rate of the parallel clock
    PAR_COUNT   : positive := 1;    -- Number of samples per clock
    DEV_ADDR    : integer := CFGBUS_ADDR_NONE;
    REG_ADDR    : integer := CFGBUS_ADDR_ANY;
    DITHER_EN   : boolean := true;  -- Enable dither on output?
    EDGE_RISING : boolean := true;  -- Default polarity?
    MSB_FIRST   : boolean := true); -- Parallel bit order
    port (
    -- Parallel square-wave output, with PTP timestamp in the same clock domain.
    par_clk     : in  std_logic;    -- Parallel clock
    par_rtc     : in  ptp_time_t;   -- PTP/RTC timestamp
    par_shdn    : in  std_logic := '0';
    par_pps_out : out std_logic_vector(PAR_COUNT-1 downto 0);

    -- ConfigBus interface (optional)
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack);
end ptp_pps_out;

architecture ptp_pps_out of ptp_pps_out is

-- Compensate for pipeline delay inside this module.
function PIPELINE_DELAY return real is
begin
    if (DITHER_EN) then
        return 5.0 / real(PAR_CLK_HZ);
    else
        return 4.0 / real(PAR_CLK_HZ);
    end if;
end function;

-- Useful constants.
constant OUT_TSAMP  : real := 1.0 / (real(PAR_COUNT) * real(PAR_CLK_HZ));
constant DITHER_MAX : tstamp_t := get_tstamp_sec(OUT_TSAMP);
constant DLY_OFFSET : tstamp_t := get_tstamp_sec(PIPELINE_DELAY);
constant SYNTH_ONE  : tstamp_t := TSTAMP_ONE_SEC;
constant SYNTH_TWO  : tstamp_t := shift_left(SYNTH_ONE, 1);
constant SYNTH_HALF : tstamp_t := shift_right(SYNTH_ONE, 1);

-- Modulo-time calculation.
signal mod_tstamp   : tstamp_t := (others => '0');
signal mod_dither   : tstamp_t := (others => '0');
signal mod_offset   : tstamp_t := (others => '0');
signal mod_final    : tstamp_t := (others => '0');
signal par_out_i    : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');

-- ConfigBus interface
subtype cfg_word is std_logic_vector(63 downto 0);
constant CFG_RSTVAL : cfg_word := (63 => bool2bit(EDGE_RISING), others => '0');
signal cpu_word     : cfg_word := CFG_RSTVAL;
signal cpu_offset   : tstamp_t;
signal cpu_rising   : std_logic;

-- For debugging, apply KEEP constraint to certain signals.
attribute KEEP : string;
attribute KEEP of mod_final : signal is "true";

begin

-- Drive top-level output.
par_pps_out <= flip_vector(par_out_i) when MSB_FIRST else par_out_i;

-- Concatenate the nanosecond and subnanosecond fields.
-- (This input is already calculated modulo one second.)
mod_tstamp <= par_rtc.nsec & par_rtc.subns;

-- Optionally add dither to the parallel timestamps.
-- (If enabled, this adds one cycle of latency.)
gen_dither1 : if DITHER_EN generate
    u_dither : entity work.ptp_dither
        port map(
        in_tstamp   => mod_tstamp,
        in_tmax     => DITHER_MAX,
        out_dither  => mod_dither,
        clk         => par_clk,
        reset_p     => par_shdn);
end generate;

gen_dither0 : if not DITHER_EN generate
    mod_dither <= mod_tstamp;
end generate;

-- Add CPU-controlled offset and reapply modulo constraint.
-- (Max offset plus dither is well under +/- 1 second.)
p_mod : process(par_clk)
begin
    if rising_edge(par_clk) then
        -- Wrap -1/0/+1 second as needed.
        if (mod_offset < SYNTH_ONE) then
            mod_final <= mod_offset;
        elsif (mod_offset < SYNTH_TWO) then
            mod_final <= mod_offset - SYNTH_ONE;
        else
            mod_final <= mod_offset + SYNTH_ONE;
        end if;

        -- Apply the configured phase offset.
        mod_offset <= mod_dither + DLY_OFFSET - cpu_offset;
    end if;
end process;

-- Comparator for each parallel output bit:
gen_cmp : for n in 0 to PAR_COUNT-1 generate
    p_cmp : process(par_clk)
        constant OFFSET : tstamp_t := get_tstamp_sec(real(n) * OUT_TSAMP);
        constant OFFMOD : tstamp_t := SYNTH_ONE - OFFSET;
        variable tlocal : tstamp_t := (others => '0');
    begin
        if rising_edge(par_clk) then
            -- Output '1' in first half of each cycle.
            par_out_i(n) <= cpu_rising xnor bool2bit(tlocal < SYNTH_HALF);

            -- Calculate local modulo (never more than one wraparound).
            if (mod_final < OFFMOD) then
                tlocal := mod_final + OFFSET;
            else
                tlocal := mod_final - OFFMOD;
            end if;
        end if;
    end process;
end generate;

-- Optional ConfigBus interface.
cpu_offset  <= unsigned(cpu_word(TSTAMP_WIDTH-1 downto 0));
cpu_rising  <= cpu_word(63);

u_cfg : cfgbus_register_wide
    generic map(
    DWIDTH      => 64,
    DEVADDR     => DEV_ADDR,
    REGADDR     => REG_ADDR,
    RSTVAL      => CFG_RSTVAL)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    sync_clk    => par_clk,
    sync_val    => cpu_word);

end ptp_pps_out;
