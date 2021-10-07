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
-- Port-type wrapper for "cfgbus_host_uart"
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

entity wrap_cfgbus_host_uart is
    generic (
    CFG_ETYPE       : std_logic_vector(15 downto 0);
    CFG_MACADDR     : std_logic_vector(47 downto 0);
    CLKREF_HZ       : positive;     -- Reference clock rate (Hz)
    UART_BAUD_HZ    : positive;     -- Input and output rate (bps)
    RD_TIMEOUT      : positive := 16);
    port (
    -- ConfigBus host interface.
    cfg_clk         : out std_logic;
    cfg_sysaddr     : out std_logic_vector(11 downto 0);
    cfg_devaddr     : out std_logic_vector(7 downto 0);
    cfg_regaddr     : out std_logic_vector(9 downto 0);
    cfg_wdata       : out std_logic_vector(31 downto 0);
    cfg_wstrb       : out std_logic_vector(3 downto 0);
    cfg_wrcmd       : out std_logic;
    cfg_rdcmd       : out std_logic;
    cfg_reset_p     : out std_logic;
    cfg_rdata       : in  std_logic_vector(31 downto 0);
    cfg_rdack       : in  std_logic;
    cfg_rderr       : in  std_logic;
    cfg_irq         : in  std_logic;

    -- UART port.
    uart_txd        : out std_logic;
    uart_rxd        : in  std_logic;

    -- System clock and reset.
    sys_clk         : in  std_logic;
    reset_p         : in  std_logic);
end wrap_cfgbus_host_uart;

architecture wrap_cfgbus_host_uart of wrap_cfgbus_host_uart is

signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert ConfigBus signals.
cfg_clk         <= cfg_cmd.clk;
cfg_sysaddr     <= i2s(cfg_cmd.sysaddr, 12);
cfg_devaddr     <= i2s(cfg_cmd.devaddr, 8);
cfg_regaddr     <= i2s(cfg_cmd.regaddr, 10);
cfg_wdata       <= cfg_cmd.wdata;
cfg_wstrb       <= cfg_cmd.wstrb;
cfg_wrcmd       <= cfg_cmd.wrcmd;
cfg_rdcmd       <= cfg_cmd.rdcmd;
cfg_reset_p     <= cfg_cmd.reset_p;
cfg_ack.rdata   <= cfg_rdata;
cfg_ack.rdack   <= cfg_rdack;
cfg_ack.rderr   <= cfg_rderr;
cfg_ack.irq     <= cfg_irq;

-- Wrapped unit. (Switch-Tx is our Rx.)
u_wrap : entity work.cfgbus_host_uart
    generic map(
    CFG_ETYPE   => CFG_ETYPE,
    CFG_MACADDR => CFG_MACADDR,
    CLKREF_HZ   => CLKREF_HZ,
    UART_BAUD   => UART_BAUD_HZ,
    UART_REPLY  => true,
    CHECK_FCS   => true,
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    uart_rxd    => uart_rxd,
    uart_txd    => uart_txd,
    sys_clk     => sys_clk,
    reset_p     => reset_p);

end wrap_cfgbus_host_uart;
