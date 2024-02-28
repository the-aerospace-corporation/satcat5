--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: Communicate with Zynq PS ethernet over a pmod serial port
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity converter_zed_top is
    port (
    -- Serial interface
    eos_pmod1 : inout std_logic;
    eos_pmod2 : inout std_logic;
    eos_pmod3 : inout std_logic;
    eos_pmod4 : inout std_logic);
end converter_zed_top;

architecture converter_zed_top of converter_zed_top is

    signal rx_data      : array_rx_m2s(1 downto 0);
    signal tx_data      : array_tx_s2m(1 downto 0);
    signal tx_ctrl      : array_tx_m2s(1 downto 0);

    signal adj_rx_data  : port_rx_m2s;
    signal adj_tx_data  : port_tx_s2m;
    signal adj_tx_ctrl  : port_tx_m2s;

    signal switch_err_t : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

    signal clk_125 : std_logic;
    signal reset_n : std_logic;
    signal reset_p : std_logic;

    signal ps_gmii_col     : std_logic;
    signal ps_gmii_crs     : std_logic;
    signal ps_gmii_rx_dv   : std_logic;
    signal ps_gmii_rx_er   : std_logic;
    signal ps_gmii_rxd     : std_logic_vector(7 downto 0);
    signal ps_gmii_tx_clk  : std_logic;
    signal ps_gmii_tx_en   : std_logic;
    signal ps_gmii_tx_er   : std_logic;
    signal ps_gmii_txd     : std_logic_vector(7 downto 0);
    -- same clock signal for tx and rx
    signal ps_gmii_clk     : std_logic;

begin

u_ps : entity work.ps_wrapper
    port map(
    clk_125           => clk_125,
    ps_gmii_col       => '0',
    ps_gmii_crs       => '0',
    ps_gmii_rx_clk    => ps_gmii_clk,
    ps_gmii_rx_dv     => ps_gmii_rx_dv,
    ps_gmii_rx_er     => ps_gmii_rx_er,
    ps_gmii_rxd       => ps_gmii_rxd,
    ps_gmii_tx_clk    => ps_gmii_clk,
    ps_gmii_tx_en(0)  => ps_gmii_tx_en,
    ps_gmii_tx_er(0)  => ps_gmii_tx_er,
    ps_gmii_txd       => ps_gmii_txd,
    ps_reset_n        => reset_n);

reset_p <= not reset_n;

-- GMII port, using the adjusted data
u_gmii : entity work.port_gmii_internal
    port map(
    -- GMII interface.
    gmii_txc   => ps_gmii_clk,
    gmii_txd   => ps_gmii_rxd,
    gmii_txen  => ps_gmii_rx_dv,
    gmii_txerr => ps_gmii_rx_er,
    gmii_rxc   => ps_gmii_clk,
    gmii_rxd   => ps_gmii_txd,
    gmii_rxdv  => ps_gmii_tx_en,
    gmii_rxerr => ps_gmii_tx_er,
    rx_data    => adj_rx_data,
    tx_data    => adj_tx_data,
    tx_ctrl    => adj_tx_ctrl,
    clk_125    => clk_125,
    reset_p    => reset_p);

-- Define the uplink port adapter.
-- (Adapter pads runt packets as needed before transmission.)
u_adapt : entity work.port_adapter
    port map(
    sw_rx_data  => rx_data(0),
    sw_tx_data  => tx_data(0),
    sw_tx_ctrl  => tx_ctrl(0),
    mac_rx_data => adj_rx_data,
    mac_tx_data => adj_tx_data,
    mac_tx_ctrl => adj_tx_ctrl);

-- switch core: Frame check and output FIFOs
u_core : entity work.switch_dual
    generic map(
    ALLOW_RUNT      => true,
    OBUF_KBYTES     => 16)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => switch_err_t);


u_pmod : entity work.port_serial_auto
    generic map(
    CLKREF_HZ => 125_000_000,
    UART_BAUD => 921_600)
    port map(
    ext_pads(0) => eos_pmod1,
    ext_pads(1) => eos_pmod2,
    ext_pads(2) => eos_pmod3,
    ext_pads(3) => eos_pmod4,
    rx_data => rx_data(1),
    tx_data => tx_data(1),
    tx_ctrl => tx_ctrl(1),
    refclk  => clk_125,
    reset_p => reset_p);


end converter_zed_top;
