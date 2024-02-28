--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: Baseline RMII + EoS switch for Xilinx AC701
--
-- This module represents the simplest configuration of the Prototype V1 Ethernet
-- Switch, with several EoS-SPI and EoS-UART ports and a single 100 Mbps uplink
-- port to the external high-bandwidth switch.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.switch_types.all;

entity switch_top_ac701_base is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN";
    PORTS_MDIO  : integer := 3);
    port (
    -- Uplink RMII interface.
    rmii_txd    : out   std_logic_vector(1 downto 0);
    rmii_txen   : out   std_logic;
    rmii_txer   : out   std_logic;
    rmii_rxd    : in    std_logic_vector(1 downto 0);
    rmii_rxen   : in    std_logic;
    rmii_rxer   : in    std_logic;
    rmii_clkin  : in    std_logic;  -- 50 MHz reference from switch

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
    stat_led_r  : out   std_logic;  -- Red LED (error strobe)
    lcd_db      : out   std_logic_vector(3 downto 0);
    lcd_e       : out   std_logic;  -- LCD Chip enable
    lcd_rw      : out   std_logic;  -- LCD Read / write-bar
    lcd_rs      : out   std_logic;  -- LCD Data / command-bar
    host_tx     : out   std_logic;  -- UART to host: Error messages
    host_rx     : in    std_logic;  -- UART from host: Control
    ext_reset_p : in    std_logic); -- Global external reset
end switch_top_ac701_base;

architecture baseline of switch_top_ac701_base is

-- Both clock references come from the parent switch.
signal clk_25       : std_logic;
signal clk_50       : std_logic;

-- Internal control from host.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal ctrl_gpo     : std_logic_vector(31 downto 0);

-- Logical port for each interface to the switch core.
constant PORTS_RMII  : integer := 1;
constant PORTS_PMOD  : integer := 4;
constant PORTS_TOTAL : integer := PORTS_RMII + PORTS_PMOD;
signal rx_data      : array_rx_m2s(PORTS_TOTAL-1 downto 0);
signal tx_data      : array_tx_s2m(PORTS_TOTAL-1 downto 0);
signal tx_ctrl      : array_tx_m2s(PORTS_TOTAL-1 downto 0);
signal adj_rx_data  : port_rx_m2s;
signal adj_tx_data  : port_tx_s2m;
signal adj_tx_ctrl  : port_tx_m2s;

-- Error reporting for UART, LCD.
signal switch_err_t : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal scrub_req_t  : std_logic;
signal msg_lcd_dat  : std_logic_vector(7 downto 0);
signal msg_lcd_wr   : std_logic;

-- Prevent renaming of clock nets.
attribute KEEP : string;
attribute KEEP OF clk_25, clk_50 : signal is "true";

begin

-- Main clock reference is the SJA1105's always-on 25 MHz output.
u_clkbuf : BUFG
    port map(
    I   => sja_clk25,
    O   => clk_25);

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

-- Define the 100 Mbps uplink port.
-- (Adapter pads runt packets as needed before transmission.)
u_adapt : entity work.port_adapter
    port map(
    sw_rx_data  => rx_data(0),
    sw_tx_data  => tx_data(0),
    sw_tx_ctrl  => tx_ctrl(0),
    mac_rx_data => adj_rx_data,
    mac_tx_data => adj_tx_data,
    mac_tx_ctrl => adj_tx_ctrl);

u_uplink : entity work.port_rmii
    generic map(MODE_CLKOUT => false)
    port map(
    rmii_txd    => rmii_txd,
    rmii_txen   => rmii_txen,
    rmii_txer   => rmii_txer,
    rmii_rxd    => rmii_rxd,
    rmii_rxen   => rmii_rxen,
    rmii_rxer   => rmii_rxer,
    rmii_clkin  => rmii_clkin,
    rmii_clkout => clk_50,
    rx_data     => adj_rx_data,
    tx_data     => adj_tx_data,
    tx_ctrl     => adj_tx_ctrl,
    lock_refclk => clk_25,
    reset_p     => ctrl_gpo(0));

-- Define each EoS-PMOD port (SPI/UART autodetect).
gen_pmod : for n in 0 to 3 generate
    u_pmod : entity work.port_serial_auto
        generic map(CLKREF_HZ => 25000000)
        port map(
        ext_pads(0) => eos_pmod1(n),
        ext_pads(1) => eos_pmod2(n),
        ext_pads(2) => eos_pmod3(n),
        ext_pads(3) => eos_pmod4(n),
        rx_data     => rx_data(n+1),
        tx_data     => tx_data(n+1),
        tx_ctrl     => tx_ctrl(n+1),
        refclk      => clk_25,
        reset_p     => ext_reset_p);
end generate;

-- Define the switch core: 8-bit pipeline running at 25 MHz.
-- (Total throughput 200 Mbps vs. max traffic 180 Mbps.)
u_core : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 25_000_000,
    ALLOW_RUNT      => true,
    PORT_COUNT      => PORTS_TOTAL,
    DATAPATH_BYTES  => 1,
    IBUF_KBYTES     => 2,
    OBUF_KBYTES     => 8)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => switch_err_t,
    scrub_req_t     => scrub_req_t,
    core_clk        => clk_25,
    core_reset_p    => ext_reset_p);

-- Auxiliary functions for error-reporting, etc.
u_aux : entity work.switch_aux
    generic map(
    SCRUB_CLK_HZ    => 25000000,
    SCRUB_ENABLE    => true,
    STARTUP_MSG     => "AC701_Base_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => switch_err_t,
    status_led_grn  => stat_led_g,
    status_led_red  => stat_led_r,
    status_uart     => host_tx,
    status_aux_dat  => msg_lcd_dat,
    status_aux_wr   => msg_lcd_wr,
    scrub_clk       => clk_25,
    scrub_req_t     => scrub_req_t,
    reset_p         => ext_reset_p);

end baseline;
