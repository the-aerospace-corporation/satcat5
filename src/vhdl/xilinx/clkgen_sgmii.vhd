--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock generator for Xilinx designs with RGMII and SGMII.
--
-- This module instantiates an MMCM that accepts a reference from
-- 25 to 200 MHz (any integer divisor of 5000 MHz).  Higher reference
-- frequencies are preferred to minimize output jitter.
--
-- It generates several output clocks:
--   * 125 MHz (phase 0)
--   * 125 MHz (phase 90)
--   * 200 MHz (for IDELAYCTRL)
--   * 625 MHz (phase 0)
--   * 625 MHz (phase 90)
--
-- Note: Default speed multiplier is 1x, but higher VCO frequency can
--       slightly improve output jitter at cost of increased power.
--       However, this is only supported at higher FPGA speed grades.
--

library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;

entity clkgen_sgmii_xilinx is
    generic (
    -- Allowed references: 25, 50, 100, 125, 156.25, 200 MHz
    REFCLK_HZ       : positive := 200_000_000;
    MMCM_BANDWIDTH  : string := "LOW";      -- "LOW" / "OPTIMIZED" / "HIGH"
    SPEED_MULT      : positive := 1);       -- 1x or 2x VCO freq. See notes.
    port (
    shdn_p          : in  std_logic;        -- Long-term shutdown
    rstin_p         : in  std_logic;        -- Reset, hold 1 msec after shdn_p
    clkin_ref0      : in  std_logic;        -- Input clock
    clkin_ref1      : in  std_logic := '0'; -- Alt. input clock (optional)
    clkin_sel       : in  std_logic := '0'; -- Alt. select (optional)
    rstout_p        : out std_logic;
    clkout_125_00   : out std_logic;
    clkout_125_90   : out std_logic;
    clkout_200      : out std_logic;
    clkout_625_00   : out std_logic;
    clkout_625_90   : out std_logic);
end entity clkgen_sgmii_xilinx;

architecture arch of clkgen_sgmii_xilinx is

constant REFCLK_MHZ : real := 0.000001 * real(REFCLK_HZ);
constant RESET_HOLD : integer := 31;

signal clkfb                : std_logic;
signal clkbuf_125_00        : std_logic;
signal clkbuf_125_90        : std_logic;
signal clkbuf_200           : std_logic;
signal clkbuf_625_00        : std_logic;
signal clkbuf_625_90        : std_logic;
signal clkout_125_00_i      : std_logic;
signal mmcm_locked          : std_logic;
signal rstctr               : integer range 0 to RESET_HOLD := RESET_HOLD;
signal rstout               : std_logic := '1';

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute dont_touch : boolean;
attribute dont_touch of mmcm_locked, rstctr, rstout : signal is true;
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of mmcm_locked : signal is true;
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of rstctr, rstout : signal is true;

begin

-- Instantiate the MMCM.  Notes:
--   * VCO = 625 MHz * SPEED_MULT.
--   * DIVCLK_DIVIDE = 1 for minimal jitter.  (Keep CLKFB high.)
--   * Select BANDWIDTH = LOW for optimal filtering of input jitter,
--     or BANDWIDTH = HIGH for minimal output jitter from a clean input.
--   * No phase alignment to input --> No BUFG required for CLKFB.
u_mmcm : MMCME2_ADV
    generic map (
    BANDWIDTH               => MMCM_BANDWIDTH,      -- string
    CLKIN1_PERIOD           => 1000.0 / REFCLK_MHZ, -- real
    CLKIN2_PERIOD           => 1000.0 / REFCLK_MHZ, -- real
    REF_JITTER1             => 0.010,       -- real
    REF_JITTER2             => 0.010,       -- real
    DIVCLK_DIVIDE           => 1,           -- integer
    CLKFBOUT_MULT_F         => 625.0 * real(SPEED_MULT) / REFCLK_MHZ,
    CLKFBOUT_PHASE          => 0.0,         -- real
    CLKFBOUT_USE_FINE_PS    => FALSE,       -- boolean
    CLKOUT0_DIVIDE_F        => 3.125 * real(SPEED_MULT),
    CLKOUT0_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT0_PHASE           => 0.0,         -- real
    CLKOUT0_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT1_DIVIDE          => SPEED_MULT,  -- integer
    CLKOUT1_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT1_PHASE           => 0.0,         -- real
    CLKOUT1_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT2_DIVIDE          => SPEED_MULT,  -- integer
    CLKOUT2_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT2_PHASE           => 90.000,      -- real
    CLKOUT2_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT3_DIVIDE          => 32,          -- integer
    CLKOUT3_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT3_PHASE           => 0.0,         -- real
    CLKOUT3_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT4_CASCADE         => FALSE,       -- boolean
    CLKOUT4_DIVIDE          => 5*SPEED_MULT, -- integer
    CLKOUT4_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT4_PHASE           => 0.0,         -- real
    CLKOUT4_USE_FINE_PS     => TRUE,        -- boolean
    CLKOUT5_DIVIDE          => 5*SPEED_MULT, -- integer
    CLKOUT5_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT5_PHASE           => 90.0,        -- real
    CLKOUT5_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT6_DIVIDE          => 32,          -- integer
    CLKOUT6_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT6_PHASE           => 0.0,         -- real
    CLKOUT6_USE_FINE_PS     => FALSE,       -- boolean
    COMPENSATION            => "INTERNAL",  -- string
    STARTUP_WAIT            => FALSE)       -- boolean
    port map (
    CLKIN1          => clkin_ref1,      -- in
    CLKIN2          => clkin_ref0,      -- in
    CLKINSEL        => clkin_sel,       -- in ('1' = CLKIN1, '0' = CLKIN2)
    CLKFBIN         => clkfb,           -- in
    CLKOUT0         => clkbuf_200,      -- out
    CLKOUT0B        => open,            -- out
    CLKOUT1         => clkbuf_625_00,   -- out
    CLKOUT1B        => open,            -- out
    CLKOUT2         => clkbuf_625_90,   -- out
    CLKOUT2B        => open,            -- out
    CLKOUT3         => open,            -- out
    CLKOUT3B        => open,            -- out
    CLKOUT4         => clkbuf_125_00,   -- out
    CLKOUT5         => clkbuf_125_90,   -- out
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

-- Instantiate BUFG (global) or BUFH (local) for each output clock.
-- Note: All 125 and 625 MHz clocks must use same buffer type, to guarantee
--       correct phase alignment for use with OSERDESE2 primitives.
u_buf0 : BUFG
    port map (I => clkbuf_200, O => clkout_200);
u_buf1 : BUFG
    port map (I => clkbuf_625_00, O => clkout_625_00);
u_buf2 : BUFG
    port map (I => clkbuf_625_90, O => clkout_625_90);
u_buf4 : BUFG
    port map (I => clkbuf_125_00, O => clkout_125_00_i);
u_buf5 : BUFG
    port map (I => clkbuf_125_90, O => clkout_125_90);
clkout_125_00 <= clkout_125_00_i;

-- Hold reset for a few cycles after MMCM is locked.
rstout_p <= rstout;

p_reset : process(rstin_p, clkbuf_125_00)
begin
    if (rstin_p = '1') then
        rstout  <= '1';
        rstctr  <= RESET_HOLD;
    elsif rising_edge(clkbuf_125_00) then
        rstout  <= bool2bit(rstctr > 0);

        if (mmcm_locked = '0') then
            rstctr <= RESET_HOLD;
        elsif (rstctr > 0) then
            rstctr <= rstctr - 1;
        end if;
    end if;
end process;

end arch;
