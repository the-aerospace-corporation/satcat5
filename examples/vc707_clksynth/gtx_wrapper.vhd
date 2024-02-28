--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Single-lane GTX wrapper.
--
-- This block is a thin wrapper for the "gtwizard_0" IP core, which
-- instantiates two GTX transceivers and shared control logic.

library ieee;
use     ieee.std_logic_1164.all;
library unisim;
use     unisim.vcomponents.all;

entity gtx_wrapper is
    port (
    ext_clk125  : in  std_logic;    -- Control & startup clock (125 MHz)
    ext_reset_p : in  std_logic;    -- ...and associated reset
    tx0_clk_out : out std_logic;    -- Transmit clock from GTX0 (156.25 MHz)
    tx0_rst_out : out std_logic;    -- ...and associated reset
    tx0_data    : in  std_logic_vector(39 downto 0);
    tx1_clk_out : out std_logic;    -- Transmit clock from GTX1 (156.25 MHz)
    tx1_rst_out : out std_logic;    -- ...and associated reset
    tx1_data    : in  std_logic_vector(39 downto 0);
    gtx0_ref_p  : in  std_logic;    -- GTX0 refclk (125 MHz)
    gtx0_ref_n  : in  std_logic;
    gtx1_ref_p  : in  std_logic;    -- GTX1 refclk (125 MHz)
    gtx1_ref_n  : in  std_logic;
    gtx0_out_p  : out std_logic;    -- GTX0 output signal
    gtx0_out_n  : out std_logic;
    gtx1_out_p  : out std_logic;    -- GTX1 output signal
    gtx1_out_n  : out std_logic);
end gtx_wrapper;

architecture gtx_wrapper of gtx_wrapper is

signal usr_reset0_n : std_logic;
signal usr_reset1_n : std_logic;

begin

tx0_rst_out <= not usr_reset0_n;
tx1_rst_out <= not usr_reset1_n;

-- Refer to Xilinx PG168 for more information on each port.
u_gtx : entity work.gtwizard_0
    port map(
    -- Shared logic and reference clocks.
    sysclk_in                   => ext_clk125,      -- Clock for startup logic
    soft_reset_tx_in            => ext_reset_p,     -- ...and associated reset
    dont_reset_on_data_error_in => '0',             -- Reset on Rx-decode error?
    q0_clk0_gtrefclk_pad_n_in   => gtx0_ref_n,
    q0_clk0_gtrefclk_pad_p_in   => gtx0_ref_p,
    q0_clk1_gtrefclk_pad_n_in   => gtx1_ref_n,
    q0_clk1_gtrefclk_pad_p_in   => gtx1_ref_p,
    gt0_qplloutclk_out          => open,
    gt0_qplloutrefclk_out       => open,
    -- GTX channel 0
    gt0_tx_fsm_reset_done_out   => open,
    gt0_rx_fsm_reset_done_out   => open,
    gt0_data_valid_in           => '0',             -- Expect valid Rx signal?
    gt0_tx_mmcm_lock_out        => open,
    gt0_txusrclk_out            => open,
    gt0_txusrclk2_out           => tx0_clk_out,
    gt0_cpllfbclklost_out       => open,
    gt0_cplllock_out            => open,
    gt0_cpllreset_in            => ext_reset_p,
    gt0_drpaddr_in              => (others => '0'),
    gt0_drpdi_in                => (others => '0'),
    gt0_drpdo_out               => open,
    gt0_drpen_in                => '0',
    gt0_drprdy_out              => open,
    gt0_drpwe_in                => '0',
    gt0_dmonitorout_out         => open,
    gt0_eyescanreset_in         => '0',
    gt0_eyescandataerror_out    => open,
    gt0_eyescantrigger_in       => '0',
    gt0_rxmonitorout_out        => open,
    gt0_rxmonitorsel_in         => (others => '0'),
    gt0_gtrxreset_in            => ext_reset_p,
    gt0_gttxreset_in            => ext_reset_p,
    gt0_txuserrdy_in            => '1',             -- Valid user data?
    gt0_txdata_in               => tx0_data,        -- Parallel data vector
    gt0_gtxtxn_out              => gtx0_out_n,
    gt0_gtxtxp_out              => gtx0_out_p,
    gt0_txoutclkfabric_out      => open,
    gt0_txoutclkpcs_out         => open,
    gt0_txresetdone_out         => usr_reset0_n,
    -- GTX channel 1
    gt1_tx_fsm_reset_done_out   => open,
    gt1_rx_fsm_reset_done_out   => open,
    gt1_data_valid_in           => '0',             -- Expect valid Rx signal?
    gt1_tx_mmcm_lock_out        => open,
    gt1_txusrclk_out            => open,
    gt1_txusrclk2_out           => tx1_clk_out,
    gt1_cpllfbclklost_out       => open,
    gt1_cplllock_out            => open,
    gt1_cpllreset_in            => ext_reset_p,
    gt1_drpaddr_in              => (others => '0'),
    gt1_drpdi_in                => (others => '0'),
    gt1_drpdo_out               => open,
    gt1_drpen_in                => '0',
    gt1_drprdy_out              => open,
    gt1_drpwe_in                => '0',
    gt1_dmonitorout_out         => open,
    gt1_eyescanreset_in         => '0',
    gt1_eyescandataerror_out    => open,
    gt1_eyescantrigger_in       => '0',
    gt1_rxmonitorout_out        => open,
    gt1_rxmonitorsel_in         => (others => '0'),
    gt1_gtrxreset_in            => ext_reset_p,
    gt1_gttxreset_in            => ext_reset_p,
    gt1_txuserrdy_in            => '1',             -- Valid user data?
    gt1_txdata_in               => tx1_data,        -- Parallel data vector
    gt1_gtxtxn_out              => gtx1_out_n,
    gt1_gtxtxp_out              => gtx1_out_p,
    gt1_txoutclkfabric_out      => open,
    gt1_txoutclkpcs_out         => open,
    gt1_txresetdone_out         => usr_reset1_n);

end gtx_wrapper;
