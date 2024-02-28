--------------------------------------------------------------------------
-- Copyright 2022-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Vernier clock generator for Xilinx 7-series FPGAs.
--
-- This module instantiates an MMCM that generates a pair of Vernier
-- clocks, suitable for use with "ptp_counter_gen" and "ptp_counter_sync".
--
-- The configuration is set using "create_vernier_config()".
-- For legacy reasons, that function is defined in "7series_mem.vhd".
-- Refer to that file for a complete list of supported reference clocks.
--

library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity clkgen_vernier is
    generic (VCONFIG : vernier_config);
    port (
    rstin_p     : in  std_logic;        -- Active high reset
    refclk      : in  std_logic;        -- Input clock
    vclka       : out std_logic;        -- Slow output clock
    vclkb       : out std_logic;        -- Fast output clock
    vreset_p    : out std_logic);       -- Output reset
end clkgen_vernier;

architecture seven_series of clkgen_vernier is

constant RESET_HOLD : integer := 31;

-- Extract named parameters from the generic array.
constant CFG_MUL    : real := VCONFIG.params(0);
constant CFG_DIV0   : real := VCONFIG.params(1);
constant CFG_DIV1   : real := VCONFIG.params(2);

signal clkfb        : std_logic;
signal clkbuf0      : std_logic;
signal clkbuf1      : std_logic;
signal clkouta      : std_logic;
signal clkoutb      : std_logic;
signal mmcm_locked  : std_logic;
signal rstclk       : std_logic;
signal rstctr       : integer range 0 to RESET_HOLD := RESET_HOLD;
signal rstout       : std_logic := '1';

-- Custom attribute makes it easy to "set_false_path" on cross-clock signals.
-- (Vivado explicitly DOES NOT allow such constraints to be set in the HDL.)
attribute dont_touch : boolean;
attribute dont_touch of mmcm_locked, rstctr, rstout : signal is true;
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of mmcm_locked : signal is true;
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of rstin_p, rstctr, rstout : signal is true;

begin

-- Instantiate the MMCM.
u_mmcm : MMCME2_ADV
    generic map (
    BANDWIDTH               => "HIGH",      -- string
    CLKIN1_PERIOD           => 1.0e9 / real(VCONFIG.input_hz),
    CLKIN2_PERIOD           => 1.0e9 / real(VCONFIG.input_hz),
    REF_JITTER1             => 0.010,       -- real
    REF_JITTER2             => 0.010,       -- real
    DIVCLK_DIVIDE           => 1,           -- integer
    CLKFBOUT_MULT_F         => CFG_MUL,     -- real
    CLKFBOUT_PHASE          => 0.0,         -- real
    CLKFBOUT_USE_FINE_PS    => FALSE,       -- boolean
    CLKOUT0_DIVIDE_F        => CFG_DIV0,    -- real
    CLKOUT0_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT0_PHASE           => 0.0,         -- real
    CLKOUT0_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT1_DIVIDE          => integer(CFG_DIV1),
    CLKOUT1_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT1_PHASE           => 0.0,         -- real
    CLKOUT1_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT2_DIVIDE          => 32,          -- integer
    CLKOUT2_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT2_PHASE           => 0.0,         -- real
    CLKOUT2_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT3_DIVIDE          => 32,          -- integer
    CLKOUT3_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT3_PHASE           => 0.0,         -- real
    CLKOUT3_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT4_CASCADE         => FALSE,       -- boolean
    CLKOUT4_DIVIDE          => 32,          -- integer
    CLKOUT4_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT4_PHASE           => 0.0,         -- real
    CLKOUT4_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT5_DIVIDE          => 32,          -- integer
    CLKOUT5_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT5_PHASE           => 0.0,         -- real
    CLKOUT5_USE_FINE_PS     => FALSE,       -- boolean
    CLKOUT6_DIVIDE          => 32,          -- integer
    CLKOUT6_DUTY_CYCLE      => 0.5,         -- real
    CLKOUT6_PHASE           => 0.0,         -- real
    CLKOUT6_USE_FINE_PS     => FALSE,       -- boolean
    COMPENSATION            => "INTERNAL",  -- string
    STARTUP_WAIT            => FALSE)       -- boolean
    port map (
    CLKIN1          => refclk,          -- in
    CLKIN2          => refclk,          -- in
    CLKINSEL        => '1',             -- in ('1' = CLKIN1, '0' = CLKIN2)
    CLKFBIN         => clkfb,           -- in
    CLKOUT0         => clkbuf0,         -- out
    CLKOUT0B        => open,            -- out
    CLKOUT1         => clkbuf1,         -- out
    CLKOUT1B        => open,            -- out
    CLKOUT2         => open,            -- out
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
    PWRDWN          => '0',             -- in
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

-- Instantiate global buffer for each output clock.
-- (Swap A/B outputs so that A is the slightly slower clock.)
gen0 : if CFG_DIV0 < CFG_DIV1 generate
    u_buf0 : BUFG port map (I => clkbuf0, O => clkoutb);
    u_buf1 : BUFG port map (I => clkbuf1, O => clkouta);
end generate;

gen1 : if CFG_DIV0 > CFG_DIV1 generate
    u_buf0 : BUFG port map (I => clkbuf0, O => clkouta);
    u_buf1 : BUFG port map (I => clkbuf1, O => clkoutb);
end generate;

-- Hold reset for a few cycles after MMCM is locked.
p_reset : process(rstin_p, clkouta)
begin
    if (rstin_p = '1') then
        rstout <= '1';
        rstctr <= RESET_HOLD;
    elsif rising_edge(clkouta) then
        rstout  <= bool2bit(rstctr > 0);

        if (mmcm_locked = '0') then
            rstctr <= RESET_HOLD;
        elsif (rstctr > 0) then
            rstctr <= rstctr - 1;
        end if;
    end if;
end process;

-- Drive top-level outputs.
vclka       <= clkouta;
vclkb       <= clkoutb;
vreset_p    <= rstout;

end seven_series;
