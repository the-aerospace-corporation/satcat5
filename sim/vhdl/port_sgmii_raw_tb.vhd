--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Simulation of Raw SGMII port
--
-- This simulation is NOT a unit test; it supplies the necessary clock and
-- reset signals for simulation purposes, but does not verify outputs.
--
-- The complete test takes about ??? milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_sgmii_raw_tb is
    -- Unit testbench top level, no I/O ports
end port_sgmii_raw_tb;

architecture tb of port_sgmii_raw_tb is

signal clk_80       : std_logic := '0';
signal clk_125      : std_logic := '0';
signal gtref_p      : std_logic;
signal gtref_n      : std_logic;
signal shared_vec   : std_logic_vector(15 downto 0);
signal sgmii_a2b_p  : std_logic;
signal sgmii_a2b_n  : std_logic;
signal sgmii_b2a_p  : std_logic;
signal sgmii_b2a_n  : std_logic;
signal tx_ctrl_a    : port_tx_m2s;
signal tx_ctrl_b    : port_tx_m2s;

begin

-- Clock and reset generation.
clk_80  <= not clk_80 after 6.25 ns;
clk_125 <= not clk_125 after 4.00 ns;
gtref_p <= clk_125;
gtref_n <= not clk_125;

-- Units under test.
uut_a : entity work.port_sgmii_raw
    generic map(
    MGT_TYPE    => "gtx",
    SHARED_EN   => true)
    port map(
    sgmii_rxp   => sgmii_b2a_p,
    sgmii_rxn   => sgmii_b2a_n,
    sgmii_txp   => sgmii_a2b_p,
    sgmii_txn   => sgmii_a2b_n,
    prx_data    => open,
    ptx_data    => TX_S2M_IDLE,
    ptx_ctrl    => tx_ctrl_a,
    port_shdn   => '0',
    gtrefclk_p  => gtref_p,
    gtrefclk_n  => gtref_n,
    shared_out  => shared_vec,
    gtsysclk    => clk_80);

uut_b : entity work.port_sgmii_raw
    generic map(
    MGT_TYPE    => "gtx",
    SHARED_EN   => false)
    port map(
    sgmii_rxp   => sgmii_a2b_p,
    sgmii_rxn   => sgmii_a2b_n,
    sgmii_txp   => sgmii_b2a_p,
    sgmii_txn   => sgmii_b2a_n,
    prx_data    => open,
    ptx_data    => TX_S2M_IDLE,
    ptx_ctrl    => tx_ctrl_b,
    port_shdn   => '0',
    gtrefclk_p  => gtref_p,
    gtrefclk_n  => gtref_n,
    shared_in   => shared_vec,
    gtsysclk    => clk_80);

-- Detect when both ports exit reset.
p_done : process
begin
    wait until (tx_ctrl_a.reset_p = '0' and tx_ctrl_b.reset_p = '0');
    report "Test completed.";
    wait;
end process;

end tb;
