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
-- Port-type wrapper for "port_status_inline"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_port_inline_status is
    generic (
    -- Inline-status parameters (see port_inline_status)
    SEND_EGRESS     : boolean;          -- Send to external network port?
    SEND_INGRESS    : boolean;          -- Send to internal switch port?
    MSG_BYTES       : integer;          -- Bytes per status message (0 = none)
    MSG_ETYPE       : std_logic_vector(15 downto 0);
    MAC_DEST        : std_logic_vector(47 downto 0);
    MAC_SOURCE      : std_logic_vector(47 downto 0);
    AUTO_DELAY_CLKS : integer;          -- Send every N clocks, or 0 for on-demand
    MIN_FRAME_BYTES : integer);         -- Pad to minimum frame size?
    port (
    -- Local switch port.
    lcl_rx_clk      : out std_logic;
    lcl_rx_data     : out std_logic_vector(7 downto 0);
    lcl_rx_last     : out std_logic;
    lcl_rx_write    : out std_logic;
    lcl_rx_error    : out std_logic;
    lcl_rx_rate     : out std_logic_vector(15 downto 0);
    lcl_rx_reset    : out std_logic;
    lcl_tx_clk      : out std_logic;
    lcl_tx_data     : in  std_logic_vector(7 downto 0);
    lcl_tx_last     : in  std_logic;
    lcl_tx_valid    : in  std_logic;
    lcl_tx_ready    : out std_logic;
    lcl_tx_error    : out std_logic;
    lcl_tx_reset    : out std_logic;

    -- Remote network port.
    net_rx_clk      : in  std_logic;
    net_rx_data     : in  std_logic_vector(7 downto 0);
    net_rx_last     : in  std_logic;
    net_rx_write    : in  std_logic;
    net_rx_error    : in  std_logic;
    net_rx_rate     : in  std_logic_vector(15 downto 0);
    net_rx_reset    : in  std_logic;
    net_tx_clk      : in  std_logic;
    net_tx_data     : out std_logic_vector(7 downto 0);
    net_tx_last     : out std_logic;
    net_tx_valid    : out std_logic;
    net_tx_ready    : in  std_logic;
    net_tx_error    : in  std_logic;
    net_tx_reset    : in  std_logic;

    -- Optional status message and write-toggle.
    status_val      : in  std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');
    status_wr_t     : in  std_logic := '0');
end wrap_port_inline_status;

architecture wrap_port_inline_status of wrap_port_inline_status is

signal lcl_rxd, net_rxd : port_rx_m2s;
signal lcl_txd, net_txd : port_tx_m2s;
signal lcl_txc, net_txc : port_tx_s2m;

begin

-- Convert port signals.
lcl_rx_clk      <= lcl_rxd.clk;
lcl_rx_data     <= lcl_rxd.data;
lcl_rx_last     <= lcl_rxd.last;
lcl_rx_write    <= lcl_rxd.write;
lcl_rx_error    <= lcl_rxd.rxerr;
lcl_rx_rate     <= lcl_rxd.rate;
lcl_rx_reset    <= lcl_rxd.reset_p;
lcl_tx_clk      <= lcl_txc.clk;
lcl_tx_ready    <= lcl_txc.ready;
lcl_tx_error    <= lcl_txc.txerr;
lcl_tx_reset    <= lcl_txc.reset_p;
lcl_txd.data    <= lcl_tx_data;
lcl_txd.last    <= lcl_tx_last;
lcl_txd.valid   <= lcl_tx_valid;

net_rxd.clk     <= net_rx_clk;
net_rxd.data    <= net_rx_data;
net_rxd.last    <= net_rx_last;
net_rxd.write   <= net_rx_write;
net_rxd.rxerr   <= net_rx_error;
net_rxd.rate    <= net_rx_rate;
net_rxd.reset_p <= net_rx_reset;
net_txc.clk     <= net_tx_clk;
net_txc.ready   <= net_tx_ready;
net_txc.txerr   <= net_tx_error;
net_txc.reset_p <= net_tx_reset;
net_tx_data     <= net_txd.data;
net_tx_last     <= net_txd.last;
net_tx_valid    <= net_txd.valid;

-- Inline status injection
u_status : entity work.port_inline_status
    generic map(
    SEND_EGRESS     => SEND_EGRESS,
    SEND_INGRESS    => SEND_INGRESS,
    MSG_BYTES       => MSG_BYTES,
    MSG_ETYPE       => MSG_ETYPE,
    MAC_DEST        => MAC_DEST,
    MAC_SOURCE      => MAC_SOURCE,
    AUTO_DELAY_CLKS => AUTO_DELAY_CLKS,
    MIN_FRAME_BYTES => MIN_FRAME_BYTES)
    port map(
    lcl_rx_data     => lcl_rxd,
    lcl_tx_data     => lcl_txd,
    lcl_tx_ctrl     => lcl_txc,
    net_rx_data     => net_rxd,
    net_tx_data     => net_txd,
    net_tx_ctrl     => net_txc,
    status_val      => status_val,
    status_wr_t     => status_wr_t);

end wrap_port_inline_status;
