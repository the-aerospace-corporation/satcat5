--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Virtual port wrapper for "cfgbus_host_eth"
--
-- This module is a thin wrapper for "cfgbus_host_eth" that connects
-- it to the generic internal port interface.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_cfgbus is
    generic (
    CFG_ETYPE   : mac_type_t := x"5C01";
    CFG_MACADDR : mac_addr_t := x"5A5ADEADBEEF";
    MIN_FRAME   : natural := 64;        -- Pad reply to minimum size? (bytes)
    RD_TIMEOUT  : positive := 16);      -- ConfigBus read timeout (clocks)
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Other control
    sys_clk     : in  std_logic;        -- Reference clock
    reset_p     : in  std_logic);       -- Reset / shutdown
end port_cfgbus;

architecture port_cfgbus of port_cfgbus is

begin

-- Convert network signals.
rx_data.clk     <= sys_clk;
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= (others => '0');
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= reset_p;
tx_ctrl.clk     <= sys_clk;
tx_ctrl.pstart  <= '1';
tx_ctrl.tnow    <= TSTAMP_DISABLED;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= reset_p;

-- Wrapped ConfigBus host. (Switch-Tx is our Rx.)
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
    rx_data     => tx_data.data,
    rx_last     => tx_data.last,
    rx_valid    => tx_data.valid,
    rx_ready    => tx_ctrl.ready,
    tx_data     => rx_data.data,
    tx_last     => rx_data.last,
    tx_valid    => rx_data.write,
    tx_ready    => '1',
    irq_out     => open,
    txrx_clk    => sys_clk,
    reset_p     => reset_p);

end port_cfgbus;
