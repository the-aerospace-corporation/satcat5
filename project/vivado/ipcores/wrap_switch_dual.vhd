--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "switch_dual"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_switch_dual is
    generic (
    ALLOW_JUMBO     : boolean;      -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;      -- Allow runt frames? (Size < 64 bytes)
    OBUF_KBYTES     : integer);     -- Output buffer size (kilobytes)
    port (
    -- Network port A
    pa_rx_clk       : in  std_logic;
    pa_rx_data      : in  std_logic_vector(7 downto 0);
    pa_rx_last      : in  std_logic;
    pa_rx_write     : in  std_logic;
    pa_rx_error     : in  std_logic;
    pa_rx_rate      : in  std_logic_vector(15 downto 0);
    pa_rx_status    : in  std_logic_vector(7 downto 0);
    pa_rx_tsof      : in  std_logic_vector(47 downto 0);
    pa_rx_reset     : in  std_logic;
    pa_tx_clk       : in  std_logic;
    pa_tx_data      : out std_logic_vector(7 downto 0);
    pa_tx_last      : out std_logic;
    pa_tx_valid     : out std_logic;
    pa_tx_ready     : in  std_logic;
    pa_tx_error     : in  std_logic;
    pa_tx_pstart    : in  std_logic;
    pa_tx_tnow      : in  std_logic_vector(47 downto 0);
    pa_tx_reset     : in  std_logic;

    -- Network port B
    pb_rx_clk       : in  std_logic;
    pb_rx_data      : in  std_logic_vector(7 downto 0);
    pb_rx_last      : in  std_logic;
    pb_rx_rate      : in  std_logic_vector(15 downto 0);
    pb_rx_status    : in  std_logic_vector(7 downto 0);
    pb_rx_write     : in  std_logic;
    pb_rx_error     : in  std_logic;
    pb_rx_tsof      : in  std_logic_vector(47 downto 0);
    pb_rx_reset     : in  std_logic;
    pb_tx_clk       : in  std_logic;
    pb_tx_data      : out std_logic_vector(7 downto 0);
    pb_tx_last      : out std_logic;
    pb_tx_valid     : out std_logic;
    pb_tx_ready     : in  std_logic;
    pb_tx_error     : in  std_logic;
    pb_tx_pstart    : in  std_logic;
    pb_tx_tnow      : in  std_logic_vector(47 downto 0);
    pb_tx_reset     : in  std_logic;

    -- Error reporting (see switch_aux).
    errvec_t        : out std_logic_vector(7 downto 0));
end wrap_switch_dual;

architecture wrap_switch_dual of wrap_switch_dual is

signal rx_data  : array_rx_m2s(1 downto 0);
signal tx_data  : array_tx_s2m(1 downto 0);
signal tx_ctrl  : array_tx_m2s(1 downto 0);

begin

-- Convert port signals.
rx_data(0).clk      <= pa_rx_clk;
rx_data(0).data     <= pa_rx_data;
rx_data(0).last     <= pa_rx_last;
rx_data(0).write    <= pa_rx_write;
rx_data(0).rxerr    <= pa_rx_error;
rx_data(0).rate     <= pa_rx_rate;
rx_data(0).status   <= pa_rx_status;
rx_data(0).tsof     <= unsigned(pa_rx_tsof);
rx_data(0).reset_p  <= pa_rx_reset;
tx_ctrl(0).clk      <= pa_tx_clk;
tx_ctrl(0).ready    <= pa_tx_ready;
tx_ctrl(0).txerr    <= pa_tx_error;
tx_ctrl(0).pstart   <= pa_tx_pstart;
tx_ctrl(0).tnow     <= unsigned(pa_tx_tnow);
tx_ctrl(0).reset_p  <= pa_tx_reset;
pa_tx_data          <= tx_data(0).data;
pa_tx_last          <= tx_data(0).last;
pa_tx_valid         <= tx_data(0).valid;

rx_data(1).clk      <= pb_rx_clk;
rx_data(1).data     <= pb_rx_data;
rx_data(1).last     <= pb_rx_last;
rx_data(1).write    <= pb_rx_write;
rx_data(1).rxerr    <= pb_rx_error;
rx_data(1).rate     <= pb_rx_rate;
rx_data(1).status   <= pb_rx_status;
rx_data(1).tsof     <= unsigned(pb_rx_tsof);
rx_data(1).reset_p  <= pb_rx_reset;
tx_ctrl(1).clk      <= pb_tx_clk;
tx_ctrl(1).ready    <= pb_tx_ready;
tx_ctrl(1).txerr    <= pb_tx_error;
tx_ctrl(1).pstart   <= pb_tx_pstart;
tx_ctrl(1).tnow     <= unsigned(pb_tx_tnow);
tx_ctrl(1).reset_p  <= pb_tx_reset;
pb_tx_data          <= tx_data(1).data;
pb_tx_last          <= tx_data(1).last;
pb_tx_valid         <= tx_data(1).valid;

-- Unit being wrapped.
u_wrap : entity work.switch_dual
    generic map(
    ALLOW_JUMBO     => ALLOW_JUMBO,
    ALLOW_RUNT      => ALLOW_RUNT,
    OBUF_KBYTES     => OBUF_KBYTES)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => errvec_t);

end wrap_switch_dual;
