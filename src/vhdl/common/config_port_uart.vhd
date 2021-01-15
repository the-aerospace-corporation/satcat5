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
-- Demo-board SPI+MDIO configuration using UART
--
-- This block implements a UART receiver that parses simple commands to
-- control various configuration interfaces on the Xilinx/Microsemi demo
-- board.  These include and SPI interface for the SJA1105 switch and a
-- number of MDIO interfaces for various Ethernet PHY transceivers, as
-- well as port-enables and other signals for the demo design.
--
-- Command framing uses SLIP. (See slip_decoder.vhd for details.)  The
-- contents of each frame relayed to config_read_command.
--
-- Currently this block is write-only, it doesn't support SPI/MDIO reads.
-- These features may be added in a future version.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.synchronization.all;

entity config_port_uart is
    generic (
    -- Baud rates and port-counts.
    CLKREF_HZ   : integer;          -- Main clock rate (Hz)
    UART_BAUD   : integer;          -- Command UART baud rate (bps)
    SPI_BAUD    : integer;          -- SPI baud rate (bps)
    SPI_MODE    : integer;          -- SPI mode index (0-3)
    MDIO_BAUD   : integer;          -- MDIO baud rate (bps)
    MDIO_COUNT  : integer;          -- Number of MDIO ports
    -- GPO initial state (optional)
    GPO_RSTVAL  : std_logic_vector(31 downto 0) := (others => '0'));
    port (
    -- Command UART
    uart_rx     : in  std_logic;    -- Command UART data

    -- SPI interface for SJA1105
    spi_csb     : out std_logic;    -- Chip select
    spi_sck     : out std_logic;    -- Clock
    spi_sdo     : out std_logic;    -- Data (FPGA to ASIC)

    -- MDIO interface for each port
    mdio_clk    : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_data   : out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_oe     : out std_logic_vector(MDIO_COUNT-1 downto 0);

    -- General-purpose outputs (internal or external)
    ctrl_out    : out std_logic_vector(31 downto 0);

    -- System interface
    ref_clk     : in  std_logic;    -- Reference clock
    ext_reset_p : in  std_logic := '0';  -- Async. reset (choose one)
    ext_reset_n : in  std_logic := '1'); -- Async. reset (choose one)
end config_port_uart;

architecture rtl of config_port_uart is

-- Global externally-triggered reset.
signal ext_rst_any  : std_logic;
signal reset_p      : std_logic;

-- Main UART and SLIP decoder.
signal uart_data    : byte_t;
signal uart_write   : std_logic;
signal slip_data    : byte_t;
signal slip_write   : std_logic;
signal slip_last    : std_logic;
signal slip_error   : std_logic;

-- Flow-control FIFO.
signal fifo_data    : byte_t;
signal fifo_last    : std_logic;
signal fifo_valid   : std_logic;
signal fifo_ready   : std_logic;
signal fifo_error   : std_logic;
signal cmd_enable   : std_logic := '0';
signal cmd_valid    : std_logic;
signal cmd_ready    : std_logic;

begin

-- External reset may be of either polarity.
-- (User typically chooses one, but could conceivably use both.)
ext_rst_any <= slip_error or fifo_error or ext_reset_p or not ext_reset_n;

u_reset : sync_reset
    generic map(KEEP_ATTR => "false")
    port map(
    in_reset_p  => ext_rst_any,
    out_reset_p => reset_p,
    out_clk     => ref_clk);

-- Main UART and SLIP decoder.
u_uart : entity work.io_uart_rx
    generic map (
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => UART_BAUD)
    port map (
    uart_rxd    => uart_rx,
    rx_data     => uart_data,
    rx_write    => uart_write,
    refclk      => ref_clk,
    reset_p     => reset_p);

-- SLIP decoder.
u_slip : entity work.slip_decoder
    port map(
    in_data     => uart_data,
    in_write    => uart_write,
    out_data    => slip_data,
    out_write   => slip_write,
    out_last    => slip_last,
    decode_err  => slip_error,
    reset_p     => reset_p,
    refclk      => ref_clk);

-- A small FIFO waits for the end of each packet, to enforce
-- the all-or-nothing rule required by config_read_command.
u_fifo : entity work.fifo_smol
    generic map(
    IO_WIDTH    => 8,  -- One byte at a time
    DEPTH_LOG2  => 5)  -- Up to 2^5 = 32 bytes
    port map(
    in_data     => slip_data,
    in_last     => slip_last,
    in_write    => slip_write,
    out_data    => fifo_data,
    out_last    => fifo_last,
    out_valid   => fifo_valid,
    out_read    => fifo_ready,
    fifo_error  => fifo_error,
    reset_p     => reset_p,
    clk         => ref_clk);

p_fifo : process(ref_clk)
    variable incr, decr : std_logic := '0';
    variable pkt_count : integer range 0 to 3 := 0;
begin
    if rising_edge(ref_clk) then
        incr := slip_write and slip_last;
        decr := fifo_valid and fifo_ready and fifo_last;
        if (reset_p = '1') then
            pkt_count := 0;
        elsif (incr = '1' and decr = '0') then
            pkt_count := pkt_count + 1;
        elsif (incr = '0' and decr = '1') then
            pkt_count := pkt_count - 1;
        end if;
        cmd_enable <= bool2bit(pkt_count > 0);
    end if;
end process;

-- Parse commands and drive each interface.
cmd_valid <= fifo_valid and cmd_enable;
fifo_ready <= cmd_ready and cmd_enable;

u_cmd : entity work.config_read_command
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE,
    MDIO_BAUD   => MDIO_BAUD,
    MDIO_COUNT  => MDIO_COUNT,
    GPO_RSTVAL  => GPO_RSTVAL)
    port map(
    cmd_data    => fifo_data,
    cmd_last    => fifo_last,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    spi_csb     => spi_csb,
    spi_sck     => spi_sck,
    spi_sdo     => spi_sdo,
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    mdio_oe     => mdio_oe,
    ctrl_out    => ctrl_out,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

end rtl;
