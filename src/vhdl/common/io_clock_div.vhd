--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock-divider using DDR output
--
-- This block accepts a reference clock and a divider ratio, then generates
-- an output clock signal suitable for connection to a GPIO pin.  The output
-- uses a DDR flop to allow odd ratios, including 1:1.
--
-- The optional "out_next" strobe is asserted on the cycle before each rising
-- edge of the output. This can be used as a write-enable strobe for other
-- registers, to synchronize output data using a "ddr_output" primitive, or
-- to make safe changes to the divide ratio.  (Ratio changes applied at any
-- other time may produce undefined transients.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.bool2bit;
use     work.common_primitives.ddr_output;

entity io_clock_div is
    port(
    -- Reference clock and divide ratio.
    ref_clk     : in  std_logic;
    cfg_divide  : in  unsigned(7 downto 0);
    -- Output "clock" and start-of-cycle strobe.
    out_clk     : out std_logic;
    out_next    : out std_logic;
    -- Optional synchronous reset.
    reset_p     : in  std_logic := '0');
end io_clock_div;

architecture io_clock_div of io_clock_div is

subtype ctr_t is unsigned(7 downto 0);
constant CTR_ZERO : ctr_t := (others => '0');

signal half : ctr_t;                -- Half of cfg_divide, round down
signal wrap : std_logic;            -- Clock-divide rollover
signal ctr  : ctr_t := CTR_ZERO;    -- Clock-divide counter
signal div0 : std_logic := '0';     -- DDR output, rising-edge
signal div1 : std_logic := '0';     -- DDR output, Falling-edge

begin

half <= shift_right(cfg_divide, 1);
wrap <= bool2bit(ctr + 1 = cfg_divide);
out_next <= wrap or bool2bit(cfg_divide = 0);

p_ctrl : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        if (reset_p = '1' or cfg_divide = 0) then
            ctr <= CTR_ZERO;    -- Reset or shutdown
        elsif (wrap = '1') then
            ctr <= CTR_ZERO;    -- Start of new cycle
        else
            ctr <= ctr + 1;     -- Continue cycle
        end if;

        if (reset_p = '1' or cfg_divide = 0) then
            div0 <= '0';        -- Reset or shutdown
            div1 <= '0';
        elsif (ctr < half) then
            div0 <= '1';        -- First half of cycle
            div1 <= '1';
        elsif (ctr = half) then
            div0 <= cfg_divide(0);
            div1 <= '0';        -- Mid-cycle split
        else
            div0 <= '0';
            div1 <= '0';        -- Second half of cycle
        end if;
    end if;
end process;

-- DDR flop drives the output signal.
u_out : ddr_output
    port map(
    d_re    => div0,
    d_fe    => div1,
    clk     => ref_clk,
    q_pin   => out_clk);

end io_clock_div;
