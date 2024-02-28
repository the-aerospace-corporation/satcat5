--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: Prototype V2 compact SatCat5 switch
--
-- This module is the top-level design for the compact prototype reference
-- design, which has 5 gigabit-Ethernet ports and 8 Ethernet-over-Serial
-- ports.  Each port also supplies switched and current-limited 5V power.
--
-- The target Xilinx FPGA is a mid-range Artix 7.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.switch_types.all;

entity switch_top_proto_v2 is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN";
    PORTS_SGMII : integer := 5;
    PORTS_EOS   : integer := 8);
    port (
    -- SGMII ports (and associated power control)
    sgmii_rxp   : in    std_logic_vector(PORTS_SGMII downto 1);
    sgmii_rxn   : in    std_logic_vector(PORTS_SGMII downto 1);
    sgmii_txp   : out   std_logic_vector(PORTS_SGMII downto 1);
    sgmii_txn   : out   std_logic_vector(PORTS_SGMII downto 1);
    sgmii_errb  : in    std_logic_vector(PORTS_SGMII-1 downto 1);
    sgmii_pwren : out   std_logic_vector(PORTS_SGMII-1 downto 1);

    -- EoS/PMOD interfaces (and associated power control)
    eos_pmod1   : inout std_logic_vector(PORTS_EOS downto 1);
    eos_pmod2   : inout std_logic_vector(PORTS_EOS downto 1);
    eos_pmod3   : inout std_logic_vector(PORTS_EOS downto 1);
    eos_pmod4   : inout std_logic_vector(PORTS_EOS downto 1);
    eos_errb    : in    std_logic_vector(PORTS_EOS downto 1);
    eos_pwren   : out   std_logic_vector(PORTS_EOS downto 1);

    -- Status indicators and other control.
    ext_clk25   : in    std_logic;  -- 25 MHz reference clock
    psense_scl  : inout std_logic;  -- I2C current monitoring
    psense_sda  : inout std_logic;
    phy_mdio    : inout std_logic;  -- MDIO for the AR8031 PHY
    phy_mdc     : out   std_logic;
    phy_rstn    : out   std_logic);
end switch_top_proto_v2;

architecture proto_v2 of switch_top_proto_v2 is

-- External reference is 25 MHz, generate all other clocks.
signal clk_25       : std_logic;
signal clk_125      : std_logic;
signal clk_200      : std_logic;
signal clk_625_00   : std_logic;
signal clk_625_90   : std_logic;

-- Internal control and status.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal ctrl_gpo     : std_logic_vector(31 downto 0);
signal fast_shdn    : std_logic;
signal fast_reset_p : std_logic;

-- Logical port for each interface to the switch core.
-- Note: Fast array size is +1 due to internal crosslink.
-- Note: Slow array size is +2 due to same, plus configuration port.
signal fast_rx_data  : array_rx_m2s(PORTS_SGMII downto 0);
signal fast_tx_data  : array_tx_s2m(PORTS_SGMII downto 0);
signal fast_tx_ctrl  : array_tx_m2s(PORTS_SGMII downto 0);
signal slow_rx_data  : array_rx_m2s(PORTS_EOS+1 downto 0);
signal slow_tx_data  : array_tx_s2m(PORTS_EOS+1 downto 0);
signal slow_tx_ctrl  : array_tx_m2s(PORTS_EOS+1 downto 0);

-- Error reporting infrastructure.
signal slow_err_t   : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal fast_err_t   : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal err_ignore   : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal swerr_vec_t  : std_logic_vector(2*SWITCH_ERR_WIDTH-1 downto 0);
signal scrub_req_t  : std_logic;

-- Prevent renaming of clocks and other key nets.
attribute KEEP : string;
attribute KEEP of clk_25, clk_125, clk_200  : signal is "true";
attribute KEEP of clk_625_00, clk_625_90    : signal is "true";
attribute KEEP of ctrl_gpo                  : signal is "true";

begin

-- Clock generation and global reset
u_clkbuf_sja : BUFG
    port map(
    I   => ext_clk25,
    O   => clk_25);

u_clkgen : entity work.clkgen_sgmii_xilinx
    generic map(
    REFCLK_HZ       => 25_000_000,
    SPEED_MULT      => 2)
    port map(
    shdn_p          => '0',
    rstin_p         => fast_shdn,
    clkin_ref0      => ext_clk25,
    clkin_ref1      => ext_clk25,
    clkin_sel       => '0',
    rstout_p        => fast_reset_p,
    clkout_125_00   => clk_125,
    clkout_125_90   => open,
    clkout_200      => clk_200,
    clkout_625_00   => clk_625_00,
    clkout_625_90   => clk_625_90);

-- Instantiate IDELAYCTRL for each bank where it's needed.
-- Note: Vivado will replicate this as needed.
u_idc : IDELAYCTRL
    port map(
    refclk  => clk_200,
    rst     => fast_reset_p,
    rdy     => open);

-- Power monitoring system.
-- TODO: Instantiate a simple state machine to poll power monitors.
-- TODO: Connect status to the power-monitoring system.
psense_scl  <= '1';
psense_sda  <= '1';

-- Crosslink between the two switch cores.
u_xlink : entity work.port_crosslink
    generic map(
    RUNT_PORTA  => true,
    RUNT_PORTB  => false)
    port map(
    rxa_data    => slow_rx_data(0),
    txa_data    => slow_tx_data(0),
    txa_ctrl    => slow_tx_ctrl(0),
    rxb_data    => fast_rx_data(0),
    txb_data    => fast_tx_data(0),
    txb_ctrl    => fast_tx_ctrl(0),
    ref_clk     => clk_25,
    reset_p     => fast_reset_p);

-- Internal configuration and status port.
-- TODO: Should the GbE port be enabled on startup?
-- TODO: Do we need a way to initialize MDIO automatically?
u_cfgbus : entity work.port_cfgbus
    generic map(
    CFG_ETYPE   => x"5C01",
    CFG_MACADDR => x"5A5ADEADBEEF")
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    rx_data     => slow_rx_data(1),
    tx_data     => slow_tx_data(1),
    tx_ctrl     => slow_tx_ctrl(1),
    sys_clk     => clk_25,
    reset_p     => '0');

u_periph : entity work.config_peripherals
    generic map(
    DEVADDR     => CFGBUS_ADDR_ANY,
    CLKREF_HZ   => 25_000_000,
    MDIO_BAUD   => 1_600_000,
    MDIO_COUNT  => 1,
    REG_RSTVAL  => (others => '1'))
    port map(
    mdio_clk(0) => phy_mdc,
    mdio_data(0)=> phy_mdio,
    reg_out     => ctrl_gpo,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

phy_rstn    <= not fast_reset_p;
fast_shdn   <= not ctrl_gpo(31);
err_ignore  <= (5 => ctrl_gpo(30), others => '0');
sgmii_pwren <= ctrl_gpo(PORTS_EOS+PORTS_SGMII-2 downto PORTS_EOS);
eos_pwren   <= ctrl_gpo(PORTS_EOS-1 downto 0);

-- Define each EoS port.
gen_eos : for n in 0 to PORTS_EOS-1 generate
    u_pmod1 : entity work.port_serial_auto
        generic map(CLKREF_HZ => 25000000)
        port map(
        ext_pads(0) => eos_pmod1(n+1),
        ext_pads(1) => eos_pmod2(n+1),
        ext_pads(2) => eos_pmod3(n+1),
        ext_pads(3) => eos_pmod4(n+1),
        rx_data     => slow_rx_data(n+2),
        tx_data     => slow_tx_data(n+2),
        tx_ctrl     => slow_tx_ctrl(n+2),
        refclk      => clk_25,
        reset_p     => '0');
end generate;

-- Define each SGMII port.
gen_sgmii : for n in 0 to PORTS_SGMII-1 generate
    u_sgmii : entity work.port_sgmii_gpio
        port map(
        sgmii_rxp   => sgmii_rxp(n+1),
        sgmii_rxn   => sgmii_rxn(n+1),
        sgmii_txp   => sgmii_txp(n+1),
        sgmii_txn   => sgmii_txn(n+1),
        prx_data    => fast_rx_data(n+1),
        ptx_data    => fast_tx_data(n+1),
        ptx_ctrl    => fast_tx_ctrl(n+1),
        port_shdn   => fast_reset_p,
        clk_125     => clk_125,
        clk_200     => clk_200,
        clk_625_00  => clk_625_00,
        clk_625_90  => clk_625_90);
end generate;

-- Define the high-speed switch core: 24-bit pipeline running at 200 MHz.
-- (Total throughput 4800 Mbps vs. theoretical max traffic 5080 Mbps.)
u_core_fast : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 200_000_000,
    ALLOW_RUNT      => false,
    PORT_COUNT      => PORTS_SGMII + 1,
    DATAPATH_BYTES  => 3,
    IBUF_KBYTES     => 4,
    OBUF_KBYTES     => 16)
    port map(
    ports_rx_data   => fast_rx_data,
    ports_tx_data   => fast_tx_data,
    ports_tx_ctrl   => fast_tx_ctrl,
    errvec_t        => fast_err_t,
    scrub_req_t     => scrub_req_t,
    core_clk        => clk_200,
    core_reset_p    => fast_reset_p);

-- Define the low-speed switch core: 8-bit pipeline running at 25 MHz.
-- (Total throughput 200 Mbps vs. max traffic 160 Mbps.)
u_core_slow : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 25_000_000,
    ALLOW_RUNT      => true,
    PORT_COUNT      => PORTS_EOS + 2,
    DATAPATH_BYTES  => 1,
    IBUF_KBYTES     => 2,
    OBUF_KBYTES     => 8)
    port map(
    ports_rx_data   => slow_rx_data,
    ports_tx_data   => slow_tx_data,
    ports_tx_ctrl   => slow_tx_ctrl,
    errvec_t        => slow_err_t,
    scrub_req_t     => scrub_req_t,
    core_clk        => clk_25,
    core_reset_p    => '0');

-- Auxiliary functions for error-reporting, etc.
-- TODO: Copy status messages to the Ethernet status port?
-- TODO: Disable or refactor some of the "aux" functions
swerr_vec_t <= fast_err_t & slow_err_t;
u_aux : entity work.switch_aux
    generic map(
    CORE_COUNT      => 2,
    SCRUB_CLK_HZ    => 25000000,
    SCRUB_ENABLE    => true,
    STARTUP_MSG     => "PROTO_V2_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => swerr_vec_t,
    swerr_ignore    => err_ignore,
    status_led_grn  => open,
    status_led_ylw  => open,
    status_led_red  => open,
    status_uart     => open,
    status_aux_dat  => open,
    status_aux_wr   => open,
    scrub_clk       => clk_25,
    scrub_req_t     => scrub_req_t,
    reset_p         => '0');

end proto_v2;
