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
-- Generic UART interfaces
--
-- This file implements a generic, byte-at-a-time blocks for transmit
-- and receive UARTs.  Each is a separate entity for maximum flexibility.
--
-- See also: https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.synchronization.all;

entity io_uart_rx is
    generic (
    CLKREF_HZ   : integer;          -- Reference clock rate (Hz)
    BAUD_HZ     : integer;          -- Input and output rate (bps)
    DEBUG_WARN  : boolean := true); -- Enable stop-bit warnings?
    port (
    -- External UART interface.
    uart_rxd    : in  std_logic;    -- Input signal

    -- Generic internal byte interface.
    rx_data     : out byte_t;
    rx_write    : out std_logic;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end io_uart_rx;

architecture io_uart_rx of io_uart_rx is

-- Calculate clocks per bit-period (round nearest), then
-- back-calculate the baud rate that was actually achieved.
constant CLOCKS_PER_BIT : integer := (CLKREF_HZ + BAUD_HZ/2) / BAUD_HZ;
constant ACTUAL_BAUD_HZ : integer := (CLKREF_HZ + CLOCKS_PER_BIT/2) / CLOCKS_PER_BIT;

-- Synchronized input signal
signal rx, rxd      : std_logic := '1';

-- Receiver state machine
signal r_data       : byte_t := (others => '0');
signal r_write      : std_logic := '0';
signal r_bit_count  : integer range 0 to 9 := 0;
signal r_clk_count  : integer range 0 to CLOCKS_PER_BIT := 0;

begin

-- Synchronization
B1: sync_buffer
    port map (
    in_flag     => uart_rxd,
    out_flag    => rx,
    out_clk     => refclk);

-- Drive block-level outputs.
rx_data  <= r_data;
rx_write <= r_write;

-- Receiver state machine
p_rx : process(refclk)
begin
    if rising_edge(refclk) then
        -- Sanity check on actual vs. target baud-rate.
        assert ((100 * BAUD_HZ < 105 * ACTUAL_BAUD_HZ)
            and (100 * BAUD_HZ >  95 * ACTUAL_BAUD_HZ))
            report "Invalid UART rate (max error 5%)" severity error;

        -- Read in each bit (LSB first)
        if (r_clk_count = 1 and r_bit_count > 0) then
            r_data <= rx & r_data(7 downto 1);
        end if;

        -- Received last bit?
        if (r_clk_count = 1 and r_bit_count = 0) then
            if (DEBUG_WARN) then
                assert (rx = '1') report "Missing stop bit" severity warning;
            end if;
            r_write <= rx;  -- Confirm stop bit = '1'
        else
            r_write <= '0';
        end if;

        -- Update counters
        if (reset_p = '1') then
            r_bit_count <= 0;
            r_clk_count <= 0;
        elsif (r_clk_count > 0) then
            r_clk_count <= r_clk_count - 1;
        elsif (r_bit_count > 0) then
            r_bit_count <= r_bit_count - 1;
            r_clk_count <= CLOCKS_PER_BIT;
        elsif (rxd = '1' and rx = '0') then
            r_bit_count <= 9; -- Start + 8 data + stop bit
            r_clk_count <= CLOCKS_PER_BIT / 2;
        end if;
        -- Delayed rx signal
        rxd <= rx;
    end if;
end process;

end io_uart_rx;



---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t

entity io_uart_tx is
    generic (
    CLKREF_HZ   : integer;          -- Reference clock rate (Hz)
    BAUD_HZ     : integer);         -- Input and output rate (bps)
    port (
    -- External UART interface.
    uart_txd    : out std_logic;    -- Output signal

    -- Generic internal byte interface.
    tx_data     : in  byte_t;
    tx_valid    : in  std_logic;
    tx_ready    : out std_logic;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end io_uart_tx;

architecture io_uart_tx of io_uart_tx is

-- Calculate clocks per bit-period (round nearest), then
-- back-calculate the baud rate that was actually achieved.
constant CLOCKS_PER_BIT : integer := (CLKREF_HZ + BAUD_HZ/2) / BAUD_HZ;
constant ACTUAL_BAUD_HZ : integer := (CLKREF_HZ + CLOCKS_PER_BIT/2) / CLOCKS_PER_BIT;

-- Transmitter state machine
signal t_ready      : std_logic := '0';
signal t_bit_count  : integer range 0 to 9 := 0;
signal t_clk_count  : integer range 0 to CLOCKS_PER_BIT := 0;
signal t_sreg       : byte_t := (others => '1');
signal uart_tx_i    : std_logic := '1';

begin

-- Drive block outputs
uart_txd    <= uart_tx_i;
tx_ready    <= t_ready;

-- Transmitter state machine
p_tx : process (refclk)
begin
    if rising_edge(refclk) then
        -- Sanity check on actual vs. target baud-rate.
        assert ((100 * BAUD_HZ < 105 * ACTUAL_BAUD_HZ)
            and (100 * BAUD_HZ >  95 * ACTUAL_BAUD_HZ))
            report "Invalid UART rate (max error 5%)" severity error;

        -- Upstream flow control: Will we be idle next cycle?
        t_ready <= bool2bit(t_bit_count = 0 and t_clk_count = 0 and tx_valid = '0')
                or bool2bit(t_bit_count = 0 and t_clk_count = 1);

        -- Counter and shift-register updates:
        if (reset_p = '1') then
            -- Port reset
            t_clk_count <= 0;
            t_bit_count <= 0;
            uart_tx_i   <= '1';
        elsif (t_clk_count > 0) then
            -- Countdown to start of next bit interval.
            t_clk_count <= t_clk_count - 1;
        elsif (t_bit_count > 0) then
            -- Tx in progress, emit next bit (including stop bit).
            uart_tx_i   <= t_sreg(0);       -- LSB first.
            t_sreg      <= '1' & t_sreg(7 downto 1);
            t_clk_count <= CLOCKS_PER_BIT;
            t_bit_count <= t_bit_count - 1;
        elsif (tx_valid = '1') then
            -- Start a new byte.
            t_clk_count <= CLOCKS_PER_BIT;
            t_bit_count <= 9;       -- Start + 8 data + stop bit
            uart_tx_i   <= '0';     -- Send start bit
            t_sreg      <= tx_data; -- Latch output byte
        else
            -- Idle.
            uart_tx_i   <= '1';
        end if;
    end if;
end process;

end io_uart_tx;
