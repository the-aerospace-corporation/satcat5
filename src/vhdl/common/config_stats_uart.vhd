--------------------------------------------------------------------------
-- Copyright 2020 The Aerospace Corporation
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
-- Port traffic statistics (with UART interface)
--
-- This module instantiates a port_statistics block for each attached
-- Ethernet port, and makes the results available over a UART interface.
--
-- To use, write a single byte to the UART.  The byte should contain the
-- index of the port to be queried, or index 0xFF to query all ports
-- consecutively.  Any other index is ignored.
--
-- For each port queried, the UART reports total observed traffic since
-- the last query to that port, in the following order:
--   * Broadcast bytes received (from device to switch)
--   * Broadcast frames received
--   * Total bytes received (from device to switch)
--   * Total frames received
--   * Total bytes sent (from switch to device)
--   * Total frames sent
-- Each field is a big-endian 32-bit unsigned integer (i.e., uint32_t).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;

entity config_stats_uart is
    generic (
    PORT_COUNT  : integer;
    COUNT_WIDTH : natural := 32;            -- Internal counter width (16-32 bits)
    BAUD_HZ     : natural := 921_600;       -- UART baud rate (Hz)
    REFCLK_HZ   : natural := 100_000_000);  -- Reference clock freq. (Hz)
    port (
    -- Generic internal port interface (monitor only)
    rx_data     : in  array_rx_m2s(PORT_COUNT-1 downto 0);
    tx_data     : in  array_tx_m2s(PORT_COUNT-1 downto 0);
    tx_ctrl     : in  array_tx_s2m(PORT_COUNT-1 downto 0);

    -- UART interface
    uart_txd    : out std_logic;
    uart_rxd    : in  std_logic;
    refclk      : in  std_logic;
    reset_p     : in  std_logic);
end config_stats_uart;

architecture config_stats_uart of config_stats_uart is

-- Special index 255 indicates a query to all ports.
constant CMD_ALL    : byte_t := (others => '1');

-- Each report is a total of 6 words = 24 bytes.
constant BYTE_COUNT : natural := 4 * 6;
constant WORD_TOTAL : natural := 6 * PORT_COUNT;

-- Return Nth byte, counting from MSB.
subtype stat_report is unsigned(8*BYTE_COUNT-1 downto 0);
function get_stat_byte(x:stat_report; n:natural) return byte_t is
    variable tmp : byte_t := (others => '0');
begin
    if (n < BYTE_COUNT) then
        tmp := std_logic_vector(x(x'left-8*n downto x'left-7-8*n));
    end if;
    return tmp;
end function;

-- Statistics module for each port.
subtype stat_word is unsigned(COUNT_WIDTH-1 downto 0);
type stats_array_t is array(WORD_TOTAL-1 downto 0) of stat_word;
signal stats_req_t  : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal stats_array  : stats_array_t := (others => (others => '0'));
signal stats_zpad   : stat_report;

-- Receive UART.
signal uart_rxdata  : byte_t;
signal uart_rxwrite : std_logic;

-- Command FIFO and state-machine.
signal cmd_data     : byte_t;
signal cmd_valid    : std_logic;
signal cmd_read     : std_logic;
signal cmd_last     : std_logic;
signal cmd_pindex    : integer range 0 to PORT_COUNT-1 := 0;
signal cmd_bindex    : integer range 0 to BYTE_COUNT-1 := 0;

-- Transmit UART.
signal uart_txdata : byte_t;
signal uart_txlast  : std_logic;
signal uart_txvalid : std_logic := '0';
signal uart_txready : std_logic;

begin

-- Statistics module for each port.
gen_stats : for n in 0 to PORT_COUNT-1 generate
    -- Instantiate module for this port.
    u_stats : entity work.port_statistics
        generic map(COUNT_WIDTH => COUNT_WIDTH)
        port map(
        stats_req_t => stats_req_t(n),
        bcst_bytes  => stats_array(6*n+0),
        bcst_frames => stats_array(6*n+1),
        rcvd_bytes  => stats_array(6*n+2),
        rcvd_frames => stats_array(6*n+3),
        sent_bytes  => stats_array(6*n+4),
        sent_frames => stats_array(6*n+5),
        rx_data     => rx_data(n),
        tx_data     => tx_data(n),
        tx_ctrl     => tx_ctrl(n));

    -- Toggle request line based on received commands.
    p_stats : process(refclk)
    begin
        if rising_edge(refclk) then
            if (uart_rxwrite = '1' and uart_rxdata = CMD_ALL) then
                stats_req_t(n) <= not stats_req_t(n);   -- All ports
            elsif (uart_rxwrite = '1' and unsigned(uart_rxdata) = n) then
                stats_req_t(n) <= not stats_req_t(n);   -- This port
            end if;
        end if;
    end process;
end generate;

-- Receive UART.
u_uart_rx : entity work.io_uart_rx
    generic map(
    CLKREF_HZ   => REFCLK_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    uart_rxd    => uart_rxd,
    rx_data     => uart_rxdata,
    rx_write    => uart_rxwrite,
    refclk      => refclk,
    reset_p     => reset_p);

-- Command FIFO.
u_cmd_fifo : entity work.fifo_smol
    generic map(
    IO_WIDTH    => 8,   -- FIFO width = 8 bits
    DEPTH_LOG2  => 4)   -- FIFO depth = 2^N
    port map(
    in_data     => uart_rxdata,
    in_write    => uart_rxwrite,
    out_data    => cmd_data,
    out_valid   => cmd_valid,
    out_read    => cmd_read,
    clk         => refclk,
    reset_p     => reset_p);

-- Detect the end-of-command condition.
cmd_read <= uart_txvalid and uart_txready and uart_txlast;

-- Transmit state-machine.
p_cmd_tx : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            -- Global reset.
            cmd_pindex      <= 0;
            cmd_bindex      <= 0;
            uart_txvalid    <= '0';
        elsif (cmd_valid = '1' and uart_txvalid = '0') then
            -- Short delay for cross-clock update request (see above).
            if (cmd_bindex < BYTE_COUNT-1) then
                cmd_bindex <= cmd_bindex + 1;
            else
                cmd_bindex <= 0;
            end if;
            -- Start of new command, if valid.
            if (cmd_bindex < BYTE_COUNT-1) then
                uart_txvalid <= '0';    -- Wait, for now.
            elsif (cmd_data = CMD_ALL) then
                uart_txvalid <= '1';    -- Read all ports
                cmd_pindex   <= 0;
            elsif (unsigned(cmd_data) < PORT_COUNT) then
                uart_txvalid <= '1';    -- Read specific port
                cmd_pindex   <= to_integer(unsigned(cmd_data));
            end if;
        elsif (cmd_valid = '1' and uart_txvalid = '1' and uart_txready = '1') then
            -- Proceed to next byte...
            if (cmd_bindex < BYTE_COUNT-1) then
                cmd_bindex   <= cmd_bindex + 1;
                uart_txvalid <= '1';    -- Next byte
            elsif (uart_txlast = '0') then
                cmd_pindex   <= cmd_pindex + 1;
                cmd_bindex   <= 0;
                uart_txvalid <= '1';    -- Next port
            else
                cmd_bindex   <= 0;
                uart_txvalid <= '0';    -- End of command
            end if;
        end if;
    end if;
end process;

-- Zero-pad counters to fixed 32-bit width, then concatentate.
stats_zpad  <= resize(stats_array(6*cmd_pindex+0), 32)
             & resize(stats_array(6*cmd_pindex+1), 32)
             & resize(stats_array(6*cmd_pindex+2), 32)
             & resize(stats_array(6*cmd_pindex+3), 32)
             & resize(stats_array(6*cmd_pindex+4), 32)
             & resize(stats_array(6*cmd_pindex+5), 32);

-- Combinational logic to select each output byte:
uart_txdata <= get_stat_byte(stats_zpad, cmd_bindex);
uart_txlast <= bool2bit(cmd_bindex = BYTE_COUNT-1) and bool2bit(cmd_pindex = PORT_COUNT-1 or cmd_data /= CMD_ALL);

-- Transmit UART.
u_uart_tx : entity work.io_uart_tx
    generic map(
    CLKREF_HZ   => REFCLK_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    uart_txd    => uart_txd,
    tx_data     => uart_txdata,
    tx_valid    => uart_txvalid,
    tx_ready    => uart_txready,
    refclk      => refclk,
    reset_p     => reset_p);

end config_stats_uart;
