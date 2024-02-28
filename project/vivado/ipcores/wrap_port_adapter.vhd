--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "port_adapter"
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

entity wrap_port_adapter is
    port (
    -- Switch-facing port
    sw_rx_clk       : out std_logic;
    sw_rx_data      : out std_logic_vector(7 downto 0);
    sw_rx_last      : out std_logic;
    sw_rx_write     : out std_logic;
    sw_rx_error     : out std_logic;
    sw_rx_rate      : out std_logic_vector(15 downto 0);
    sw_rx_status    : out std_logic_vector(7 downto 0);
    sw_rx_tsof      : out std_logic_vector(47 downto 0);
    sw_rx_reset     : out std_logic;
    sw_tx_clk       : out std_logic;
    sw_tx_data      : in  std_logic_vector(7 downto 0);
    sw_tx_last      : in  std_logic;
    sw_tx_valid     : in  std_logic;
    sw_tx_ready     : out std_logic;
    sw_tx_error     : out std_logic;
    sw_tx_pstart    : out std_logic;
    sw_tx_tnow      : out std_logic_vector(47 downto 0);
    sw_tx_reset     : out std_logic;

    -- MAC-facing port
    mac_rx_clk      : in  std_logic;
    mac_rx_data     : in  std_logic_vector(7 downto 0);
    mac_rx_last     : in  std_logic;
    mac_rx_write    : in  std_logic;
    mac_rx_error    : in  std_logic;
    mac_rx_rate     : in  std_logic_vector(15 downto 0);
    mac_rx_status   : in  std_logic_vector(7 downto 0);
    mac_rx_tsof     : in  std_logic_vector(47 downto 0);
    mac_rx_reset    : in  std_logic;
    mac_tx_clk      : in  std_logic;
    mac_tx_data     : out std_logic_vector(7 downto 0);
    mac_tx_last     : out std_logic;
    mac_tx_valid    : out std_logic;
    mac_tx_ready    : in  std_logic;
    mac_tx_error    : in  std_logic;
    mac_tx_pstart   : in  std_logic;
    mac_tx_tnow     : in  std_logic_vector(47 downto 0);
    mac_tx_reset    : in  std_logic);
end wrap_port_adapter;

architecture wrap_port_adapter of wrap_port_adapter is

signal sw_rxd, mac_rxd : port_rx_m2s;
signal sw_txd, mac_txd : port_tx_s2m;
signal sw_txc, mac_txc : port_tx_m2s;

begin

-- Convert port signals.
sw_rx_clk       <= sw_rxd.clk;
sw_rx_data      <= sw_rxd.data;
sw_rx_last      <= sw_rxd.last;
sw_rx_write     <= sw_rxd.write;
sw_rx_error     <= sw_rxd.rxerr;
sw_rx_rate      <= sw_rxd.rate;
sw_rx_tsof      <= std_logic_vector(sw_rxd.tsof);
sw_rx_status    <= sw_rxd.status;
sw_rx_reset     <= sw_rxd.reset_p;
sw_tx_clk       <= sw_txc.clk;
sw_tx_ready     <= sw_txc.ready;
sw_tx_pstart    <= sw_txc.pstart;
sw_tx_tnow      <= std_logic_vector(sw_txc.tnow);
sw_tx_error     <= sw_txc.txerr;
sw_tx_reset     <= sw_txc.reset_p;
sw_txd.data     <= sw_tx_data;
sw_txd.last     <= sw_tx_last;
sw_txd.valid    <= sw_tx_valid;

mac_rxd.clk     <= mac_rx_clk;
mac_rxd.data    <= mac_rx_data;
mac_rxd.last    <= mac_rx_last;
mac_rxd.write   <= mac_rx_write;
mac_rxd.rxerr   <= mac_rx_error;
mac_rxd.rate    <= mac_rx_rate;
mac_rxd.tsof    <= unsigned(mac_rx_tsof);
mac_rxd.status  <= mac_rx_status;
mac_rxd.reset_p <= mac_rx_reset;
mac_txc.clk     <= mac_tx_clk;
mac_txc.ready   <= mac_tx_ready;
mac_txc.pstart  <= mac_tx_pstart;
mac_txc.tnow    <= unsigned(mac_tx_tnow);
mac_txc.txerr   <= mac_tx_error;
mac_txc.reset_p <= mac_tx_reset;
mac_tx_data     <= mac_txd.data;
mac_tx_last     <= mac_txd.last;
mac_tx_valid    <= mac_txd.valid;

-- Unit being wrapped.
u_wrap : entity work.port_adapter
    port map(
    sw_rx_data  => sw_rxd,
    sw_tx_data  => sw_txd,
    sw_tx_ctrl  => sw_txc,
    mac_rx_data => mac_rxd,
    mac_tx_data => mac_txd,
    mac_tx_ctrl => mac_txc);

end wrap_port_adapter;
