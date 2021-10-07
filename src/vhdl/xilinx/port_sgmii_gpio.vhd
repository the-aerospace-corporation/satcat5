--------------------------------------------------------------------------
-- Copyright 2019, 2020, 2021 The Aerospace Corporation
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
-- Xilinx 7-series interface for one or more SGMII ports
--
-- This module instantiates:
--   * A self-synchronizing oversampled SGMII receiver.
--   * A thin OSERDESE2 wrapper for an SGMII transmitter.
--   * Generic SGMII encode/decode/state-machine logic.
--
-- This configuration is suitable for use with 7-series GPIO.
-- For use with GTX and other SERDES, see "port_sgmii_gtx".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity port_sgmii_gpio is
    generic (
    TX_INVERT   : boolean := false;     -- Invert Tx polarity
    TX_IOSTD    : string := "LVDS_25";  -- Tx I/O standard
    RX_INVERT   : boolean := false;     -- Invert Rx polarity
    RX_IOSTD    : string := "LVDS_25";  -- Rx I/O standard
    RX_BIAS_EN  : boolean := false;     -- Enable split-termination biasing
    RX_TERM_EN  : boolean := true;      -- Enable differential termination
    SHAKE_WAIT  : boolean := false);    -- Wait for MAC/PHY handshake?
    port (
    -- External SGMII interfaces (direct to FPGA pins)
    sgmii_rxp   : in  std_logic;
    sgmii_rxn   : in  std_logic;
    sgmii_txp   : out std_logic;
    sgmii_txn   : out std_logic;

    -- Generic internal port interfaces.
    prx_data    : out port_rx_m2s;
    ptx_data    : in  port_tx_s2m;
    ptx_ctrl    : out port_tx_m2s;
    port_shdn   : in  std_logic;

    -- Reference clocks and reset.
    clk_125     : in  std_logic;
    clk_200     : in  std_logic;
    clk_625_00  : in  std_logic;
    clk_625_90  : in  std_logic);
end port_sgmii_gpio;

architecture xilinx of port_sgmii_gpio is

signal tx_data      : std_logic_vector(9 downto 0);
signal rx_raw_data  : std_logic_vector(39 downto 0);
signal rx_sync_data : std_logic_vector(9 downto 0);
signal rx_raw_next  : std_logic;
signal rx_sync_next : std_logic;
signal rx_lock      : std_logic;

begin

-- Transmit serializer.
u_tx : entity work.sgmii_serdes_tx
    generic map(
    IOSTANDARD  => TX_IOSTD,
    POL_INVERT  => TX_INVERT)
    port map(
    TxD_p_pin   => sgmii_txp,
    TxD_n_pin   => sgmii_txn,
    par_data    => tx_data,
    clk_625     => clk_625_00,
    clk_125     => clk_125,
    reset_p     => port_shdn);

-- Oversampled receive deserializer.
u_rx : entity work.sgmii_serdes_rx
    generic map(
    BIAS_ENABLE => RX_BIAS_EN,
    DIFF_TERM   => RX_TERM_EN,
    IOSTANDARD  => RX_IOSTD,
    POL_INVERT  => RX_INVERT,
    REFCLK_MHZ  => 200)
    port map(
    RxD_p_pin   => sgmii_rxp,
    RxD_n_pin   => sgmii_rxn,
    out_clk     => clk_200,
    out_data    => rx_raw_data,
    out_next    => rx_raw_next,
    clk_125     => clk_125,
    clk_625_00  => clk_625_00,
    clk_625_90  => clk_625_90,
    reset_p     => port_shdn);

-- Detect bit transitions in oversampled data.
u_sync : entity work.sgmii_data_sync
    generic map(LANE_COUNT => 10)
    port map(
    in_data     => rx_raw_data,
    in_next     => rx_raw_next,
    out_data    => rx_sync_data,
    out_next    => rx_sync_next,
    out_locked  => rx_lock,
    clk         => clk_200,
    reset_p     => port_shdn);

-- Instantiate platform-independent interface logic.
u_if : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => SHAKE_WAIT)
    port map(
    tx_clk      => clk_125,
    tx_cken     => '1',
    tx_data     => tx_data,
    rx_clk      => clk_200,
    rx_cken     => rx_sync_next,
    rx_lock     => rx_lock,
    rx_data     => rx_sync_data,
    prx_data    => prx_data,
    ptx_data    => ptx_data,
    ptx_ctrl    => ptx_ctrl,
    reset_p     => port_shdn);

end xilinx;
