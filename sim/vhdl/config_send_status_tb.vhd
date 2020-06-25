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
-- Testbench for the Ethernet status reporting block.
--
-- This testbench generates a series of fixed-size status words,
-- and confirms that the packets sent match the expected format.
-- The status word is randomized after the end of each packet.
--
-- The test sequence covers different flow-control conditions, and
-- completes within 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity config_send_status_tb is
    -- Unit testbench, no I/O ports.
end config_send_status_tb;

architecture tb of config_send_status_tb is

-- Test configuration:
constant MSG_BYTES   : integer := 8;
constant MSG_ETYPE   : std_logic_vector(15 downto 0) := x"5C00";
constant MAC_DEST    : std_logic_vector(47 downto 0) := x"FFFFFFFFFFFF";
constant MAC_SOURCE  : std_logic_vector(47 downto 0) := x"536174436174";

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Status word
signal status       : std_logic_vector(8*MSG_BYTES-1 downto 0) := (others => '0');

-- Output stream
signal ref_data     : byte_t := (others => '0');
signal out_data     : byte_t;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic;
signal out_rate     : real := 0.0;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Generate a new status word before the start of each packet.
p_src : process(clk_100)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable empty  : boolean := true;
begin
    if rising_edge(clk_100) then
        -- Clear contents after word is consumed.
        if (reset_p = '0' and out_valid = '1' and out_ready = '1' and out_last = '1') then
            empty := true;
        end if;

        -- Flow-control randomization.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < out_rate);

        -- Generate a new random word on demand.
        if (empty) then
            for n in status'range loop
                uniform(seed1, seed2, rand);
                status(n) <= bool2bit(rand < 0.5);
            end loop;
            empty := false;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.config_send_status
    generic map(
    MSG_BYTES   => MSG_BYTES,
    MSG_ETYPE   => MSG_ETYPE,
    MAC_DEST    => MAC_DEST,
    MAC_SOURCE  => MAC_SOURCE,
    AUTO_DELAY  => 1000)    -- Send every N clock cycles
    port map(
    status_val  => status,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the output stream.
p_chk : process(clk_100)
    -- Bit-at-a-time CRC32 update function, with optimizations.
    subtype crc_word_t is std_logic_vector(31 downto 0);
    function crc_next(prev : crc_word_t; data : byte_t) return crc_word_t is
        constant CRC_POLY : crc_word_t := x"04C11DB7";
        variable sreg : crc_word_t := prev;
        variable mask : crc_word_t := (others => '0');
    begin
        -- Ethernet convention is LSB-first within each byte.
        for n in 0 to 7 loop
            mask := (others => data(n) xor sreg(31));
            sreg := (sreg(30 downto 0) & '0') xor (mask and CRC_POLY);
        end loop;
        return sreg;
    end function;

    -- Expected packet length, not including FCS.
    constant FRAME_BYTES : integer := MSG_BYTES + 14;

    -- Extract indexed byte from a larger vector.
    function get_byte(x : std_logic_vector; b : integer) return byte_t is
        variable x2 : std_logic_vector(x'length-1 downto 0) := x;
        variable temp : byte_t := x2(x2'left-8*b downto x2'left-8*b-7);
    begin
        -- Default byte order is big-endian.
        return temp;
    end function;

    function get_fcs(x : crc_word_t; b : integer) return byte_t is
        variable temp : byte_t;
    begin
        -- Ethernet CRC transmission is bit-swapped and byte-swapped.
        for n in 0 to 7 loop
            temp(n) := not x(31-(8*b+n));
        end loop;
        return temp;
    end function;

    -- Working variables
    variable byte_idx : integer := 0;
    variable crc_sreg : crc_word_t := (others => '1');
begin
    if rising_edge(clk_100) then
        -- Confirm data against reference sequence.
        if (reset_p = '1') then
            byte_idx := 0;
            crc_sreg := (others => '1');
        elsif (out_valid = '1' and out_ready = '1') then
            assert (out_data = ref_data) report "Data mismatch" severity error;
            byte_idx := byte_idx + 1;
            if (out_last = '1') then
                -- Check length before starting new frame.
                assert (byte_idx = FRAME_BYTES+4)
                    report "Length mismatch" severity error;
                byte_idx := 0;
                crc_sreg := (others => '1');
            elsif (byte_idx <= FRAME_BYTES) then
                -- Calculate CRC for expected duration.
                crc_sreg := crc_next(crc_sreg, out_data);
            end if;
        end if;

        -- Generate next byte in the reference sequence.
        if (byte_idx < FRAME_BYTES) then
            ref_data <= get_byte(MAC_DEST & MAC_SOURCE & MSG_ETYPE & status, byte_idx);
        elsif (byte_idx < FRAME_BYTES + 4) then
            ref_data <= get_fcs(crc_sreg, byte_idx-FRAME_BYTES);
        else
            ref_data <= (others => 'X');    -- Invalid...
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
begin
    wait until falling_edge(reset_p);
    for n in 1 to 10 loop
        report "Starting test #" & integer'image(n);
        out_rate <= real(n) / 10.0;
        wait for 99 us;
    end loop;
    report "All tests finished.";
    wait;
end process;

end tb;
