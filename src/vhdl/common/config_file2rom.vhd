--------------------------------------------------------------------------
-- Copyright 2019-2020 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Define functions that load constants or lookup-table data from a file.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_textio.all;
use ieee.numeric_std.all;
use std.textio.all;

package CONFIG_FILE2ROM is
    -- Define helper types:
    subtype nybble_t is std_logic_vector(3 downto 0);
    type rom_file_t is file of character;

    -- Read binary files, one byte at a time.  Each byte is concatenated
    -- into a single big-endian std_logic_vector.
    -- NOTE: Auto-width does NOT work correctly in Vivado 2016.3.
    impure function read_bin_file(
        filename    : string;           -- Filename to be read
        ovr_width   : integer := -1)    -- Output width, if known
        return std_logic_vector;

    -- Read plaintext files where each line is a hexadecimal string.
    -- Valid characters (0-9, A-F, a-f) are interpreted as hexadecimal
    -- values and concatenated into a single big-endian std_logic_vector.
    -- Whitespace and all other values are ignored.
    impure function read_hex_file(
        filename    : string;           -- Filename to be read
        ovr_width   : integer := -1)    -- Output width, if known
        return std_logic_vector;

    -- Helper function to decode hexadecimal characters.
    -- Valid characters (0-9, A-F, a-f) return 0-15, others return "XXXX".
    function hex_decode(x : character) return nybble_t;

    -- Helper functions for determining the length (in bits) of a given input.
    impure function len_bin_file(
        filename    : string;           -- Filename to be read
        ovr_width   : integer := -1)    -- Override length, if known
        return integer;
    impure function len_hex_file(
        filename    : string;           -- Filename to be read
        ovr_width   : integer := -1)    -- Override length, if known
        return integer;
end package;

package body CONFIG_FILE2ROM is
    impure function read_bin_file(
        filename    : string;
        ovr_width   : integer := -1)
        return std_logic_vector
    is
        -- Pre-open file to determine length, allocate accordingly.
        constant NBITS  : integer := len_bin_file(filename, ovr_width);
        variable result : std_logic_vector(NBITS-1 downto 0);
        -- Working variables used to read the file.
        file in_file : rom_file_t open read_mode is filename;
        variable c   : character;           -- Raw character
        variable d   : integer;             -- Decoded value
        variable wr  : integer := NBITS;    -- Write index
    begin
        while wr > 0 and not endfile(in_file) loop
            -- Read and decode next character...
            read(in_file, c);
            d := character'pos(c);
            -- Write result to the output array.
            result(wr-1 downto wr-8) := std_logic_vector(to_unsigned(d,8));
            wr := wr - 8;
        end loop;
        return result;
    end function;

    impure function read_hex_file(
        filename    : string;
        ovr_width   : integer := -1)
        return std_logic_vector
    is
        -- Pre-open file to determine length, allocate accordingly.
        constant NBITS  : integer := len_hex_file(filename, ovr_width);
        variable result : std_logic_vector(NBITS-1 downto 0);
        -- Working variables used to read the file.
        file in_file : TEXT open read_mode is filename;
        variable ln  : LINE;                -- Line buffer
        variable c   : character;           -- Raw character
        variable d   : nybble_t;            -- Decoded value
        variable wr  : integer := NBITS;    -- Write index
    begin
        while wr > 0 and not endfile(in_file) loop
            -- Read line and decode each character...
            readline(in_file, ln);
            for n in ln'range loop
                -- Write each valid hex character to the output array.
                d := hex_decode(ln(n));
                if (d(0) /= 'X') then
                    result(wr-1 downto wr-4) := d;
                    wr := wr - 4;
                end if;
            end loop;
        end loop;
        return result;
    end function;

    function hex_decode(x : character) return nybble_t is
        variable y : nybble_t := (others => 'X');
    begin
        case (x) is
            when '0' => y := x"0";
            when '1' => y := x"1";
            when '2' => y := x"2";
            when '3' => y := x"3";
            when '4' => y := x"4";
            when '5' => y := x"5";
            when '6' => y := x"6";
            when '7' => y := x"7";
            when '8' => y := x"8";
            when '9' => y := x"9";
            when 'A' => y := x"A";
            when 'B' => y := x"B";
            when 'C' => y := x"C";
            when 'D' => y := x"D";
            when 'E' => y := x"E";
            when 'F' => y := x"F";
            when 'a' => y := x"A";
            when 'b' => y := x"B";
            when 'c' => y := x"C";
            when 'd' => y := x"D";
            when 'e' => y := x"E";
            when 'f' => y := x"F";
            when others => null;
        end case;
        return y;
    end function;

    -- 
    impure function len_bin_file(
        filename    : string;
        ovr_width   : integer := -1)
        return integer
    is
        file in_file : rom_file_t;
        variable fst : file_open_status;
        variable c   : character;
        variable len : integer := 0;
    begin
        -- If width is known, return that value.
        if (ovr_width >= 0) then
            return ovr_width;
        end if;
        -- Otherwise, attempt to open the file...
        file_open(fst, in_file, filename, READ_MODE);
        assert (fst = OPEN_OK) report "Can't read file: " & filename;
        -- ...and then scan the contents.
        while not endfile(in_file) loop
            -- Read next character and increment length.
            read(in_file, c);
            len := len + 8; -- Each character = 8 output bits
        end loop;
        file_close(in_file);
        return len;
    end function;

    impure function len_hex_file(
        filename    : string;
        ovr_width   : integer := -1)
        return integer
    is
        file in_file : TEXT;
        variable fst : file_open_status;
        variable ln  : LINE;
        variable d   : nybble_t;
        variable len : integer := 0;
    begin
        -- If width is known, return that value.
        if (ovr_width >= 0) then
            return ovr_width;
        end if;
        -- Otherwise, attempt to open the file...
        file_open(fst, in_file, filename, READ_MODE);
        assert (fst = OPEN_OK) report "Can't read file: " & filename;
        -- ...and then scan the contents.
        while not endfile(in_file) loop
            -- Read next line and decode each character.
            readline(in_file, ln);
            for n in ln'range loop
                -- Increment length only for valid hex characters.
                d := hex_decode(ln(n));
                if (d(0) /= 'X') then
                    len := len + 4; -- Each hex character = 4 output bits
                end if;
            end loop;
        end loop;
        file_close(in_file);
        return len;
    end function;
end package body;
