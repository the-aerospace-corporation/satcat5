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
-- Ethernet-over-Serial SPI transceiver port (clock output)
--
-- This module implements a serial-over-Ethernet port with a four-wire SPI
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an SPI clock source (i.e., this block drives chip-select and clock).
--
-- Use of this block is not recommended for normal devices, but it may
-- be required for switch-to-switch links.
--
-- The only provided flow-control is through an optional "pause" flag.
-- Unless this flag is asserted, the SPI clock is always running.
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;
use     work.synchronization.all;

entity port_serial_spi_clkout is
    generic (
    CLKREF_HZ   : integer;          -- Reference clock rate (Hz)
    SPI_BAUD    : integer;          -- SPI baud rate (bps)
    SPI_MODE    : integer := 3);    -- SPI clock phase & polarity
    port (
    -- External SPI interface.
    spi_csb     : out std_logic;    -- Chip-select bar (output)
    spi_sclk    : out std_logic;    -- Serial clock out (output)
    spi_sdi     : in  std_logic;    -- Serial data in
    spi_sdo     : out std_logic;    -- Serial data out

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_m2s;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_s2m;  -- Flow control for tx_data

    -- Pause flag (optional)
    ext_pause   : in  std_logic := '0';

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_spi_clkout;

architecture port_serial_spi_clkout of port_serial_spi_clkout is

-- Flow control and idle token insertion.
signal flow_data    : byte_t := SLIP_FEND;
signal flow_last    : std_logic := '0';
signal flow_valid   : std_logic := '0';
signal flow_ready   : std_logic;

-- Byte transfers from raw SPI interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic := '0';
signal dec_data     : byte_t;
signal dec_write    : std_logic;

-- Synchronous reset signal.
signal reset_sync   : std_logic;

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= reset_sync;
tx_ctrl.txerr   <= '0';     -- No Tx error states

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => refclk);

-- Raw SPI interface
u_spi : entity work.io_spi_clkout
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE)
    port map(
    cmd_data    => flow_data,
    cmd_last    => flow_last,
    cmd_valid   => flow_valid,
    cmd_ready   => flow_ready,
    rcvd_data   => dec_data,
    rcvd_write  => dec_write,
    spi_csb     => spi_csb,
    spi_sck     => spi_sclk,
    spi_sdo     => spi_sdo,
    spi_sdi     => spi_sdi,
    ref_clk     => refclk,
    reset_p     => reset_sync);

-- Flow control and idle token insertion:
-- Arbitrarily break each SPI transaction into fixed-length chunks, so
-- that the chip-select line is exercised frequently. (This minimizes
-- lost data on startup or after an error.)  Before starting each chunk,
-- check the pause flag to allow some degree of flow control.
-- If there's no data available, insert a SLIP idle token instead.
p_flow : process(refclk)
    -- Counter wraparound every 2^6 = 64 bytes.
    subtype flow_count_t is unsigned(5 downto 0);
    constant BYTE_LAST  : flow_count_t := (others => '1');
    variable byte_ctr   : flow_count_t := (others => '0');
begin
    if rising_edge(refclk) then
        enc_ready <= '0';   -- Set default
        if (reset_sync = '1') then
            -- Global reset
            flow_data   <= SLIP_FEND;
            flow_last   <= '0';
            flow_valid  <= '0';
            enc_ready   <= '0';
            byte_ctr    := (others => '0');
        elsif (flow_valid = '0' or flow_ready = '1') then
            -- Ready to present the next byte.
            if (enc_valid = '1') then
                flow_data <= enc_data;      -- Normal data
            else
                flow_data <= SLIP_FEND;     -- Idle filler
            end if;
            -- End of each chunk briefly deasserts chip-select.
            flow_last <= bool2bit(byte_ctr = BYTE_LAST);
            -- Optional pause at the start of each chunk.
            -- Note: Single-cycle delay in enc_ready is safe because
            --       SPI will always take many clock cycles per byte.
            if (byte_ctr = 0 and ext_pause = '1') then
                flow_valid <= '0';          -- Paused
            else
                flow_valid <= '1';          -- Continue
                enc_ready  <= enc_valid;    -- Byte consumed?
                byte_ctr   := byte_ctr + 1; -- Increment with wraparound
            end if;
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

end port_serial_spi_clkout;
