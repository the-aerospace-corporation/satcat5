--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level design: RMII to SPI/UART adapter board
--
-- This design is for the Lattice ice40-hx8k adapter board containing a single
-- RMII ethernet port and a single UART port.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity switch_top_rmii_serial_adapter is
    generic (
    BUILD_DATE  : string := "BD_UNKNOWN";
    PORTS_MDIO  : integer := 1;
    PORTS_UART  : integer := 1);
    port (
    -- Uplink RMII interface.
    rmii_txd    : out   std_logic_vector(1 downto 0);
    rmii_txen   : out   std_logic;
    rmii_rxd    : in    std_logic_vector(1 downto 0);
    rmii_rxen   : in    std_logic;
    rmii_refclk : in    std_logic; -- 50 MHz reference from PHY board

    -- EoS-UART interfaces.
    uart_txd    : out   std_logic_vector(PORTS_UART-1 downto 0);
    uart_rxd    : in    std_logic_vector(PORTS_UART-1 downto 0);
    uart_rts_n  : out   std_logic_vector(PORTS_UART-1 downto 0);
    uart_cts_n  : in    std_logic_vector(PORTS_UART-1 downto 0);

    -- Onboard 12MHz oscillator
    clk_12      : in    std_logic;  -- Reference clock (replaces SJA1105 25MHz clock)

    -- Status indicators and other control.
    stat_led_g    : out std_logic;  -- Green LED (breathing pattern)
    stat_led_err  : out std_logic;  -- Red LED (error strobe)
    stat_led_lock : out std_logic;  -- PLL lock indicator
    host_tx       : out std_logic;  -- UART to host: Error messages
    ext_reset_n   : in  std_logic); -- Global external reset (This is active low)
end switch_top_rmii_serial_adapter;

architecture rmii of switch_top_rmii_serial_adapter is

-- Synthesized 25 MHz and 50 MHz clocks
signal clk_25_00    : std_logic;

-- Logical port for each interface to the switch core.
constant PORTS_RMII  : integer := 1;
constant PORTS_TOTAL : integer := PORTS_RMII + PORTS_UART;
signal rx_data      : array_rx_m2s(PORTS_TOTAL-1 downto 0);
signal tx_data      : array_tx_s2m(PORTS_TOTAL-1 downto 0);
signal tx_ctrl      : array_tx_m2s(PORTS_TOTAL-1 downto 0);
signal adj_rx_data  : port_rx_m2s;
signal adj_tx_data  : port_tx_s2m;
signal adj_tx_ctrl  : port_tx_m2s;

-- Error reporting
signal switch_err_t     : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

-- Global asynchronous reset.
signal ext_reset_p  : std_logic;
signal stat_led_g_raw : std_logic;

attribute KEEP : string;
attribute KEEP of clk_25_00 : signal is "true";

component rmii_serial_adapter_pll_dev port(
    REFERENCECLK    : in  std_logic;
    PLLOUTCOREA     : out std_logic;
    PLLOUTCOREB     : out std_logic;
    PLLOUTGLOBALA   : out std_logic;
    PLLOUTGLOBALB   : out std_logic;
    RESET           : in  std_logic;
    LOCK            : out std_logic);
end component;

begin

ext_reset_p <= not ext_reset_n; -- External reset is active low

u_clkgen : rmii_serial_adapter_pll_dev
    port map(
    REFERENCECLK    => clk_12,
    PLLOUTCOREA     => open,
    PLLOUTCOREB     => open,
    PLLOUTGLOBALA   => open,
    PLLOUTGLOBALB   => clk_25_00,
    RESET           => '1',
    LOCK            => stat_led_lock);

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
    rmii_txer   => open, -- Optional, we don't have it connected
    rmii_rxd    => rmii_rxd,
    rmii_rxen   => rmii_rxen,
    rmii_rxer   => '0',  -- We don't have this signal from our PHY
    rmii_clkin  => rmii_refclk,
    rmii_clkout => open, -- Leave this open because we have MODE_CLKOUT = false
    rx_data     => adj_rx_data,
    tx_data     => adj_tx_data,
    tx_ctrl     => adj_tx_ctrl,
    lock_refclk => clk_25_00,
    reset_p     => ext_reset_p);

gen_uart : for n in 0 to PORTS_UART-1 generate
    u_uart : entity work.port_serial_uart_4wire
        generic map(
        CLKREF_HZ   => 25_000_000,
        BAUD_HZ     => 921600)
        port map(
        uart_txd    => uart_txd(n),
        uart_rxd    => uart_rxd(n),
        uart_rts_n  => uart_rts_n(n),
        uart_cts_n  => uart_cts_n(n),
        rx_data     => rx_data(n+PORTS_RMII),
        tx_data     => tx_data(n+PORTS_RMII),
        tx_ctrl     => tx_ctrl(n+PORTS_RMII),
        refclk      => clk_25_00,
        reset_p     => ext_reset_p);
end generate;

-- Define the switch core: 8-bit pipeline running at 25 MHz.
-- (Total throughput 200 Mbps vs. max traffic 20 Mbps.)
u_core : entity work.switch_dual
    generic map(
    ALLOW_RUNT      => true,
    OBUF_KBYTES     => 4)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => switch_err_t);

-- Auxiliary functions for error-reporting, etc.
u_aux : entity work.switch_aux
    generic map(
    SCRUB_CLK_HZ    => 25_000_000,
    STARTUP_MSG     => "iCE40_Ref_" & BUILD_DATE,
    STATUS_LED_LIT  => '1')
    port map(
    swerr_vec_t     => switch_err_t,
    status_led_grn  => stat_led_g_raw,
    status_led_red  => stat_led_err,
    status_uart     => host_tx,
    status_aux_dat  => open,
    status_aux_wr   => open,
    scrub_clk       => clk_25_00,
    scrub_req_t     => open,
    reset_p         => ext_reset_p);

-- Turn off LED during reset
stat_led_g <= stat_led_g_raw and ext_reset_n;

end rmii;
