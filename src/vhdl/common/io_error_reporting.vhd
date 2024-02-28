--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Error-reporting using UART
--
-- This module accepts a series of discrete error strobes, and generates
-- status reports using a plaintext UART interface.  The error message
-- associated with each strobe is set by a set of generics.  To avoid
-- saturating the UART interface, unique error types will always print
-- a message but repeated strobes are ignored if the output is busy.
-- For every N seconds with no error strobes, it will transmit "OK".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity io_error_reporting is
    generic (
    CLK_HZ      : positive;         -- Main clock rate (Hz)
    OUT_BAUD    : positive;         -- UART baud rate (bps)
    OK_CLOCKS   : positive;         -- Report "OK" every N clock cycles
    START_MSG   : string := "";     -- Startup message
    ERR_COUNT   : positive;         -- Number of error messages (max 16)
    ERR_MSG00   : string := "";     -- String for each error type...
    ERR_MSG01   : string := "";
    ERR_MSG02   : string := "";
    ERR_MSG03   : string := "";
    ERR_MSG04   : string := "";
    ERR_MSG05   : string := "";
    ERR_MSG06   : string := "";
    ERR_MSG07   : string := "";
    ERR_MSG08   : string := "";
    ERR_MSG09   : string := "";
    ERR_MSG10   : string := "";
    ERR_MSG11   : string := "";
    ERR_MSG12   : string := "";
    ERR_MSG13   : string := "";
    ERR_MSG14   : string := "";
    ERR_MSG15   : string := "");
    port (
    -- UART output
    err_uart    : out std_logic;        -- UART output

    -- Auxiliary output
    aux_data    : out std_logic_vector(7 downto 0);
    aux_wren    : out std_logic;

    -- Error strobes and system control
    err_strobe  : in  std_logic_vector(ERR_COUNT-1 downto 0);
    err_clk     : in  std_logic;        -- Main clock
    reset_p     : in  std_logic);       -- Active high async reset
end io_error_reporting;

architecture io_error_reporting of io_error_reporting is

-- UART clock-divider is fixed at build-time.
constant UART_CLKDIV : unsigned(15 downto 0) :=
    to_unsigned(clocks_per_baud_uart(CLK_HZ, OUT_BAUD), 16);

-- Generics and arrays don't mix; use this function to index.
constant TOTAL_MSGS : integer := ERR_COUNT + 2;
subtype msgidx_t is integer range 0 to TOTAL_MSGS-1;

impure function get_err_msg(n : integer) return string is
begin
    case n is
        when  0 => return "OK";
        when  1 => return START_MSG;
        when  2 => return ERR_MSG00;    -- Note +2 offset
        when  3 => return ERR_MSG01;
        when  4 => return ERR_MSG02;
        when  5 => return ERR_MSG03;
        when  6 => return ERR_MSG04;
        when  7 => return ERR_MSG05;
        when  8 => return ERR_MSG06;
        when  9 => return ERR_MSG07;
        when 10 => return ERR_MSG08;
        when 11 => return ERR_MSG09;
        when 12 => return ERR_MSG10;
        when 13 => return ERR_MSG11;
        when 14 => return ERR_MSG12;
        when 15 => return ERR_MSG13;
        when 16 => return ERR_MSG14;
        when 17 => return ERR_MSG15;
        when others => return "UNK";
    end case;
end function;

impure function get_err_len(n : msgidx_t) return integer is
    constant msg : string := get_err_msg(n);
begin
    return msg'length;
end function;

-- Calculate total length of all active messages (including startup).
impure function get_total_bytes return integer is
    constant EXTRA_CHARS : integer := 2;    -- Msg + CR + LF
    variable total : integer := 0;
begin
    for n in 0 to TOTAL_MSGS-1 loop
        total := total + get_err_len(n) + EXTRA_CHARS;
    end loop;
    return total;
end function;

constant TOTAL_BYTES : integer := get_total_bytes;

-- Define terminal newline characters (CR+LF)
constant NEWLINE_CR : byte_t := i2s(13, 8);
constant NEWLINE_LF : byte_t := i2s(10, 8);

-- Create ROM array with all concatenated messages.
type array_t is array(0 to TOTAL_BYTES-1) of byte_t;
subtype romaddr_t is integer range 0 to TOTAL_BYTES-1;

impure function get_msg_array return array_t is
    variable result : array_t := (others => (others => '0'));
    variable ridx   : integer := 0;

    procedure append(constant msg : string) is
    begin
        -- Append the message to the output array.
        for c in 0 to msg'length-1 loop
            result(ridx) := i2s(character'pos(msg(msg'left+c)), 8);
            ridx := ridx + 1;
        end loop;
        -- Then append the CR+LF characters.
        result(ridx+0) := NEWLINE_CR;
        result(ridx+1) := NEWLINE_LF;
        ridx := ridx + 2;
    end procedure;
begin
    -- For each fixed message...
    for n in 0 to TOTAL_MSGS-1 loop
        append(get_err_msg(n));
    end loop;
    return result;
end function;

constant MESSAGE_ROM : array_t := get_msg_array;

-- Error-flag state machine:
signal err_flags    : std_logic_vector(TOTAL_MSGS-1 downto 0) := (others => '0');
signal rom_incr     : std_logic := '1';
signal rom_mstart   : std_logic := '1';
signal rom_byte     : byte_t := MESSAGE_ROM(0);
signal msg_start    : std_logic;
signal msg_index    : msgidx_t := 0;
signal msg_busy     : std_logic := '0';
signal uart_start   : std_logic := '0';
signal uart_ready   : std_logic := '0';

begin

-- Error-flag state machine:
p_flags : process(err_clk)
    variable idle_count : integer range 0 to OK_CLOCKS := OK_CLOCKS;
begin
    if rising_edge(err_clk) then
        -- Special case for the Idle/OK message.
        err_flags(0) <= bool2bit(idle_count = 0);

        -- Special case for the startup message.
        if (reset_p = '1') then
            err_flags(1) <= '1';
        elsif (msg_start = '1') then
            err_flags(1) <= '0';
        end if;

        -- All others: Set bit whenever a new error strobe occurs.
        -- Clear bit when the UART begins sending that message.
        for n in 0 to ERR_COUNT-1 loop
            if (reset_p = '1') then
                err_flags(n+2) <= '0';  -- Note +2 offset
            elsif (err_strobe(n) = '1') then
                err_flags(n+2) <= '1';
            elsif (msg_start = '1' and msg_index = n+2) then
                err_flags(n+2) <= '0';
            end if;
        end loop;

        -- Update the idle-time counter.
        if (reset_p = '1' or uart_ready = '0') then
            idle_count := OK_CLOCKS;
        elsif (idle_count > 0) then
            idle_count := idle_count - 1;
        end if;
    end if;
end process;

-- Constantly scan through the ROM contents.
p_read : process(err_clk)
    variable rom_addr : romaddr_t := 0;
begin
    if rising_edge(err_clk) then
        -- Use CR+LF terminations to detect end of each message
        -- as we scan over the ROM contents.
        rom_mstart <= rom_incr and bool2bit(rom_byte = NEWLINE_LF);
        if (reset_p = '1' or rom_addr = 0) then
            -- Reset or address 0 = Message 0.
            msg_index <= 0;
        elsif (rom_incr = '1' and rom_byte = NEWLINE_LF) then
            -- End of message (CR+LF), increment index.
            if (msg_index = TOTAL_MSGS-1) then
                msg_index <= 0;
            else
                msg_index <= msg_index + 1;
            end if;
        end if;

        -- Increment address and read next byte.
        if (reset_p = '1') then
            rom_addr := 0;    -- Reset
        elsif (rom_incr = '1' and rom_addr = TOTAL_BYTES-1) then
            rom_addr := 0;    -- Wraparound
        elsif (rom_incr = '1') then
            rom_addr := rom_addr + 1;
        end if;
        rom_byte <= MESSAGE_ROM(rom_addr);
    end if;
end process;

-- Combinational logic for the ROM and UART clock-enables.
msg_start   <= rom_mstart and err_flags(msg_index) and uart_ready;
rom_incr    <= uart_ready;
uart_start  <= msg_start or (rom_incr and msg_busy);

-- Message transmission state machine.
p_msg : process(err_clk)
begin
    if rising_edge(err_clk) then
        -- Update the "message in progress" flag.
        if (reset_p = '1') then
            msg_busy <= '0';    -- Global reset
        elsif (msg_start = '1') then
            msg_busy <= '1';    -- Start of new message
        elsif (uart_ready = '1' and rom_byte = NEWLINE_LF) then
            msg_busy <= '0';    -- Reached end of message
        end if;
    end if;
end process;

-- Transmit-only UART, one byte at a time.
u_uart : entity work.io_uart_tx
    port map (
    uart_txd    => err_uart,
    tx_data     => rom_byte,
    tx_valid    => uart_start,
    tx_ready    => uart_ready,
    rate_div    => UART_CLKDIV,
    refclk      => err_clk,
    reset_p     => reset_p);

-- Auxiliary output is just a copy of data going to the UART.
aux_data <= std_logic_vector(rom_byte);
aux_wren <= uart_start;

end io_error_reporting;
