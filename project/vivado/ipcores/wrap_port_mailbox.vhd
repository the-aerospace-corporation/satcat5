--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Port-type wrapper for "port_mailbox"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_port_mailbox is
    generic (
    DEV_ADDR    : integer := 0;         -- ConfigBus peripheral address
    MIN_FRAME   : integer := 0;         -- Minimum output frame size
    APPEND_FCS  : boolean := true;      -- Append FCS to each sent frame??
    STRIP_FCS   : boolean := true);     -- Remove FCS from received frames?
    port (
    -- Internal Ethernet port.
    sw_rx_clk       : out std_logic;
    sw_rx_data      : out std_logic_vector(7 downto 0);
    sw_rx_last      : out std_logic;
    sw_rx_write     : out std_logic;
    sw_rx_error     : out std_logic;
    sw_rx_rate      : out std_logic_vector(15 downto 0);
    sw_rx_status    : out std_logic_vector(7 downto 0);
    sw_rx_reset     : out std_logic;
    sw_tx_clk       : out std_logic;
    sw_tx_data      : in  std_logic_vector(7 downto 0);
    sw_tx_last      : in  std_logic;
    sw_tx_valid     : in  std_logic;
    sw_tx_ready     : out std_logic;
    sw_tx_error     : out std_logic;
    sw_tx_reset     : out std_logic;

    -- ConfigBus interface
    cfg_clk         : in  std_logic;
    cfg_devaddr     : in  std_logic_vector(7 downto 0);
    cfg_regaddr     : in  std_logic_vector(9 downto 0);
    cfg_wdata       : in  std_logic_vector(31 downto 0);
    cfg_wstrb       : in  std_logic_vector(3 downto 0);
    cfg_wrcmd       : in  std_logic;
    cfg_rdcmd       : in  std_logic;
    cfg_reset_p     : in  std_logic;
    cfg_rdata       : out std_logic_vector(31 downto 0);
    cfg_rdack       : out std_logic;
    cfg_rderr       : out std_logic;
    cfg_irq         : out std_logic);
end wrap_port_mailbox;

architecture wrap_port_mailbox of wrap_port_mailbox is

signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_s2m;
signal tx_ctrl  : port_tx_m2s;
signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert port signals.
sw_rx_clk       <= rx_data.clk;
sw_rx_data      <= rx_data.data;
sw_rx_last      <= rx_data.last;
sw_rx_write     <= rx_data.write;
sw_rx_error     <= rx_data.rxerr;
sw_rx_rate      <= rx_data.rate;
sw_rx_status    <= rx_data.status;
sw_rx_reset     <= rx_data.reset_p;
sw_tx_clk       <= tx_ctrl.clk;
sw_tx_ready     <= tx_ctrl.ready;
sw_tx_error     <= tx_ctrl.txerr;
sw_tx_reset     <= tx_ctrl.reset_p;
tx_data.data    <= sw_tx_data;
tx_data.last    <= sw_tx_last;
tx_data.valid   <= sw_tx_valid;

-- Convert ConfigBus signals.
cfg_cmd.clk     <= cfg_clk;
cfg_cmd.sysaddr <= 0;   -- Unused
cfg_cmd.devaddr <= u2i(cfg_devaddr);
cfg_cmd.regaddr <= u2i(cfg_regaddr);
cfg_cmd.wdata   <= cfg_wdata;
cfg_cmd.wstrb   <= cfg_wstrb;
cfg_cmd.wrcmd   <= cfg_wrcmd;
cfg_cmd.rdcmd   <= cfg_rdcmd;
cfg_cmd.reset_p <= cfg_reset_p;
cfg_rdata       <= cfg_ack.rdata;
cfg_rdack       <= cfg_ack.rdack;
cfg_rderr       <= cfg_ack.rderr;
cfg_irq         <= cfg_ack.irq;

-- Mailbox port.
u_wrap : entity work.port_mailbox
    generic map(
    DEV_ADDR    => DEV_ADDR,
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => STRIP_FCS)
    port map(
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end wrap_port_mailbox;
