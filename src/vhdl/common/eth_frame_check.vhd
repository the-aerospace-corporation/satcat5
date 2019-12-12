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
-- Ethernet frame verification
--
-- Given an Ethernet byte stream, detect frame boundaries and test
-- whether each packet is valid:
--  * Matching frame check sequence (CRC32)
--  * Maximum frame length is 1522 bytes (normal) or 9022 bytes (jumbo).
--  * Minimum frame length is either 64 bytes (normal mode) or 18 bytes
--    (if runt frames are allowed on this interface).
--  * Frame length at least 64 bytes (unless runt frames are allowed).
--  * If length is specified (EtherType <= 1530), verify exact match.
--
-- This block optionally strips the frame-check sequence from the end of
-- each output frame; in this case it must be replaced before transmission.
--
-- For more information, refer to:
-- https://en.wikipedia.org/wiki/Ethernet_frame
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_types.all;
use     work.eth_frame_common.all;

entity eth_frame_check is
    generic (
    ALLOW_JUMBO : boolean := false;     -- Allow frames longer than 1522 bytes?
    ALLOW_RUNT  : boolean := false;     -- Allow frames below standard length?
    STRIP_FCS   : boolean := false;     -- Remove FCS from output?
    OUTPUT_REG  : boolean := true);     -- Extra register at output?
    port (
    -- Input data stream (with strobe for final byte)
    in_data     : in  std_logic_vector(7 downto 0);
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- Output data stream (with pass/fail on last byte)
    out_data    : out std_logic_vector(7 downto 0);
    out_write   : out std_logic;
    out_commit  : out std_logic;
    out_revert  : out std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_check;

architecture rtl of eth_frame_check is

-- Minimum frame size depends on ALLOW_RUNT parameter.
-- (Returned size includes header, user data, and CRC.)
function MIN_FRAME_BYTES_LOCAL return integer is
begin
    if (ALLOW_RUNT) then
        return MIN_RUNT_BYTES;  -- Min user = 0 bytes
    else
        return MIN_FRAME_BYTES; -- Min user = 46 bytes
    end if;
end function;

-- Maximum frame size depends on the ALLOW_JUMBO parameter.
-- (Returned size includes header, user data, and CRC.)
function MAX_FRAME_BYTES_LOCAL return integer is
begin
    if (ALLOW_JUMBO) then
        return MAX_JUMBO_BYTES;
    else
        return MAX_FRAME_BYTES;
    end if;
end function;

-- Maximum "length" field is always 1530, even if jumbo frames are allowed.
constant MAX_USERLEN_BYTES  : integer := 1530;

-- Local type definitions:
constant COUNT_WIDTH : integer := log2_ceil(MAX_FRAME_BYTES_LOCAL+2);
subtype ethertype_len  is unsigned(COUNT_WIDTH-1 downto 0);
subtype ethertype_full is unsigned(15 downto 0);
subtype byte_t is std_logic_vector(7 downto 0);
subtype crc_word_t is std_logic_vector(31 downto 0);
constant COUNT_MAX : ethertype_len := (others => '1');

-- Single-cycle delay for the input stream.
signal reg_data         : byte_t := (others => '0');
signal reg_last         : std_logic := '0';
signal reg_write        : std_logic := '0';
signal reg_commit       : std_logic := '0';
signal reg_revert       : std_logic := '0';

-- Buffered output signals (optional, for better timing)
signal buf_data         : byte_t := (others => '0');
signal buf_write        : std_logic := '0';
signal buf_commit       : std_logic := '0';
signal buf_revert       : std_logic := '0';

-- Modified output signals with no FCS (optional)
signal trim_data        : byte_t := (others => '0');
signal trim_write       : std_logic := '0';
signal trim_commit      : std_logic := '0';
signal trim_revert      : std_logic := '0';

-- Frame-check state machine:
signal byte_first       : std_logic := '1';
signal len_count        : ethertype_len := (others => '0');
signal len_field_etype  : std_logic := '0';
signal len_field_cmp    : ethertype_len := (others => '0');
signal len_field_full   : ethertype_full := (others => '0');
signal crc_sreg         : crc_word_t := CRC_INIT;
signal frame_ok         : std_logic := '0';

begin

-- Frame-checking state machine:
p_frame : process(clk)
begin
    if rising_edge(clk) then
        -- Single-cycle delay for the input stream.
        reg_data  <= in_data;
        reg_write <= in_write;
        reg_last  <= in_write and in_last;

        -- Set the "first-byte" flag after reset or end-of-frame.
        if (reset_p = '1') then
            byte_first <= '1';
        elsif (in_write = '1') then
            byte_first <= in_last;
        end if;

        -- Precalculate comparisons on the EtherType / length field.
        -- Note: Only need LSBs for comparison to len_count.
        len_field_cmp   <= len_field_full(COUNT_WIDTH-1 downto 0) + HEADER_CRC_BYTES;
        len_field_etype <= bool2bit(len_field_full > MAX_USERLEN_BYTES);

        -- Update all other state variables whenever we receive new data...
        if (in_write = '1') then
            -- Store the Ethertype / Length field (12th + 13th bytes).
            if (len_count = 12) then
                len_field_full(15 downto 8) <= unsigned(in_data);    -- MSB first
            elsif (len_count = 13) then
                len_field_full(7 downto 0) <= unsigned(in_data);
            end if;

            -- Update length counter.
            if (byte_first = '1') then
                len_count <= to_unsigned(1, len_count'length);
            elsif (len_count /= COUNT_MAX) then
                len_count <= len_count + 1;
            end if;

            -- Update CRC:
            if (byte_first = '1') then
                crc_sreg <= crc_next(CRC_INIT, in_data);
            else
                crc_sreg <= crc_next(crc_sreg, in_data);
            end if;
        end if;
    end if;
end process;

-- Check all frame validity requirements.
frame_ok <= bool2bit(
    (crc_sreg = CRC_RESIDUE) and
    (len_count >= MIN_FRAME_BYTES_LOCAL) and
    (len_count <= MAX_FRAME_BYTES_LOCAL) and
    (len_field_etype = '1' or len_count = len_field_cmp));

reg_commit <= reg_last and frame_ok;
reg_revert <= reg_last and not frame_ok;

-- Optionally instantiate additional output logic:
gen_buffer : if OUTPUT_REG generate
    -- Simple buffered output, for better timing.
    p_out_reg : process(clk)
    begin
        if rising_edge(clk) then
            buf_data    <= reg_data;
            buf_write   <= reg_write;
            buf_commit  <= reg_commit;
            buf_revert  <= reg_revert;
        end if;
    end process;
end generate;

gen_strip : if STRIP_FCS generate
    -- Instantiate state machine to remove FCS from the end of each packet.
    p_out_strip : process(clk)
        constant DELAY_MAX : integer := 4;
        type sreg_t is array(1 to DELAY_MAX) of byte_t;
        variable sreg : sreg_t := (others => (others => '0'));
        variable count : integer range 0 to DELAY_MAX := DELAY_MAX;
    begin
        if rising_edge(clk) then
            -- Four-byte delay using a shift register.
            if (reg_write = '1') then
                sreg := reg_data & sreg(1 to DELAY_MAX-1);
            end if;
            trim_data <= sreg(DELAY_MAX);

            -- Drive the output strobes.
            trim_write  <= bool2bit(count = 0) and reg_write;
            trim_commit <= bool2bit(count = 0) and reg_commit;
            trim_revert <= bool2bit(count = 0) and reg_revert;

            -- Counter suppresses the first four bytes in each frame.
            if (reset_p = '1' or reg_last = '1') then
                count := DELAY_MAX;
            elsif (reg_write = '1' and count > 0) then
                count := count - 1;
            end if;
        end if;
    end process;
end generate;

-- Select final output signal based on configuration.
out_data   <= trim_data when STRIP_FCS
         else buf_data when OUTPUT_REG
         else reg_data;
out_write  <= trim_write when STRIP_FCS
         else buf_write when OUTPUT_REG
         else reg_write;
out_commit <= trim_commit when STRIP_FCS
         else buf_commit when OUTPUT_REG
         else reg_commit;
out_revert <= trim_revert when STRIP_FCS
         else buf_revert when OUTPUT_REG
         else reg_revert;

end rtl;
