--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "port_sgmii_gpio"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity wrap_port_sgmii_gpio is
    generic (
    TX_INVERT   : boolean := false;     -- Invert Tx polarity
    TX_IOSTD    : string := "LVDS_25";  -- Tx I/O standard
    RX_INVERT   : boolean := false;     -- Invert Rx polarity
    RX_IOSTD    : string := "LVDS_25";  -- Rx I/O standard
    RX_BIAS_EN  : boolean := false;     -- Enable split-termination biasing
    RX_TERM_EN  : boolean := true;      -- Enable internal termination
    SHAKE_WAIT  : boolean := true;      -- Wait for MAC/PHY handshake?
    PTP_ENABLE  : boolean := false;     -- Enable PTP timestamps?
    PTP_REF_HZ  : integer := 0;         -- Vernier reference frequency
    PTP_TAU_MS  : integer := 50;        -- Tracking time constant (msec)
    PTP_AUX_EN  : boolean := true);     -- Enable extra tracking filter?
    port (
    -- External SGMII interface.
    sgmii_rxp   : in  std_logic;
    sgmii_rxn   : in  std_logic;
    sgmii_txp   : out std_logic;
    sgmii_txn   : out std_logic;

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
    sw_tx_reset : out std_logic;

    -- Vernier reference time (optional)
    tref_vclka  : in  std_logic;
    tref_vclkb  : in  std_logic;
    tref_tnext  : in  std_logic;
    tref_tstamp : in  std_logic_vector(47 downto 0);

    -- Reference clock and reset.
    clk_125     : in  std_logic;
    clk_200     : in  std_logic;
    clk_625_00  : in  std_logic;
    clk_625_90  : in  std_logic;
    reset_p     : in  std_logic);
end wrap_port_sgmii_gpio;

architecture wrap_port_sgmii_gpio of wrap_port_sgmii_gpio is

constant VCONFIG : vernier_config := create_vernier_config(
    value_else_zero(PTP_REF_HZ, PTP_ENABLE), real(PTP_TAU_MS), PTP_AUX_EN);

signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_s2m;
signal tx_ctrl  : port_tx_m2s;
signal ref_time : port_timeref;

begin

-- Convert port signals.
sw_rx_clk       <= rx_data.clk;
sw_rx_data      <= rx_data.data;
sw_rx_last      <= rx_data.last;
sw_rx_write     <= rx_data.write;
sw_rx_error     <= rx_data.rxerr;
sw_rx_rate      <= rx_data.rate;
sw_rx_tsof      <= std_logic_vector(rx_data.tsof);
sw_rx_status    <= rx_data.status;
sw_rx_reset     <= rx_data.reset_p;
sw_tx_clk       <= tx_ctrl.clk;
sw_tx_ready     <= tx_ctrl.ready;
sw_tx_pstart    <= tx_ctrl.pstart;
sw_tx_tnow      <= std_logic_vector(tx_ctrl.tnow);
sw_tx_error     <= tx_ctrl.txerr;
sw_tx_reset     <= tx_ctrl.reset_p;
tx_data.data    <= sw_tx_data;
tx_data.last    <= sw_tx_last;
tx_data.valid   <= sw_tx_valid;

-- Convert Vernier signals.
ref_time.vclka  <= tref_vclka;
ref_time.vclkb  <= tref_vclkb;
ref_time.tnext  <= tref_tnext;
ref_time.tstamp <= unsigned(tref_tstamp);

-- Unit being wrapped.
u_wrap : entity work.port_sgmii_gpio
    generic map(
    TX_INVERT   => TX_INVERT,
    TX_IOSTD    => TX_IOSTD,
    RX_INVERT   => RX_INVERT,
    RX_IOSTD    => RX_IOSTD,
    RX_BIAS_EN  => RX_BIAS_EN,
    RX_TERM_EN  => RX_TERM_EN,
    SHAKE_WAIT  => SHAKE_WAIT,
    VCONFIG     => VCONFIG)
    port map(
    sgmii_rxp   => sgmii_rxp,
    sgmii_rxn   => sgmii_rxn,
    sgmii_txp   => sgmii_txp,
    sgmii_txn   => sgmii_txn,
    ref_time    => ref_time,
    prx_data    => rx_data,
    ptx_data    => tx_data,
    ptx_ctrl    => tx_ctrl,
    port_shdn   => reset_p,
    clk_125     => clk_125,
    clk_200     => clk_200,
    clk_625_00  => clk_625_00,
    clk_625_90  => clk_625_90);

end wrap_port_sgmii_gpio;
