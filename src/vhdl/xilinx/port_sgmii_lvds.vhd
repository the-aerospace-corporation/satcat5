--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SGMII port using Xilinx Ultrascale LVDS SERDES
--
-- This module is a thin wrapper for a Xilinx SGMII IP core, "1G/2.5G Ethernet
-- PCS/PMA or SGMII", that uses LVDS SERDES to implement an SGMII connection.
-- Documentation for this IP core is in Xilinx document PG047:
-- https://www.xilinx.com/support/documentation/ip_documentation/gig_ethernet_pcs_pma/v16_1/pg047-gig-eth-pcs-pma.pdf
--
-- This block depends on the IP-core, which can be added to the Vivado project
-- by running "generate_sgmii_lvds.tcl" in the Xilinx projects folder.
--
-- For a fully custom SGMII port using regular GPIO, see "port_sgmii_gpio".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_sgmii_lvds is
    generic (
    AUTONEG_EN        : boolean;                           -- Enable or disable autonegotiation
    REFCLK_FREQ_HZ    : integer := 625_000_000;            -- 125, 156.25, 625 MHz (Only 625 supported for now)
    VCONFIG           : vernier_config := VERNIER_DISABLED);
    port (
    -- External SGMII interfaces (direct to GTX pins)
    sgmii_rxp   : in  std_logic;
    sgmii_rxn   : in  std_logic;
    sgmii_txp   : out std_logic;
    sgmii_txn   : out std_logic;

    -- Generic internal port interfaces.
    prx_data    : out port_rx_m2s;
    ptx_data    : in  port_tx_s2m;
    ptx_ctrl    : out port_tx_m2s;
    port_shdn   : in  std_logic;

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- Reference clocks and reset.
    refclk_p    : in  std_logic;    -- RefClk: 125, 156.25, or 625 - must match the core choice!
    refclk_n    : in  std_logic;    -- (Differential)
    clkout_125  : out std_logic);   -- Optional 125 MHz output
end port_sgmii_lvds;

architecture port_sgmii_lvds of port_sgmii_lvds is

-- Component declaration for the black-box IP core.
-- Note that the core changes the refclk name depending upon the refclk frequency 
component sgmii_lvds0 is
    port(
    txn                  : out std_logic;
    txp                  : out std_logic;
    rxn                  : in  std_logic;
    rxp                  : in  std_logic;
    mmcm_locked_out      : out std_logic;
    sgmii_clk_r          : out std_logic;
    sgmii_clk_f          : out std_logic;
    sgmii_clk_en         : out std_logic;
    clk125_out           : out std_logic;
    clk625_out           : out std_logic;
    clk312_out           : out std_logic;
    rst_125_out          : out std_logic;
    refclk625_n          : in  std_logic;
    refclk625_p          : in  std_logic;
    gmii_txd             : in  std_logic_vector(7 DOWNTO 0);
    gmii_tx_en           : in  std_logic;
    gmii_tx_er           : in  std_logic;
    gmii_rxd             : out std_logic_vector(7 DOWNTO 0);
    gmii_rx_dv           : out std_logic;
    gmii_rx_er           : out std_logic;
    gmii_isolate         : out std_logic;
    configuration_vector : in  std_logic_vector(4 DOWNTO 0);
    an_interrupt         : out std_logic;
    an_adv_config_vector : in  std_logic_vector(15 DOWNTO 0);
    an_restart_config    : in  std_logic;
    speed_is_10_100      : in  std_logic;
    speed_is_100         : in  std_logic;
    status_vector        : out std_logic_vector(15 DOWNTO 0);
    reset                : in  std_logic;
    signal_detect        : in  std_logic;
    idelay_rdy_out       : out std_logic);
end component;

-- Control signals
signal txrx_pwren       : std_logic;
signal tx_pkten         : std_logic;
signal clk_locked       : std_logic;
signal config_vec       : std_logic_vector(4 downto 0);
signal auto_neg_cfg_vec : std_logic_vector(15 downto 0);
signal status_vec       : std_logic_vector(15 downto 0);
signal status_linkok    : std_logic;
signal status_sync      : std_logic;
signal status_disperr   : std_logic;
signal status_badsymb   : std_logic;
signal status_phyok     : std_logic;
signal aux_err_async    : std_logic;
signal aux_err_sync     : std_logic;

-- Receiver timestamp logic, if enabled.
signal txrx_reset       : std_logic := '0';
signal rx_treset        : std_logic := '0';
signal rx_tstamp        : tstamp_t := TSTAMP_DISABLED;
signal rx_tvalid        : std_logic := '0';
signal tx_treset        : std_logic := '0';
signal tx_tstamp        : tstamp_t := TSTAMP_DISABLED;
signal tx_tvalid        : std_logic := '0';

-- IP-core provides a quasi-GMII interface.
signal core_clk_125_out : std_logic;
signal gmii_tx_clk      : std_logic;
signal gmii_tx_data     : byte_t;
signal gmii_tx_en       : std_logic;
signal gmii_tx_er       : std_logic;
signal gmii_rx_clk      : std_logic;
signal gmii_rx_data     : byte_t;
signal gmii_rx_dv       : std_logic;
signal gmii_rx_er       : std_logic;
signal gmii_status      : port_status_t;

begin

-- Add preambles to the outgoing data:
u_amble_tx : entity work.eth_preamble_tx
    port map(
    out_data    => gmii_tx_data,
    out_dv      => gmii_tx_en,
    out_err     => gmii_tx_er,
    tx_clk      => gmii_tx_clk,
    tx_pwren    => txrx_pwren,
    tx_pkten    => tx_pkten,
    tx_tstamp   => tx_tstamp,
    tx_data     => ptx_data,
    tx_ctrl     => ptx_ctrl);

-- Receiver timestamp logic, if enabled.
-- TODO: This logic doesn't have visibility into the Xilinx SGMII IP core.
--  As a result, various internal delays will result in uncontrolled error.
--  The error will likely be an integer multiple of the bit period and may
--  be quasi-static on each reset.  The end-to-end result could be up to
--  +/- 100 nsec of uncorrectable bias.  Later versions should integrate
--  the core's PTP timestamps to correct this deficiency.
gen_tstamp : if VCONFIG.input_hz > 0 generate
    txrx_reset <= not clk_locked;

    u_rx_treset : sync_reset
        port map(
        in_reset_p  => txrx_reset,
        out_reset_p => rx_treset,
        out_clk     => gmii_rx_clk);

    u_tx_treset : sync_reset
        port map(
        in_reset_p  => txrx_reset,
        out_reset_p => tx_treset,
        out_clk     => gmii_tx_clk);

    u_rx_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => gmii_rx_clk,
        user_ctr    => rx_tstamp,
        user_lock   => rx_tvalid,
        user_rst_p  => rx_treset);

    u_tx_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => gmii_tx_clk,
        user_ctr    => tx_tstamp,
        user_lock   => tx_tvalid,
        user_rst_p  => tx_treset);
end generate;

-- Remove preambles from the incoming data:
u_amble_rx : entity work.eth_preamble_rx
    port map(
    raw_clk     => gmii_rx_clk,
    raw_lock    => clk_locked,
    raw_cken    => '1',
    raw_data    => gmii_rx_data,
    raw_dv      => gmii_rx_dv,
    raw_err     => gmii_rx_er,
    rate_word   => get_rate_word(1000),
    rx_tstamp   => rx_tstamp,
    aux_err     => aux_err_sync,
    status      => gmii_status,
    rx_data     => prx_data);

-- Flush received data if we get an 8b/10b decode error.
aux_err_async <= clk_locked and (status_disperr or status_badsymb);

u_errsync : sync_toggle2pulse
    generic map(RISING_ONLY => true)
    port map(
    in_toggle   => aux_err_async,
    out_strobe  => aux_err_sync,
    out_clk     => gmii_rx_clk);

-- Other control signals:
txrx_pwren  <= not port_shdn;
tx_pkten    <= clk_locked and status_linkok;

config_vec <= (
    4 => bool2bit(AUTONEG_EN),  -- Enable/disable auto-negotation
    3 => '0',                   -- Normal GMII operation
    2 => port_shdn,             -- Power-down strobe
    1 => '0',                   -- Disable loopback
    0 => '0');                  -- Bidirectional mode

-- From: https://docs.xilinx.com/r/en-US/pg047-gig-eth-pcs-pma/Configuration-and-Status-Vectors?section=pvz1665994834969__table_rrk_r2m_fvb
-- Need VHDL-2008 support to make these assignments cleaner with multi-bit assignments
-- TODO - is this vector required?  It appears we do not need to pulse the an_restart_config signal
auto_neg_cfg_vec <= (
    15           => '0',          -- SGMII: 0 - Link Down, 1 - Link Up
    14           => '0',          -- SGMII: Acknowledge (FIXME - not sure what this really means)
    13           => '0',          -- SGMII: Reserved
    12           => '1',          -- SGMII: 0 - Half Duplex, 1 - Full Duplex
    11           => '1',          -- SGMII Speed (11:10): 00: 10Mbps, 01: 100Mbps, 10: 1000Mbps, 11: Reserved
    10           => '0',
     9           => '0',          -- Reserved
     8           => '0',          -- SGMII - Reserved
     7           => '0',          -- SGMII - Reserved
     6           => '0',          -- Reserved
     5           => '0',          -- SGMII - Reserved
     4           => '0',          -- 4:1 - Reserved
     3           => '0',
     2           => '0',
     1           => '0',
     0           => '1');         -- 0: 1000BASE-X/2500BASE-X-Reserved, 1:SGMII

-- From the User Guide about "an_restart_config":
-- This signal is valid only when AN is present. The rising edge of this signal
-- is the enable signal to overwrite Bit 9 of Register 0. For triggering a fresh
-- AN Start, this signal should be deasserted and then reasserted.

status_linkok   <= status_vec(0);   -- SGMII link ready for use
status_sync     <= status_vec(1);   -- 8b/10b initial sync
status_disperr  <= status_vec(5);   -- 8b/10b disparity error
status_badsymb  <= status_vec(6);   -- 8b/10b decode error
status_phyok    <= status_vec(7);   -- Attached PHY status, if applicable

gmii_status <= (
    0 => port_shdn,
    1 => clk_locked,
    2 => status_sync,
    3 => status_linkok,
    4 => status_phyok,
    5 => rx_tvalid and tx_tvalid,
    others => '0');

-- Instantiate the IP-core.
-- TODO: Support for multiple instances, will need different core-names.
-- TODO: Cross-connect shared logic and clocks if there's more than one lane.
gmii_rx_clk <= core_clk_125_out;  -- This is the only 125 MHz clock avail from core
gmii_tx_clk <= core_clk_125_out;  -- This is the only 125 MHz clock avail from core
clkout_125  <= core_clk_125_out;
g_625MHz_clk: if REFCLK_FREQ_HZ = 625_000_000 generate
    u_ipcore : sgmii_lvds0
        port map(
            txp                     => sgmii_txp,
            txn                     => sgmii_txn,
            rxp                     => sgmii_rxp,
            rxn                     => sgmii_rxn,
            mmcm_locked_out         => clk_locked,
            sgmii_clk_r             => open,            -- Line-rate Tx clock
            sgmii_clk_f             => open,
            sgmii_clk_en            => open,
            clk125_out              => core_clk_125_out,
            clk625_out              => open,
            clk312_out              => open,
            rst_125_out             => open,
            refclk625_p             => refclk_p,
            refclk625_n             => refclk_n,
            gmii_txd                => gmii_tx_data,    -- GMII Tx
            gmii_tx_en              => gmii_tx_en,
            gmii_tx_er              => gmii_tx_er,
            gmii_rxd                => gmii_rx_data,    -- GMII Rx
            gmii_rx_dv              => gmii_rx_dv,
            gmii_rx_er              => gmii_rx_er,
            gmii_isolate            => open,
            configuration_vector    => config_vec,      -- See PG047, Table 2-39
            an_interrupt            => open,
            an_adv_config_vector    => auto_neg_cfg_vec,
            an_restart_config       => '0',
            speed_is_10_100         => '0',             -- Always 1000 Mbps
            speed_is_100            => '0',             -- Always 1000 Mbps
            status_vector           => status_vec,      -- See PG047, Table 2-41
            reset                   => port_shdn,       -- Reset the entire core
            signal_detect           => '1',
            idelay_rdy_out          => open
        );
end generate;
end port_sgmii_lvds;


