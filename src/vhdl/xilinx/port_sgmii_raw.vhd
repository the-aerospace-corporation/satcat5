--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SGMII port using Xilinx 7-series GTX SERDES in raw mode
--
-- This module uses the Xilinx "Transceivers Wizard" IP-core in raw mode.
-- (i.e., The transceiver silicon is used for serialization and CDR only.)
-- Unlike the "port_sgmii_gtx" block, all 8b/10b and SGMII logic is built
-- using regular HDL.  This consumes additional fabric resources, but allows
-- sub-nanosecond timestamp accuracy for PTP.
--
-- This block depends on the IP-core, which can be added to the Vivado project
-- by performing the following steps:
--  * From a TCL console in the SatCat5 "project/vivado" folder:
--      * Run `source generate_sgmii_gtx.tcl`
--      * For 7-series FPGAs using a GTX primitive:
--          * Run `generate_sgmii_raw sgmii_raw_gtx0 gtx 125.000 REFCLK0_Q0`
--          * Run `generate_sgmii_raw sgmii_raw_gtx1 gtx 125.000 REFCLK0_Q1`
--      * For Ultrascale and Ultrascale+ FPGAs using a GTY primitive:
--          * Run `generate_sgmii_raw sgmii_raw_gty0 gty`
--  * Instantiate the first "port_sgmii_raw" block with SHARED_EN = true.
--  * Instantiate remaining "port_sgmii_raw" block(s) with SHARED_EN = false.
--    Link each "shared_in" port to "shared_out" port on the first instance.
--
-- See also: port_sgmii_gpio.vhd, port_sgmii_gtx.vhd
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_sgmii_raw is
    generic (
    MGT_TYPE    : string;               -- "gtx", "gty", etc.
    REFCLK_SRC  : integer := 1;         -- 7-series only: REFCLK0 or REFCLK1?
    SHAKE_WAIT  : boolean := false;     -- Wait for MAC/PHY handshake?
    SHARED_EN   : boolean := true;      -- Does the IP-core include shared logic?
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- External SGMII interfaces (direct to MGT pins)
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

    -- Shared-logic enabled?
    -- (Refclk must match frequency set in TCL scripts, default 125 MHz.)
    gtrefclk_p  : in  std_logic := '0'; -- GTX RefClk
    gtrefclk_n  : in  std_logic := '0'; -- (Differential)
    shared_out  : out std_logic_vector(15 downto 0);

    -- Shared-logic disabled?
    shared_in   : in  std_logic_vector(15 downto 0) := (others => '0');

    -- Additional clocks.
    gtsysclk    : in  std_logic);   -- Independent free-running clock
end port_sgmii_raw;

architecture port_sgmii_raw of port_sgmii_raw is

-- Component declarations are copied from Xilinx templates.
component sgmii_raw_gtx0 is
    port (
    sysclk_in                   : in  std_logic;
    soft_reset_tx_in            : in  std_logic;
    soft_reset_rx_in            : in  std_logic;
    dont_reset_on_data_error_in : in  std_logic;
    gt0_tx_fsm_reset_done_out   : out std_logic;
    gt0_rx_fsm_reset_done_out   : out std_logic;
    gt0_data_valid_in           : in  std_logic;
    gt0_cpllfbclklost_out       : out std_logic;
    gt0_cplllock_out            : out std_logic;
    gt0_cplllockdetclk_in       : in  std_logic;
    gt0_cpllreset_in            : in  std_logic;
    gt0_gtrefclk0_in            : in  std_logic;
    gt0_gtrefclk1_in            : in  std_logic;
    gt0_drpaddr_in              : in  std_logic_vector(8 downto 0);
    gt0_drpclk_in               : in  std_logic;
    gt0_drpdi_in                : in  std_logic_vector(15 downto 0);
    gt0_drpdo_out               : out std_logic_vector(15 downto 0);
    gt0_drpen_in                : in  std_logic;
    gt0_drprdy_out              : out std_logic;
    gt0_drpwe_in                : in  std_logic;
    gt0_dmonitorout_out         : out std_logic_vector(7 downto 0);
    gt0_eyescanreset_in         : in  std_logic;
    gt0_rxuserrdy_in            : in  std_logic;
    gt0_eyescandataerror_out    : out std_logic;
    gt0_eyescantrigger_in       : in  std_logic;
    gt0_rxusrclk_in             : in  std_logic;
    gt0_rxusrclk2_in            : in  std_logic;
    gt0_rxdata_out              : out std_logic_vector(19 downto 0);
    gt0_gtxrxp_in               : in  std_logic;
    gt0_gtxrxn_in               : in  std_logic;
    gt0_rxphmonitor_out         : out std_logic_vector(4 downto 0);
    gt0_rxphslipmonitor_out     : out std_logic_vector(4 downto 0);
    gt0_rxdfelpmreset_in        : in  std_logic;
    gt0_rxmonitorout_out        : out std_logic_vector(6 downto 0);
    gt0_rxmonitorsel_in         : in  std_logic_vector(1 downto 0);
    gt0_rxoutclk_out            : out std_logic;
    gt0_rxoutclkfabric_out      : out std_logic;
    gt0_gtrxreset_in            : in  std_logic;
    gt0_rxpmareset_in           : in  std_logic;
    gt0_rxresetdone_out         : out std_logic;
    gt0_gttxreset_in            : in  std_logic;
    gt0_txuserrdy_in            : in  std_logic;
    gt0_txusrclk_in             : in  std_logic;
    gt0_txusrclk2_in            : in  std_logic;
    gt0_txdata_in               : in  std_logic_vector(19 downto 0);
    gt0_gtxtxn_out              : out std_logic;
    gt0_gtxtxp_out              : out std_logic;
    gt0_txoutclk_out            : out std_logic;
    gt0_txoutclkfabric_out      : out std_logic;
    gt0_txoutclkpcs_out         : out std_logic;
    gt0_txresetdone_out         : out std_logic;
    gt0_qplloutclk_in           : in  std_logic;
    gt0_qplloutrefclk_in        : in  std_logic);
end component;

component sgmii_raw_gtx1 is
    port (
    sysclk_in                   : in  std_logic;
    soft_reset_tx_in            : in  std_logic;
    soft_reset_rx_in            : in  std_logic;
    dont_reset_on_data_error_in : in  std_logic;
    gt0_tx_fsm_reset_done_out   : out std_logic;
    gt0_rx_fsm_reset_done_out   : out std_logic;
    gt0_data_valid_in           : in  std_logic;
    gt0_cpllfbclklost_out       : out std_logic;
    gt0_cplllock_out            : out std_logic;
    gt0_cplllockdetclk_in       : in  std_logic;
    gt0_cpllreset_in            : in  std_logic;
    gt0_gtrefclk0_in            : in  std_logic;
    gt0_gtrefclk1_in            : in  std_logic;
    gt0_drpaddr_in              : in  std_logic_vector(8 downto 0);
    gt0_drpclk_in               : in  std_logic;
    gt0_drpdi_in                : in  std_logic_vector(15 downto 0);
    gt0_drpdo_out               : out std_logic_vector(15 downto 0);
    gt0_drpen_in                : in  std_logic;
    gt0_drprdy_out              : out std_logic;
    gt0_drpwe_in                : in  std_logic;
    gt0_dmonitorout_out         : out std_logic_vector(7 downto 0);
    gt0_eyescanreset_in         : in  std_logic;
    gt0_rxuserrdy_in            : in  std_logic;
    gt0_eyescandataerror_out    : out std_logic;
    gt0_eyescantrigger_in       : in  std_logic;
    gt0_rxusrclk_in             : in  std_logic;
    gt0_rxusrclk2_in            : in  std_logic;
    gt0_rxdata_out              : out std_logic_vector(19 downto 0);
    gt0_gtxrxp_in               : in  std_logic;
    gt0_gtxrxn_in               : in  std_logic;
    gt0_rxphmonitor_out         : out std_logic_vector(4 downto 0);
    gt0_rxphslipmonitor_out     : out std_logic_vector(4 downto 0);
    gt0_rxdfelpmreset_in        : in  std_logic;
    gt0_rxmonitorout_out        : out std_logic_vector(6 downto 0);
    gt0_rxmonitorsel_in         : in  std_logic_vector(1 downto 0);
    gt0_rxoutclk_out            : out std_logic;
    gt0_rxoutclkfabric_out      : out std_logic;
    gt0_gtrxreset_in            : in  std_logic;
    gt0_rxpmareset_in           : in  std_logic;
    gt0_rxresetdone_out         : out std_logic;
    gt0_gttxreset_in            : in  std_logic;
    gt0_txuserrdy_in            : in  std_logic;
    gt0_txusrclk_in             : in  std_logic;
    gt0_txusrclk2_in            : in  std_logic;
    gt0_txdata_in               : in  std_logic_vector(19 downto 0);
    gt0_gtxtxn_out              : out std_logic;
    gt0_gtxtxp_out              : out std_logic;
    gt0_txoutclk_out            : out std_logic;
    gt0_txoutclkfabric_out      : out std_logic;
    gt0_txoutclkpcs_out         : out std_logic;
    gt0_txresetdone_out         : out std_logic;
    gt0_qplloutclk_in           : in  std_logic;
    gt0_qplloutrefclk_in        : in  std_logic);
end component;

component sgmii_raw_gty0 is
    port (
    gtwiz_userclk_tx_reset_in           : in  std_logic_vector(0 downto 0);
    gtwiz_userclk_tx_active_in          : in  std_logic_vector(0 downto 0);
    gtwiz_userclk_rx_active_in          : in  std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_reset_in        : in  std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_start_user_in   : in  std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_done_out        : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_tx_error_out       : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_reset_in        : in  std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_start_user_in   : in  std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_done_out        : out std_logic_vector(0 downto 0);
    gtwiz_buffbypass_rx_error_out       : out std_logic_vector(0 downto 0);
    gtwiz_reset_clk_freerun_in          : in  std_logic_vector(0 downto 0);
    gtwiz_reset_all_in                  : in  std_logic_vector(0 downto 0);
    gtwiz_reset_tx_pll_and_datapath_in  : in  std_logic_vector(0 downto 0);
    gtwiz_reset_tx_datapath_in          : in  std_logic_vector(0 downto 0);
    gtwiz_reset_rx_pll_and_datapath_in  : in  std_logic_vector(0 downto 0);
    gtwiz_reset_rx_datapath_in          : in  std_logic_vector(0 downto 0);
    gtwiz_reset_rx_cdr_stable_out       : out std_logic_vector(0 downto 0);
    gtwiz_reset_tx_done_out             : out std_logic_vector(0 downto 0);
    gtwiz_reset_rx_done_out             : out std_logic_vector(0 downto 0);
    gtwiz_userdata_tx_in                : in  std_logic_vector(19 downto 0);
    gtwiz_userdata_rx_out               : out std_logic_vector(19 downto 0);
    drpclk_in               : in  std_logic_vector(0 downto 0);
    gtrefclk0_in            : in  std_logic_vector(0 downto 0);
    gtyrxn_in               : in  std_logic_vector(0 downto 0);
    gtyrxp_in               : in  std_logic_vector(0 downto 0);
    rxusrclk_in             : in  std_logic_vector(0 downto 0);
    rxusrclk2_in            : in  std_logic_vector(0 downto 0);
    txusrclk_in             : in  std_logic_vector(0 downto 0);
    txusrclk2_in            : in  std_logic_vector(0 downto 0);
    gtpowergood_out         : out std_logic_vector(0 downto 0);
    gtytxn_out              : out std_logic_vector(0 downto 0);
    gtytxp_out              : out std_logic_vector(0 downto 0);
    rxoutclk_out            : out std_logic_vector(0 downto 0);
    rxpmaresetdone_out      : out std_logic_vector(0 downto 0);
    txoutclk_out            : out std_logic_vector(0 downto 0);
    txpmaresetdone_out      : out std_logic_vector(0 downto 0);
    txprgdivresetdone_out   : out std_logic_vector(0 downto 0));
end component;

-- Reset signals for each clock domain.
signal reset_req    : std_logic;
signal async_reset  : std_logic;
signal tx_reset_p   : std_logic;
signal rx_reset_p   : std_logic;

-- Transmit datapath.
signal tx_clk125    : std_logic;
signal tx_data10    : std_logic_vector(9 downto 0);
signal tx_data20    : std_logic_vector(19 downto 0);
signal tx_tstamp    : tstamp_t := TSTAMP_DISABLED;
signal tx_tvalid    : std_logic := '0';

-- Receive datapath.
signal rx_clk125    : std_logic;
signal rx_locked    : std_logic;
signal rx_data10    : std_logic_vector(9 downto 0);
signal rx_data20    : std_logic_vector(19 downto 0);
signal rx_tstamp10  : tstamp_t;
signal rx_tstamp20  : tstamp_t := TSTAMP_DISABLED;
signal rx_tvalid    : std_logic := '0';

-- MGT control signals.
signal gtrefclk_bb  : std_logic := '0';
signal gtrefclk_bp  : std_logic := '0';
signal gtrefclk_bn  : std_logic := '0';
signal gtrefclk_q1  : std_logic := '0';
signal gtrefclk_q2  : std_logic := '0';
signal gtoutclk_rx  : std_logic := '0';
signal gtoutclk_tx  : std_logic := '0';
signal gt_ready_rx  : std_logic;
signal gt_ready_tx  : std_logic;

-- Forbid premature removal of clock-buffer signals.
attribute dont_touch : string;
attribute dont_touch of gtrefclk_p,  gtrefclk_n: signal is "true";
attribute dont_touch of gtrefclk_bp, gtrefclk_bn: signal is "true";

begin

-- Enforce minimum duration for MGT reset, including power-on-reset.
u_reset_req : sync_reset
    generic map(HOLD_MIN => 80) -- 1.0 usec @ 80 MHz
    port map(
    in_reset_p  => port_shdn,
    out_reset_p => reset_req,
    out_clk     => gtsysclk);

-- Reset signals for each clock domain.
async_reset <= reset_req or not (gt_ready_rx and gt_ready_tx);

u_rx_reset : sync_reset
    port map(
    in_reset_p  => async_reset,
    out_reset_p => rx_reset_p,
    out_clk     => rx_clk125);

u_tx_reset : sync_reset
    port map(
    in_reset_p  => async_reset,
    out_reset_p => tx_reset_p,
    out_clk     => tx_clk125);

-- Timestamps for each clock domain, if enabled.
gen_tstamp : if VCONFIG.input_hz > 0 generate
    u_rx_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => rx_clk125,
        user_ctr    => rx_tstamp20,
        user_lock   => rx_tvalid,
        user_rst_p  => rx_reset_p);

    u_tx_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => 125_000_000)
        port map(
        ref_time    => ref_time,
        user_clk    => tx_clk125,
        user_ctr    => tx_tstamp,
        user_lock   => tx_tvalid,
        user_rst_p  => tx_reset_p);
end generate;

-- Connect 8b/10b signals to the SatCat5 port interface.
-- Also includes preamble insertion, rate-detect state machine, etc.
u_sgmii : entity work.port_sgmii_common
    generic map(
    MSB_FIRST   => false,
    SHAKE_WAIT  => SHAKE_WAIT)
    port map(
    tx_clk      => tx_clk125,
    tx_data     => tx_data10,
    tx_tstamp   => tx_tstamp,
    tx_tvalid   => tx_tvalid,
    rx_clk      => rx_clk125,
    rx_lock     => rx_locked,
    rx_data     => rx_data10,
    rx_tstamp   => rx_tstamp10,
    rx_tvalid   => rx_tvalid,
    prx_data    => prx_data,
    ptx_data    => ptx_data,
    ptx_ctrl    => ptx_ctrl,
    reset_p     => tx_reset_p);

-- To simplify clock structure, MGT operates at 2.5 GHz instead of 1.25 GHz.
-- MGT locks to one of two phases at random; "resample" block detects which.
u_resample : entity work.io_resample_fixed
    generic map(
    IO_CLK_HZ   => 125_000_000,
    IO_WIDTH    => 10,
    OVERSAMPLE  => 2,
    MSB_FIRST   => false)
    port map(
    tx_in_data  => tx_data10,
    tx_out_data => tx_data20,
    rx_clk      => rx_clk125,
    rx_in_data  => rx_data20,
    rx_in_time  => rx_tstamp20,
    rx_out_data => rx_data10,
    rx_out_time => rx_tstamp10,
    rx_out_lock => rx_locked,
    rx_reset_p  => rx_reset_p);

-- Instantiate the appropriate Transceiver Wizard IP-core.
gen_gtx0 : if MGT_TYPE = "gtx" generate
    -- Note: Using 3 of 16 bits; the rest are reserved for future expansion.
    shared_out <= (
        0 => gtrefclk_bb,
        1 => gtrefclk_q1,
        2 => gtrefclk_q2,
        others => '0');

    -- Pull signals from the upstream source?
    gen_shared0 : if not SHARED_EN generate
        gtrefclk_bb <= shared_in(0);
        gtrefclk_q1 <= shared_in(1);
        gtrefclk_q2 <= shared_in(2);
    end generate;

    -- Instantiate logic that is shared with other GTX lanes, if present.
    gen_shared1 : if SHARED_EN generate
        -- Input buffers for the reference clock.
        u_bufp : ibuf port map(I => gtrefclk_p, O => gtrefclk_bp);
        u_bufn : ibuf port map(I => gtrefclk_n, O => gtrefclk_bn);
        u_bufb : ibufds_gte2
            port map(
            I       => gtrefclk_bp,
            IB      => gtrefclk_bn,
            CEB     => '0',
            O       => gtrefclk_bb,
            ODIV2   => open);

        -- The "GTXE2_COMMON" block is required even if we're not using a QPLL.
        -- Settings are copied from the auto-generated Xilinx IP-core.
        gtxe2_common_i : GTXE2_COMMON
            generic map(
            SIM_RESET_SPEEDUP       => "TRUE",
            SIM_QPLLREFCLK_SEL      => "001",
            SIM_VERSION             => "4.0",
            BIAS_CFG                => x"0000040000001000",
            COMMON_CFG              => x"00000000",
            QPLL_CFG                => x"06801C1",
            QPLL_CLKOUT_CFG         => "0000",
            QPLL_COARSE_FREQ_OVRD   => "010000",
            QPLL_COARSE_FREQ_OVRD_EN=> '0',
            QPLL_CP                 => "0000011111",
            QPLL_CP_MONITOR_EN      => '0',
            QPLL_DMONITOR_SEL       => '0',
            QPLL_FBDIV              => "0000100000",
            QPLL_FBDIV_MONITOR_EN   => '0',
            QPLL_FBDIV_RATIO        => '1',
            QPLL_INIT_CFG           => x"000006",
            QPLL_LOCK_CFG           => x"21E8",
            QPLL_LPF                => "1111",
            QPLL_REFCLK_DIV         => 1)
            port map(
            drpaddr                 => (others => '0'),
            drpclk                  => gtsysclk,
            drpdi                   => (others => '0'),
            drpdo                   => open,
            drpen                   => '0',
            drprdy                  => open,
            drpwe                   => '0',
            gtgrefclk               => '0', -- QPLL is not used, no-connect OK
            gtnorthrefclk0          => '0',
            gtnorthrefclk1          => '0',
            gtrefclk0               => '0',
            gtrefclk1               => '0',
            gtsouthrefclk0          => '0',
            gtsouthrefclk1          => '0',
            qplldmonitor            => open,
            qplloutclk              => gtrefclk_q1,
            qplloutrefclk           => gtrefclk_q2,
            refclkoutmonitor        => open,
            qpllfbclklost           => open,
            qplllock                => open,
            qplllockdetclk          => gtsysclk,
            qplllocken              => '1',
            qplloutreset            => '0',
            qpllpd                  => '1',
            qpllrefclklost          => open,
            qpllrefclksel           => "001",
            qpllreset               => reset_req,
            qpllrsvd1               => "0000000000000000",
            qpllrsvd2               => "11111",
            bgbypassb               => '1',
            bgmonitorenb            => '1',
            bgpdb                   => '1',
            bgrcalovrd              => "11111",
            pmarsvd                 => "00000000",
            rcalenb                 => '1');
    end generate;

    -- Clock buffers bring Tx and Rx clocks into FPGA fabric.
    u_rxclk : bufg
        port map(I => gtoutclk_rx, O => rx_clk125);
    u_txclk : bufg
        port map(I => gtoutclk_tx, O => tx_clk125);

    -- Instantiate the Xilinx IP-core with the designated source index.
    -- (Internal logic is different, depending on REFCLK_SRC selection.)
    gen_src0 : if REFCLK_SRC = 0 generate
        u_mgt : sgmii_raw_gtx0
            port map(
            sysclk_in                   => gtsysclk,
            soft_reset_tx_in            => reset_req,
            soft_reset_rx_in            => reset_req,
            dont_reset_on_data_error_in => '1',
            gt0_tx_fsm_reset_done_out   => gt_ready_tx,
            gt0_rx_fsm_reset_done_out   => gt_ready_rx,
            gt0_data_valid_in           => '1',
            gt0_cpllfbclklost_out       => open,
            gt0_cplllock_out            => open,
            gt0_cplllockdetclk_in       => gtsysclk,
            gt0_cpllreset_in            => reset_req,
            gt0_gtrefclk0_in            => gtrefclk_bb,
            gt0_gtrefclk1_in            => '0',
            gt0_drpaddr_in              => (others => '0'),
            gt0_drpclk_in               => gtsysclk,
            gt0_drpdi_in                => (others => '0'),
            gt0_drpdo_out               => open,
            gt0_drpen_in                => '0',
            gt0_drprdy_out              => open,
            gt0_drpwe_in                => '0',
            gt0_dmonitorout_out         => open,
            gt0_eyescanreset_in         => '0',
            gt0_rxuserrdy_in            => '1',
            gt0_eyescandataerror_out    => open,
            gt0_eyescantrigger_in       => '0',
            gt0_rxusrclk_in             => rx_clk125,
            gt0_rxusrclk2_in            => rx_clk125,
            gt0_rxdata_out              => rx_data20,
            gt0_gtxrxp_in               => sgmii_rxp,
            gt0_gtxrxn_in               => sgmii_rxn,
            gt0_rxphmonitor_out         => open,
            gt0_rxphslipmonitor_out     => open,
            gt0_rxdfelpmreset_in        => '0',
            gt0_rxmonitorout_out        => open,
            gt0_rxmonitorsel_in         => (others => '0'),
            gt0_rxoutclk_out            => gtoutclk_rx,
            gt0_rxoutclkfabric_out      => open,
            gt0_gtrxreset_in            => reset_req,
            gt0_rxpmareset_in           => reset_req,
            gt0_rxresetdone_out         => open,
            gt0_gttxreset_in            => reset_req,
            gt0_txuserrdy_in            => '1',
            gt0_txusrclk_in             => tx_clk125,
            gt0_txusrclk2_in            => tx_clk125,
            gt0_txdata_in               => tx_data20,
            gt0_gtxtxn_out              => sgmii_txn,
            gt0_gtxtxp_out              => sgmii_txp,
            gt0_txoutclk_out            => gtoutclk_tx,
            gt0_txoutclkfabric_out      => open,
            gt0_txoutclkpcs_out         => open,
            gt0_txresetdone_out         => open,
            gt0_qplloutclk_in           => gtrefclk_q1,
            gt0_qplloutrefclk_in        => gtrefclk_q2);
    end generate;

    gen_src1 : if REFCLK_SRC = 1 generate
        u_mgt : sgmii_raw_gtx1
            port map(
            sysclk_in                   => gtsysclk,
            soft_reset_tx_in            => reset_req,
            soft_reset_rx_in            => reset_req,
            dont_reset_on_data_error_in => '1',
            gt0_tx_fsm_reset_done_out   => gt_ready_tx,
            gt0_rx_fsm_reset_done_out   => gt_ready_rx,
            gt0_data_valid_in           => '1',
            gt0_cpllfbclklost_out       => open,
            gt0_cplllock_out            => open,
            gt0_cplllockdetclk_in       => gtsysclk,
            gt0_cpllreset_in            => reset_req,
            gt0_gtrefclk0_in            => '0',
            gt0_gtrefclk1_in            => gtrefclk_bb,
            gt0_drpaddr_in              => (others => '0'),
            gt0_drpclk_in               => gtsysclk,
            gt0_drpdi_in                => (others => '0'),
            gt0_drpdo_out               => open,
            gt0_drpen_in                => '0',
            gt0_drprdy_out              => open,
            gt0_drpwe_in                => '0',
            gt0_dmonitorout_out         => open,
            gt0_eyescanreset_in         => '0',
            gt0_rxuserrdy_in            => '1',
            gt0_eyescandataerror_out    => open,
            gt0_eyescantrigger_in       => '0',
            gt0_rxusrclk_in             => rx_clk125,
            gt0_rxusrclk2_in            => rx_clk125,
            gt0_rxdata_out              => rx_data20,
            gt0_gtxrxp_in               => sgmii_rxp,
            gt0_gtxrxn_in               => sgmii_rxn,
            gt0_rxphmonitor_out         => open,
            gt0_rxphslipmonitor_out     => open,
            gt0_rxdfelpmreset_in        => '0',
            gt0_rxmonitorout_out        => open,
            gt0_rxmonitorsel_in         => (others => '0'),
            gt0_rxoutclk_out            => gtoutclk_rx,
            gt0_rxoutclkfabric_out      => open,
            gt0_gtrxreset_in            => reset_req,
            gt0_rxpmareset_in           => reset_req,
            gt0_rxresetdone_out         => open,
            gt0_gttxreset_in            => reset_req,
            gt0_txuserrdy_in            => '1',
            gt0_txusrclk_in             => tx_clk125,
            gt0_txusrclk2_in            => tx_clk125,
            gt0_txdata_in               => tx_data20,
            gt0_gtxtxn_out              => sgmii_txn,
            gt0_gtxtxp_out              => sgmii_txp,
            gt0_txoutclk_out            => gtoutclk_tx,
            gt0_txoutclkfabric_out      => open,
            gt0_txoutclkpcs_out         => open,
            gt0_txresetdone_out         => open,
            gt0_qplloutclk_in           => gtrefclk_q1,
            gt0_qplloutrefclk_in        => gtrefclk_q2);
    end generate;
end generate;

gen_gty0 : if MGT_TYPE = "gty" generate
    -- Shared signals are not required in this mode.
    shared_out <= (others => '0');

    u_refclk : ibufds_gte4
        port map(
        CEB     => '0',
        I       => gtrefclk_p,
        IB      => gtrefclk_n,
        O       => gtrefclk_bb,
        ODIV2   => open);

    u_mgt : sgmii_raw_gty0
        port map(
        drpclk_in                           => (others => gtsysclk),
        gtpowergood_out                     => open,
        gtrefclk0_in(0)                     => gtrefclk_bb,
        gtwiz_buffbypass_rx_done_out        => open,
        gtwiz_buffbypass_rx_error_out       => open,
        gtwiz_buffbypass_rx_reset_in        => (others => async_reset),
        gtwiz_buffbypass_rx_start_user_in   => (others => '0'),
        gtwiz_buffbypass_tx_done_out        => open,
        gtwiz_buffbypass_tx_error_out       => open,
        gtwiz_buffbypass_tx_reset_in        => (others => async_reset),
        gtwiz_buffbypass_tx_start_user_in   => (others => '0'),
        gtwiz_reset_all_in                  => (others => reset_req),
        gtwiz_reset_clk_freerun_in          => (others => gtsysclk),
        gtwiz_reset_rx_cdr_stable_out       => open,
        gtwiz_reset_rx_datapath_in          => (others => reset_req),
        gtwiz_reset_rx_done_out(0)          => gt_ready_rx,
        gtwiz_reset_rx_pll_and_datapath_in  => (others => reset_req),
        gtwiz_reset_tx_datapath_in          => (others => reset_req),
        gtwiz_reset_tx_done_out(0)          => gt_ready_tx,
        gtwiz_reset_tx_pll_and_datapath_in  => (others => reset_req),
        gtwiz_userclk_rx_active_in          => (others => '1'),
        gtwiz_userclk_tx_active_in          => (others => '1'),
        gtwiz_userclk_tx_reset_in           => (others => reset_req),
        gtwiz_userdata_rx_out               => rx_data20,
        gtwiz_userdata_tx_in                => tx_data20,
        gtyrxn_in(0)                        => sgmii_rxn,
        gtyrxp_in(0)                        => sgmii_rxp,
        gtytxn_out(0)                       => sgmii_txn,
        gtytxp_out(0)                       => sgmii_txp,
        rxoutclk_out(0)                     => rx_clk125,
        rxpmaresetdone_out                  => open,
        rxusrclk_in(0)                      => rx_clk125,
        rxusrclk2_in(0)                     => rx_clk125,
        txoutclk_out(0)                     => tx_clk125,
        txpmaresetdone_out                  => open,
        txprgdivresetdone_out               => open,
        txusrclk_in(0)                      => tx_clk125,
        txusrclk2_in(0)                     => tx_clk125);
end generate;

end port_sgmii_raw;
