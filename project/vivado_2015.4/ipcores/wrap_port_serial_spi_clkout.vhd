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
-- Port-type wrapper for "port_serial_spi_clkout"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_port_serial_spi_clkout is
    generic (
    CLKREF_HZ   : positive;         -- Reference clock rate (Hz)
    SPI_BAUD    : positive;         -- SPI baud rate (bps)
    SPI_MODE    : natural := 3);    -- SPI clock phase & polarity
    port (
    -- External 4-wire interface.
    ext_pads    : inout std_logic_vector(3 downto 0);

    -- Network port
    sw_rx_clk   : out std_logic;
    sw_rx_data  : out std_logic_vector(7 downto 0);
    sw_rx_last  : out std_logic;
    sw_rx_write : out std_logic;
    sw_rx_error : out std_logic;
    sw_rx_reset : out std_logic;
    sw_tx_clk   : out std_logic;
    sw_tx_data  : in  std_logic_vector(7 downto 0);
    sw_tx_last  : in  std_logic;
    sw_tx_valid : in  std_logic;
    sw_tx_ready : out std_logic;
    sw_tx_error : out std_logic;
    sw_tx_reset : out std_logic;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end wrap_port_serial_spi_clkout;

architecture wrap_port_serial_spi_clkout of wrap_port_serial_spi_clkout is

signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_m2s;
signal tx_ctrl  : port_tx_s2m;
signal csb, sck, sdi, sdo : std_logic;

begin

-- Convert port signals.
sw_rx_clk       <= rx_data.clk;
sw_rx_data      <= rx_data.data;
sw_rx_last      <= rx_data.last;
sw_rx_write     <= rx_data.write;
sw_rx_error     <= rx_data.rxerr;
sw_rx_reset     <= rx_data.reset_p;
sw_tx_clk       <= tx_ctrl.clk;
sw_tx_ready     <= tx_ctrl.ready;
sw_tx_error     <= tx_ctrl.txerr;
sw_tx_reset     <= tx_ctrl.reset_p;
tx_data.data    <= sw_tx_data;
tx_data.last    <= sw_tx_last;
tx_data.valid   <= sw_tx_valid;

-- Convert external interface.
u_csb : entity work.bidir_io
    port map(
    io_pin  => ext_pads(0),
    d_in    => open,
    d_out   => csb,
    t_en    => '0');    -- Output only
u_sdo : entity work.bidir_io
    port map(
    io_pin  => ext_pads(1),
    d_in    => open,
    d_out   => sdo,
    t_en    => '0');    -- Output only
u_sdi : entity work.bidir_io
    port map(
    io_pin  => ext_pads(2),
    d_in    => sdi,
    d_out   => '1',
    t_en    => '1');    -- Input only
u_sck : entity work.bidir_io
    port map(
    io_pin  => ext_pads(3),
    d_in    => open,
    d_out   => sck,
    t_en    => '0');    -- Output only

-- Unit being wrapped.
u_wrap : entity work.port_serial_spi_clkout
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE)
    port map(
    spi_csb     => csb,
    spi_sclk    => sck,
    spi_sdi     => sdi,
    spi_sdo     => sdo,
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    refclk      => refclk,
    reset_p     => reset_p);

end wrap_port_serial_spi_clkout;
