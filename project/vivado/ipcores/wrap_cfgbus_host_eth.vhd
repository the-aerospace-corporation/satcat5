--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "cfgbus_host_eth"
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

entity wrap_cfgbus_host_eth is
    generic (
    CFG_ETYPE       : std_logic_vector(15 downto 0);
    CFG_MACADDR     : std_logic_vector(47 downto 0);
    MIN_FRAME       : integer := 64;
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

    -- Network port.
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
    sw_tx_tnow      : out std_logic_vector(47 downto 0);
    sw_tx_reset     : out std_logic;

    -- Interrupt (optional)
    irq_out         : out std_logic;

    -- System clock and reset.
    sys_clk         : in  std_logic;
    reset_p         : in  std_logic);
end wrap_cfgbus_host_eth;

architecture wrap_cfgbus_host_eth of wrap_cfgbus_host_eth is

signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert network signals.
sw_rx_clk       <= sys_clk;
sw_rx_error     <= '0';
sw_rx_rate      <= get_rate_word(1);
sw_rx_tsof      <= (others => '0');
sw_rx_status    <= (others => '0');
sw_rx_reset     <= reset_p;
sw_tx_clk       <= sys_clk;
sw_tx_error     <= '0';
sw_tx_tnow      <= (others => '0');
sw_tx_reset     <= reset_p;

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
u_wrap : entity work.cfgbus_host_eth
    generic map(
    CFG_ETYPE   => CFG_ETYPE,
    CFG_MACADDR => CFG_MACADDR,
    APPEND_FCS  => true,
    MIN_FRAME   => MIN_FRAME,
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    rx_data     => sw_tx_data,
    rx_last     => sw_tx_last,
    rx_valid    => sw_tx_valid,
    rx_ready    => sw_tx_ready,
    tx_data     => sw_rx_data,
    tx_last     => sw_rx_last,
    tx_valid    => sw_rx_write,
    tx_ready    => '1',
    irq_out     => irq_out,
    txrx_clk    => sys_clk,
    reset_p     => reset_p);

end wrap_cfgbus_host_eth;
