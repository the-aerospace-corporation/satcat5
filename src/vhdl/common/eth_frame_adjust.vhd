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
-- Ethernet frame adjustment prior to transmission.
--
-- Given a stream of frames, perform any of the following steps to
-- produce valid Ethernet frames:
-- * Strip original FCS, if present (optional, enabled by default)
-- * Pad short frames with zeros to bring them up to minimum size.
--   (Optional, minimum size 64 by default per 802.3 spec)
-- * Append a newly-calculated FCS (required)
--
-- This block can be used for multiple purposes, including calculating
-- FCS for a raw data stream, padding runt frames to a minimum length before
-- transmission on another network segment, etc.
--
-- Note: This block uses AXI-style flow control, with additional guarantees.
-- If input data is supplied immediately on request, then the output will have
-- the same property.  This allows use with port_adjust and other blocks that
-- require contiguous data streams.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_adjust is
    generic (
    MIN_FRAME   : integer := 64;        -- Minimum output frame size
    META_WIDTH  : natural := 0;         -- Width of optional metadata field
    APPEND_FCS  : boolean := true;      -- Append new FCS to output?
    STRIP_FCS   : boolean := true);     -- Remove FCS from input?
    port (
    -- Input data stream (with or without FCS, AXI flow control).
    in_data     : in  std_logic_vector(7 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    -- Output data stream (with zero-padding and FCS, AXI flow control).
    out_data    : out std_logic_vector(7 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_adjust;

architecture rtl of eth_frame_adjust is

subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);

-- FCS removal (optional)
signal in_write     : std_logic := '0';
signal frm_data     : byte_t := (others => '0');
signal frm_meta     : meta_t := (others => '0');
signal frm_last     : std_logic := '0';
signal frm_valid    : std_logic := '0';
signal frm_ready    : std_logic := '0';

-- Zero-padding of runt frames
signal pad_data     : byte_t := (others => '0');
signal pad_meta     : meta_t := (others => '0');
signal pad_last     : std_logic := '0';
signal pad_valid    : std_logic := '0';
signal pad_ready    : std_logic := '0';
signal pad_ovr      : std_logic := '0';

-- Frame-check recalculation
signal fcs_data     : byte_t := (others => '0');
signal fcs_meta     : meta_t := (others => '0');
signal fcs_last     : std_logic := '0';
signal fcs_valid    : std_logic := '0';
signal fcs_ready    : std_logic := '0';
signal fcs_ovr      : std_logic := '0';
signal fcs_crc32    : crc_word_t := CRC_INIT;

begin

-- Optionally remove FCS from the end of each packet.
gen_nostrip : if not STRIP_FCS generate
    -- Input has already had FCS removed, no need to modify.
    frm_data    <= in_data;
    frm_meta    <= in_meta;
    frm_last    <= in_valid and in_last;
    frm_valid   <= in_valid;
    in_ready    <= frm_ready;
    in_write    <= '0'; -- Unused
end generate;

gen_strip : if STRIP_FCS generate
    -- Upstream flow control.
    in_write    <= in_valid and (frm_ready or not frm_valid);
    in_ready    <= frm_ready or not frm_valid;

    -- Remove last four bytes of each packet.
    p_out_strip : process(clk)
        constant DELAY_MAX : integer := 4;
        type sreg_data_t is array(0 to DELAY_MAX) of byte_t;
        type sreg_meta_t is array(0 to DELAY_MAX) of meta_t;
        variable sreg_data : sreg_data_t := (others => (others => '0'));
        variable sreg_meta : sreg_meta_t := (others => (others => '0'));
        variable count : integer range 0 to DELAY_MAX := DELAY_MAX;
    begin
        if rising_edge(clk) then
            -- Four-byte delay using a shift register.
            if (in_write = '1') then
                sreg_data := in_data & sreg_data(0 to DELAY_MAX-1);
                if (META_WIDTH > 0) then
                    sreg_meta := in_meta & sreg_meta(0 to DELAY_MAX-1);
                end if;
            end if;
            frm_data <= sreg_data(DELAY_MAX);
            if (META_WIDTH > 0) then
                frm_meta <= sreg_meta(DELAY_MAX);
            end if;

            -- Drive the output strobes.
            if (reset_p = '1') then
                frm_valid <= '0';
                frm_last  <= '0';
            elsif (in_write = '1') then
                frm_valid <= bool2bit(count = 0);
                frm_last  <= bool2bit(count = 0) and in_last;
            elsif (frm_ready = '1') then
                frm_valid <= '0';
                frm_last  <= '0';
            end if;

            -- Counter suppresses the first four bytes in each frame.
            if (reset_p = '1') then
                count := DELAY_MAX; -- General reset
            elsif (in_write = '1' and in_last = '1') then
                count := DELAY_MAX; -- End of packet
            elsif (in_write = '1' and count > 0) then
                count := count - 1; -- Countdown to zero
            end if;
        end if;
    end process;
end generate;

-- Upstream flow control
frm_ready <= (not pad_valid) or (pad_ready and not pad_ovr);

-- Pad resulting stub-frames to minimum normal size as needed.
p_pad : process(clk)
    -- Counter max value is equal to the worst-case pad length.
    -- i.e., min size = N bytes + current byte + 4-byte FCS.
    constant BCOUNT_MAX : integer := int_max(MIN_FRAME-5, 0);
    variable bcount : integer range 0 to BCOUNT_MAX := 0;
begin
    if rising_edge(clk) then
        -- Update the output stream.
        if (frm_valid = '1' and frm_ready = '1') then
            -- Pass along each input byte.
            pad_data  <= frm_data;
            pad_meta  <= frm_meta;
        elsif (pad_ready = '1' and pad_ovr = '1') then
            -- Zero-padding mode.
            pad_data  <= (others => '0');
        end if;

        -- Update the VALID and LAST strobes.
        if (reset_p = '1') then
            pad_valid <= '0';
            pad_last  <= '0';
        elsif (frm_valid = '1' and frm_ready = '1') then
            -- Regular data, pass "last" strobe only if packet >= 60 bytes.
            -- (Minimum regular frame size, not including FCS.)
            pad_valid <= '1';
            pad_last  <= frm_last and bool2bit(bcount = BCOUNT_MAX);
        elsif (pad_ready = '1' and pad_ovr = '1') then
            -- Zero-padding up to minimum frame size.
            pad_valid <= '1';
            pad_last  <= bool2bit(bcount = BCOUNT_MAX);
        elsif (pad_ready = '1') then
            -- Otherwise, mark previous byte as consumed.
            pad_valid <= '0';
            pad_last  <= '0';
        end if;

        -- Update the pad-override flag.
        if (reset_p = '1') then
            -- General reset -> Normal mode.
            pad_ovr <= '0';
        elsif (frm_valid = '1' and frm_ready = '1') then
            -- End of input packet -> Override if < 60 bytes.
            pad_ovr <= bool2bit(bcount < BCOUNT_MAX) and frm_last;
        elsif (pad_ovr = '1' and pad_ready = '1') then
            -- Padding mode enabled, revert to normal at 60 bytes.
            pad_ovr <= bool2bit(bcount < BCOUNT_MAX);
        end if;

        -- Update the byte-counter.
        if (reset_p = '1') then
            -- General reset.
            bcount := 0;
        elsif (frm_valid = '1' and frm_ready = '1') then
            -- Accept next input byte.
            if (bcount < BCOUNT_MAX) then
                bcount := bcount + 1;   -- Normal increment
            elsif (frm_last = '1') then
                bcount := 0;            -- End of packet, no padding
            end if;
        elsif (pad_ready = '1' and pad_ovr = '1') then
            -- Generate next zero-padding byte.
            if (bcount < BCOUNT_MAX) then
                bcount := bcount + 1;   -- Pad to minimum size
            else
                bcount := 0;            -- Final padding byte
            end if;
        end if;
    end if;
end process;

-- Optionally append a new FCS to the end of each packet.
gen_noappend : if not APPEND_FCS generate
    fcs_data  <= pad_data;
    fcs_meta  <= pad_meta;
    fcs_last  <= pad_last;
    fcs_valid <= pad_valid;
    pad_ready <= fcs_ready;
end generate;

gen_append : if APPEND_FCS generate
    -- Upstream flow control
    pad_ready <= (not fcs_valid) or (fcs_ready and not fcs_ovr);

    -- Recalculate and append the CRC.
    p_crc : process(clk)
        variable bcount : integer range 0 to 3 := 0;
    begin
        if rising_edge(clk) then
            -- Relay data until end, then append FCS.
            if (pad_valid = '1' and pad_ready = '1') then
                -- Relay normal data until end of frame.
                fcs_data  <= pad_data;
                fcs_meta  <= pad_meta;
                fcs_ovr   <= pad_last;
            elsif (fcs_ovr = '1' and fcs_ready = '1') then
                -- Append each FCS byte, flipping polarity and bit order.
                -- (CRC is MSB-first, but Ethernet convention is LSB-first.)
                fcs_data  <= not flip_byte(fcs_crc32(31 downto 24));
                fcs_ovr   <= bool2bit(bcount < 3);
            end if;

            -- Update the VALID and LAST strobes.
            if (reset_p = '1') then
                -- Global reset.
                fcs_valid <= '0';
                fcs_last  <= '0';
            elsif ((pad_valid = '1' and pad_ready = '1')
                or (fcs_ovr = '1' and fcs_ready = '1')) then
                -- Append each new data or FCS byte.
                fcs_valid <= '1';
                fcs_last  <= bool2bit(bcount = 3);
            elsif (fcs_ready = '1') then
                -- Mark previous byte as consumed.
                fcs_valid <= '0';
                fcs_last  <= '0';
            end if;

            -- Update the CRC word and output byte counter.
            if (reset_p = '1') then
                -- General reset.
                fcs_crc32 <= CRC_INIT;
                bcount    := 0;
            elsif (pad_valid = '1' and pad_ready = '1') then
                -- Normal data, update CRC.
                fcs_crc32 <= crc_next(fcs_crc32, pad_data);
                bcount    := 0;
            elsif (fcs_ovr = '1' and fcs_ready = '1') then
                -- Emit next byte from CRC.
                fcs_crc32 <= fcs_crc32(23 downto 0) & x"FF";
                if (bcount < 3) then
                    bcount := bcount + 1;
                else
                    bcount := 0;
                end if;
            end if;
        end if;
    end process;
end generate;

-- Final output stage
out_data  <= fcs_data;
gen_withmeta : if (META_WIDTH > 0) generate
    out_meta  <= fcs_meta;
end generate;
out_last  <= fcs_last;
out_valid <= fcs_valid;
fcs_ready <= out_ready;

end rtl;
