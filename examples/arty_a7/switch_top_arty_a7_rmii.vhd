--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Top-level design: Baseline RMII + EoS switch for Digilent Arty A7
--
-- This module represents a reference configuration of a SatCat5 Ethernet
-- Switch on an off-the-shelf board.
-- It contains several EoS-SPI and EoS-UART ports and a single 100 Mbps uplink
-- port to an external high-bandwidth switch.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;
use     work.switch_types.all;

entity switch_top_arty_a7_rmii is
    generic (
    BUILD_DATE   : string := "BD_UNKNOWN";
    PORTS_MDIO   : integer := 1;
    PORTS_SERIAL : integer := 4);
    port (
    -- Uplink RMII interface.
    rmii_txd    : out   std_logic_vector(1 downto 0);
    rmii_txen   : out   std_logic;
    rmii_rxd    : in    std_logic_vector(1 downto 0);
    rmii_rxen   : in    std_logic;
    rmii_rxer   : in    std_logic;
    rmii_mode   : out   std_logic; -- 1 for RMII, 0 for MII
    rmii_refclk : out   std_logic; -- 50 MHz reference from clkgen
    rmii_resetn : out   std_logic; -- PHY reset#

    -- MDIO signals
    mdio_clk    : out   std_logic_vector(PORTS_MDIO-1 downto 0);
    mdio_data   : inout std_logic_vector(PORTS_MDIO-1 downto 0);

    -- EoS-PMOD interfaces (SPI/UART)
    eos_pmod1  : inout   std_logic_vector(PORTS_SERIAL-1 downto 0);
    eos_pmod2  : inout   std_logic_vector(PORTS_SERIAL-1 downto 0);
    eos_pmod3  : inout   std_logic_vector(PORTS_SERIAL-1 downto 0);
    eos_pmod4  : inout   std_logic_vector(PORTS_SERIAL-1 downto 0);

    -- Onboard 100MHz oscillator
    ref_clk100  : in    std_logic;  -- Reference clock (replaces SJA1105 25MHz clock)

    -- Status indicators and other control.
    stat_led_g  : out   std_logic;  -- Green LED (breathing pattern)
    stat_led_r  : out   std_logic;  -- Red LED (error strobe)
    lcd_db      : out   std_logic_vector(3 downto 0);
    lcd_e       : out   std_logic;  -- LCD Chip enable
    lcd_rw      : out   std_logic;  -- LCD Read / write-bar
    lcd_rs      : out   std_logic;  -- LCD Data / command-bar
    host_tx     : out   std_logic;  -- UART to host: Error messages
    host_rx     : in    std_logic;  -- UART from host: Control
    ext_reset_n : in    std_logic); -- Global external reset (This is active low)
end switch_top_arty_a7_rmii;

architecture rmii of switch_top_arty_a7_rmii is

-- 50 Mhz clock generated via clkgen
signal clk_50_00    : std_logic;

-- External oscillator 100Mhz
signal clk_100      : std_logic;

-- Logical port for each interface to the switch core.
constant PORTS_RMII  : integer := 1;
constant PORTS_TOTAL : integer := PORTS_RMII + PORTS_SERIAL;
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

-- Global reset and internal control
signal ext_reset_p  : std_logic;
signal clkgen_rst_p : std_logic;
signal rmii_reset_p : std_logic;
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;

attribute KEEP : string;
attribute KEEP of clk_100, clk_50_00 : signal is "true";

begin

u_clkbuf : BUFG
    port map (
    I   => ref_clk100,
    O   => clk_100);

rmii_mode   <= '1';
ext_reset_p <= not ext_reset_n;
rmii_resetn <= not rmii_reset_p;

u_clkgen : entity work.clkgen_rmii_xilinx
    port map(
    shdn_p          => '0',
    rstin_p         => '0',
    clkin_100       => clk_100,
    rstout_p        => clkgen_rst_p,
    clkout_50_00    => clk_50_00,
    clkout_50_90    => open,
    clkout_200      => open);

-- Hold RMII in reset for at least 1 msec.
u_phyrst : sync_reset
    generic map(HOLD_MIN => 100_000)
    port map(
    in_reset_p  => clkgen_rst_p,
    out_reset_p => rmii_reset_p,
    out_clk     => clk_100);

-- Main control from host UART.
u_cfgbus : entity work.cfgbus_host_uart
    generic map(
    CLKREF_HZ   => 100_000_000,
    UART_BAUD   => 921_600,
    UART_REPLY  => false,
    CHECK_FCS   => false)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    uart_rxd    => host_rx,
    uart_txd    => open,
    sys_clk     => clk_100,
    reset_p     => ext_reset_p);

u_periph : entity work.config_peripherals
    generic map(
    DEVADDR     => CFGBUS_ADDR_ANY,
    CLKREF_HZ   => 100_000_000,
    MDIO_BAUD   => 1_600_000,
    MDIO_COUNT  => PORTS_MDIO,
    REG_RSTVAL  => (others => '1'))
    port map(
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    reg_out     => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- LCD controller mirrors status messages.
u_lcd : entity work.io_text_lcd
    generic map(REFCLK_HZ => 100_000_000)
    port map(
    lcd_db      => lcd_db,
    lcd_e       => lcd_e,
    lcd_rw      => lcd_rw,
    lcd_rs      => lcd_rs,
    strm_clk    => clk_100,
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
    generic map(MODE_CLKOUT => true)
    port map(
    rmii_txd    => rmii_txd,
    rmii_txen   => rmii_txen,
    rmii_txer   => open, -- Unused for DP83848 PHY
    rmii_rxd    => rmii_rxd,
    rmii_rxen   => rmii_rxen,
    rmii_rxer   => rmii_rxer,
    rmii_clkin  => clk_50_00,
    rmii_clkout => rmii_refclk,
    rx_data     => adj_rx_data,
    tx_data     => adj_tx_data,
    tx_ctrl     => adj_tx_ctrl,
    lock_refclk => clk_100,
    reset_p     => rmii_reset_p);

gen_uart : for n in 0 to PORTS_SERIAL-1 generate
    u_pmod : entity work.port_serial_auto
        generic map(
        CLKREF_HZ   => 100_000_000,
        UART_BAUD   => 921600)
        port map(
        ext_pads(0) => eos_pmod1(n),
        ext_pads(1) => eos_pmod2(n),
        ext_pads(2) => eos_pmod3(n),
        ext_pads(3) => eos_pmod4(n),
        rx_data     => rx_data(n+PORTS_RMII),
        tx_data     => tx_data(n+PORTS_RMII),
        tx_ctrl     => tx_ctrl(n+PORTS_RMII),
        refclk      => clk_100,
        reset_p     => ext_reset_p);
end generate;

-- Define the switch core: 8-bit pipeline running at 100 MHz.
-- (Total throughput 800 Mbps vs. max traffic 180 Mbps.)
u_core : entity work.switch_core
    generic map(
    CORE_CLK_HZ     => 100_000_000,
    ALLOW_RUNT      => true,
    ALLOW_PRECOMMIT => true,
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
    core_clk        => clk_100,
    core_reset_p    => ext_reset_p);

-- Auxiliary functions for error-reporting, etc.
u_aux : entity work.switch_aux
    generic map(
    SCRUB_CLK_HZ    => 100_000_000,
    SCRUB_ENABLE    => true,
    STARTUP_MSG     => "ARTY_A7_Ref_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => switch_err_t,
    status_led_grn  => stat_led_g,
    status_led_red  => stat_led_r,
    status_uart     => host_tx,
    status_aux_dat  => msg_lcd_dat,
    status_aux_wr   => msg_lcd_wr,
    scrub_clk       => clk_100,
    scrub_req_t     => scrub_req_t,
    reset_p         => ext_reset_p);

end rmii;
