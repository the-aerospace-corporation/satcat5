--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-interface wrapper for a generic AXI-stream
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--
-- Note: The "rx_error" port is used for out-of-band error strobes,
--       for compatibility with the Xilinx TEMAC or AVB output streams.
--       If it is unused, leave it disconnected or connect it to zero.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity wrap_port_stream is
    generic (
    DELAY_REG   : boolean;      -- Enable delay register?
    RATE_MBPS   : integer;      -- Estimated throughput
    RX_MIN_FRM  : natural;      -- Pad Rx frames to min size?
    RX_HAS_FCS  : boolean;      -- Does Rx data include FCS?
    TX_HAS_FCS  : boolean;      -- Retain FCS for each Tx frame?
    PTP_ENABLE  : boolean;      -- Enable PTP timestamps?
    PTP_REF_HZ  : integer;      -- Vernier reference frequency
    PTP_TAU_MS  : integer;      -- Tracking time constant (msec)
    PTP_AUX_EN  : boolean;      -- Enable extra tracking filter?
    RX_CLK_HZ   : integer;      -- Frequency of rx_clk (PTP only)
    TX_CLK_HZ   : integer);     -- Frequency of tx_clk (PTP only)
    port (
    -- AXI-stream interface (Rx).
    rx_clk      : in  std_logic;
    rx_data     : in  std_logic_vector(7 downto 0);
    rx_error    : in  std_logic_vector(0 downto 0);
    rx_last     : in  std_logic;
    rx_valid    : in  std_logic;
    rx_ready    : out std_logic;
    rx_reset    : in  std_logic;

    -- AXI-stream interface (Tx).
    tx_clk      : in  std_logic;
    tx_data     : out std_logic_vector(7 downto 0);
    tx_last     : out std_logic;
    tx_valid    : out std_logic;
    tx_ready    : in  std_logic;
    tx_reset    : in  std_logic;

    -- Vernier reference time (optional)
    tref_vclka  : in  std_logic;
    tref_vclkb  : in  std_logic;
    tref_tnext  : in  std_logic;
    tref_tstamp : in  std_logic_vector(47 downto 0);

    -- Network port
    sw_rx_clk   : out std_logic;
    sw_rx_data  : out std_logic_vector(7 downto 0);
    sw_rx_last  : out std_logic;
    sw_rx_write : out std_logic;
    sw_rx_error : out std_logic;
    sw_rx_rate  : out std_logic_vector(15 downto 0);
    sw_rx_status: out std_logic_vector(7 downto 0);
    sw_rx_tsof  : out std_logic_vector(47 downto 0);
    sw_rx_reset : out std_logic;
    sw_tx_clk   : out std_logic;
    sw_tx_data  : in  std_logic_vector(7 downto 0);
    sw_tx_last  : in  std_logic;
    sw_tx_valid : in  std_logic;
    sw_tx_ready : out std_logic;
    sw_tx_error : out std_logic;
    sw_tx_pstart: out std_logic;
    sw_tx_tnow  : out std_logic_vector(47 downto 0);
    sw_tx_reset : out std_logic);
end wrap_port_stream;

architecture wrap_port_stream of wrap_port_stream is

constant VCONFIG : vernier_config := create_vernier_config(
    value_else_zero(PTP_REF_HZ, PTP_ENABLE), real(PTP_TAU_MS), PTP_AUX_EN);

signal prx_data : port_rx_m2s;
signal ptx_data : port_tx_s2m;
signal ptx_ctrl : port_tx_m2s;
signal ref_time : port_timeref;

begin

-- Convert port signals.
sw_rx_clk       <= prx_data.clk;
sw_rx_data      <= prx_data.data;
sw_rx_last      <= prx_data.last;
sw_rx_write     <= prx_data.write;
sw_rx_error     <= prx_data.rxerr;
sw_rx_rate      <= prx_data.rate;
sw_rx_tsof      <= std_logic_vector(prx_data.tsof);
sw_rx_status    <= prx_data.status;
sw_rx_reset     <= prx_data.reset_p;
sw_tx_clk       <= ptx_ctrl.clk;
sw_tx_ready     <= ptx_ctrl.ready;
sw_tx_pstart    <= ptx_ctrl.pstart;
sw_tx_tnow      <= std_logic_vector(ptx_ctrl.tnow);
sw_tx_error     <= ptx_ctrl.txerr;
sw_tx_reset     <= ptx_ctrl.reset_p;
ptx_data.data   <= sw_tx_data;
ptx_data.last   <= sw_tx_last;
ptx_data.valid  <= sw_tx_valid;

-- Convert Vernier signals.
ref_time.vclka  <= tref_vclka;
ref_time.vclkb  <= tref_vclkb;
ref_time.tnext  <= tref_tnext;
ref_time.tstamp <= unsigned(tref_tstamp);

-- Unit being wrapped.
u_wrap : entity work.port_stream
    generic map(
    DELAY_REG   => DELAY_REG,
    RATE_MBPS   => RATE_MBPS,
    RX_MIN_FRM  => RX_MIN_FRM,
    RX_HAS_FCS  => RX_HAS_FCS,
    TX_HAS_FCS  => TX_HAS_FCS,
    RX_CLK_HZ   => value_else_zero(RX_CLK_HZ, PTP_ENABLE),
    TX_CLK_HZ   => value_else_zero(TX_CLK_HZ, PTP_ENABLE),
    VCONFIG     => VCONFIG)
    port map(
    rx_clk      => rx_clk,
    rx_data     => rx_data,
    rx_error    => rx_error(0),
    rx_last     => rx_last,
    rx_valid    => rx_valid,
    rx_ready    => rx_ready,
    rx_reset    => rx_reset,
    tx_clk      => tx_clk,
    tx_data     => tx_data,
    tx_last     => tx_last,
    tx_valid    => tx_valid,
    tx_ready    => tx_ready,
    tx_reset    => tx_reset,
    ref_time    => ref_time,
    prx_data    => prx_data,
    ptx_data    => ptx_data,
    ptx_ctrl    => ptx_ctrl);

end wrap_port_stream;
