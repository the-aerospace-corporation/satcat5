--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- SGMII port using Microsemi's XCVR Trancievers in raw mode
--
-- This module uses the Microsemi "Transceiver Interface", "Transmit PLL",
-- and "Tranciever Reference Clock" IP-cores. The Tranciever interface is
-- set up in raw mode (i.e., The transceiver silicon is used for serialization
-- and CDR only.) All 8b/10b and SGMII logic is built using regular HDL. This
-- consumes additional fabric resources, but allows sub-nanosecond timestamp
-- accuracy for PTP.
--
-- This block depends on the IP-cores, which can be added to the Libero project
-- by performing the following steps:
--  * From a TCL build script or libero's source script command source
--  * PF_TX_PLL.tcl, PF_XCVR_ERM.tcl, and PF_XCVR_REF_CLK.tcl
--      * Finally `source generate_sgmii_gtx.tcl`
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_sgmii_raw is
    generic (
    SHAKE_WAIT  : boolean := false;     -- Wait for MAC/PHY handshake?
    LANES       : integer := 4;         -- Does this instance of XCVR use multiple lanes
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (

    -- External SGMII interfaces (direct to MGT pins)
    sgmii_rxp   : in  std_logic_vector(LANES-1 downto 0);
    sgmii_rxn   : in  std_logic_vector(LANES-1 downto 0);
    sgmii_txp   : out std_logic_vector(LANES-1 downto 0);
    sgmii_txn   : out std_logic_vector(LANES-1 downto 0);

    -- Generic internal port interfaces.
    prx_data    : out array_rx_m2s (LANES-1 downto 0);
    ptx_data    : in  array_tx_s2m (LANES-1 downto 0);
    ptx_ctrl    : out array_tx_m2s (LANES-1 downto 0);
    quad_shdn   : in  std_logic;
    lane_shdn   : in  std_logic_vector (LANES-1 downto 0);
    lane_test   : in  std_logic_vector (LANES-1 downto 0) := (others => '0');

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;

    -- (Refclk must match frequency set in TCL scripts, default 125 MHz.)
    refclk_p    : in  std_logic;
    refclk_n    : in  std_logic;

    -- Additional clocks.
    sysclk      : in  std_logic);   -- Independent free-running clock
end port_sgmii_raw;

architecture port_sgmii_raw of port_sgmii_raw is

-- Component declarations are copied from Microchip templates.
component pf_xcvr_1_c0 is
    port (
    TX_BIT_CLK_0        : in   std_logic;
    TX_PLL_LOCK_0       : in   std_logic;
    TX_PLL_REF_CLK_0    : in   std_logic;

    LANE0_CDR_REF_CLK_0 : in   std_logic;
    LANE0_PCS_ARST_N    : in   std_logic;
    LANE0_PMA_ARST_N    : in   std_logic;
    LANE0_RXD_N         : in   std_logic;
    LANE0_RXD_P         : in   std_logic;
    LANE0_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE0_TX_ELEC_IDLE  : in   std_logic;
    LANE0_RX_BYPASS_DATA : out   std_logic;
    LANE0_RX_CLK_R      : out   std_logic;
    LANE0_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE0_RX_IDLE       : out   std_logic;
    LANE0_RX_READY      : out   std_logic;
    LANE0_RX_VAL        : out   std_logic;
    LANE0_TXD_N         : out   std_logic;
    LANE0_TXD_P         : out   std_logic;
    LANE0_TX_CLK_R      : out   std_logic;
    LANE0_TX_CLK_STABLE : out   std_logic);
end component;

component pf_xcvr_2_c0 is
    port (
    TX_BIT_CLK_0        : in   std_logic;
    TX_PLL_LOCK_0       : in   std_logic;
    TX_PLL_REF_CLK_0    : in   std_logic;

    LANE0_CDR_REF_CLK_0 : in   std_logic;
    LANE0_PCS_ARST_N    : in   std_logic;
    LANE0_PMA_ARST_N    : in   std_logic;
    LANE0_RXD_N         : in   std_logic;
    LANE0_RXD_P         : in   std_logic;
    LANE0_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE0_TX_ELEC_IDLE  : in   std_logic;
    LANE0_RX_BYPASS_DATA : out   std_logic;
    LANE0_RX_CLK_R      : out   std_logic;
    LANE0_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE0_RX_IDLE       : out   std_logic;
    LANE0_RX_READY      : out   std_logic;
    LANE0_RX_VAL        : out   std_logic;
    LANE0_TXD_N         : out   std_logic;
    LANE0_TXD_P         : out   std_logic;
    LANE0_TX_CLK_R      : out   std_logic;
    LANE0_TX_CLK_STABLE : out   std_logic;

    LANE1_CDR_REF_CLK_0 : in   std_logic;
    LANE1_PCS_ARST_N    : in   std_logic;
    LANE1_PMA_ARST_N    : in   std_logic;
    LANE1_RXD_N         : in   std_logic;
    LANE1_RXD_P         : in   std_logic;
    LANE1_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE1_TX_ELEC_IDLE  : in   std_logic;
    LANE1_RX_BYPASS_DATA : out   std_logic;
    LANE1_RX_CLK_R      : out   std_logic;
    LANE1_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE1_RX_IDLE       : out   std_logic;
    LANE1_RX_READY      : out   std_logic;
    LANE1_RX_VAL        : out   std_logic;
    LANE1_TXD_N         : out   std_logic;
    LANE1_TXD_P         : out   std_logic;
    LANE1_TX_CLK_R      : out   std_logic;
    LANE1_TX_CLK_STABLE : out   std_logic);
end component;

component pf_xcvr_3_c0 is
    port (
    TX_BIT_CLK_0        : in   std_logic;
    TX_PLL_LOCK_0       : in   std_logic;
    TX_PLL_REF_CLK_0    : in   std_logic;

    LANE0_CDR_REF_CLK_0 : in   std_logic;
    LANE0_PCS_ARST_N    : in   std_logic;
    LANE0_PMA_ARST_N    : in   std_logic;
    LANE0_RXD_N         : in   std_logic;
    LANE0_RXD_P         : in   std_logic;
    LANE0_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE0_TX_ELEC_IDLE  : in   std_logic;
    LANE0_RX_BYPASS_DATA : out   std_logic;
    LANE0_RX_CLK_R      : out   std_logic;
    LANE0_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE0_RX_IDLE       : out   std_logic;
    LANE0_RX_READY      : out   std_logic;
    LANE0_RX_VAL        : out   std_logic;
    LANE0_TXD_N         : out   std_logic;
    LANE0_TXD_P         : out   std_logic;
    LANE0_TX_CLK_R      : out   std_logic;
    LANE0_TX_CLK_STABLE : out   std_logic;

    LANE1_CDR_REF_CLK_0 : in   std_logic;
    LANE1_PCS_ARST_N    : in   std_logic;
    LANE1_PMA_ARST_N    : in   std_logic;
    LANE1_RXD_N         : in   std_logic;
    LANE1_RXD_P         : in   std_logic;
    LANE1_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE1_TX_ELEC_IDLE  : in   std_logic;
    LANE1_RX_BYPASS_DATA : out   std_logic;
    LANE1_RX_CLK_R      : out   std_logic;
    LANE1_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE1_RX_IDLE       : out   std_logic;
    LANE1_RX_READY      : out   std_logic;
    LANE1_RX_VAL        : out   std_logic;
    LANE1_TXD_N         : out   std_logic;
    LANE1_TXD_P         : out   std_logic;
    LANE1_TX_CLK_R      : out   std_logic;
    LANE1_TX_CLK_STABLE : out   std_logic;

    LANE2_CDR_REF_CLK_0 : in   std_logic;
    LANE2_PCS_ARST_N    : in   std_logic;
    LANE2_PMA_ARST_N    : in   std_logic;
    LANE2_RXD_N         : in   std_logic;
    LANE2_RXD_P         : in   std_logic;
    LANE2_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE2_TX_ELEC_IDLE  : in   std_logic;
    LANE2_RX_BYPASS_DATA : out   std_logic;
    LANE2_RX_CLK_R      : out   std_logic;
    LANE2_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE2_RX_IDLE       : out   std_logic;
    LANE2_RX_READY      : out   std_logic;
    LANE2_RX_VAL        : out   std_logic;
    LANE2_TXD_N         : out   std_logic;
    LANE2_TXD_P         : out   std_logic;
    LANE2_TX_CLK_R      : out   std_logic;
    LANE2_TX_CLK_STABLE : out   std_logic);
end component;

component pf_xcvr_4_c0 is
    port (
    TX_BIT_CLK_0        : in   std_logic;
    TX_PLL_LOCK_0       : in   std_logic;
    TX_PLL_REF_CLK_0    : in   std_logic;

    LANE0_CDR_REF_CLK_0 : in   std_logic;
    LANE0_PCS_ARST_N    : in   std_logic;
    LANE0_PMA_ARST_N    : in   std_logic;
    LANE0_RXD_N         : in   std_logic;
    LANE0_RXD_P         : in   std_logic;
    LANE0_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE0_TX_ELEC_IDLE  : in   std_logic;
    LANE0_RX_BYPASS_DATA : out   std_logic;
    LANE0_RX_CLK_R      : out   std_logic;
    LANE0_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE0_RX_IDLE       : out   std_logic;
    LANE0_RX_READY      : out   std_logic;
    LANE0_RX_VAL        : out   std_logic;
    LANE0_TXD_N         : out   std_logic;
    LANE0_TXD_P         : out   std_logic;
    LANE0_TX_CLK_R      : out   std_logic;
    LANE0_TX_CLK_STABLE : out   std_logic;

    LANE1_CDR_REF_CLK_0 : in   std_logic;
    LANE1_PCS_ARST_N    : in   std_logic;
    LANE1_PMA_ARST_N    : in   std_logic;
    LANE1_RXD_N         : in   std_logic;
    LANE1_RXD_P         : in   std_logic;
    LANE1_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE1_TX_ELEC_IDLE  : in   std_logic;
    LANE1_RX_BYPASS_DATA : out   std_logic;
    LANE1_RX_CLK_R      : out   std_logic;
    LANE1_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE1_RX_IDLE       : out   std_logic;
    LANE1_RX_READY      : out   std_logic;
    LANE1_RX_VAL        : out   std_logic;
    LANE1_TXD_N         : out   std_logic;
    LANE1_TXD_P         : out   std_logic;
    LANE1_TX_CLK_R      : out   std_logic;
    LANE1_TX_CLK_STABLE : out   std_logic;

    LANE2_CDR_REF_CLK_0 : in   std_logic;
    LANE2_PCS_ARST_N    : in   std_logic;
    LANE2_PMA_ARST_N    : in   std_logic;
    LANE2_RXD_N         : in   std_logic;
    LANE2_RXD_P         : in   std_logic;
    LANE2_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE2_TX_ELEC_IDLE  : in   std_logic;
    LANE2_RX_BYPASS_DATA : out   std_logic;
    LANE2_RX_CLK_R      : out   std_logic;
    LANE2_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE2_RX_IDLE       : out   std_logic;
    LANE2_RX_READY      : out   std_logic;
    LANE2_RX_VAL        : out   std_logic;
    LANE2_TXD_N         : out   std_logic;
    LANE2_TXD_P         : out   std_logic;
    LANE2_TX_CLK_R      : out   std_logic;
    LANE2_TX_CLK_STABLE : out   std_logic;

    LANE3_CDR_REF_CLK_0 : in   std_logic;
    LANE3_PCS_ARST_N    : in   std_logic;
    LANE3_PMA_ARST_N    : in   std_logic;
    LANE3_RXD_N         : in   std_logic;
    LANE3_RXD_P         : in   std_logic;
    LANE3_TX_DATA       : in   std_logic_vector (9 downto 0);
    LANE3_TX_ELEC_IDLE  : in   std_logic;
    LANE3_RX_BYPASS_DATA : out   std_logic;
    LANE3_RX_CLK_R      : out   std_logic;
    LANE3_RX_DATA       : out   std_logic_vector (9 downto 0);
    LANE3_RX_IDLE       : out   std_logic;
    LANE3_RX_READY      : out   std_logic;
    LANE3_RX_VAL        : out   std_logic;
    LANE3_TXD_N         : out   std_logic;
    LANE3_TXD_P         : out   std_logic;
    LANE3_TX_CLK_R      : out   std_logic;
    LANE3_TX_CLK_STABLE : out   std_logic);
end component;

component pf_xcvr_ref_clk_c0
    port (
    REF_CLK_PAD_P       : in  std_logic;
    REF_CLK_PAD_N       : in  std_logic;
    REF_CLK             : out std_logic);
end component;

component pf_tx_pll_c0
    port (
    REF_CLK             : in  std_logic;
    PLL_LOCK            : in  std_logic;
    BIT_CLK             : in  std_logic;
    LOCK                : out std_logic;
    REF_CLK_TO_LANE     : out std_logic;
    CLK_125             : out std_logic);
end component;

-- Reset signals for each clock domain.
signal reset_req    : std_logic;
signal async_reset  : std_logic_vector (LANES-1 downto 0);
signal tx_reset_p   : std_logic_vector (LANES-1 downto 0);
signal rx_reset_p   : std_logic_vector (LANES-1 downto 0);

-- Array types used in datapath
-- I do not think these will be used anywhere else so not putting in ptp_types
type array_tstamp is array(natural range<>) of tstamp_t;
type array_tfreq is array(natural range<>) of tfreq_t;

-- Transmit datapath.
signal tx_clk125    : std_logic_vector (LANES-1 downto 0);
signal tx_data10    : std_logic_vector(10*LANES-1 downto 0);
signal tx_tstamp    : array_tstamp (LANES-1 downto 0) := (others => TSTAMP_DISABLED);
signal tx_tfreq     : array_tfreq (LANES-1 downto 0) := (others => TFREQ_DISABLED);
signal tx_tvalid    : std_logic_vector (LANES-1 downto 0) := (others => '0');

-- Receive datapath.
signal rx_clk125    : std_logic_vector (LANES-1 downto 0);
signal rx_locked    : std_logic_vector (LANES-1 downto 0);
signal rx_data10    : std_logic_vector(10*LANES-1 downto 0);
signal rx_tstamp10  : array_tstamp (LANES-1 downto 0) := (others => TSTAMP_DISABLED);
signal rx_tstamp20  : array_tstamp (LANES-1 downto 0) := (others => TSTAMP_DISABLED);
signal rx_tfreq     : array_tfreq (LANES-1 downto 0) := (others => TFREQ_DISABLED);
signal rx_tvalid    : std_logic_vector (LANES-1 downto 0) := (others => '0');

-- MGT control signals.
signal ready_rx     : std_logic_vector (LANES-1 downto 0);
signal ready_tx     : std_logic_vector (LANES-1 downto 0);

signal xcvr_ref_clk_single  : std_logic;
signal tx_bit_clk   : std_logic;
signal tx_lock      : std_logic;
signal tx_ref_clk   : std_logic;
signal pll_lock     : std_logic;

begin
    -- I do not think this is technically needed. Docs say XCVR reset is async
    -- CDR is reset by this and CDR clock ref is xcvr_ref_clk_single
    u_reset_req : sync_reset
        port map(
        in_reset_p  => quad_shdn,
        out_reset_p => reset_req,
        out_clk     => xcvr_ref_clk_single);

    u_xcvr_ref_clk : pf_xcvr_ref_clk_c0
        port map(
            REF_CLK_PAD_P       => refclk_p,
            REF_CLK_PAD_N       => refclk_n,
            REF_CLK             => xcvr_ref_clk_single);

    u_tx_pll : pf_tx_pll_c0
        port map(
            REF_CLK             => xcvr_ref_clk_single,
            PLL_LOCK            => pll_lock,        -- Hanging as in example design
            BIT_CLK             => tx_bit_clk,
            LOCK                => tx_lock,
            REF_CLK_TO_LANE     => tx_ref_clk,
            CLK_125             => open);

    gen_ts_support : for n in 0 to LANES-1 generate
        -- I am not sure that this is what we want because whenever the rx datapath does not have
        -- valid data, the rest of logic would be held in reset. It makes more sense to me that
        -- reset would be triggered off of clock locked like so
        --async_reset(n) <= reset_req or not (rx_locked(n) and ready_tx(n));
        -- Please carefully check my reset and clocking logic because I understood that the least

        -- Documenting Alex's comment from pr:
        -- Let's get this PR merged but keep the reset logic as a watch item.
        -- My gut feeling is that we may need to separate the Tx-reset from the Rx-reset. This
        -- avoids a possible deadlock if two SGMII ports are connected back-to-back. i.e., At
        -- least one port needs to start transmitting a signal before there's a valid received
        -- signal, or there's a chicken-and-egg problem. To do that, the "port_sgmii_common"
        -- block should be released from reset as soon as there's a valid tx clock.
        -- On that note, my recommendation would be something like:
        -- async_reset_rx(n) <= reset_req or not ready_rx;
        -- async_reset_tx(n) <= reset_req or not ready_tx;
        -- ...and then update the two sync_reset blocks accordingly.
        async_reset(n) <= reset_req or not (ready_rx(n) and ready_tx(n));

        -- Each lane has its own tx and rx clock
        u_rx_rst : sync_reset
            port map(
            in_reset_p  => async_reset(n),
            out_reset_p => rx_reset_p(n),
            out_clk     => rx_clk125(n));

        u_tx_rst : sync_reset
            port map(
            in_reset_p  => async_reset(n),
            out_reset_p => tx_reset_p(n),
            out_clk     => tx_clk125(n));

        -- Each lane needs timestamping logic for tx and rx
        -- Timestamps for each clock domain, if enabled.
        gen_tstamp : if VCONFIG.input_hz > 0 generate
            u_rx_tstamp : entity work.ptp_counter_sync
                generic map(
                VCONFIG     => VCONFIG,
                USER_CLK_HZ => 125_000_000)
                port map(
                ref_time    => ref_time,
                user_clk    => rx_clk125(n),
                user_ctr    => rx_tstamp20(n),
                user_freq   => rx_tfreq(n),
                user_lock   => rx_tvalid(n),
                user_rst_p  => rx_reset_p(n));

            u_tx_tstamp : entity work.ptp_counter_sync
                generic map(
                VCONFIG     => VCONFIG,
                USER_CLK_HZ => 125_000_000)
                port map(
                ref_time    => ref_time,
                user_clk    => tx_clk125(n),
                user_ctr    => tx_tstamp(n),
                user_freq   => tx_tfreq(n),
                user_lock   => tx_tvalid(n),
                user_rst_p  => tx_reset_p(n));
        end generate;

        -- Interface for each lane
        -- Connect 8b/10b signals to the SatCat5 port interface.
        -- Also includes preamble insertion, rate-detect state machine, etc.
        u_sgmii : entity work.port_sgmii_common
            generic map(
            MSB_FIRST   => false,
            SHAKE_WAIT  => SHAKE_WAIT)
            port map(
            tx_clk      => tx_clk125(n),
            tx_data     => tx_data10((n+1)*10-1 downto n*10),
            tx_tstamp   => tx_tstamp(n),
            tx_tfreq    => tx_tfreq(n),
            tx_tvalid   => tx_tvalid(n),
            port_test   => lane_test(n),
            rx_clk      => rx_clk125(n),
            rx_lock     => rx_locked(n),
            rx_data     => rx_data10((n+1)*10-1 downto n*10),
            rx_tstamp   => rx_tstamp10(n),
            rx_tfreq    => rx_tfreq(n),
            rx_tvalid   => rx_tvalid(n),
            prx_data    => prx_data(n),
            ptx_data    => ptx_data(n),
            ptx_ctrl    => ptx_ctrl(n),
            reset_p     => tx_reset_p(n));
    end generate;

    -- Cant instantiate in loop because conditional ports are impossible
    gen_xcvr_1 : if LANES = 1 generate
        xcvr : pf_xcvr_1_c0
            port map(
            -- Shared
            TX_BIT_CLK_0            => tx_bit_clk,
            TX_PLL_LOCK_0           => tx_lock,
            TX_PLL_REF_CLK_0        => tx_ref_clk,
            -- Lane 0 Inputs
            LANE0_RXD_N             => sgmii_rxn(0),
            LANE0_RXD_P             => sgmii_rxp(0),
            LANE0_CDR_REF_CLK_0     => xcvr_ref_clk_single,  -- Example design connects it to single ended xcvr_ref_clk that feeds pll
            LANE0_PCS_ARST_N        => reset_req,           -- Async active low for PCS lane
            LANE0_PMA_ARST_N        => reset_req,           -- Async active low for PMA lane
            LANE0_TX_DATA           => tx_data10(9 downto 0),
            LANE0_TX_ELEC_IDLE      => lane_shdn(0),
            -- Lane 0 Outputs
            LANE0_TXD_N             => sgmii_txn(0),
            LANE0_TXD_P             => sgmii_txp(0),
            LANE0_RX_BYPASS_DATA    => open,                -- Low spreed rx bypass for debug, leaving open for now
            LANE0_RX_CLK_R          => rx_clk125(0),
            LANE0_RX_DATA           => rx_data10(9 downto 0),
            LANE0_RX_IDLE           => open,                -- Electrical idle detection flag, async assert, sync deassert to rx_clk_out. open for now
            LANE0_RX_READY          => rx_locked(0),        -- Rx PLL locked, asserts when CDR completes fine lock detection and deserializer is powered
            LANE0_RX_VAL            => ready_rx(0),         -- XCVR data path is initialized, contains actual data recovered from serial stream
            LANE0_TX_CLK_R          => tx_clk125(0),
            LANE0_TX_CLK_STABLE     => ready_tx(0));        -- Tx clock locked, in the example design it is routed to reset block. Assuming ready_tx
    end generate;

    gen_xcvr_2 : if LANES = 2 generate
        xcvr : pf_xcvr_2_c0
            port map(
            -- Shared
            TX_BIT_CLK_0            => tx_bit_clk,
            TX_PLL_LOCK_0           => tx_lock,
            TX_PLL_REF_CLK_0        => tx_ref_clk,
            -- Lane 0 Inputs
            LANE0_RXD_N             => sgmii_rxn(0),
            LANE0_RXD_P             => sgmii_rxp(0),
            LANE0_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE0_PCS_ARST_N        => reset_req,
            LANE0_PMA_ARST_N        => reset_req,
            LANE0_TX_DATA           => tx_data10(9 downto 0),
            LANE0_TX_ELEC_IDLE      => lane_shdn(0),
            -- Lane 0 Outputs
            LANE0_TXD_N             => sgmii_txn(0),
            LANE0_TXD_P             => sgmii_txp(0),
            LANE0_RX_BYPASS_DATA    => open,
            LANE0_RX_CLK_R          => rx_clk125(0),
            LANE0_RX_DATA           => rx_data10(9 downto 0),
            LANE0_RX_IDLE           => open,
            LANE0_RX_READY          => rx_locked(0),
            LANE0_RX_VAL            => ready_rx(0),
            LANE0_TX_CLK_R          => tx_clk125(0),
            LANE0_TX_CLK_STABLE     => ready_tx(0),

            -- Lane 1 Inputs
            LANE1_RXD_N             => sgmii_rxn(1),
            LANE1_RXD_P             => sgmii_rxp(1),
            LANE1_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE1_PCS_ARST_N        => reset_req,
            LANE1_PMA_ARST_N        => reset_req,
            LANE1_TX_DATA           => tx_data10(19 downto 10),
            LANE1_TX_ELEC_IDLE      => lane_shdn(1),
            -- Lane 1 Outputs
            LANE1_TXD_N             => sgmii_txn(1),
            LANE1_TXD_P             => sgmii_txp(1),
            LANE1_RX_BYPASS_DATA    => open,
            LANE1_RX_CLK_R          => rx_clk125(1),
            LANE1_RX_DATA           => rx_data10(19 downto 10),
            LANE1_RX_IDLE           => open,
            LANE1_RX_READY          => rx_locked(1),
            LANE1_RX_VAL            => ready_rx(1),
            LANE1_TX_CLK_R          => tx_clk125(1),
            LANE1_TX_CLK_STABLE     => ready_tx(1));
    end generate;

    gen_xcvr_3 : if LANES = 3 generate
        xcvr3 : pf_xcvr_3_c0
            port map(
            -- Shared
            TX_BIT_CLK_0            => tx_bit_clk,
            TX_PLL_LOCK_0           => tx_lock,
            TX_PLL_REF_CLK_0        => tx_ref_clk,
            -- Lane 0 Inputs
            LANE0_RXD_N             => sgmii_rxn(0),
            LANE0_RXD_P             => sgmii_rxp(0),
            LANE0_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE0_PCS_ARST_N        => reset_req,
            LANE0_PMA_ARST_N        => reset_req,
            LANE0_TX_DATA           => tx_data10(9 downto 0),
            LANE0_TX_ELEC_IDLE      => lane_shdn(0),
            -- Lane 0 Outputs
            LANE0_TXD_N             => sgmii_txn(0),
            LANE0_TXD_P             => sgmii_txp(0),
            LANE0_RX_BYPASS_DATA    => open,
            LANE0_RX_CLK_R          => rx_clk125(0),
            LANE0_RX_DATA           => rx_data10(9 downto 0),
            LANE0_RX_IDLE           => open,
            LANE0_RX_READY          => rx_locked(0),
            LANE0_RX_VAL            => ready_rx(0),
            LANE0_TX_CLK_R          => tx_clk125(0),
            LANE0_TX_CLK_STABLE     => ready_tx(0),

            -- Lane 1 Inputs
            LANE1_RXD_N             => sgmii_rxn(1),
            LANE1_RXD_P             => sgmii_rxp(1),
            LANE1_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE1_PCS_ARST_N        => reset_req,
            LANE1_PMA_ARST_N        => reset_req,
            LANE1_TX_DATA           => tx_data10(19 downto 10),
            LANE1_TX_ELEC_IDLE      => lane_shdn(1),
            -- Lane 1 Outputs
            LANE1_TXD_N             => sgmii_txn(1),
            LANE1_TXD_P             => sgmii_txp(1),
            LANE1_RX_BYPASS_DATA    => open,
            LANE1_RX_CLK_R          => rx_clk125(1),
            LANE1_RX_DATA           => rx_data10(19 downto 10),
            LANE1_RX_IDLE           => open,
            LANE1_RX_READY          => rx_locked(1),
            LANE1_RX_VAL            => ready_rx(1),
            LANE1_TX_CLK_R          => tx_clk125(1),
            LANE1_TX_CLK_STABLE     => ready_tx(1),

            -- Lane 2 Inputs
            LANE2_RXD_N             => sgmii_rxn(2),
            LANE2_RXD_P             => sgmii_rxp(2),
            LANE2_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE2_PCS_ARST_N        => reset_req,
            LANE2_PMA_ARST_N        => reset_req,
            LANE2_TX_DATA           => tx_data10(29 downto 20),
            LANE2_TX_ELEC_IDLE      => lane_shdn(2),
            -- Lane 2 Outputs
            LANE2_TXD_N             => sgmii_txn(2),
            LANE2_TXD_P             => sgmii_txp(2),
            LANE2_RX_BYPASS_DATA    => open,
            LANE2_RX_CLK_R          => rx_clk125(2),
            LANE2_RX_DATA           => rx_data10(29 downto 20),
            LANE2_RX_IDLE           => open,
            LANE2_RX_READY          => rx_locked(2),
            LANE2_RX_VAL            => ready_rx(2),
            LANE2_TX_CLK_R          => tx_clk125(2),
            LANE2_TX_CLK_STABLE     => ready_tx(2));
    end generate;

    gen_xcvr_4 : if LANES = 4 generate
        xcvr : pf_xcvr_4_c0
            port map(
            -- Shared
            TX_BIT_CLK_0            => tx_bit_clk,
            TX_PLL_LOCK_0           => tx_lock,
            TX_PLL_REF_CLK_0        => tx_ref_clk,

            -- Lane 0 Inputs
            LANE0_RXD_N             => sgmii_rxn(0),
            LANE0_RXD_P             => sgmii_rxp(0),
            LANE0_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE0_PCS_ARST_N        => reset_req,
            LANE0_PMA_ARST_N        => reset_req,
            LANE0_TX_DATA           => tx_data10(9 downto 0),
            LANE0_TX_ELEC_IDLE      => lane_shdn(0),
            -- Lane 0 Outputs
            LANE0_TXD_N             => sgmii_txn(0),
            LANE0_TXD_P             => sgmii_txp(0),
            LANE0_RX_BYPASS_DATA    => open,
            LANE0_RX_CLK_R          => rx_clk125(0),
            LANE0_RX_DATA           => rx_data10(9 downto 0),
            LANE0_RX_IDLE           => open,
            LANE0_RX_READY          => rx_locked(0),
            LANE0_RX_VAL            => ready_rx(0),
            LANE0_TX_CLK_R          => tx_clk125(0),
            LANE0_TX_CLK_STABLE     => ready_tx(0),

            -- Lane 1 Inputs
            LANE1_RXD_N             => sgmii_rxn(1),
            LANE1_RXD_P             => sgmii_rxp(1),
            LANE1_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE1_PCS_ARST_N        => reset_req,
            LANE1_PMA_ARST_N        => reset_req,
            LANE1_TX_DATA           => tx_data10(19 downto 10),
            LANE1_TX_ELEC_IDLE      => lane_shdn(1),
            -- Lane 1 Outputs
            LANE1_TXD_N             => sgmii_txn(1),
            LANE1_TXD_P             => sgmii_txp(1),
            LANE1_RX_BYPASS_DATA    => open,
            LANE1_RX_CLK_R          => rx_clk125(1),
            LANE1_RX_DATA           => rx_data10(19 downto 10),
            LANE1_RX_IDLE           => open,
            LANE1_RX_READY          => rx_locked(1),
            LANE1_RX_VAL            => ready_rx(1),
            LANE1_TX_CLK_R          => tx_clk125(1),
            LANE1_TX_CLK_STABLE     => ready_tx(1),

            -- Lane 2 Inputs
            LANE2_RXD_N             => sgmii_rxn(2),
            LANE2_RXD_P             => sgmii_rxp(2),
            LANE2_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE2_PCS_ARST_N        => reset_req,
            LANE2_PMA_ARST_N        => reset_req,
            LANE2_TX_DATA           => tx_data10(29 downto 20),
            LANE2_TX_ELEC_IDLE      => lane_shdn(2),
            -- Lane 2 Outputs
            LANE2_TXD_N             => sgmii_txn(2),
            LANE2_TXD_P             => sgmii_txp(2),
            LANE2_RX_BYPASS_DATA    => open,
            LANE2_RX_CLK_R          => rx_clk125(2),
            LANE2_RX_DATA           => rx_data10(29 downto 20),
            LANE2_RX_IDLE           => open,
            LANE2_RX_READY          => rx_locked(2),
            LANE2_RX_VAL            => ready_rx(2),
            LANE2_TX_CLK_R          => tx_clk125(2),
            LANE2_TX_CLK_STABLE     => ready_tx(2),

            -- Lane 3 Inputs
            LANE3_RXD_N             => sgmii_rxn(3),
            LANE3_RXD_P             => sgmii_rxp(3),
            LANE3_CDR_REF_CLK_0     => xcvr_ref_clk_single,
            LANE3_PCS_ARST_N        => reset_req,
            LANE3_PMA_ARST_N        => reset_req,
            LANE3_TX_DATA           => tx_data10(39 downto 30),
            LANE3_TX_ELEC_IDLE      => lane_shdn(3),
            -- Lane 3 Outputs
            LANE3_TXD_N             => sgmii_txn(3),
            LANE3_TXD_P             => sgmii_txp(3),
            LANE3_RX_BYPASS_DATA    => open,
            LANE3_RX_CLK_R          => rx_clk125(3),
            LANE3_RX_DATA           => rx_data10(39 downto 30),
            LANE3_RX_IDLE           => open,
            LANE3_RX_READY          => rx_locked(3),
            LANE3_RX_VAL            => ready_rx(3),
            LANE3_TX_CLK_R          => tx_clk125(3),
            LANE3_TX_CLK_STABLE     => ready_tx(3));
    end generate;

end port_sgmii_raw;
