--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Vernier clock generator for Microsemi PolarFire FPGAs.
--
-- This module expects two Clock Conditioning Circuitry (CCC) IP to have been
-- generated. They should both be configured as single PLL with External
-- feedback. Run "project/libero/gen_ccc.tcl" to generate these IP. This
-- module will wrap this pair of Vernier clocks, so they are suitable for use
-- with "ptp_counter_gen" and "ptp_counter_sync".
--
-- The generic VCONFIG is unused, since the configuration is pre-generated.
--
-- The configuration is set using "create_vernier_config()".
-- For legacy reasons, that function is defined in "ultrascale_mem.vhd".
-- Refer to that file for a complete list of supported reference clocks.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity clkgen_vernier is
    generic (VCONFIG : vernier_config); -- Unused
    port (
    rstin_p     : in  std_logic;        -- Active high reset
    refclk      : in  std_logic;        -- Input clock
    vclka       : out std_logic;        -- Slow output clock
    vclkb       : out std_logic;        -- Fast output clock
    vreset_p    : out std_logic);       -- Output reset

    attribute satcat5_cross_clock_dst : boolean;
    attribute satcat5_cross_clock_dst of rstin_p : signal is true;
end clkgen_vernier;

architecture polarfire of clkgen_vernier is

constant RESET_HOLD : integer := 31;

signal clkfb0       : std_logic;
signal clkfb1       : std_logic;
signal clkbuf0      : std_logic;
signal clkbuf1      : std_logic;
signal pll_locked0  : std_logic;
signal pll_locked1  : std_logic;
signal rstctr       : integer range 0 to RESET_HOLD;
signal rstout       : std_logic;
signal rstin_n      : std_logic;

component CCC_VERNIER_SLOW
port(
    FB_CLK_0 : in std_logic;
    PLL_POWERDOWN_N_0 : in std_logic;
    REF_CLK_0 : in std_logic;
    OUT0_FABCLK_0 : out std_logic;
    OUT1_FABCLK_0 : out std_logic;
    PLL_LOCK_0 : out std_logic);
end component CCC_VERNIER_SLOW;

component CCC_VERNIER_FAST
port(
    FB_CLK_0 : in std_logic;
    PLL_POWERDOWN_N_0 : in std_logic;
    REF_CLK_0 : in std_logic;
    OUT0_FABCLK_0 : out std_logic;
    OUT1_FABCLK_0 : out std_logic;
    PLL_LOCK_0 : out std_logic);
end component CCC_VERNIER_FAST;

component CLKINT
port (
    A   : in  std_logic;
    Y   : out std_logic);
end component;

attribute alspreserve : boolean;
attribute alspreserve of pll_locked0, pll_locked1, rstctr, rstout : signal is true;

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of pll_locked0, pll_locked1 : signal is true;
attribute satcat5_cross_clock_dst of rstctr, rstout : signal is true;

begin

rstin_n <= not rstin_p;

-- Instantiate the CCCs.
-- CCCs contain global clock buffer, so no need to instantiate our own.
u_ccc_vernier_slow : CCC_VERNIER_SLOW
    port map(
        FB_CLK_0 => clkfb0,
        PLL_POWERDOWN_N_0 => rstin_n,
        REF_CLK_0 => refclk,
        OUT0_FABCLK_0 => clkfb0,
        OUT1_FABCLK_0 => clkbuf0,
        PLL_LOCK_0 => pll_locked0);

u_ccc_vernier_fast : CCC_VERNIER_FAST
    port map(
        FB_CLK_0 => clkfb1,
        PLL_POWERDOWN_N_0 => rstin_n,
        REF_CLK_0 => refclk,
        OUT0_FABCLK_0 => clkfb1,
        OUT1_FABCLK_0 => clkbuf1,
        PLL_LOCK_0 => pll_locked1);

-- Hold reset for a few cycles after PLL is locked.
p_reset : process(rstin_p, clkbuf0)
begin
    if (rstin_p = '1') then
        rstout <= '1';
        rstctr <= RESET_HOLD;
    elsif rising_edge(clkbuf0) then
        rstout  <= bool2bit(rstctr > 0);

        if (pll_locked0 = '0' or pll_locked1 = '0') then
            rstctr <= RESET_HOLD;
        elsif (rstctr > 0) then
            rstctr <= rstctr - 1;
        end if;
    end if;
end process;

-- Drive top-level outputs.
vclka       <= clkbuf0;
vclkb       <= clkbuf1;
vreset_p    <= rstout;

end polarfire;
