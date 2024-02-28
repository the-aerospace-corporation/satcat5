--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- A two-port switch, configured to translate a GMII internal interface
-- (typically found on Zynq 70xx-PS) to EoS/SPI.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.switch_types.all;

entity switch_gmii_to_spi is
    generic (
    SPI_MODE    : natural := 3);
    port (
    -- GMII Interface
    gmii_col    : out std_logic;
    gmii_crs    : out std_logic;

    gmii_txc    : out std_logic;
    gmii_txd    : out std_logic_vector(7 downto 0);
    gmii_txen   : out std_logic;
    gmii_txerr  : out std_logic;

    gmii_rxc    : out std_logic;
    gmii_rxd    : in  std_logic_vector(7 downto 0);
    gmii_rxdv   : in  std_logic;
    gmii_rxerr  : in  std_logic;

    -- EoS-PMOD interfaces (SPI/UART)
    eos         : inout std_logic_vector(3 downto 0);

    -- System clock and reset
    clk_125     : in  std_logic;
    reset_p     : in  std_logic);
end switch_gmii_to_spi;

architecture gmii of switch_gmii_to_spi is

signal rx_data      : array_rx_m2s(1 downto 0);
signal tx_data      : array_tx_s2m(1 downto 0);
signal tx_ctrl      : array_tx_m2s(1 downto 0);

signal adj_rx_data  : port_rx_m2s;
signal adj_tx_data  : port_tx_s2m;
signal adj_tx_ctrl  : port_tx_m2s;

signal switch_err_t : std_logic_vector(SWITCH_ERR_WIDTH-1 downto 0);

begin

gmii_col <= '0';
gmii_crs <= '0';
gmii_rxc <= clk_125;

-- GMII port, using the adjusted data
u_gmii : entity work.port_gmii_internal
    port map(
    -- GMII interface.
    gmii_txc        => gmii_txc,
    gmii_txd        => gmii_txd,
    gmii_txen       => gmii_txen,
    gmii_txerr      => gmii_txerr,
    gmii_rxc        => clk_125,
    gmii_rxd        => gmii_rxd,
    gmii_rxdv       => gmii_rxdv,
    gmii_rxerr      => gmii_rxerr,

    rx_data         => adj_rx_data,
    tx_data         => adj_tx_data,
    tx_ctrl         => adj_tx_ctrl,
    clk_125         => clk_125,
    reset_p         => reset_p);

-- Define the uplink port adapter.
-- (Adapter pads runt packets as needed before transmission.)
u_adapt : entity work.port_adapter
    port map(
    sw_rx_data      => rx_data(0),
    sw_tx_data      => tx_data(0),
    sw_tx_ctrl      => tx_ctrl(0),
    mac_rx_data     => adj_rx_data,
    mac_tx_data     => adj_tx_data,
    mac_tx_ctrl     => adj_tx_ctrl);

-- switch core: Frame check and output FIFOs
u_core : entity work.switch_dual
    generic map(
    ALLOW_RUNT      => true,
    OBUF_KBYTES     => 16)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    errvec_t        => switch_err_t);

u_pmod : entity work.port_serial_spi_controller
    generic map(
    CLKREF_HZ       => 125_000_000,
    SPI_BAUD        => 4_000_000,
    SPI_MODE        => SPI_MODE)
    port map (
    spi_csb         => eos(0),
    spi_sclk        => eos(3),
    spi_sdi         => eos(2),
    spi_sdo         => eos(1),
    rx_data         => rx_data(1),
    tx_data         => tx_data(1),
    tx_ctrl         => tx_ctrl(1),
    refclk          => clk_125,
    reset_p         => reset_p);

end gmii;
