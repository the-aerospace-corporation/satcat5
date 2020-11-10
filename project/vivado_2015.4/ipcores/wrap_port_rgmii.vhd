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
-- Port-type wrapper for "port_rgmii"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_port_rgmii is
    generic (
    RXCLK_ALIGN : boolean := false; -- Enable precision clock-buffer deskew
    RXCLK_LOCAL : boolean := false; -- Enable input clock buffer (local)
    RXCLK_GLOBL : boolean := true;  -- Enable input clock buffer (global)
    RXCLK_DELAY : integer := 0;     -- Input clock delay, in picoseconds (typ. 0 or 2000)
    RXDAT_DELAY : integer := 0;     -- Input data/control delay, in picoseconds
    POWER_SAVE  : boolean := true); -- Enable power-saving on idle ports
    port (
    -- External RGMII interface.
    rgmii_txc   : out std_logic;
    rgmii_txd   : out std_logic_vector(3 downto 0);
    rgmii_txctl : out std_logic;
    rgmii_rxc   : in  std_logic;
    rgmii_rxd   : in  std_logic_vector(3 downto 0);
    rgmii_rxctl : in  std_logic;

    -- Network port
    sw_rx_clk   : out std_logic;
    sw_rx_data  : out std_logic_vector(7 downto 0);
    sw_rx_last  : out std_logic;
    sw_rx_write : out std_logic;
    sw_rx_error : out std_logic;
    sw_rx_reset : out std_logic;
    sw_tx_clk   : out std_logic;
    sw_tx_data  : in  std_logic_vector(7 downto 0);
    sw_tx_last  : in  std_logic;
    sw_tx_valid : in  std_logic;
    sw_tx_ready : out std_logic;
    sw_tx_error : out std_logic;
    sw_tx_reset : out std_logic;

    -- Reference clock and reset.
    clk_125     : in  std_logic;    -- Main reference clock
    clk_txc     : in  std_logic;    -- Same clock or delayed clock
    reset_p     : in  std_logic);   -- Reset / port shutdown
end wrap_port_rgmii;

architecture wrap_port_rgmii of wrap_port_rgmii is

signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_m2s;
signal tx_ctrl  : port_tx_s2m;

begin

-- Convert port signals.
sw_rx_clk       <= rx_data.clk;
sw_rx_data      <= rx_data.data;
sw_rx_last      <= rx_data.last;
sw_rx_write     <= rx_data.write;
sw_rx_error     <= rx_data.rxerr;
sw_rx_reset     <= rx_data.reset_p;
sw_tx_clk       <= tx_ctrl.clk;
sw_tx_ready     <= tx_ctrl.ready;
sw_tx_error     <= tx_ctrl.txerr;
sw_tx_reset     <= tx_ctrl.reset_p;
tx_data.data    <= sw_tx_data;
tx_data.last    <= sw_tx_last;
tx_data.valid   <= sw_tx_valid;

-- Unit being wrapped.
-- Note: Unit conversion from picoseconds (integer) to nanoseconds (real)
--       is a workaround for bugs in certain Vivado versions.  See also:
--       https://www.xilinx.com/support/answers/58038.html
u_wrap : entity work.port_rgmii
    generic map(
    RXCLK_ALIGN => RXCLK_ALIGN,
    RXCLK_LOCAL => RXCLK_LOCAL,
    RXCLK_GLOBL => RXCLK_GLOBL,
    RXCLK_DELAY => 0.001 * real(RXCLK_DELAY),
    RXDAT_DELAY => 0.001 * real(RXDAT_DELAY),
    POWER_SAVE  => POWER_SAVE)
    port map(
    rgmii_txc   => rgmii_txc,
    rgmii_txd   => rgmii_txd,
    rgmii_txctl => rgmii_txctl,
    rgmii_rxc   => rgmii_rxc,
    rgmii_rxd   => rgmii_rxd,
    rgmii_rxctl => rgmii_rxctl,
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    clk_125     => clk_125,
    clk_txc     => clk_txc,
    reset_p     => reset_p);

end wrap_port_rgmii;
