--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Top-level file for the "Clock-Synthesizer" demo
--
-- This design demonstrates the capabilities of the cross-clock counter
-- synchronizer, by synthesizing a synchronized 25 MHz clock signal in
-- several different clock domains:
--  * GTX0 sampled at 6,250 MHz (derived from onboard 125 MHz oscillator)
--  * GPIO0 sampled at 1,250 MHz (derived from GTX0 clock)
--  * GTX1 sampled at 6,250 MHz (derived from external 125 MHz reference)
--  * GPIO1 sampled at 1,250 MHz (derived from GTX1 clock)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.round;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.io_leds.all;
use     work.ptp_types.all;

entity vc707_clksynth is
    generic (
    SYNTH_HZ    : integer := 25_000_000;
    STATUS_SEL  : integer := -1);   -- Debug mode for status_led
    port (
    ext_rst_p   : in  std_logic;    -- "CPU reset" button
    sys_clk_p   : in  std_logic;    -- SYSCLK (200 MHz)
    sys_clk_n   : in  std_logic;    -- SYSCLK (200 MHz)
    status_led  : out std_logic_vector(7 downto 0);
    gpio0_out_p : out std_logic;    -- GPIO0 output (synthesized clock)
    gpio0_out_n : out std_logic;    -- GPIO0 output (differential)
    gpio1_out_p : out std_logic;    -- GPIO1 output (synthesized clock)
    gpio1_out_n : out std_logic;    -- GPIO1 output (differential)
    gtx0_ref_p  : in  std_logic;    -- GTX0 reference (125 MHz fixed)
    gtx0_ref_n  : in  std_logic;    -- GTX0 reference (125 MHz fixed)
    gtx0_out_p  : out std_logic;    -- GTX0 output (synthesized clock)
    gtx0_out_n  : out std_logic;    -- GTX0 output (differential)
    gtx1_ref_p  : in  std_logic;    -- GTX1 reference (125 MHz nominal)
    gtx1_ref_n  : in  std_logic;    -- GTX1 reference (125 MHz nominal)
    gtx1_out_p  : out std_logic;    -- GTX1 output (synthesized clock)
    gtx1_out_n  : out std_logic);   -- GTX1 output (differential)
end vc707_clksynth;

architecture vc707_clksynth of vc707_clksynth is

constant SYS_CLK_HZ     : positive := 200_000_000;
constant GTX_TXCLK_HZ   : positive := 156_250_000;
constant GPIO_TXCLK_HZ  : positive := 125_000_000;

-- Vernier clock synthesizer at 19.979 and 20.021 MHz.
constant VCONFIG : vernier_config := create_vernier_config(SYS_CLK_HZ);
signal sys_clk_buf  : std_logic;
signal sys_clk_125  : std_logic;
signal sys_reset_p  : std_logic;
signal vclka        : std_logic;
signal vclkb        : std_logic;
signal vreset_p     : std_logic;

-- Reference and resynchronized counters.
signal ref_time     : port_timeref;
signal gtx0_time    : tstamp_t;
signal gtx1_time    : tstamp_t;
signal gpio0_time   : tstamp_t;
signal gpio1_time   : tstamp_t;
signal gtx0_lock    : std_logic;
signal gtx1_lock    : std_logic;
signal gpio0_lock   : std_logic;
signal gpio1_lock   : std_logic;

-- Status reporting and diagnostics.
signal diag_gtx0    : std_logic_vector(7 downto 0);
signal diag_gtx1    : std_logic_vector(7 downto 0);
signal diag_gpio0   : std_logic_vector(7 downto 0);
signal diag_gpio1   : std_logic_vector(7 downto 0);
signal diag_led     : std_logic_vector(7 downto 0);

-- GTX interface
signal gtx0_txclk   : std_logic;
signal gtx1_txclk   : std_logic;
signal gtx0_txdata  : std_logic_vector(39 downto 0);
signal gtx1_txdata  : std_logic_vector(39 downto 0);
signal gtx0_reset_p : std_logic;
signal gtx1_reset_p : std_logic;
signal usr0_reset_i : std_logic;
signal usr1_reset_i : std_logic;
signal usr0_reset_p : std_logic;
signal usr1_reset_p : std_logic;

-- GPIO interface
signal gpio0_clk125 : std_logic;
signal gpio1_clk125 : std_logic;
signal gpio0_clk625 : std_logic;
signal gpio1_clk625 : std_logic;
signal gpio0_txdata : std_logic_vector(9 downto 0);
signal gpio1_txdata : std_logic_vector(9 downto 0);
signal gpio0_rst_p  : std_logic;
signal gpio1_rst_p  : std_logic;

-- KEEP specific signals for Chipscope.
attribute keep : boolean;
attribute keep of gtx0_lock, gtx0_reset_p, gtx0_time, gtx0_txdata : signal is true;
attribute keep of gtx1_lock, gtx1_reset_p, gtx1_time, gtx1_txdata : signal is true;
attribute keep of gpio0_lock, gpio0_rst_p, gpio0_time, gpio0_txdata : signal is true;
attribute keep of gpio1_lock, gpio1_rst_p, gpio1_time, gpio1_txdata : signal is true;
attribute keep of usr0_reset_p, usr1_reset_p, vreset_p : signal is true;

begin

-- System clock buffer.
u_sys_clk : ibufds
    generic map(
    DIFF_TERM   => false,   -- External resistor
    IOSTANDARD  => "LVDS")  -- LVDS on a 1.5V bank
    port map(
    I   => sys_clk_p,
    IB  => sys_clk_n,
    O   => sys_clk_buf);

-- Clock synthesis.
-- Power-on reset + Minimum hold 600 nsec.
u_clkgen_sys : entity work.clkgen_sgmii_xilinx
    generic map(REFCLK_HZ => SYS_CLK_HZ)
    port map(
    shdn_p          => '0',
    rstin_p         => ext_rst_p,
    clkin_ref0      => sys_clk_buf,
    rstout_p        => sys_reset_p,
    clkout_125_00   => sys_clk_125);

u_clkgen_gpio0 : entity work.clkgen_sgmii_xilinx
    generic map(REFCLK_HZ => GTX_TXCLK_HZ)
    port map(
    shdn_p          => '0',
    rstin_p         => usr0_reset_p,
    clkin_ref0      => gtx0_txclk,
    rstout_p        => gpio0_rst_p,
    clkout_125_00   => gpio0_clk125,
    clkout_625_00   => gpio0_clk625);

u_clkgen_gpio1 : entity work.clkgen_sgmii_xilinx
    generic map(REFCLK_HZ => GTX_TXCLK_HZ)
    port map(
    shdn_p          => '0',
    rstin_p         => usr1_reset_p,
    clkin_ref0      => gtx1_txclk,
    rstout_p        => gpio1_rst_p,
    clkout_125_00   => gpio1_clk125,
    clkout_625_00   => gpio1_clk625);

-- Vernier clock synthesizer.
u_vernier : clkgen_vernier
    generic map (VCONFIG => VCONFIG)
    port map(
    rstin_p     => sys_reset_p,
    refclk      => sys_clk_buf,
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p);

-- Generate the reference counter.
u_ctrgen : entity work.ptp_counter_gen
    generic map(VCONFIG => VCONFIG)
    port map(
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p,
    ref_time    => ref_time);

-- Synthesizer reset from user or GTX.
usr0_reset_i <= vreset_p or gtx0_reset_p;
usr1_reset_i <= vreset_p or gtx1_reset_p;

u_usr0_reset : sync_reset
    port map(
    in_reset_p  => usr0_reset_i,
    out_reset_p => usr0_reset_p,
    out_clk     => gtx0_txclk);

u_usr1_reset : sync_reset
    port map(
    in_reset_p  => usr1_reset_i,
    out_reset_p => usr1_reset_p,
    out_clk     => gtx1_txclk);

-- Resynchronized counter in each GTX and GPIO clock domain.
u_sync_gtx0 : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => GTX_TXCLK_HZ)
    port map(
    ref_time    => ref_time,
    diagnostics => diag_gtx0,
    user_clk    => gtx0_txclk,
    user_ctr    => gtx0_time,
    user_lock   => gtx0_lock,
    user_rst_p  => usr0_reset_p);

u_sync_gtx1 : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => GTX_TXCLK_HZ)
    port map(
    ref_time    => ref_time,
    diagnostics => diag_gtx1,
    user_clk    => gtx1_txclk,
    user_ctr    => gtx1_time,
    user_lock   => gtx1_lock,
    user_rst_p  => usr1_reset_p);

u_sync_gpio0 : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => GPIO_TXCLK_HZ)
    port map(
    ref_time    => ref_time,
    diagnostics => diag_gpio0,
    user_clk    => gpio0_clk125,
    user_ctr    => gpio0_time,
    user_lock   => gpio0_lock,
    user_rst_p  => gpio0_rst_p);

u_sync_gpio1 : entity work.ptp_counter_sync
    generic map(
    VCONFIG     => VCONFIG,
    USER_CLK_HZ => GPIO_TXCLK_HZ)
    port map(
    ref_time    => ref_time,
    diagnostics => diag_gpio1,
    user_clk    => gpio1_clk125,
    user_ctr    => gpio1_time,
    user_lock   => gpio1_lock,
    user_rst_p  => gpio1_rst_p);

-- Synthesize each psuedo-clock signal.
u_synth_gtx0 : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => GTX_TXCLK_HZ,
    PAR_COUNT   => 40,
    MSB_FIRST   => true)
    port map(
    par_clk     => gtx0_txclk,
    par_tstamp  => gtx0_time,
    par_out     => gtx0_txdata,
    reset_p     => usr0_reset_p);

u_synth_gtx1 : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => GTX_TXCLK_HZ,
    PAR_COUNT   => 40,
    MSB_FIRST   => true)
    port map(
    par_clk     => gtx1_txclk,
    par_tstamp  => gtx1_time,
    par_out     => gtx1_txdata,
    reset_p     => usr1_reset_p);

u_synth_gpio0 : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => GPIO_TXCLK_HZ,
    PAR_COUNT   => 10,
    MSB_FIRST   => true)
    port map(
    par_clk     => gpio0_clk125,
    par_tstamp  => gpio0_time,
    par_out     => gpio0_txdata,
    reset_p     => gpio0_rst_p);

u_synth_gpio1 : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => GPIO_TXCLK_HZ,
    PAR_COUNT   => 10,
    MSB_FIRST   => true)
    port map(
    par_clk     => gpio1_clk125,
    par_tstamp  => gpio1_time,
    par_out     => gpio1_txdata,
    reset_p     => gpio1_rst_p);

-- Status LEDs:
u_led0 : breathe_led
    generic map(RATE => breathe_led_rate(SYS_CLK_HZ))
    port map(led => diag_led(0), clk => sys_clk_buf);

u_led1 : breathe_led
    generic map(RATE => breathe_led_rate(GTX_TXCLK_HZ))
    port map(led => diag_led(1), clk => gtx0_txclk);

u_led2 : breathe_led
    generic map(RATE => breathe_led_rate(GTX_TXCLK_HZ))
    port map(led => diag_led(2), clk => gtx1_txclk);

diag_led(3) <= ref_time.tstamp(45);   -- About 0.93 Hz
diag_led(4) <= gtx0_time(45);         -- Should be sync'd
diag_led(5) <= gtx1_time(45);         -- Should be sync'd
diag_led(6) <= gpio0_time(45);        -- Should be sync'd
diag_led(7) <= gpio1_time(45);        -- Should be sync'd

-- Choose which diagnostic word drives the LEDs.
status_led <= diag_gtx0 when STATUS_SEL = 0
         else diag_gtx1 when STATUS_SEL = 1
         else diag_gpio0 when STATUS_SEL = 2
         else diag_gpio1 when STATUS_SEL = 3
         else diag_led;

-- Instantiate each GPIO serializer.
u_gpio0 : entity work.sgmii_serdes_tx
    generic map(IOSTANDARD => "LVDS")
    port map(
    TxD_p_pin   => gpio0_out_p,
    TxD_n_pin   => gpio0_out_n,
    par_data    => gpio0_txdata,
    clk_625     => gpio0_clk625,
    clk_125     => gpio0_clk125,
    reset_p     => gpio0_rst_p);

u_gpio1 : entity work.sgmii_serdes_tx
    generic map(IOSTANDARD => "LVDS")
    port map(
    TxD_p_pin   => gpio1_out_p,
    TxD_n_pin   => gpio1_out_n,
    par_data    => gpio1_txdata,
    clk_625     => gpio1_clk625,
    clk_125     => gpio1_clk125,
    reset_p     => gpio1_rst_p);

-- Instantiate paired GTX serializers with shared support logic.
u_gtx : entity work.gtx_wrapper
    port map(
    ext_clk125  => sys_clk_125,
    ext_reset_p => sys_reset_p,
    tx0_clk_out => gtx0_txclk,
    tx0_rst_out => gtx0_reset_p,
    tx0_data    => gtx0_txdata,
    gtx0_ref_p  => gtx0_ref_p,
    gtx0_ref_n  => gtx0_ref_n,
    gtx0_out_p  => gtx0_out_p,
    gtx0_out_n  => gtx0_out_n,
    tx1_clk_out => gtx1_txclk,
    tx1_rst_out => gtx1_reset_p,
    tx1_data    => gtx1_txdata,
    gtx1_ref_p  => gtx1_ref_p,
    gtx1_ref_n  => gtx1_ref_n,
    gtx1_out_p  => gtx1_out_p,
    gtx1_out_n  => gtx1_out_n);

end vc707_clksynth;
