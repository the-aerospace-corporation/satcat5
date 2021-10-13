--------------------------------------------------------------------------
-- Copyright 2020, 2021 The Aerospace Corporation
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
-- SGMII port using Xilinx 7-series GTX SERDES
--
-- This module is a thin wrapper for a Xilinx SGMII IP core, "1G/2.5G Ethernet
-- PCS/PMA or SGMII", that uses a GTX SERDES to implement an SGMII connection.
-- Documentation for this IP core is in Xilinx document PG047:
-- https://www.xilinx.com/support/documentation/ip_documentation/gig_ethernet_pcs_pma/v16_1/pg047-gig-eth-pcs-pma.pdf
--
-- This block depends on the IP-core, which can be added to the Vivado project
-- by running "generate_sgmii_gtx.tcl" in the Xilinx projects folder.
--
-- For an SGMII port using regular GPIO, see "port_sgmii_xilinx".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity port_sgmii_gtx is
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

    -- Reference clocks and reset.
    gtref_125p  : in  std_logic;    -- GTX RefClk
    gtref_125n  : in  std_logic;    -- (Differential)
    clkin_200   : in  std_logic;    -- IDELAYCTRL clock
    clkout_125  : out std_logic);   -- Optional 125 MHz output
end port_sgmii_gtx;

architecture port_sgmii_gtx of port_sgmii_gtx is

-- Component declaration for the black-box IP core.
component sgmii_gtx0 is
    port(
    gtrefclk_p              : in  std_logic;
    gtrefclk_n              : in  std_logic;
    gtrefclk_out            : out std_logic;
    gtrefclk_bufg_out       : out std_logic;
    txp                     : out std_logic;
    txn                     : out std_logic;
    rxp                     : in std_logic;
    rxn                     : in std_logic;
    resetdone               : out std_logic;
    userclk_out             : out std_logic;
    userclk2_out            : out std_logic;
    rxuserclk_out           : out std_logic;
    rxuserclk2_out          : out std_logic;
    pma_reset_out           : out std_logic;
    mmcm_locked_out         : out std_logic;
    independent_clock_bufg  : in std_logic;
    sgmii_clk_r             : out std_logic;
    sgmii_clk_f             : out std_logic;
    sgmii_clk_en            : out std_logic;
    gmii_txd                : in std_logic_vector(7 downto 0);
    gmii_tx_en              : in std_logic;
    gmii_tx_er              : in std_logic;
    gmii_rxd                : out std_logic_vector(7 downto 0);
    gmii_rx_dv              : out std_logic;
    gmii_rx_er              : out std_logic;
    gmii_isolate            : out std_logic;
    configuration_vector    : in std_logic_vector(4 downto 0);
    speed_is_10_100         : in std_logic;
    speed_is_100            : in std_logic;
    status_vector           : out std_logic_vector(15 downto 0);
    reset                   : in std_logic;
    signal_detect           : in std_logic;
    gt0_qplloutclk_out      : out std_logic;
    gt0_qplloutrefclk_out   : out std_logic);
end component;

-- Control signals
signal txrx_pwren       : std_logic;
signal tx_pkten         : std_logic;
signal clk_locked       : std_logic;
signal config_vec       : std_logic_vector(4 downto 0);
signal status_vec       : std_logic_vector(15 downto 0);
signal status_linkok    : std_logic;
signal status_sync      : std_logic;
signal status_disperr   : std_logic;
signal status_badsymb   : std_logic;
signal status_phyok     : std_logic;
signal aux_err_async    : std_logic;
signal aux_err_sync     : std_logic;

-- IP-core provides a quasi-GMII interface.
signal gmii_user_clk2   : std_logic;
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
    tx_data     => ptx_data,
    tx_ctrl     => ptx_ctrl);

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
    4 => '1',       -- Enable auto-negotation
    3 => '0',       -- Normal GMII operation
    2 => port_shdn, -- Power-down strobe
    1 => '0',       -- Disable loopback
    0 => '0');      -- Bidirectional mode

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
    others => '0');

-- Instantiate the IP-core.
-- TODO: Support for multiple instances, will need different core-names.
-- TODO: Cross-connect shared logic and clocks if there's more than one lane.
gmii_rx_clk <= gmii_user_clk2;  -- This is the only 125 MHz clock avail from core
gmii_tx_clk <= gmii_user_clk2;  -- This is the only 125 MHz clock avail from core

u_ipcore : sgmii_gtx0
    port map(
    gtrefclk_p              => gtref_125p,
    gtrefclk_n              => gtref_125n,
    gtrefclk_out            => clkout_125,
    gtrefclk_bufg_out       => open,
    txp                     => sgmii_txp,
    txn                     => sgmii_txn,
    rxp                     => sgmii_rxp,
    rxn                     => sgmii_rxn,
    resetdone               => open,
    userclk_out             => open,            -- Tx 62.5 MHz
    userclk2_out            => gmii_user_clk2,  -- Tx 125 MHz
    rxuserclk_out           => open,            -- Rx 62.5 MHz
    rxuserclk2_out          => open,            -- Rx 62.5 MHz
    pma_reset_out           => open,
    mmcm_locked_out         => clk_locked,
    independent_clock_bufg  => clkin_200,       -- Clock for control logic
    sgmii_clk_r             => open,            -- Line-rate Tx clock
    sgmii_clk_f             => open,
    sgmii_clk_en            => open,
    gmii_txd                => gmii_tx_data,    -- GMII Tx
    gmii_tx_en              => gmii_tx_en,
    gmii_tx_er              => gmii_tx_er,
    gmii_rxd                => gmii_rx_data,    -- GMII Rx
    gmii_rx_dv              => gmii_rx_dv,
    gmii_rx_er              => gmii_rx_er,
    gmii_isolate            => open,
    configuration_vector    => config_vec,      -- See PG047, Table 2-39
    speed_is_10_100         => '0',             -- Always 1000 Mbps
    speed_is_100            => '0',             -- Always 1000 Mbps
    status_vector           => status_vec,      -- See PG047, Table 2-41
    reset                   => port_shdn,       -- Reset the entire core
    signal_detect           => '1',
    gt0_qplloutclk_out      => open,
    gt0_qplloutrefclk_out   => open);

end port_sgmii_gtx;
