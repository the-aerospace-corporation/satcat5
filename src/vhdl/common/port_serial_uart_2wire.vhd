--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- Ethernet-over-Serial UART transceiver port, 2-wire variant
--
-- This module implements a serial-over-Ethernet port using a two-wire UART
-- interface, including SLIP encoding and decoding.  The two wires are used
-- solely for data; flow-control is derived using a query/response model.
--
-- In this model, a "query" occurs any time the remote device sends the SLIP
-- end-of-frame character (0xC0).  This includes the end of a regular frame,
-- or simply a single byte sent between frames as a placeholder.  Once received,
-- the UART will reply with the next packet if one is available, or with a single
-- end-of-frame character if idle.
--
-- See also: https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;
use     work.synchronization.all;

entity port_serial_uart_2wire is
    generic (
    CLKREF_HZ   : integer;          -- Reference clock rate (Hz)
    BAUD_HZ     : integer);         -- Input and output rate (bps)
    port (
    -- External UART interface.
    uart_txd    : out std_logic;    -- Data from switch to user
    uart_rxd    : in  std_logic;    -- Data from user to switch

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_m2s;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_s2m;  -- Flow control for tx_data

    -- Flow-control override, used for unit test ONLY.
    req_now     : in  std_logic := '0';

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_uart_2wire;

architecture port_serial_uart_2wire of port_serial_uart_2wire is

-- Raw transmit interface (flow control and idle insertion)
signal raw_data     : byte_t;
signal raw_valid    : std_logic;
signal raw_ready    : std_logic;
signal pkt_nodata   : std_logic := '0';
signal pkt_running  : std_logic := '0';

-- Internal reset signals.
signal reset_sync   : std_logic;
signal wdog_rst_p   : std_logic := '1';

-- SLIP encoder and decoder
signal dec_data     : byte_t;
signal dec_write    : std_logic;
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.rate    <= get_rate_word(clocks_per_baud(BAUD_HZ, 1_000_000));
rx_data.status  <= (0 => reset_sync, others => '0');
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= wdog_rst_p;
tx_ctrl.txerr   <= '0';     -- No error states

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => refclk);

-- Transmit and receive UARTs:
u_rx : entity work.io_uart_rx
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    uart_rxd    => uart_rxd,
    rx_data     => dec_data,
    rx_write    => dec_write,
    refclk      => refclk,
    reset_p     => reset_sync);

u_tx : entity work.io_uart_tx
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    uart_txd    => uart_txd,
    tx_data     => raw_data,
    tx_valid    => raw_valid,
    tx_ready    => raw_ready,
    refclk      => refclk,
    reset_p     => reset_sync);

-- Raw transmit interface (flow control and idle insertion)
raw_data  <= SLIP_FEND when (pkt_nodata = '1') else enc_data;
raw_valid <= pkt_nodata or (pkt_running and enc_valid);
enc_ready <= pkt_running and raw_ready;

p_flow : process(refclk)
begin
    if rising_edge(refclk) then
        pkt_nodata <= '0';  -- Set default
        if ((req_now = '1') or (dec_write = '1' and dec_data = SLIP_FEND)) then
            -- Received end-of-frame, send reply (next frame or idle).
            pkt_nodata  <= not enc_valid;
            pkt_running <= enc_valid;
        elsif (enc_valid = '1' and enc_ready = '1' and enc_data = SLIP_FEND) then
            -- Just sent end of packet, stop until next query.
            pkt_running <= '0';
            pkt_nodata  <= '0';
        end if;
    end if;
end process;

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

end port_serial_uart_2wire;
