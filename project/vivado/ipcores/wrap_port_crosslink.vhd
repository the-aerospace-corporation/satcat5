--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "port_crosslink"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity wrap_port_crosslink is
    generic (
    RUNT_PORTA  : boolean;          -- Allow runt packets on Port A?
    RUNT_PORTB  : boolean;          -- Allow runt packets on Port B?
    RATE_DIV    : integer;          -- Rate limit of 1/N
    PTP_ENABLE  : boolean := false; -- Enable PTP timestamps?
    PTP_REF_HZ  : integer := 0;     -- Vernier reference frequency
    PTP_TAU_MS  : integer := 50;    -- Tracking time constant (msec)
    PTP_AUX_EN  : boolean := true); -- Enable extra tracking filter?
    port (
    -- Network port A
    pa_rx_clk       : out std_logic;
    pa_rx_data      : out std_logic_vector(7 downto 0);
    pa_rx_last      : out std_logic;
    pa_rx_write     : out std_logic;
    pa_rx_error     : out std_logic;
    pa_rx_rate      : out std_logic_vector(15 downto 0);
    pa_rx_status    : out std_logic_vector(7 downto 0);
    pa_rx_tsof      : out std_logic_vector(47 downto 0);
    pa_rx_reset     : out std_logic;
    pa_tx_clk       : out std_logic;
    pa_tx_data      : in  std_logic_vector(7 downto 0);
    pa_tx_last      : in  std_logic;
    pa_tx_valid     : in  std_logic;
    pa_tx_ready     : out std_logic;
    pa_tx_error     : out std_logic;
    pa_tx_pstart    : out std_logic;
    pa_tx_tnow      : out std_logic_vector(47 downto 0);
    pa_tx_reset     : out std_logic;

    -- Network port B
    pb_rx_clk       : out std_logic;
    pb_rx_data      : out std_logic_vector(7 downto 0);
    pb_rx_last      : out std_logic;
    pb_rx_write     : out std_logic;
    pb_rx_error     : out std_logic;
    pb_rx_rate      : out std_logic_vector(15 downto 0);
    pb_rx_status    : out std_logic_vector(7 downto 0);
    pb_rx_tsof      : out std_logic_vector(47 downto 0);
    pb_rx_reset     : out std_logic;
    pb_tx_clk       : out std_logic;
    pb_tx_data      : in  std_logic_vector(7 downto 0);
    pb_tx_last      : in  std_logic;
    pb_tx_valid     : in  std_logic;
    pb_tx_ready     : out std_logic;
    pb_tx_error     : out std_logic;
    pb_tx_pstart    : out std_logic;
    pb_tx_tnow      : out std_logic_vector(47 downto 0);
    pb_tx_reset     : out std_logic;

    -- Vernier reference time (optional)
    tref_vclka  : in  std_logic;
    tref_vclkb  : in  std_logic;
    tref_tnext  : in  std_logic;
    tref_tstamp : in  std_logic_vector(47 downto 0);

    -- Other control
    ref_clk     : in  std_logic;    -- Transfer clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end wrap_port_crosslink;

architecture wrap_port_crosslink of wrap_port_crosslink is

constant VCONFIG : vernier_config := create_vernier_config(
    value_else_zero(PTP_REF_HZ, PTP_ENABLE), real(PTP_TAU_MS), PTP_AUX_EN);

signal ref_time   : port_timeref;
signal arxd, brxd : port_rx_m2s;
signal atxd, btxd : port_tx_s2m;
signal atxc, btxc : port_tx_m2s;

begin

-- Convert port signals.
pa_rx_clk   <= arxd.clk;
pa_rx_data  <= arxd.data;
pa_rx_last  <= arxd.last;
pa_rx_write <= arxd.write;
pa_rx_error <= arxd.rxerr;
pa_rx_rate  <= arxd.rate;
pa_rx_tsof  <= std_logic_vector(arxd.tsof);
pa_rx_status<= arxd.status;
pa_rx_reset <= arxd.reset_p;
pa_tx_clk   <= atxc.clk;
pa_tx_ready <= atxc.ready;
pa_tx_tnow  <= std_logic_vector(atxc.tnow);
pa_tx_pstart<= atxc.pstart;
pa_tx_error <= atxc.txerr;
pa_tx_reset <= atxc.reset_p;
atxd.data   <= pa_tx_data;
atxd.last   <= pa_tx_last;
atxd.valid  <= pa_tx_valid;

pb_rx_clk   <= brxd.clk;
pb_rx_data  <= brxd.data;
pb_rx_last  <= brxd.last;
pb_rx_write <= brxd.write;
pb_rx_error <= brxd.rxerr;
pb_rx_rate  <= brxd.rate;
pb_rx_tsof  <= std_logic_vector(brxd.tsof);
pb_rx_status<= brxd.status;
pb_rx_reset <= brxd.reset_p;
pb_tx_clk   <= btxc.clk;
pb_tx_ready <= btxc.ready;
pb_tx_pstart<= btxc.pstart;
pb_tx_tnow  <= std_logic_vector(btxc.tnow);
pb_tx_error <= btxc.txerr;
pb_tx_reset <= btxc.reset_p;
btxd.data   <= pb_tx_data;
btxd.last   <= pb_tx_last;
btxd.valid  <= pb_tx_valid;

-- Convert Vernier signals.
ref_time.vclka  <= tref_vclka;
ref_time.vclkb  <= tref_vclkb;
ref_time.tnext  <= tref_tnext;
ref_time.tstamp <= unsigned(tref_tstamp);

-- Unit being wrapped.
u_wrap : entity work.port_crosslink
    generic map(
    RUNT_PORTA  => RUNT_PORTA,
    RUNT_PORTB  => RUNT_PORTB,
    RATE_DIV    => RATE_DIV,
    VCONFIG     => VCONFIG)
    port map(
    rxa_data    => arxd,
    txa_data    => atxd,
    txa_ctrl    => atxc,
    rxb_data    => brxd,
    txb_data    => btxd,
    txb_ctrl    => btxc,
    ref_time    => ref_time,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

end wrap_port_crosslink;
