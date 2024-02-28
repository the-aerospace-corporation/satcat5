--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- RGMII clock generator for Microsemi designs without SGMII.
--
-- This module instantiates an CCC that accepts a 50 MHz reference.
-- It generates several output clocks:
--   * 125 MHz (phase 0)
--   * 125 MHz (phase 90)
--   * 200 MHz (currently unused)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.std_logic_unsigned.all;
use     work.common_functions.all;

entity clkgen_rgmii_microsemi is
    port (
    shdn_p          : in  std_logic;    -- Long-term shutdown
    rstin_p         : in  std_logic;    -- Reset, hold 1 msec after shdn_p
    clkin_50        : in  std_logic;
    rstout_p        : out std_logic;
    clkout_125_00   : out std_logic;
    clkout_125_90   : out std_logic;
    clkout_200      : out std_logic);
end entity clkgen_rgmii_microsemi;

architecture arch of clkgen_rgmii_microsemi is

signal clkfb                : std_logic;
signal s_clkbuf_125_00      : std_logic;
signal s_clkbuf_125_90      : std_logic;
signal s_clkbuf_200         : std_logic;
signal ccc_locked           : std_logic;
signal shdn_n               : std_logic;
signal rstout               : std_logic := '1';

component CLKINT
port (
    I   : in std_logic;
    O   : out std_logic);
end component;

component PF_CCC_C1
port (
    PLL_POWERDOWN_N_0 : in std_logic;
    REF_CLK_0         : in std_logic;
    OUT0_FABCLK_0     : out std_logic;
    OUT1_FABCLK_0     : out std_logic;
    OUT2_FABCLK_0     : out std_logic;
    PLL_LOCK_0        : out std_logic);
end component;


begin

shdn_n <= not(shdn_p);

u_ccc : PF_CCC_C1
    port map(
    -- Inputs --
    PLL_POWERDOWN_N_0   => shdn_n,
    REF_CLK_0           => clkin_50,

    -- Outputs --
    OUT0_FABCLK_0       => clkout_200,
    OUT1_FABCLK_0       => clkout_125_00,
    OUT2_FABCLK_0       => clkout_125_90,
    PLL_LOCK_0          => ccc_locked
);

-- Hold reset for a few cycles after CCC is locked.
rstout_p <= rstout;

p_reset : process(rstin_p, clkin_50)
    constant RESET_HOLD : integer := 31;
    variable count : integer range 0 to RESET_HOLD := RESET_HOLD;
begin
    if (rstin_p = '1') then
        rstout  <= '1';
        count   := RESET_HOLD;
    elsif rising_edge(clkin_50) then
        rstout  <= bool2bit(count > 0);

        if (ccc_locked = '0') then
            count := RESET_HOLD;
        elsif (count > 0) then
            count := count - 1;
        end if;
    end if;
end process;

end arch;