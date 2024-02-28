--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Simple testbench for io_text_lcd
--
-- This module doesn't emulate the S162D display logic, but it
-- does echo each nybble or byte as it is written.
--
-- The complete test takes a little under 250 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     std.textio.all;
use     work.common_functions.all;

entity io_text_lcd_tb is
    -- Testbench.  No I/O pads
end io_text_lcd_tb;

architecture testbench of io_text_lcd_tb is

function hstr(slv: std_logic_vector) return string is
    variable hexlen     : integer;
    variable longslv    : std_logic_vector(67 downto 0) := (others => '0');
    variable hexstr     : string(1 to 16);
    variable fourbit    : std_logic_vector(3 downto 0);
begin
    hexlen := (slv'left+1)/4;
    if (slv'left+1) mod 4 /= 0 then
        hexlen := hexlen + 1;
    end if;
    longslv(slv'left downto 0) := slv;
    for i in (hexlen -1) downto 0 loop
        fourbit := longslv(((i*4)+3) downto (i*4));
        case fourbit is
            when "0000" => hexstr(hexlen -I) := '0';
            when "0001" => hexstr(hexlen -I) := '1';
            when "0010" => hexstr(hexlen -I) := '2';
            when "0011" => hexstr(hexlen -I) := '3';
            when "0100" => hexstr(hexlen -I) := '4';
            when "0101" => hexstr(hexlen -I) := '5';
            when "0110" => hexstr(hexlen -I) := '6';
            when "0111" => hexstr(hexlen -I) := '7';
            when "1000" => hexstr(hexlen -I) := '8';
            when "1001" => hexstr(hexlen -I) := '9';
            when "1010" => hexstr(hexlen -I) := 'A';
            when "1011" => hexstr(hexlen -I) := 'B';
            when "1100" => hexstr(hexlen -I) := 'C';
            when "1101" => hexstr(hexlen -I) := 'D';
            when "1110" => hexstr(hexlen -I) := 'E';
            when "1111" => hexstr(hexlen -I) := 'F';
            when "ZZZZ" => hexstr(hexlen -I) := 'Z';
            when "UUUU" => hexstr(hexlen -I) := 'U';
            when "XXXX" => hexstr(hexlen -I) := 'X';
            when others => hexstr(hexlen -I) := '?';
        end case;
    end loop;
    return hexstr(1 to hexlen);
end hstr;

subtype byte_t is std_logic_vector(7 downto 0);

-- Clock and reset generation
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- LCD interface
signal lcd_db       : std_logic_vector(3 downto 0);
signal lcd_e        : std_logic;
signal lcd_rw       : std_logic;
signal lcd_rs       : std_logic;

-- Streaming data interface
signal strm_data    : byte_t := (others => '0');
signal strm_wr      : std_logic := '0';

begin

-- Clock and reset generation
clk     <= not clk after 5 ns;  -- 100 MHz
reset_p <= '0' after 1 us;

-- Streaming data source.
p_src : process
    procedure send_str(str : string) is
        variable c : character;
    begin
        for n in 1 to str'length loop
            wait until rising_edge(clk);
            c := str(n);
            strm_data <= i2s(character'pos(c), 8);
            strm_wr   <= '1';
            wait until rising_edge(clk);
            strm_wr   <= '0';
            wait for 10 us; -- Emulate UART-rate input
        end loop;
    end procedure;

    constant NEWLINE_CRLF : string := character'val(13) & character'val(10);
begin
    wait until falling_edge(reset_p);
    wait for 30 ms;

    -- Send simple message:
    send_str("Hello world!" & NEWLINE_CRLF);
    wait for 80 ms;

    -- Send two-line message:
    send_str("Two-line" & NEWLINE_CRLF & " test!" & NEWLINE_CRLF);
    wait for 80 ms;

    -- Send two messages in rapid succession:
    send_str("Two quick" & NEWLINE_CRLF);
    wait for 5 ms;
    send_str("Messages" & NEWLINE_CRLF);
    wait for 80 ms;

    -- Done.
    report "All tests completed.";
    wait;
end process;

-- Unit under test.
uut : entity work.io_text_lcd
    generic map(
    REFCLK_HZ   => 100000000,
    MSG_WAIT    => 50)
    port map(
    lcd_db      => lcd_db,
    lcd_e       => lcd_e,
    lcd_rw      => lcd_rw,
    lcd_rs      => lcd_rs,
    strm_clk    => clk,
    strm_data   => strm_data,
    strm_wr     => strm_wr,
    reset_p     => reset_p);

-- Don't try to emulate LCD controller, just echo data as it is written.
-- Commands echo each half-byte; data echoes each line (many characters).
echo_nybble : process(lcd_e)
    constant LINE_LEN  : integer := 16; -- Characters per line
    variable nybb_ct   : integer := 0;  -- Nybbles received so far
    variable data_sreg : std_logic_vector(8*LINE_LEN-1 downto 0) := (others => '0');
    variable data_temp : byte_t := (others => '0');
    variable data_str  : string(1 to LINE_LEN);
begin
    if falling_edge(lcd_e) and (lcd_rw = '0') then
        if(lcd_rs = '0') then
            -- Print any accumulated characters:
            if (nybb_ct > 0) then
                for n in data_str'range loop
                    data_temp := data_sreg(135-8*n downto 128-8*n);
                    data_str(n) := character'val(u2i(data_temp));
                end loop;
                report "LCD data: '" & data_str & "'";
            end if;
            -- Check line state before clearing.
            assert (nybb_ct = 0 or nybb_ct = 2*LINE_LEN)
                report "Unexpected line state: " & integer'image(nybb_ct);
            data_sreg := (others => '0');
            nybb_ct   := 0;
            -- Command words are printed immediately.
            report "LCD command: 0x" & hstr(lcd_db);
        else
            -- Latch each data nybble (MSB first)
            if (nybb_ct < 2*LINE_LEN) then
                data_sreg(127-4*nybb_ct downto 124-4*nybb_ct) := lcd_db;
            end if;
            nybb_ct := nybb_ct + 1;
        end if;
    end if;
end process;

end;
