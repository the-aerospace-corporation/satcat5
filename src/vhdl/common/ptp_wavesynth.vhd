--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Wave-synthesis unit using cross-clock counter
--
-- This block is a fixed-frequency function generator that uses SatCat5
-- timestamp counters as the time reference.  (See also: ptp_counter_sync)
-- It generates sine and cosine outputs with a period of 2^M nanoseconds.
-- (See also: sine_interp.vhd)  This allows for high-precision measurements
-- of VERDACT performance using benchtop instruments.
--
-- In the default mode (PAR_COUNT = 1), the output is a regular signed signal.
-- In this mode, the PAR_CLK_HZ and MSW_FIRST parameters have no effect.
--
-- The output can be expanded to generate any number of samples per clock by
-- specifying PAR_COUNT > 1.  (e.g., For compatibility with the Xilinx RFSoC.)
-- To generate parallel outputs, the user must also specify PAR_CLK_HZ to
-- calibrate the inter-sample spacing.  Fields in the output vector may be
-- ordered MSW-first or LSW-first.
--
-- The block is configured to compensate for all internal latency sources,
-- so that the output phase is aligned with the input timestamp.  External
-- latency can also be compensated, if known, by setting DAC_LATENCY.
--
-- Since this module has no persistent state, and its output is flushed
-- within a few clock cycles, no reset is required.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_wavesynth is
    generic (
    LOG_NSEC    : natural;          -- Synth period = 2^N nanoseconds
    DAC_WIDTH   : positive;         -- Bits per DAC sample
    DAC_LATENCY : real := 0.0;      -- Estimated DAC latency (nsec)
    PAR_CLK_HZ  : natural := 0;     -- Rate of the parallel clock
    PAR_COUNT   : positive := 1;    -- Number of samples per clock
    MSW_FIRST   : boolean := true); -- Parallel bit order
    port (
    par_clk     : in  std_logic;    -- Parallel clock
    par_tstamp  : in  tstamp_t;     -- Timestamp (from ptp_counter_sync)
    par_out_cos : out signed(DAC_WIDTH*PAR_COUNT-1 downto 0);
    par_out_sin : out signed(DAC_WIDTH*PAR_COUNT-1 downto 0));
end ptp_wavesynth;

architecture ptp_wavesynth of ptp_wavesynth is

-- Calculate time offset for the Nth lane.
function get_offset(n : natural) return tstamp_t is
    -- Time per parallel clock and time per output sample, in nanoseconds.
    constant TPAR  : real := 1.0e9 / real(PAR_CLK_HZ);
    constant TSAMP : real := TPAR / real(PAR_COUNT);
    -- Running total of time-offset in nanoseconds:
    --  * Six par_clk for sin/cos calculation (u_interp)
    --  * User-specified delay.
    variable tlane : real := 6.0 * TPAR + DAC_LATENCY;
begin
    -- Adjust time-offset for each lane index.
    -- (Earliest sample has the largest offset, equal to TPAR.)
    if MSW_FIRST then
        tlane := tlane + TSAMP * real(n+1);
    else
        tlane := tlane + TSAMP * real(PAR_COUNT-n);
    end if;
    -- Convert nanoseconds to a numeric timestamp.
    return get_tstamp_nsec(tlane);
end function;

begin

-- Instantiate logic for each output lane...
gen_lane : for n in 0 to PAR_COUNT-1 generate
    local : block
        -- Offset = Lane index
        constant OFFSET : tstamp_t := get_offset(n);
        constant TWIDTH : positive := TSTAMP_SCALE + LOG_NSEC;
        signal lcl_time : tstamp_t := (others => '0');
        signal lcl_tmod : unsigned(TWIDTH-1 downto 0) := (others => '0');
    begin
        -- Apply time offset for this channel.
        p_offset : process(par_clk)
        begin
            if rising_edge(par_clk) then
                lcl_time <= par_tstamp - OFFSET;
            end if;
        end process;

        -- Truncate bits to convert time to phase/angle.
        lcl_tmod <= lcl_time(TWIDTH-1 downto 0);

        -- Sine/cosine synthesis.
        u_interp : entity work.sine_interp
            generic map(
            IN_WIDTH    => TWIDTH,
            OUT_WIDTH   => DAC_WIDTH)
            port map(
            in_theta    => lcl_tmod,
            out_cos     => par_out_cos((n+1)*DAC_WIDTH-1 downto n*DAC_WIDTH),
            out_sin     => par_out_sin((n+1)*DAC_WIDTH-1 downto n*DAC_WIDTH),
            clk         => par_clk);
    end block;
end generate;

end ptp_wavesynth;
