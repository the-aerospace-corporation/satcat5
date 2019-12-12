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
-- Define functions that load constants or lookup-table data from a file.
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

package CONFIG_FILE2ROM is
    -- Define helper types:
    subtype nybble_t is std_logic_vector(3 downto 0);
    type rom_file_t is file of character;

    -- Read binary files, one byte at a time.  Each byte is concatenated
    -- into a single big-endian std_logic_vector.
    impure function read_bin_file(filename : string) return std_logic_vector;

    -- Read plaintext files where each line is a hexadecimal string.
    -- Valid characters (0-9, A-F, a-f) are interpreted as hexadecimal
    -- values and concatenated into a single big-endian std_logic_vector.
    -- Whitespace and all other values are ignored.
    impure function read_hex_file(filename : string) return std_logic_vector;

    -- Helper function to decode hexadecimal characters.
    -- Valid characters (0-9, A-F, a-f) return 0-15, others return "XXXX".
    function hex_decode(x : character) return nybble_t;

    -- Helper functions for determining the length (in bits) of a given input.
    impure function len_bin_file(filename : string) return integer;
    impure function len_hex_file(filename : string) return integer;
end package;

package body CONFIG_FILE2ROM is
    impure function read_bin_file(filename : string) return std_logic_vector is
        -- Pre-open file to determine length, allocate accordingly.
        constant NBITS : integer := len_bin_file(filename);
        variable result : std_logic_vector(NBITS-1 downto 0);
        -- Working variables used to read the file.
        file in_file : rom_file_t is filename;
        variable c   : character;           -- Raw character
        variable d   : integer;             -- Decoded value
        variable n   : integer := NBITS;    -- Write index
    begin
        while n > 0 loop
            -- Read and decode next character...
            read(in_file, c);
            d := character'pos(c);
            -- Write result to the output array.
            result(n-1 downto n-8) := std_logic_vector(to_unsigned(d,8));
            n := n - 8;
        end loop;
        return result;
    end function;

    impure function read_hex_file(filename : string) return std_logic_vector is
        -- Pre-open file to determine length, allocate accordingly.
        constant NBITS : integer := len_hex_file(filename);
        variable result : std_logic_vector(NBITS-1 downto 0);
        -- Working variables used to read the file.
        file in_file : rom_file_t is filename;
        variable c   : character;           -- Raw character
        variable d   : nybble_t;            -- Decoded value
        variable n   : integer := NBITS;    -- Write index
    begin
        while n > 0 loop
            -- Read and decode next character...
            read(in_file, c);
            d := hex_decode(c);
            -- If valid, write result to the output array.
            if (d(0) /= 'X') then
                result(n-1 downto n-4) := d;
                n := n - 4;
            end if;
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

    impure function len_bin_file(filename : string) return integer is
        file in_file : rom_file_t is filename;
        variable c   : character;
        variable len : integer := 0;
    begin
        while not endfile(in_file) loop
            -- Read next character and increment length.
            read(in_file, c);
            len := len + 8; -- Each character = 8 output bits
        end loop;
        return len;
    end function;

    impure function len_hex_file(filename : string) return integer is
        file in_file : rom_file_t is filename;
        variable c   : character;
        variable d   : nybble_t;
        variable len : integer := 0;
    begin
        while not endfile(in_file) loop
            -- Read and decode next character...
            read(in_file, c);
            d := hex_decode(c);
            -- If decode succeeds, increment length.
            if (d(0) /= 'X') then
                len := len + 4; -- Each hex character = 4 output bits
            end if;
        end loop;
        return len;
    end function;
end package body;
