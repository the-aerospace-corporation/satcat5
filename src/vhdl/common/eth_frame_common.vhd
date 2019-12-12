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
-- Package definition: Useful constants and functions for Ethernet frames
--
-- This package define a variety constants and functions for manipulating
-- Ethernet frames, to maximize code reuse among various blocks.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package eth_frame_common is
    -- Size parameters including header, user data, and FCS.
    constant HEADER_CRC_BYTES   : integer := 18;    -- Header and CRC bytes ONLY.
    constant HEADER_TAG_BYTES   : integer := 4;     -- Additional bytes for 802.11Q
    constant MIN_RUNT_BYTES     : integer := 18;    -- Minimum runt frame
    constant MIN_FRAME_BYTES    : integer := 64;    -- Minimum normal frame
    constant MAX_FRAME_BYTES    : integer := 1522;  -- Maximum normal frame
    constant MAX_JUMBO_BYTES    : integer := 9022;  -- Maximum jumbo frame

    -- Local type definitions for Frame Check Sequence (FCS):
    subtype byte_t is std_logic_vector(7 downto 0);
    subtype crc_word_t is std_logic_vector(31 downto 0);
    constant CRC_INIT    : crc_word_t := (others => '1');
    constant CRC_RESIDUE : crc_word_t := x"C704DD7B";

    -- SLIP token definitions.
    constant SLIP_FEND      : byte_t := X"C0";
    constant SLIP_ESC       : byte_t := X"DB";
    constant SLIP_ESC_END   : byte_t := X"DC";
    constant SLIP_ESC_ESC   : byte_t := X"DD";

    -- Flip bit-order of the given byte.
    function flip_byte(data : byte_t) return byte_t;

    -- Byte-at-a-time CRC32 update function for polynomial 0x04C11DB7
    -- Derived from general-purpose CRC32 by Michael Cheung, 2014 June.
    function crc_next(prev : crc_word_t; data : byte_t) return crc_word_t;
end package;


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

package body eth_frame_common is

function flip_byte(data : byte_t) return byte_t is
    variable drev : byte_t;
begin
    for i in drev'range loop
        drev(i) := data(7-i);
    end loop;
    return drev;
end function;

function crc_next(prev : crc_word_t; data : byte_t) return crc_word_t is
    variable drev   : byte_t;
    variable result : crc_word_t;
begin
    -- Reverse input bit order.
    -- (Ethernet convention is LSB-first, with CRC sent MSB-first)
    drev := flip_byte(data);

    -- Giant XOR table for the specified polynomial.
    result(0)  := drev(6) xor drev(0) xor prev(24) xor prev(30);
    result(1)  := drev(7) xor drev(6) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(30) xor prev(31);
    result(2)  := drev(7) xor drev(6) xor drev(2) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(26) xor prev(30) xor prev(31);
    result(3)  := drev(7) xor drev(3) xor drev(2) xor drev(1) xor  prev(25) xor prev(26) xor prev(27) xor prev(31);
    result(4)  := drev(6) xor drev(4) xor drev(3) xor drev(2) xor drev(0) xor prev(24) xor prev(26) xor prev(27) xor prev(28) xor prev(30);
    result(5)  := drev(7) xor drev(6) xor drev(5) xor drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(24) xor prev(25) xor prev(27) xor prev(28) xor prev(29) xor prev(30) xor prev(31);
    result(6)  := drev(7) xor drev(6) xor drev(5) xor drev(4) xor drev(2) xor drev(1) xor prev(25) xor prev(26) xor prev(28) xor prev(29) xor prev(30) xor prev(31);
    result(7)  := drev(7) xor drev(5) xor drev(3) xor drev(2) xor drev(0) xor prev(24) xor prev(26) xor prev(27) xor prev(29) xor prev(31);
    result(8)  := drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(0) xor prev(24) xor prev(25) xor prev(27) xor prev(28);
    result(9)  := drev(5) xor drev(4) xor drev(2) xor drev(1) xor prev(1) xor prev(25) xor prev(26) xor prev(28) xor prev(29);
    result(10) := drev(5) xor drev(3) xor drev(2) xor drev(0) xor prev(2) xor prev(24) xor prev(26) xor prev(27) xor prev(29);
    result(11) := drev(4) xor drev(3) xor drev(1) xor drev(0) xor prev(3) xor prev(24) xor prev(25) xor prev(27) xor prev(28);
    result(12) := drev(6) xor drev(5) xor drev(4) xor drev(2) xor drev(1) xor drev(0) xor prev(4) xor prev(24) xor prev(25) xor prev(26) xor prev(28) xor prev(29) xor prev(30);
    result(13) := drev(7) xor drev(6) xor drev(5) xor drev(3) xor drev(2) xor drev(1) xor prev(5) xor prev(25) xor prev(26) xor prev(27) xor prev(29) xor prev(30) xor prev(31);
    result(14) := drev(7) xor drev(6) xor drev(4) xor drev(3) xor drev(2) xor prev(6) xor prev(26) xor prev(27) xor prev(28) xor prev(30) xor prev(31);
    result(15) := drev(7) xor drev(5) xor drev(4) xor drev(3) xor prev(7) xor prev(27) xor prev(28) xor prev(29) xor prev(31);
    result(16) := drev(5) xor drev(4) xor drev(0) xor prev(8) xor prev(24) xor prev(28) xor prev(29);
    result(17) := drev(6) xor drev(5) xor drev(1) xor prev(9) xor prev(25) xor prev(29) xor prev(30);
    result(18) := drev(7) xor drev(6) xor drev(2) xor prev(10) xor prev(26) xor prev(30) xor prev(31);
    result(19) := drev(7) xor drev(3) xor prev(11) xor prev(27) xor prev(31);
    result(20) := drev(4) xor prev(12) xor prev(28);
    result(21) := drev(5) xor prev(13) xor prev(29);
    result(22) := drev(0) xor prev(14) xor prev(24);
    result(23) := drev(6) xor drev(1) xor drev(0) xor prev(15) xor prev(24) xor prev(25) xor prev(30);
    result(24) := drev(7) xor drev(2) xor drev(1) xor prev(16) xor prev(25) xor prev(26) xor prev(31);
    result(25) := drev(3) xor drev(2) xor prev(17) xor prev(26) xor prev(27);
    result(26) := drev(6) xor drev(4) xor drev(3) xor drev(0) xor prev(18) xor prev(24) xor prev(27) xor prev(28) xor prev(30);
    result(27) := drev(7) xor drev(5) xor drev(4) xor drev(1) xor prev(19) xor prev(25) xor prev(28) xor prev(29) xor prev(31);
    result(28) := drev(6) xor drev(5) xor drev(2) xor prev(20) xor prev(26) xor prev(29) xor prev(30);
    result(29) := drev(7) xor drev(6) xor drev(3) xor prev(21) xor prev(27) xor prev(30) xor prev(31);
    result(30) := drev(7) xor drev(4) xor prev(22) xor prev(28) xor prev(31);
    result(31) := drev(5) xor prev(23) xor prev(29);
    return result;
end function;

end package body;
