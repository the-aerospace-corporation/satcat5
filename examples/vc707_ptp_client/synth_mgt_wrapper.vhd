--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Simple wrapper for a GTX quad
--
-- Wrapper for SERDES used as single-bit blind-oversample D/A.
-- Primarily exists to remove unused signals and set expected constants.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity synth_mgt_wrapper is
    generic (
    PAR_WIDTH   : positive);
    port (
    -- System clock, reset, and configuration signals.
    free_clk    : in  std_logic;
    reset_req_p : in  std_logic;
    reset_out_p : out std_logic;
    tx_diffctrl : in  std_logic_vector(3 downto 0);

    -- Parallel data from each synthesizer.
    par_clk     : out std_logic;
    par_lane0   : in  std_logic_vector(PAR_WIDTH-1 downto 0);
    par_lane1   : in  std_logic_vector(PAR_WIDTH-1 downto 0);
    par_lane2   : in  std_logic_vector(PAR_WIDTH-1 downto 0);
    par_lane3   : in  std_logic_vector(PAR_WIDTH-1 downto 0);

    -- MGT quad pins
    refclk_n    : in  std_logic;
    refclk_p    : in  std_logic;
    pin_tx_n    : out std_logic_vector(3 downto 0);
    pin_tx_p    : out std_logic_vector(3 downto 0));
end synth_mgt_wrapper;

architecture synth_mgt_wrapper of synth_mgt_wrapper is

-- From gtwizard_fmc2_stub.vhd
component gtwizard_fmc2 is
    port (
    SOFT_RESET_TX_IN : in STD_LOGIC;
    DONT_RESET_ON_DATA_ERROR_IN : in STD_LOGIC;
    Q4_CLK0_GTREFCLK_PAD_N_IN : in STD_LOGIC;
    Q4_CLK0_GTREFCLK_PAD_P_IN : in STD_LOGIC;
    GT0_TX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT0_RX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT0_DATA_VALID_IN : in STD_LOGIC;
    GT0_TX_MMCM_LOCK_OUT : out STD_LOGIC;
    GT1_TX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT1_RX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT1_DATA_VALID_IN : in STD_LOGIC;
    GT1_TX_MMCM_LOCK_OUT : out STD_LOGIC;
    GT2_TX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT2_RX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT2_DATA_VALID_IN : in STD_LOGIC;
    GT2_TX_MMCM_LOCK_OUT : out STD_LOGIC;
    GT3_TX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT3_RX_FSM_RESET_DONE_OUT : out STD_LOGIC;
    GT3_DATA_VALID_IN : in STD_LOGIC;
    GT3_TX_MMCM_LOCK_OUT : out STD_LOGIC;
    GT0_TXUSRCLK_OUT : out STD_LOGIC;
    GT0_TXUSRCLK2_OUT : out STD_LOGIC;
    GT1_TXUSRCLK_OUT : out STD_LOGIC;
    GT1_TXUSRCLK2_OUT : out STD_LOGIC;
    GT2_TXUSRCLK_OUT : out STD_LOGIC;
    GT2_TXUSRCLK2_OUT : out STD_LOGIC;
    GT3_TXUSRCLK_OUT : out STD_LOGIC;
    GT3_TXUSRCLK2_OUT : out STD_LOGIC;
    gt0_drpaddr_in : in STD_LOGIC_VECTOR ( 8 downto 0 );
    gt0_drpdi_in : in STD_LOGIC_VECTOR ( 15 downto 0 );
    gt0_drpdo_out : out STD_LOGIC_VECTOR ( 15 downto 0 );
    gt0_drpen_in : in STD_LOGIC;
    gt0_drprdy_out : out STD_LOGIC;
    gt0_drpwe_in : in STD_LOGIC;
    gt0_dmonitorout_out : out STD_LOGIC_VECTOR ( 7 downto 0 );
    gt0_eyescanreset_in : in STD_LOGIC;
    gt0_eyescandataerror_out : out STD_LOGIC;
    gt0_eyescantrigger_in : in STD_LOGIC;
    gt0_rxmonitorout_out : out STD_LOGIC_VECTOR ( 6 downto 0 );
    gt0_rxmonitorsel_in : in STD_LOGIC_VECTOR ( 1 downto 0 );
    gt0_gtrxreset_in : in STD_LOGIC;
    gt0_gttxreset_in : in STD_LOGIC;
    gt0_txuserrdy_in : in STD_LOGIC;
    gt0_txbufstatus_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
    gt0_txdiffctrl_in : in STD_LOGIC_VECTOR (3 downto 0);
    gt0_txdata_in : in STD_LOGIC_VECTOR ( 79 downto 0 );
    gt0_gtxtxn_out : out STD_LOGIC;
    gt0_gtxtxp_out : out STD_LOGIC;
    gt0_txoutclkfabric_out : out STD_LOGIC;
    gt0_txoutclkpcs_out : out STD_LOGIC;
    gt0_txresetdone_out : out STD_LOGIC;
    gt1_drpaddr_in : in STD_LOGIC_VECTOR ( 8 downto 0 );
    gt1_drpdi_in : in STD_LOGIC_VECTOR ( 15 downto 0 );
    gt1_drpdo_out : out STD_LOGIC_VECTOR ( 15 downto 0 );
    gt1_drpen_in : in STD_LOGIC;
    gt1_drprdy_out : out STD_LOGIC;
    gt1_drpwe_in : in STD_LOGIC;
    gt1_dmonitorout_out : out STD_LOGIC_VECTOR ( 7 downto 0 );
    gt1_eyescanreset_in : in STD_LOGIC;
    gt1_eyescandataerror_out : out STD_LOGIC;
    gt1_eyescantrigger_in : in STD_LOGIC;
    gt1_rxmonitorout_out : out STD_LOGIC_VECTOR ( 6 downto 0 );
    gt1_rxmonitorsel_in : in STD_LOGIC_VECTOR ( 1 downto 0 );
    gt1_gtrxreset_in : in STD_LOGIC;
    gt1_gttxreset_in : in STD_LOGIC;
    gt1_txuserrdy_in : in STD_LOGIC;
    gt1_txbufstatus_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
    gt1_txdiffctrl_in : in STD_LOGIC_VECTOR (3 downto 0);
    gt1_txdata_in : in STD_LOGIC_VECTOR ( 79 downto 0 );
    gt1_gtxtxn_out : out STD_LOGIC;
    gt1_gtxtxp_out : out STD_LOGIC;
    gt1_txoutclkfabric_out : out STD_LOGIC;
    gt1_txoutclkpcs_out : out STD_LOGIC;
    gt1_txresetdone_out : out STD_LOGIC;
    gt2_drpaddr_in : in STD_LOGIC_VECTOR ( 8 downto 0 );
    gt2_drpdi_in : in STD_LOGIC_VECTOR ( 15 downto 0 );
    gt2_drpdo_out : out STD_LOGIC_VECTOR ( 15 downto 0 );
    gt2_drpen_in : in STD_LOGIC;
    gt2_drprdy_out : out STD_LOGIC;
    gt2_drpwe_in : in STD_LOGIC;
    gt2_dmonitorout_out : out STD_LOGIC_VECTOR ( 7 downto 0 );
    gt2_eyescanreset_in : in STD_LOGIC;
    gt2_eyescandataerror_out : out STD_LOGIC;
    gt2_eyescantrigger_in : in STD_LOGIC;
    gt2_rxmonitorout_out : out STD_LOGIC_VECTOR ( 6 downto 0 );
    gt2_rxmonitorsel_in : in STD_LOGIC_VECTOR ( 1 downto 0 );
    gt2_gtrxreset_in : in STD_LOGIC;
    gt2_gttxreset_in : in STD_LOGIC;
    gt2_txuserrdy_in : in STD_LOGIC;
    gt2_txbufstatus_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
    gt2_txdiffctrl_in : in STD_LOGIC_VECTOR (3 downto 0);
    gt2_txdata_in : in STD_LOGIC_VECTOR ( 79 downto 0 );
    gt2_gtxtxn_out : out STD_LOGIC;
    gt2_gtxtxp_out : out STD_LOGIC;
    gt2_txoutclkfabric_out : out STD_LOGIC;
    gt2_txoutclkpcs_out : out STD_LOGIC;
    gt2_txresetdone_out : out STD_LOGIC;
    gt3_drpaddr_in : in STD_LOGIC_VECTOR ( 8 downto 0 );
    gt3_drpdi_in : in STD_LOGIC_VECTOR ( 15 downto 0 );
    gt3_drpdo_out : out STD_LOGIC_VECTOR ( 15 downto 0 );
    gt3_drpen_in : in STD_LOGIC;
    gt3_drprdy_out : out STD_LOGIC;
    gt3_drpwe_in : in STD_LOGIC;
    gt3_dmonitorout_out : out STD_LOGIC_VECTOR ( 7 downto 0 );
    gt3_eyescanreset_in : in STD_LOGIC;
    gt3_eyescandataerror_out : out STD_LOGIC;
    gt3_eyescantrigger_in : in STD_LOGIC;
    gt3_rxmonitorout_out : out STD_LOGIC_VECTOR ( 6 downto 0 );
    gt3_rxmonitorsel_in : in STD_LOGIC_VECTOR ( 1 downto 0 );
    gt3_gtrxreset_in : in STD_LOGIC;
    gt3_gttxreset_in : in STD_LOGIC;
    gt3_txuserrdy_in : in STD_LOGIC;
    gt3_txbufstatus_out : out STD_LOGIC_VECTOR ( 1 downto 0 );
    gt3_txdiffctrl_in : in STD_LOGIC_VECTOR (3 downto 0);
    gt3_txdata_in : in STD_LOGIC_VECTOR ( 79 downto 0 );
    gt3_gtxtxn_out : out STD_LOGIC;
    gt3_gtxtxp_out : out STD_LOGIC;
    gt3_txoutclkfabric_out : out STD_LOGIC;
    gt3_txoutclkpcs_out : out STD_LOGIC;
    gt3_txresetdone_out : out STD_LOGIC;
    GT0_QPLLLOCK_OUT : out STD_LOGIC;
    GT0_QPLLREFCLKLOST_OUT : out STD_LOGIC;
    GT0_QPLLOUTCLK_OUT : out STD_LOGIC;
    GT0_QPLLOUTREFCLK_OUT : out STD_LOGIC;
    sysclk_in : in STD_LOGIC);
end component;

signal clk_tx_full  : std_logic_vector(3 downto 0);
signal clk_tx_half  : std_logic_vector(3 downto 0);
signal init_done    : std_logic_vector(3 downto 0);
signal refclk_bn    : std_logic;
signal refclk_bp    : std_logic;
signal reset_any_p  : std_logic;

-- Forbid inappropriate double-insertion of IBUF during out-of-context synthesis.
-- https://support.xilinx.com/s/question/0D52E00006iHicDSAS/
-- https://support.xilinx.com/s/question/0D52E00006iHrKoSAK/
attribute dont_touch : string;
attribute dont_touch of u_bufn, u_bufp: label is "true";
attribute dont_touch of refclk_p, refclk_n: signal is "true";
attribute dont_touch of refclk_bp, refclk_bn: signal is "true";
attribute io_buffer_type : string;
attribute io_buffer_type of refclk_p, refclk_n: signal is "none";

begin

-- Clock buffer for the parallel user clock.
-- All lanes synchronous -> Safe to use any Tx clock for every lane.
par_clk <= clk_tx_half(0);

-- Explicit input buffers required for out-of-context synthesis.
u_bufn : ibuf port map(I => refclk_n, O => refclk_bn);
u_bufp : ibuf port map(I => refclk_p, O => refclk_bp);

-- Hold reset until all lanes are initialized.
reset_any_p <= not and_reduce(init_done);

u_reset : sync_reset
    port map(
    in_reset_p  => reset_any_p,
    out_reset_p => reset_out_p,
    out_clk     => clk_tx_half(0));

-- Instantiate the transceiver wizard IP.
u_wizard : gtwizard_fmc2
    port map(
    SOFT_RESET_TX_IN => reset_req_p,
    DONT_RESET_ON_DATA_ERROR_IN => '1',
    Q4_CLK0_GTREFCLK_PAD_N_IN => refclk_bn,
    Q4_CLK0_GTREFCLK_PAD_P_IN => refclk_bp,
    GT0_TX_FSM_RESET_DONE_OUT => init_done(0),
    GT0_RX_FSM_RESET_DONE_OUT => open,
    GT0_DATA_VALID_IN => '1',
    GT0_TX_MMCM_LOCK_OUT => open,
    GT1_TX_FSM_RESET_DONE_OUT => init_done(1),
    GT1_RX_FSM_RESET_DONE_OUT => open,
    GT1_DATA_VALID_IN => '1',
    GT1_TX_MMCM_LOCK_OUT => open,
    GT2_TX_FSM_RESET_DONE_OUT => init_done(2),
    GT2_RX_FSM_RESET_DONE_OUT => open,
    GT2_DATA_VALID_IN => '1',
    GT2_TX_MMCM_LOCK_OUT => open,
    GT3_TX_FSM_RESET_DONE_OUT => init_done(3),
    GT3_RX_FSM_RESET_DONE_OUT => open,
    GT3_DATA_VALID_IN => '1',
    GT3_TX_MMCM_LOCK_OUT => open,
    GT0_TXUSRCLK_OUT  => clk_tx_full(0),
    GT0_TXUSRCLK2_OUT => clk_tx_half(0),
    GT1_TXUSRCLK_OUT  => clk_tx_full(1),
    GT1_TXUSRCLK2_OUT => clk_tx_half(1),
    GT2_TXUSRCLK_OUT  => clk_tx_full(2),
    GT2_TXUSRCLK2_OUT => clk_tx_half(2),
    GT3_TXUSRCLK_OUT  => clk_tx_full(3),
    GT3_TXUSRCLK2_OUT => clk_tx_half(3),
    gt0_drpaddr_in => (others => '0'),
    gt0_drpdi_in => (others => '0'),
    gt0_drpdo_out => open,
    gt0_drpen_in => '0',
    gt0_drprdy_out => open,
    gt0_drpwe_in => '0',
    gt0_dmonitorout_out => open,
    gt0_eyescanreset_in => '0',
    gt0_eyescandataerror_out => open,
    gt0_eyescantrigger_in => '0',
    gt0_rxmonitorout_out => open,
    gt0_rxmonitorsel_in => (others => '0'),
    gt0_gtrxreset_in => '0',
    gt0_gttxreset_in => '0',
    gt0_txuserrdy_in => '1',
    gt0_txbufstatus_out => open,
    gt0_txdiffctrl_in => tx_diffctrl,
    gt0_txdata_in => par_lane0,
    gt0_gtxtxn_out => pin_tx_n(0),
    gt0_gtxtxp_out => pin_tx_p(0),
    gt0_txoutclkfabric_out => open,
    gt0_txoutclkpcs_out => open,
    gt0_txresetdone_out => open,
    gt1_drpaddr_in => (others => '0'),
    gt1_drpdi_in => (others => '0'),
    gt1_drpdo_out => open,
    gt1_drpen_in => '0',
    gt1_drprdy_out => open,
    gt1_drpwe_in => '0',
    gt1_dmonitorout_out => open,
    gt1_eyescanreset_in => '0',
    gt1_eyescandataerror_out => open,
    gt1_eyescantrigger_in => '0',
    gt1_rxmonitorout_out => open,
    gt1_rxmonitorsel_in => (others => '0'),
    gt1_gtrxreset_in => '0',
    gt1_gttxreset_in => '0',
    gt1_txuserrdy_in => '1',
    gt1_txbufstatus_out => open,
    gt1_txdiffctrl_in => tx_diffctrl,
    gt1_txdata_in => par_lane1,
    gt1_gtxtxn_out => pin_tx_n(1),
    gt1_gtxtxp_out => pin_tx_p(1),
    gt1_txoutclkfabric_out => open,
    gt1_txoutclkpcs_out => open,
    gt1_txresetdone_out => open,
    gt2_drpaddr_in => (others => '0'),
    gt2_drpdi_in => (others => '0'),
    gt2_drpdo_out => open,
    gt2_drpen_in => '0',
    gt2_drprdy_out => open,
    gt2_drpwe_in => '0',
    gt2_dmonitorout_out => open,
    gt2_eyescanreset_in => '0',
    gt2_eyescandataerror_out => open,
    gt2_eyescantrigger_in => '0',
    gt2_rxmonitorout_out => open,
    gt2_rxmonitorsel_in => (others => '0'),
    gt2_gtrxreset_in => '0',
    gt2_gttxreset_in => '0',
    gt2_txuserrdy_in => '1',
    gt2_txbufstatus_out => open,
    gt2_txdiffctrl_in => tx_diffctrl,
    gt2_txdata_in => par_lane2,
    gt2_gtxtxn_out => pin_tx_n(2),
    gt2_gtxtxp_out => pin_tx_p(2),
    gt2_txoutclkfabric_out => open,
    gt2_txoutclkpcs_out => open,
    gt2_txresetdone_out => open,
    gt3_drpaddr_in => (others => '0'),
    gt3_drpdi_in => (others => '0'),
    gt3_drpdo_out => open,
    gt3_drpen_in => '0',
    gt3_drprdy_out => open,
    gt3_drpwe_in => '0',
    gt3_dmonitorout_out => open,
    gt3_eyescanreset_in => '0',
    gt3_eyescandataerror_out => open,
    gt3_eyescantrigger_in => '0',
    gt3_rxmonitorout_out => open,
    gt3_rxmonitorsel_in => (others => '0'),
    gt3_gtrxreset_in => '0',
    gt3_gttxreset_in => '0',
    gt3_txuserrdy_in => '1',
    gt3_txbufstatus_out => open,
    gt3_txdiffctrl_in => tx_diffctrl,
    gt3_txdata_in => par_lane3,
    gt3_gtxtxn_out => pin_tx_n(3),
    gt3_gtxtxp_out => pin_tx_p(3),
    gt3_txoutclkfabric_out => open,
    gt3_txoutclkpcs_out => open,
    gt3_txresetdone_out => open,
    GT0_QPLLLOCK_OUT => open,
    GT0_QPLLREFCLKLOST_OUT => open,
    GT0_QPLLOUTCLK_OUT => open,
    GT0_QPLLOUTREFCLK_OUT => open,
    sysclk_in => free_clk);

end synth_mgt_wrapper;
