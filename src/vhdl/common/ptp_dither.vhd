--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Dither generator for PTP timestamps
--
-- For any process with discrete outputs, adding dither can improve
-- linearity by ensuring an accurate time-average over many samples.
-- For example, consider the operation floor(8.3) vs. floor(8.3 + rand),
-- where rand is in the range [0,1). The former is biased (output = 8),
-- but the latter is unbiased (70% chance of output 8, 30% chance of 9).
--
-- This block generates a pseudorandom signal that is uniformly distributed
-- from zero to TMAX.  When synthesizing signals with a discrete-time output,
-- such as the "ptp_clksynth" block, this reduces bias at millisecond scale.
-- The signal can be used as-is, or added to an optional timestamp input.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.prng_lfsr_common.all;
use     work.ptp_types.all;

entity ptp_dither is
    generic (
    PRNG_WIDTH  : positive := 12;   -- PRNG precision
    TMAX_WIDTH  : positive := 18);  -- TMAX full-scale
    port (
    in_tstamp   : in  tstamp_t := (others => '0');
    in_tmax     : in  tstamp_t;     -- Dither scale
    out_dither  : out tstamp_t;     -- Scaled PRNG output
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_dither;

architecture ptp_dither of ptp_dither is

signal prng_raw : std_logic_vector(PRNG_WIDTH-1 downto 0);
signal prng_buf : unsigned(PRNG_WIDTH-1 downto 0) := (others => '0');
signal tmax_buf : unsigned(TMAX_WIDTH-1 downto 0) := (others => '0');
signal prng_mul : unsigned(PRNG_WIDTH+TMAX_WIDTH-1 downto 0) := (others => '0');
signal prng_out : tstamp_t := (others => '0');

begin

-- Generate a PRNG sequence.
u_prng : entity work.prng_lfsr_gen
    generic map(
    IO_WIDTH    => PRNG_WIDTH,
    LFSR_SPEC   => create_prbs(23))
    port map(
    out_data    => prng_raw,
    out_valid   => open,
    out_ready   => '1',
    clk         => clk,
    reset_p     => reset_p);

-- Scale the PRNG to the desired scale.
p_scale : process(clk)
begin
    if rising_edge(clk) then
        -- Pipeline stage 3: Scale and format.
        prng_out <= in_tstamp + resize(shift_right(prng_mul, PRNG_WIDTH), TSTAMP_WIDTH);

        -- Pipeline stage 2: Multiply.
        prng_mul <= prng_buf * tmax_buf;

        -- Pipeline stage 1: Buffer both inputs.
        prng_buf <= unsigned(prng_raw);
        tmax_buf <= resize(in_tmax, TMAX_WIDTH);
    end if;
end process;

-- Drive top-level output.
out_dither <= prng_out;

end ptp_dither;
