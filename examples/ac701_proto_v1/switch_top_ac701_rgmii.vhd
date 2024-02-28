--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: Extended RGMII + EoS switch for Xilinx AC701
--
-- This module represents the extended configuration of the Prototype V1 Ethernet
-- Switch, with several gigabit-Ethernet, EoS-SPI, and EoS-UART ports.  This
-- version is designed to work with the Xilinx AC701 eval board and a custom
-- FMC interface board.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.switch_types.all;

entity switch_top_ac701_rgmii is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN";
    PORTS_MDIO  : integer := 3);
    port (
    -- Uplink RGMII interface.
    uplnk_txc   : out   std_logic;
    uplnk_txd   : out   std_logic_vector(3 downto 0);
    uplnk_txctl : out   std_logic;
    uplnk_rxc   : in    std_logic;
    uplnk_rxd   : in    std_logic_vector(3 downto 0);
    uplnk_rxctl : in    std_logic;

    -- Auxiliary RGMII interface.
    rgmii_txc   : out   std_logic;
    rgmii_txd   : out   std_logic_vector(3 downto 0);
    rgmii_txctl : out   std_logic;
    rgmii_rxc   : in    std_logic;
    rgmii_rxd   : in    std_logic_vector(3 downto 0);
    rgmii_rxctl : in    std_logic;

    -- EoS-PMOD interfaces (SPI/UART)
    eos_pmod1   : inout std_logic_vector(3 downto 0);
    eos_pmod2   : inout std_logic_vector(3 downto 0);
    eos_pmod3   : inout std_logic_vector(3 downto 0);
    eos_pmod4   : inout std_logic_vector(3 downto 0);

    -- Interface-board control.
    sja_clk25   : in    std_logic;  -- SJA1105 25 MHz clock
    sja_rstn    : out   std_logic;  -- SJA1105 switch: Reset
    sja_csb     : out   std_logic;  -- SJA1105 switch: SPI chip-sel
    sja_sck     : out   std_logic;  -- SJA1105 switch: SPI clock
    sja_sdo     : out   std_logic;  -- SJA1105 switch: SPI data
    mdio_clk    : out   std_logic_vector(PORTS_MDIO-1 downto 0);
    mdio_data   : inout std_logic_vector(PORTS_MDIO-1 downto 0);
    eth1_rstn   : out   std_logic;  -- PHY Control (see schematic)
    eth1_wake   : out   std_logic;  -- PHY Control (see schematic)
    eth1_en     : out   std_logic;  -- PHY Control (see schematic)
    eth1_mdir   : out   std_logic;  -- PHY Control (see schematic)
    eth2_rstn   : out   std_logic;  -- PHY Control (see schematic)
    eth3_rstn   : out   std_logic;  -- PHY Control (see schematic)

    -- Status indicators and other control.
    stat_led_g  : out   std_logic;  -- Green LED (breathing pattern)
    stat_led_y  : out   std_logic;  -- Yellow LED (clock-locked strobe)
    stat_led_r  : out   std_logic;  -- Red LED (error strobe)
    lcd_db      : out   std_logic_vector(3 downto 0);
    lcd_e       : out   std_logic;  -- LCD Chip enable
    lcd_rw      : out   std_logic;  -- LCD Read / write-bar
    lcd_rs      : out   std_logic;  -- LCD Data / command-bar
    host_tx     : out   std_logic;  -- UART to host: Error messages
    host_rx     : in    std_logic;  -- UART from host: Control
    ext_reset_p : in    std_logic); -- Global external reset
end switch_top_ac701_rgmii;

architecture rgmii of switch_top_ac701_rgmii is

-- Switch provides 25 MHz, MCMM core generates all other clocks.
signal clk_25       : std_logic;
signal clk_125_00   : std_logic;
signal clk_125_90   : std_logic;
signal clk_200      : std_logic;
signal clk_stopped  : std_logic;

-- Internal control from host.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal ctrl_gpo     : std_logic_vector(31 downto 0);

-- Logical port for each interface to the switch core.
-- Note: Actual array size is +1 in each case due to internal crosslink.
constant FAST_PORTS : integer := 2;
constant SLOW_PORTS : integer := 4;
signal fast_rx_data  : array_rx_m2s(FAST_PORTS downto 0);
signal fast_tx_data  : array_tx_s2m(FAST_PORTS downto 0);
signal fast_tx_ctrl  : array_tx_m2s(FAST_PORTS downto 0);
signal slow_rx_data  : array_rx_m2s(SLOW_PORTS downto 0);
signal slow_tx_data  : array_tx_s2m(SLOW_PORTS downto 0);
signal slow_tx_ctrl  : array_tx_m2s(SLOW_PORTS downto 0);

-- Error reporting for UART, LCD.
signal slow_err_t   : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal fast_err_t   : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal swerr_vec_t  : std_logic_vector(2*SWITCH_ERR_WIDTH-1 downto 0);
signal scrub_req_t  : std_logic;
signal msg_lcd_dat  : std_logic_vector(7 downto 0);
signal msg_lcd_wr   : std_logic;

-- Prevent renaming of clock nets.
attribute KEEP : string;
attribute KEEP of clk_25, clk_200           : signal is "true";
attribute KEEP of clk_125_00, clk_125_90    : signal is "true";

-- Lock location of each IDELAYCTRL unit.
attribute LOC : string;
attribute LOC of u_idc_bank15 : label is "IDELAYCTRL_X0Y3";
attribute LOC of u_idc_bank16 : label is "IDELAYCTRL_X0Y4";

begin

-- Main clock buffer and clock generation.
u_clkbuf : BUFG
    port map(
    I => sja_clk25,
    O => clk_25);

u_clkgen : entity work.clkgen_rgmii_xilinx
    port map(
    shdn_p          => ctrl_gpo(26),
    rstin_p         => ctrl_gpo(23),
    clkin_25        => clk_25,
    rstout_p        => clk_stopped,
    clkout_125_00   => clk_125_00,
    clkout_125_90   => clk_125_90,
    clkout_200      => clk_200);

-- Instantiate IDELAYCTRL for each bank where it's needed.
u_idc_bank15 : IDELAYCTRL
    port map(
    refclk  => clk_200,
    rst     => ctrl_gpo(31),
    rdy     => open);
u_idc_bank16 : IDELAYCTRL
    port map(
    refclk  => clk_200,
    rst     => ctrl_gpo(31),
    rdy     => open);

-- Main control from host UART.
u_cfgbus : entity work.cfgbus_host_uart
    generic map(
    CLKREF_HZ   => 25_000_000,
    UART_BAUD   => 921_600,
    UART_REPLY  => false,
    CHECK_FCS   => false)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    uart_rxd    => host_rx,
    uart_txd    => open,
    sys_clk     => clk_25,
    reset_p     => ext_reset_p);

u_periph : entity work.config_peripherals
    generic map(
    DEVADDR     => CFGBUS_ADDR_ANY,
    CLKREF_HZ   => 25_000_000,
    MDIO_BAUD   => 1_600_000,
    MDIO_COUNT  => PORTS_MDIO,
    REG_RSTVAL  => (others => '1'))
    port map(
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    reg_out     => ctrl_gpo,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

sja_csb     <= '1'; -- SJA1105's SPI interface is not used.
sja_sck     <= '0';
sja_sdo     <= '0';
sja_rstn    <= ctrl_gpo(16);
eth1_rstn   <= ctrl_gpo(17);
eth1_wake   <= ctrl_gpo(18);
eth1_en     <= ctrl_gpo(19);
eth1_mdir   <= ctrl_gpo(20);
eth2_rstn   <= ctrl_gpo(21);
eth3_rstn   <= ctrl_gpo(22);

-- LCD controller mirrors status messages.
u_lcd : entity work.io_text_lcd
    generic map(REFCLK_HZ => 25000000)
    port map(
    lcd_db      => lcd_db,
    lcd_e       => lcd_e,
    lcd_rw      => lcd_rw,
    lcd_rs      => lcd_rs,
    strm_clk    => clk_25,
    strm_data   => msg_lcd_dat,
    strm_wr     => msg_lcd_wr,
    reset_p     => ext_reset_p);

-- Define the two RGMII ports.
-- Note: Uplink port (SJA1105) needs Tx+Rx clock shift.
u_rgmii0 : entity work.port_rgmii
    generic map(
    RXCLK_DELAY => 2.0,         -- Shifted RxClk (see above)
    RXDAT_DELAY => 2.0)         -- Shifted RxDat (empirical)
    port map(
    rgmii_txc   => uplnk_txc,
    rgmii_txd   => uplnk_txd,
    rgmii_txctl => uplnk_txctl,
    rgmii_rxc   => uplnk_rxc,
    rgmii_rxd   => uplnk_rxd,
    rgmii_rxctl => uplnk_rxctl,
    rx_data     => fast_rx_data(1),
    tx_data     => fast_tx_data(1),
    tx_ctrl     => fast_tx_ctrl(1),
    clk_125     => clk_125_00,
    clk_txc     => clk_125_90,  -- Shifted TxClk
    shdn_p      => ctrl_gpo(26),
    reset_p     => ctrl_gpo(0));

-- Note: Direct port (AR8031) needs Tx clock shift ONLY.
--       (Rx clock shift is performed by the PHY)
u_rgmii1 : entity work.port_rgmii
    generic map(
    RXCLK_DELAY => 0.0,         -- No RxClk shift
    RXDAT_DELAY => 2.0)         -- Shifted RxDat (empirical)
    port map(
    rgmii_txc   => rgmii_txc,
    rgmii_txd   => rgmii_txd,
    rgmii_txctl => rgmii_txctl,
    rgmii_rxc   => rgmii_rxc,
    rgmii_rxd   => rgmii_rxd,
    rgmii_rxctl => rgmii_rxctl,
    rx_data     => fast_rx_data(2),
    tx_data     => fast_tx_data(2),
    tx_ctrl     => fast_tx_ctrl(2),
    clk_125     => clk_125_00,
    clk_txc     => clk_125_90,  -- Shifted TxClk
    shdn_p      => ctrl_gpo(26),
    reset_p     => ctrl_gpo(1));

-- Define each EoS-PMOD port (SPI/UART autodetect).
gen_pmod : for n in 0 to 3 generate
    u_pmod : entity work.port_serial_auto
        generic map(CLKREF_HZ => 25000000)
        port map(
        ext_pads(0) => eos_pmod1(n),
        ext_pads(1) => eos_pmod2(n),
        ext_pads(2) => eos_pmod3(n),
        ext_pads(3) => eos_pmod4(n),
        rx_data     => slow_rx_data(n+1),
        tx_data     => slow_tx_data(n+1),
        tx_ctrl     => slow_tx_ctrl(n+1),
        refclk      => clk_25,
        reset_p     => ext_reset_p);
end generate;

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
    reset_p     => ctrl_gpo(31));

-- Define the high-speed switch core: 24-bit pipeline running at 125 MHz.
-- (Total throughput 3000 Mbps vs. max traffic 2080 Mbps.)
u_core_fast : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 125_000_000,
    ALLOW_RUNT      => false,
    PORT_COUNT      => FAST_PORTS + 1,
    DATAPATH_BYTES  => 3,
    IBUF_KBYTES     => 4,
    OBUF_KBYTES     => 16)
    port map(
    ports_rx_data   => fast_rx_data,
    ports_tx_data   => fast_tx_data,
    ports_tx_ctrl   => fast_tx_ctrl,
    errvec_t        => fast_err_t,
    scrub_req_t     => scrub_req_t,
    core_clk        => clk_125_00,
    core_reset_p    => ctrl_gpo(31));

-- Define the low-speed switch core: 8-bit pipeline running at 25 MHz.
-- (Total throughput 200 Mbps vs. max traffic 160 Mbps.)
u_core_slow : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 25_000_000,
    ALLOW_RUNT      => true,
    PORT_COUNT      => SLOW_PORTS + 1,
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
    core_reset_p    => ext_reset_p);

-- Auxiliary functions for error-reporting, etc.
swerr_vec_t <= fast_err_t & slow_err_t;
u_aux : entity work.switch_aux
    generic map(
    CORE_COUNT      => 2,
    SCRUB_CLK_HZ    => 25000000,
    SCRUB_ENABLE    => true,
    STARTUP_MSG     => "AC701_RGMII_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => swerr_vec_t,
    clock_stopped   => clk_stopped,
    status_led_grn  => stat_led_g,
    status_led_ylw  => stat_led_y,
    status_led_red  => stat_led_r,
    status_uart     => host_tx,
    status_aux_dat  => msg_lcd_dat,
    status_aux_wr   => msg_lcd_wr,
    scrub_clk       => clk_25,
    scrub_req_t     => scrub_req_t,
    reset_p         => ext_reset_p);

end rgmii;
