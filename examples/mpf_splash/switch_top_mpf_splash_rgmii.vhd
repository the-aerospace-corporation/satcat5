--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: RGMII + EoS switch for Microsemi MPF300-SPLASH-KIT-ES
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.switch_types.all;

entity switch_top_mpf_splash_rgmii is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN";
    PORTS_EOS   : integer := 3);
    port (
    -- Uplink RGMII interface.
    uplnk_txc     : out   std_logic;
    uplnk_txd     : out   std_logic_vector(3 downto 0);
    uplnk_txctl   : out   std_logic;
    uplnk_rxc     : in    std_logic;
    uplnk_rxd     : in    std_logic_vector(3 downto 0);
    uplnk_rxctl   : in    std_logic;

    -- EoS-PMOD interfaces (SPI/UART)
    uart_txd      : out std_logic_vector(PORTS_EOS-1 downto 0);
    uart_rxd      : in  std_logic_vector(PORTS_EOS-1 downto 0);

    -- Interface-board control.
    mdio_clk      : out   std_logic;
    mdio_data     : out   std_logic;

    -- phy control signals?
    eth1_rstn     : out   std_logic;  -- PHY resetn
    eth1_squelch  : out   std_logic;  -- PHY recovered clock squelch. don't care

    -- Status indicators and other control.
    stat_led_g    : out   std_logic;  -- Green LED (breathing pattern)
    stat_led_y    : out   std_logic;  -- Yellow LED (clock-locked strobe)
    stat_led_r    : out   std_logic;  -- Red LED (error strobe)
    host_tx       : out   std_logic;  -- UART to host: Error messages
    --host_rx       : in    std_logic;  -- Control UART from host unused
    REF_CLK_50MHZ : in    std_logic;  -- External clock input
    RST_N         : in    std_logic); -- Global external reset
end switch_top_mpf_splash_rgmii;

architecture rgmii of switch_top_mpf_splash_rgmii is

-- 50MHz input
signal clk_50       : std_logic;
signal clk_125_00   : std_logic;
signal clk_125_90   : std_logic;
signal clk_200      : std_logic;
signal clk_stopped  : std_logic;

signal ext_reset_p  : std_logic;
signal eth1_rstp    : std_logic;

-- Logical port for each interface to the switch core.
-- With just 1 fast port we don't use a separate fast switch core.
constant FAST_PORTS : integer := 1;
constant SLOW_PORTS : integer := PORTS_EOS;
signal rx_data  : array_rx_m2s(FAST_PORTS+SLOW_PORTS-1 downto 0);
signal tx_data  : array_tx_s2m(FAST_PORTS+SLOW_PORTS-1 downto 0);
signal tx_ctrl  : array_tx_m2s(FAST_PORTS+SLOW_PORTS-1 downto 0);
-- Padded data for uplink port
signal uplink_rx_data  : port_rx_m2s;
signal uplink_tx_data  : port_tx_s2m;
signal uplink_tx_ctrl  : port_tx_m2s;
-- Error reporting for UART, LCD.
signal swerr_vec_t  : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);
signal scrub_req_t  : std_logic;

-- Prevent renaming of clock nets.
attribute KEEP : string;
attribute KEEP of clk_50, clk_200           : signal is "true";
attribute KEEP of clk_125_00, clk_125_90    : signal is "true";


-- MDIO Configuration
-- Helper function to format command words.
subtype cmd_word is std_logic_vector(31 downto 0);
function make_cmd(dly, phy, reg : integer; dat : std_logic_vector) return cmd_word is
    variable cmd : cmd_word :=
        i2s(dly, 6) & i2s(phy, 5) & i2s(reg, 5) & dat;
begin
    return cmd;
end function;

-- Based on VSC8541-01 rev 4.1 datasheet section 3.18.1
-- RX_CLK pulled low, so straps are in managed mode. Settings:
--  PHY address 5'b11111
--  RGMII mode
--  NOT forced 100BASE-T
constant CMD_COUNT  : integer := 31;
constant ROM_VECTOR : std_logic_vector(32*CMD_COUNT-1 downto 0) :=
    -- drive NRESET high
    -- Wait 15ms
    -- reg 31: 0 access main registers
    make_cmd(50, 31, 31, x"0000") &
    -- reg 23: [12:11] = 10 RGMII
    make_cmd(50, 31, 23, x"1000") & -- should default to correct value
    -- reg 0: [15] = 1 software reset
    make_cmd(50, 31, 0, x"9040") &
    -- Wait for reset to complete
    -- reg 0: [8] = 1 full duplex
    --        [9] = 1 restart autonegotiation
    make_cmd(50, 31, 0, x"1340") &
    -- Blink LED1 OFF/ON 3 times. 200ms each, end assert
    -- reg 29 [7:4] = 0xE de-assert 0xF assert. assert is ON
    -- de-assert (OFF)
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    -- assert (ON)
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    -- de-assert (OFF)
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    -- assert (ON)
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
        -- de-assert (OFF)
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    make_cmd(50, 31, 29, x"00E1") &
    -- assert (ON)
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    make_cmd(50, 31, 29, x"00F1") &
    -- Set LED1 to be ON or blink if 10/100 link present
    -- LED0 ON or blink if 1000 link present
    make_cmd(50, 31, 29, x"0061") &
    -- reg 31: 2 to access E2 registers
    make_cmd(50, 31, 31, x"0002") &
    -- reg 20E2: [11:0] for 2ns RX and TX delay
    make_cmd(50, 31, 20, x"0044");

component CLKINT
port (
    A   : in std_logic;
    Y   : out std_logic);
end component;

begin

ext_reset_p <= not RST_N;

u_clkbuf : CLKINT
    port map(
    A   => REF_CLK_50MHZ,
    Y   => clk_50);

u_clkgen : entity work.clkgen_rgmii_microsemi
    port map(
    shdn_p          => '0',
    rstin_p         => '0',
    clkin_50        => clk_50,
    rstout_p        => clk_stopped,
    clkout_125_00   => clk_125_00,
    clkout_125_90   => clk_125_90,
    clkout_200      => clk_200);

-- PHY ctrl signals
u_phy_rstn_sync: sync_reset
port map(
    in_reset_p  => ext_reset_p,
    out_reset_p => eth1_rstp,
    out_clk     => clk_50);
eth1_rstn    <= not eth1_rstp;
eth1_squelch <= '0';


u_mdio: entity work.config_mdio_rom
    generic map(
    CLKREF_HZ   => 50_000_000,
    MDIO_BAUD   => 1_600_000,
    ROM_VECTOR  => ROM_VECTOR)
    port map(
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    mdio_oe     => open,
    ref_clk     => clk_50,
    reset_p     => ext_reset_p);


-- Define the RGMII (uplink) port.
-- TODO research PHY for shifts, etc.
u_rgmii0 : entity work.port_rgmii
    generic map(
    RXCLK_DELAY => -1.0,        -- Shifted by PHY
    RXDAT_DELAY => -1.0)        -- Shifted by PHY
    port map(
    rgmii_txc   => uplnk_txc,
    rgmii_txd   => uplnk_txd,
    rgmii_txctl => uplnk_txctl,
    rgmii_rxc   => uplnk_rxc,
    rgmii_rxd   => uplnk_rxd,
    rgmii_rxctl => uplnk_rxctl,
    rx_data     => uplink_rx_data,
    tx_data     => uplink_tx_data,
    tx_ctrl     => uplink_tx_ctrl,
    clk_125     => clk_125_00,
    clk_txc     => clk_125_00,  -- Shifted by PHY
    shdn_p      => '0',
    reset_p     => ext_reset_p);

-- Use a port adapter for uplink so core can support
-- runt packets on slow ports while remaining 802.3
-- compliant on uplink
u_adapt: entity work.port_adapter
    port map (
    sw_rx_data  => rx_data(0),
    sw_tx_data  => tx_data(0),
    sw_tx_ctrl  => tx_ctrl(0),
    mac_rx_data => uplink_rx_data,
    mac_tx_data => uplink_tx_data,
    mac_tx_ctrl => uplink_tx_ctrl);


-- Define each EoS-PMOD port (SPI/UART autodetect).
gen_pmod : for n in 0 to PORTS_EOS - 1 generate
    u_pmod : entity work.port_serial_uart_4wire
        generic map(
        CLKREF_HZ   => 50_000_000,
        BAUD_HZ     => 921_600)
        port map(
        uart_txd    => uart_txd(n),
        uart_rxd    => uart_rxd(n),
        uart_rts_n  => open,
        uart_cts_n  => '0',
        rx_data     => rx_data(n+1),
        tx_data     => tx_data(n+1),
        tx_ctrl     => tx_ctrl(n+1),
        refclk      => clk_50,
        reset_p     => ext_reset_p);
end generate;

-- Define the switch core: 24-bit pipeline running at 125 MHz.
-- (Total throughput 3000 Mbps vs. max traffic 2*1000+2*3*10 Mbps.)
u_core : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 125_000_000,
    ALLOW_RUNT      => true,
    PORT_COUNT      => FAST_PORTS + SLOW_PORTS,
    DATAPATH_BYTES  => 3,
    IBUF_KBYTES     => 4,
    OBUF_KBYTES     => 16,
    MAC_TABLE_SIZE  => 31)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => swerr_vec_t,
    scrub_req_t     => scrub_req_t,
    core_clk        => clk_125_00,
    core_reset_p    => ext_reset_p);

-- Auxiliary functions for error-reporting, etc.
u_aux : entity work.switch_aux
    generic map(
    CORE_COUNT      => 1,
    SCRUB_CLK_HZ    => 50_000_000,
    STARTUP_MSG     => "MPF_SPLASH_RGMII_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => swerr_vec_t,
    clock_stopped   => clk_stopped,
    status_led_grn  => stat_led_g,
    status_led_ylw  => stat_led_y,
    status_led_red  => stat_led_r,
    status_uart     => host_tx,
    status_aux_dat  => open,
    status_aux_wr   => open,
    scrub_clk       => clk_50,
    scrub_req_t     => scrub_req_t,
    reset_p         => ext_reset_p);

end rgmii;