--------------------------------------------------------------------------
-- Copyright 2020-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- FPGA-internal GMII port for MAC-to-MAC operation. 
-- Useful for integrating with other IPs that expose a GMII
-- interface and must connect to a switch core or 
-- require conversion to a different SatCat5 port type,
-- such as the Zynq and Zynq Ultrascale+ PS ethernet peripherals.
--
-- This module adapts a GMII interface to the generic internal
-- format used throughout this design.
--
-- As this is an internal port, clock shifting logic and device-specific 
-- I/O structures are not implemented. Clocks are assumed to already be
-- on the FPGA clock network
--
-- See also: IEEE 802.3-2002 (8 March 2002) section 35
-- https://web.archive.org/web/20100620164048/http://people.ee.duke.edu/~mbrooke/ece4006/spring2003/G5/802-3zStandard.pdf
--
-- Note: 10/100 Mbps modes are not supported.
--
-- Note: COL (collision detect) and CS (carrier sense) are not supported
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_gmii_internal is
    generic (
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- GMII interface.
    gmii_txc    : out std_logic;
    gmii_txd    : out std_logic_vector(7 downto 0);
    gmii_txen   : out std_logic;
    gmii_txerr  : out std_logic;
    gmii_rxc    : in  std_logic;
    gmii_rxd    : in  std_logic_vector(7 downto 0);
    gmii_rxdv   : in  std_logic;
    gmii_rxerr  : in  std_logic;

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Reference clock and reset.
    clk_125     : in  std_logic;    -- Main reference clock
    reset_p     : in  std_logic);   -- Reset / port shutdown
end port_gmii_internal;

architecture port_gmii_internal of port_gmii_internal is

signal tx_meta          : std_logic_vector(3 downto 0);
signal rx_lock          : std_logic := '0';
signal lcl_tstamp       : tstamp_t := (others => '0');
signal lcl_tvalid       : std_logic := '0';
signal reset_sync       : std_logic;        -- Reset sync'd to clk_125
signal status_word      : port_status_t;

begin

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => clk_125);

-- 802.3z 35.2.2.1 GTX_CLK is continuous (i.e., no shutdown during reset)
gmii_txc    <= clk_125;

-- 802.3z 35.2.2.2 RX_CLK is continuous (i.e., always considered locked)
rx_lock     <= '1';

-- Status-reporting
status_word <= (0 => reset_sync, 1 => lcl_tvalid, others => '0');

-- If enabled, generate timestamps with a Vernier synchronizer.
gen_ptp : if VCONFIG.input_hz > 0 generate
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => gmii_rxc,
        user_ctr    => lcl_tstamp,
        user_lock   => lcl_tvalid,
        user_rst_p  => reset_sync);
end generate;

-- Receive state machine, including preamble removal.
u_amble_rx : entity work.eth_preamble_rx
    generic map(
    DV_XOR_ERR  => false)
    port map(
    raw_clk     => gmii_rxc,
    raw_lock    => rx_lock,
    raw_data    => gmii_rxd,
    raw_dv      => gmii_rxdv,
    raw_err     => gmii_rxerr,
    rate_word   => get_rate_word(1000),
    rx_tstamp   => lcl_tstamp,
    status      => status_word,
    rx_data     => rx_data);

-- Transmit state machine, including insertion of preamble,
-- start-of-frame delimiter, and inter-packet gap.
tx_meta <= "110" & rx_lock;     -- 1 Gbps full duplex
u_amble_tx : entity work.eth_preamble_tx
    generic map(DV_XOR_ERR => false)
    port map(
    out_data    => gmii_txd,
    out_dv      => gmii_txen,
    out_err     => gmii_txerr,
    tx_clk      => clk_125,
    tx_pwren    => '1',
    tx_pkten    => rx_lock,
    tx_tstamp   => lcl_tstamp,
    tx_idle     => tx_meta,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl);

end port_gmii_internal;
