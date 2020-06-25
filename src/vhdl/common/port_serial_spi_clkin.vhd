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
-- Ethernet-over-Serial SPI transceiver port (clock input)
--
-- This module implements a serial-over-Ethernet port with a four-wire SPI
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an SPI follower (i.e., remote device drives chip-select and clock).
--
-- To minimize required FPGA resources, the input clock is treated as a regular
-- signal, oversampled by the global reference clock.  (Typically 50-125 MHz vs.
-- ~10 Mbps max for a typical SPI interface.)  As a result, all inputs are
-- asynchronous and must use metastability buffers for safe operation.
--
-- In both modes, the remote device sets the rate of transmission by providing
-- the serial clock.  If either end of the link does not currently have data to
-- transmit, it should repeatedly send the SLIP inter-frame token (0xC0).
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
--
-- NOTE: Reference clock must be a few times faster than SCLK.
--       See io_spi_clkin.vhd for details.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;
use     work.synchronization.all;

entity port_serial_spi_clkin is
    generic (
    CLKREF_HZ   : integer;          -- Reference clock rate (Hz)
    SPI_MODE    : integer := 3);    -- SPI clock phase & polarity
    port (
    -- External SPI interface.
    spi_csb     : in  std_logic;    -- Chip-select bar (input)
    spi_sclk    : in  std_logic;    -- Serial clock in (input)
    spi_sdi     : in  std_logic;    -- Serial data in (user to switch)
    spi_sdo     : out std_logic;    -- Serial data out (switch to user)
    spi_sdt     : out std_logic;    -- Tristate signal for SDO (optional).

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_m2s;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_s2m;  -- Flow control for tx_data

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock (refclk >> spi_sck*)
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_spi_clkin;

architecture port_serial_spi_clkin of port_serial_spi_clkin is

-- Byte transfers from raw SPI interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;
signal dec_data     : byte_t;
signal dec_write    : std_logic;

-- Internal reset signals.
signal reset_sync   : std_logic;
signal wdog_rst_p   : std_logic := '1';

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= wdog_rst_p;
tx_ctrl.txerr   <= '0';     -- No Tx error states

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => refclk);

-- Raw SPI interface
u_spi : entity work.io_spi_clkin
    generic map(
    IDLE_BYTE   => SLIP_FEND,
    SPI_MODE    => SPI_MODE)
    port map(
    spi_csb     => spi_csb,
    spi_sclk    => spi_sclk,
    spi_sdi     => spi_sdi,
    spi_sdo     => spi_sdo,
    spi_sdt     => spi_sdt,
    tx_data     => enc_data,
    tx_valid    => enc_valid,
    tx_ready    => enc_ready,
    rx_data     => dec_data,
    rx_write    => dec_write,
    refclk      => refclk);

-- Detect inactive ports and clear transmit buffer.
-- (Otherwise, broadcast packets will overflow the buffer.)
p_wdog : process(refclk, reset_sync)
    constant TIMEOUT : integer := 2*CLKREF_HZ;
    variable wdog_ctr : integer range 0 to TIMEOUT := TIMEOUT;
begin
    if (reset_sync = '1') then
        wdog_rst_p  <= '1';
        wdog_ctr    := TIMEOUT;
    elsif rising_edge(refclk) then
        wdog_rst_p  <= bool2bit(wdog_ctr = 0);
        if (dec_write = '1') then
            wdog_ctr := TIMEOUT;        -- Activity detect
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;   -- Countdown to zero
        end if;
    end if;
end process;

-- SLIP encoder (for Tx) and decoder (for Rx)
u_enc : entity work.slip_encoder
    port map (
    in_data     => tx_data.data,
    in_last     => tx_data.last,
    in_valid    => tx_data.valid,
    in_ready    => tx_ctrl.ready,
    out_data    => enc_data,
    out_valid   => enc_valid,
    out_ready   => enc_ready,
    refclk      => refclk,
    reset_p     => reset_sync);

u_dec : entity work.slip_decoder
    port map (
    in_data     => dec_data,
    in_write    => dec_write,
    out_data    => rx_data.data,
    out_write   => rx_data.write,
    out_last    => rx_data.last,
    decode_err  => rx_data.rxerr,
    refclk      => refclk,
    reset_p     => reset_sync);

end port_serial_spi_clkin;
