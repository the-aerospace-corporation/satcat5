--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- FPGA-internal GMII port for MAC-to-MAC operation. 
-- Useful for integrating with other IPs that expose a GMII
-- interface and must connect to a switch core or 
-- require conversion to a different SatCat5 port type,
-- such as the Zynq and Zynq Ultrascale+ PS ethernet peripherals.
--
-- This module adapts a GMII interface to the generic internal
-- format used throughout this design.
--
-- As this is an internal port, clock shifting logic and device-specific 
-- I/O structures are not implemented. Clocks are assumed to already be
-- on the FPGA clock network
--
-- See also: IEEE 802.3-2002 (8 March 2002) section 35
-- https://web.archive.org/web/20100620164048/http://people.ee.duke.edu/~mbrooke/ece4006/spring2003/G5/802-3zStandard.pdf
--
-- Note: 10/100 Mbps modes are not supported.
--
-- Note: COL (collision detect) and CS (carrier sense) are not supported
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.switch_types.all;

entity port_gmii_internal is
    port (
    -- GMII interface.
    gmii_txc    : out std_logic;
    gmii_txd    : out std_logic_vector(7 downto 0);
    gmii_txen   : out std_logic;
    gmii_txerr  : out std_logic;
    gmii_rxc    : in  std_logic;
    gmii_rxd    : in  std_logic_vector(7 downto 0);
    gmii_rxdv   : in  std_logic;
    gmii_rxerr  : in  std_logic;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Reference clock and reset.
    clk_125     : in  std_logic;    -- Main reference clock
    reset_p     : in  std_logic);   -- Reset / port shutdown
end port_gmii_internal;

architecture port_gmii_internal of port_gmii_internal is

signal txdata           : std_logic_vector(7 downto 0) := (others => '0');
signal txmeta           : std_logic_vector(3 downto 0);
signal txdv, txerr      : std_logic := '0';

signal rxclk            : std_logic;
signal rxlock           : std_logic := '0';
signal rxdata           : std_logic_vector(7 downto 0) := (others => '0');
signal rxdv, rxerr      : std_logic;

signal reset_sync       : std_logic;        -- Reset sync'd to clk_125

signal status_word      : port_status_t;

begin

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => clk_125);

-- 802.3z 35.2.2.1 GTX_CLK is continuous
gmii_txc <= clk_125;
-- 802.3z 35.2.2.2 RX_CLK is continuous
rxclk <= gmii_rxc;
rxlock <= '1';

-- No conversion necessary
gmii_txd <= txdata;
gmii_txen <= txdv;
gmii_txerr <= txerr;
rxdata <= gmii_rxd;
rxdv <= gmii_rxdv;
rxerr <= gmii_rxerr;

-- Status-reporting
status_word <= (0 => reset_sync, others => '0');

-- Receive state machine, including preamble removal.
u_amble_rx : entity work.eth_preamble_rx
    generic map(
    DV_XOR_ERR  => false)
    port map(
    raw_clk     => rxclk,
    raw_lock    => rxlock,
    raw_data    => rxdata,
    raw_dv      => rxdv,
    raw_err     => rxerr,
    rate_word   => get_rate_word(1000),
    status      => status_word,
    rx_data     => rx_data);

-- Transmit state machine, including insertion of preamble,
-- start-of-frame delimiter, and inter-packet gap.
-- This is irrelevant
txmeta <= "110" & rxlock;   -- 1 Gbps full duplex
u_amble_tx : entity work.eth_preamble_tx
    generic map(DV_XOR_ERR => false)
    port map(
    out_data    => txdata,
    out_dv      => txdv,
    out_err     => txerr,
    tx_clk      => clk_125,
    tx_pwren    => '1',
    tx_pkten    => rxlock,
    tx_idle     => txmeta,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl);

end port_gmii_internal;
