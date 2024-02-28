--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-X traffic statistics
--
-- Thin wrapper that connects a 10-GbE port to the "eth_statistics" block.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity portx_statistics is
    generic (
    COUNT_WIDTH : positive := 32;       -- Width of each statistics counter
    SAFE_COUNT  : boolean := true);     -- Safe counters (no overflow)
    port (
    -- Statistics interface (bytes received/sent, frames received/sent
    stats_req_t : in  std_logic;        -- Toggle to request next block
    bcst_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    bcst_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_frames : out unsigned(COUNT_WIDTH-1 downto 0);

    -- Port status-reporting.
    status_clk  : in  std_logic;
    status_word : out cfgbus_word;

    -- Error counters.
    err_port    : in  port_error_t;
    err_mii     : out byte_u;
    err_ovr_tx  : out byte_u;
    err_ovr_rx  : out byte_u;
    err_pkt     : out byte_u;
    err_ptp_tx  : out byte_u;
    err_ptp_rx  : out byte_u;

    -- Generic internal port interface (monitor only)
    rx_data     : in  port_rx_m2sx;
    tx_data     : in  port_tx_s2mx;
    tx_ctrl     : in  port_tx_m2sx);
end portx_statistics;

architecture portx_statistics of portx_statistics is

signal rx_word                  : xword_t;
signal rx_nlast,    tx_nlast    : integer range 0 to 8;
signal rx_clk,      tx_clk      : std_logic;
signal rx_reset,    tx_reset    : std_logic;
signal rx_write,    tx_write    : std_logic;

begin

-- Clock reassignment, as a workaround for simulator bugs.
rx_clk      <= to_01_std(rx_data.clk);
tx_clk      <= to_01_std(tx_ctrl.clk);

-- Some simulators require a pseudo-delay to keep clock-edges aligned.
rx_reset    <= rx_data.reset_p;
rx_word     <= rx_data.data;
rx_nlast    <= rx_data.nlast;
rx_write    <= rx_data.write;

tx_reset    <= tx_ctrl.reset_p;
tx_nlast    <= tx_data.nlast;
tx_write    <= tx_data.valid and tx_ctrl.ready;

-- Instantiate the inner block.
u_stats : entity work.eth_statistics
    generic map(
    IO_BYTES    => 8,
    COUNT_WIDTH => COUNT_WIDTH,
    SAFE_COUNT  => SAFE_COUNT)
    port map(
    stats_req_t => stats_req_t,
    bcst_bytes  => bcst_bytes,
    bcst_frames => bcst_frames,
    rcvd_bytes  => rcvd_bytes,
    rcvd_frames => rcvd_frames,
    sent_bytes  => sent_bytes,
    sent_frames => sent_frames,
    port_rate   => rx_data.rate,
    port_status => rx_data.status,
    status_clk  => status_clk,
    status_word => status_word,
    err_port    => err_port,
    err_mii     => err_mii,
    err_ovr_tx  => err_ovr_tx,
    err_ovr_rx  => err_ovr_rx,
    err_pkt     => err_pkt,
    err_ptp_tx  => err_ptp_tx,
    err_ptp_rx  => err_ptp_rx,
    rx_reset_p  => rx_reset,
    rx_clk      => rx_clk,
    rx_data     => rx_word,
    rx_nlast    => rx_nlast,
    rx_write    => rx_write,
    tx_reset_p  => tx_reset,
    tx_clk      => tx_clk,
    tx_nlast    => tx_nlast,
    tx_write    => tx_write);

end portx_statistics;
