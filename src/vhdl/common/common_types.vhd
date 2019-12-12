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
-- Generic functions that are useful to nearly any VHDL block
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

package COMMON_TYPES is
-- Functions
    -- Convert a standard logic vector to an unsigned integer
    function U2I(a: std_logic_vector) return natural;
    -- Convert a standard logic (bit) to an integer: '0'->0, '1'->1
    function U2I(a: std_logic)        return natural;
    -- Convert an integer to a L-bit standard logic vector of length
    function I2S(a: integer; l: integer) return std_logic_vector;
    -- Convert a boolean to a bit, false->'0', true->'1'
    function bool2bit(a: boolean)     return std_logic;

    -- Resize a std_logic_vector using the rules for UNSIGNED
    function resize(a: std_logic_vector; B: integer) return std_logic_vector;

    -- Perform an XOR reduction
    function xor_reduce(a : std_logic_vector) return std_logic;
    -- Return '1' if any of the bits in the input are '1'
    function or_reduce(a: std_logic_vector) return std_logic;
    -- Return '1' if all the bits in the input are '1'
    function and_reduce(a: std_logic_vector) return std_logic;

    -- Log2(x), rounded up or down.
    function log2_ceil(a: integer) return integer;
    function log2_floor(a: integer) return integer;

    -- Return the maximum of the two inputs
    function max(a,b : integer) return integer;
    -- Return the minimum of the two inputs
    function min(a,b : integer) return integer;

    -- Map 'X', 'U' to '0'
    function to_01(a: std_logic_vector) return std_logic_vector;
    function to_01(a: std_logic)        return std_logic;
end package;

package body COMMON_TYPES is
    function U2I(a: std_logic_vector) return natural is
    begin
        return TO_INTEGER(UNSIGNED(a));
    end;
    function U2I(a: std_logic)        return natural is
    begin
        if a = '0' then return 0; else return 1; end if;
    end;

    function I2S(a: integer; l: integer) return std_logic_vector is
    begin
        return std_logic_vector(TO_UNSIGNED(a,l));
    end;

    function bool2bit(a: boolean)   return std_logic is
    begin
        if a then return '1'; else return '0'; end if;
    end;

    function resize(a: std_logic_vector; B: integer) return std_logic_vector is
    begin
        return std_logic_vector(resize(UNSIGNED(a), B));
    end;

    function xor_reduce(a : std_logic_vector) return std_logic is
        variable result : std_logic;
    begin
        result := '0';
        for i in a'range loop
            result := result xor a(i);
        end loop;
        return result;
    end;

    function or_reduce(a: std_logic_vector) return std_logic is
        variable z : std_logic;
    begin
        z := '0';
        for i in a'range loop z := z or a(i); end loop;
        return z;
    end;

    function and_reduce(a: std_logic_vector) return std_logic is
        variable z : std_logic;
    begin
        z := '1';
        for i in a'range loop z := z and a(i); end loop;
        return z;
    end;

    function log2_ceil(a: integer) return integer is
    begin
        return log2_floor(2*a-1);
    end;

    function log2_floor(a: integer) return integer is
        variable b, l: integer;
    begin
        assert a > 0 report "Outside of log2 range" severity failure;
        b := a; l := 0;
        while b > 1 loop
            l := l + 1; b := b / 2;
        end loop;
        return l;
    end;

    function max(a, b : integer) return integer is
    begin
        if a > b then return a;
        else return b;
        end if;
    end;

    function min(a, b : integer) return integer is
    begin
        if a < b then return a;
        else return b;
        end if;
    end;

    -- This function is useful to avoid having X's in simulation when feedback
    -- loops are present.  Note that it synthesizes to no hardware.
    function to_01(a: std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(a'range);
    begin
        result := a;
-- translate_off
        for i in a'range loop
            if(a(i) = '1' or a(i) = 'H') then
                result(i) := '1';
            else
                result(i) := '0';
            end if;
        end loop;
-- translate_on
        return result;
    end;

    function to_01(a: std_logic) return std_logic is
        variable result : std_logic;
    begin
        result := a;
-- translate_off
        if(a = '1' or a = 'H') then
            result := '1';
        else
            result := '0';
        end if;
-- translate_on
        return result;
    end;
end package body;
