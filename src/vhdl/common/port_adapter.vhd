--------------------------------------------------------------------------
-- Copyright 2019-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Internal port adapter, for switches with a single uplink port
--
-- Some switch designs support runt packets, and only have one or two
-- ports that must be fully 802.3 compliant.  This block acts as a shim
-- that ensures outgoing packets are padded as required.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_adapter is
    port (
    -- Switch-facing interface.
    sw_rx_data  : out port_rx_m2s;
    sw_tx_data  : in  port_tx_s2m;
    sw_tx_ctrl  : out port_tx_m2s;

    -- MAC-facing interface.
    mac_rx_data : in  port_rx_m2s;
    mac_tx_data : out port_tx_s2m;
    mac_tx_ctrl : in  port_tx_m2s);
end port_adapter;

architecture port_adapter of port_adapter is

signal adjust_data      : axi_stream8;
signal flow_fifo_empty  : std_logic;
signal flow_fifo_full   : std_logic;
signal flow_fifo_write  : std_logic;

begin

-- Clocks and other strobes are forwarded directly.
sw_rx_data.clk      <= mac_rx_data.clk;
sw_rx_data.rxerr    <= mac_rx_data.rxerr;
sw_rx_data.rate     <= mac_rx_data.rate;
sw_rx_data.status   <= mac_rx_data.status;
sw_rx_data.reset_p  <= mac_rx_data.reset_p;
sw_tx_ctrl.clk      <= mac_tx_ctrl.clk;
sw_tx_ctrl.pstart   <= mac_tx_ctrl.pstart and flow_fifo_empty;
sw_tx_ctrl.tnow     <= mac_tx_ctrl.tnow;
sw_tx_ctrl.txerr    <= mac_tx_ctrl.txerr;
sw_tx_ctrl.reset_p  <= mac_tx_ctrl.reset_p;

-- Incoming data needs no modification.
sw_rx_data.data     <= mac_rx_data.data;
sw_rx_data.last     <= mac_rx_data.last;
sw_rx_data.write    <= mac_rx_data.write;
sw_rx_data.tsof     <= mac_rx_data.tsof;

-- Outgoing data may need padding.
u_adj : entity work.eth_frame_adjust
    port map(
    in_data     => sw_tx_data.data,
    in_last     => sw_tx_data.last,
    in_valid    => sw_tx_data.valid,
    in_ready    => sw_tx_ctrl.ready,
    out_data    => adjust_data.data,
    out_last    => adjust_data.last,
    out_valid   => adjust_data.valid,
    out_ready   => adjust_data.ready,
    clk         => mac_tx_ctrl.clk,
    reset_p     => mac_tx_ctrl.reset_p);

-- AXI standard allows downstream blocks to wait for valid before
-- asserting ready; eth_frame_adjust can't handle this condition.
-- To avoid possibility of deadlock, add a small FIFO here.
-- (No extra cost for making this FIFO up to 16 words.)
adjust_data.ready   <= not flow_fifo_full;
flow_fifo_write     <= adjust_data.valid and adjust_data.ready;

u_flow_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => adjust_data.data,
    in_last     => adjust_data.last,
    in_write    => flow_fifo_write,
    out_data    => mac_tx_data.data,
    out_last    => mac_tx_data.last,
    out_valid   => mac_tx_data.valid,
    out_read    => mac_tx_ctrl.ready,
    fifo_full   => flow_fifo_full,
    fifo_empty  => flow_fifo_empty,
    fifo_hfull  => open,
    fifo_hempty => open,
    fifo_error  => open,
    clk         => mac_tx_ctrl.clk,
    reset_p     => mac_tx_ctrl.reset_p);

end port_adapter;