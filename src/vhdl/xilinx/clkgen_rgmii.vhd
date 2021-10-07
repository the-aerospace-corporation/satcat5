--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- RGMII clock generator for Xilinx designs without SGMII.
--
-- This module instantiates an MMCM that accepts a 25 MHz reference.
-- It generates several output clocks:
--   * 125 MHz (phase 0)
--   * 125 MHz (phase 90)
--   * 200 MHz (for IDELAYCTRL)
--

library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;

entity clkgen_rgmii_xilinx is
    port (
    shdn_p          : in  std_logic;    -- Long-term shutdown
    rstin_p         : in  std_logic;    -- Reset, hold 1 msec after shdn_p
    clkin_25        : in  std_logic;
    rstout_p        : out std_logic;
    clkout_125_00   : out std_logic;
    clkout_125_90   : out std_logic;
    clkout_200      : out std_logic);
end entity clkgen_rgmii_xilinx;

architecture arch of clkgen_rgmii_xilinx is

signal clkfb                : std_logic;
signal clkbuf_125_00        : std_logic;
signal clkbuf_125_90        : std_logic;
signal clkbuf_200           : std_logic;
signal mmcm_locked          : std_logic;
signal rstout               : std_logic := '1';

begin

-- Instantiate the MMCM.
-- Note: No BUFG for clkfb, since no phase align for input & output clocks.
u_mmcm : MMCME2_ADV
    generic map (
    BANDWIDTH               => "OPTIMIZED", -- string
    CLKIN1_PERIOD           => 40.0,        -- real
    CLKIN2_PERIOD           => 0.0,         -- real
    REF_JITTER1             => 0.010,       -- real
    REF_JITTER2             => 0.0,         -- real
    DIVCLK_DIVIDE           => 1,           -- integer
    CLKFBOUT_MULT_F         => 25.0,        -- real
    CLKFBOUT_PHASE          => 0.0,         -- real
    CLKFBOUT_USE_FINE_PS    => FALSE,       -- boolean
    CLKOUT0_DIVIDE_F        => 3.125,       -- real
    CLKOUT0_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT0_PHASE           => 0.0,         -- real
    CLKOUT0_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT1_DIVIDE          => 5,           -- integer
    CLKOUT1_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT1_PHASE           => 0.0,         -- real
    CLKOUT1_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT2_DIVIDE          => 5,           -- integer
    CLKOUT2_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT2_PHASE           => 90.000,      -- real
    CLKOUT2_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT3_DIVIDE          => 32,          -- integer
    CLKOUT3_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT3_PHASE           => 0.0,         -- real
    CLKOUT3_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT4_CASCADE         => FALSE,       -- boolean
    CLKOUT4_DIVIDE          => 32,          -- integer
    CLKOUT4_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT4_PHASE           => 0.0,         -- real
    CLKOUT4_USE_FINE_PS     => TRUE,        -- boolean
    CLKOUT5_DIVIDE          => 32,          -- integer
    CLKOUT5_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT5_PHASE           => 0.0,         -- real
    CLKOUT5_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT6_DIVIDE          => 32,          -- integer
    CLKOUT6_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT6_PHASE           => 0.0,         -- real
    CLKOUT6_USE_FINE_PS     => FALSE,       -- boolean
    COMPENSATION            => "ZHOLD",     -- string
    STARTUP_WAIT            => FALSE)       -- boolean
    port map (
    CLKIN1          => clkin_25,        -- in
    CLKIN2          => '0',             -- in
    CLKINSEL        => '1',             -- in
    CLKFBIN         => clkfb,           -- in
    CLKOUT0         => clkbuf_200,      -- out
    CLKOUT0B        => open,            -- out
    CLKOUT1         => clkbuf_125_00,   -- out
    CLKOUT1B        => open,            -- out
    CLKOUT2         => clkbuf_125_90,   -- out
    CLKOUT2B        => open,            -- out
    CLKOUT3         => open,            -- out
    CLKOUT3B        => open,            -- out
    CLKOUT4         => open,            -- out
    CLKOUT5         => open,            -- out
    CLKOUT6         => open,            -- out
    CLKFBOUT        => clkfb,           -- out
    CLKFBOUTB       => open,            -- out
    CLKINSTOPPED    => open,            -- out
    CLKFBSTOPPED    => open,            -- out
    LOCKED          => mmcm_locked,     -- out
    PWRDWN          => shdn_p,          -- in
    RST             => rstin_p,         -- in
    DI              => (others => '0'), -- in
    DADDR           => (others => '0'), -- in
    DCLK            => '0',             -- in
    DEN             => '0',             -- in
    DWE             => '0',             -- in
    DO              => open,            -- out
    DRDY            => open,            -- out
    PSINCDEC        => '0',             -- in
    PSEN            => '0',             -- in
    PSCLK           => '0',             -- in
    PSDONE          => open);           -- out

-- Instantiate BUFG for each output clock.
u_buf0 : BUFG
    port map (I => clkbuf_200, O => clkout_200);
u_buf1 : BUFG
    port map (I => clkbuf_125_00, O => clkout_125_00);
u_buf2 : BUFG
    port map (I => clkbuf_125_90, O => clkout_125_90);

-- Hold reset for a few cycles after MMCM is locked.
rstout_p <= rstout;

p_reset : process(rstin_p, clkin_25)
    constant RESET_HOLD : integer := 31;
    variable count : integer range 0 to RESET_HOLD := RESET_HOLD;
begin
    if (rstin_p = '1') then
        rstout  <= '1';
        count   := RESET_HOLD;
    elsif rising_edge(clkin_25) then
        rstout  <= bool2bit(count > 0);

        if (mmcm_locked = '0') then
            count := RESET_HOLD;
        elsif (count > 0) then
            count := count - 1;
        end if;
    end if;
end process;

end arch;
