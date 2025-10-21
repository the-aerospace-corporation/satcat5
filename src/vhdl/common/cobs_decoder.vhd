--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Constant Overhead Byte Stuffing (COBS) Decoder
--
-- Consistent Overhead Byte Stuffing (COBS) is a packet-delimiting protocol.
-- Its function is similar to SLIP, with equivalent *average* overhead but
-- much better worst-case: just ceil(n/254) additional bytes vs. SLIP's
-- potential to double packet length in extreme cases. See "slip_decoder.vhd".
--
-- This block accepts a COBS-encoded stream of bytes, decoding the original
-- byte stream with packet boundaries. Both sides use simple "write" strobes
-- with no backpressure. No buffering is required.
--
-- See also:
-- https://en.wikipedia.org/wiki/Consistent_Overhead_Byte_Stuffing
-- http://www.stuartcheshire.org/papers/COBSforToN.pdf
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity cobs_decoder is
    port(
    -- Input byte-stream
    in_data     : in  byte_t;
    in_write    : in  std_logic;

    -- Output byte-stream
    out_data    : out byte_t;
    out_last    : out std_logic;
    out_write   : out std_logic;
    out_result  : out frm_result_t;

    -- Clock & Reset
    clk         : in std_logic;
    reset_p     : in std_logic := '0');
end cobs_decoder;

architecture cobs_decoder of cobs_decoder is

constant COBS_END   : byte_t := (others => '0');
constant COBS_MAX   : byte_t := (others => '1');
constant DONT_CARE  : byte_t := (others => '-');
type blk_t is (BLK_EMPTY, BLK_DATA, BLK_TERM);

signal dec_data     : byte_t := (others => '0');
signal dec_rem      : byte_u := (others => '0');
signal dec_type     : blk_t := BLK_EMPTY;
signal dec_valid    : std_logic := '0';
signal dec_eof      : std_logic := '0';
signal dec_err      : std_logic := '0';
signal dec_write    : std_logic := '0';

signal fin_data     : byte_t := (others => '0');
signal fin_write    : std_logic := '0';
signal fin_result   : frm_result_t := FRM_RESULT_NULL;

begin

-- Drive block-level outputs:
out_data    <= fin_data;
out_last    <= fin_result.commit or fin_result.revert;
out_write   <= fin_write;
out_result  <= fin_result;

-- Decoder state machine:
p_decode : process(clk)
begin
    if rising_edge(clk) then
        -- Align end-of-frame strobes with the final byte.
        fin_data    <= dec_data;
        fin_write   <= in_write and dec_valid;
        if (reset_p = '1' or in_write = '0' or in_data /= COBS_END) then
            fin_result <= FRM_RESULT_NULL;      -- Idle
        elsif (dec_type = BLK_EMPTY) then
            fin_result <= FRM_RESULT_NULL;      -- Empty frame
        elsif (dec_rem = 0) then
            fin_result <= FRM_RESULT_COMMIT;    -- Valid frame
        else
            fin_result <= frm_result_error(DROP_BADFRM);
        end if;

        -- Update decoder state after each byte.
        if (reset_p = '1') then
            -- System reset.
            dec_data    <= DONT_CARE;
            dec_rem     <= (others => '0');
            dec_type    <= BLK_EMPTY;
            dec_valid   <= '0';
        elsif (in_write = '1' and in_data = COBS_END) then
            -- End of frame token.
            dec_data    <= DONT_CARE;
            dec_rem     <= (others => '0');
            dec_type    <= BLK_EMPTY;
            dec_valid   <= '0';
        elsif (in_write = '1' and dec_rem > 0) then
            -- Countdown to end of segment.
            dec_data    <= in_data;
            dec_rem     <= dec_rem - 1;
            dec_valid   <= '1';
        elsif (in_write = '1' and in_data = COBS_MAX) then
            -- Read segment length (unterminated).
            dec_data    <= COBS_END;
            dec_rem     <= unsigned(in_data) - 1;
            dec_type    <= BLK_DATA;
            dec_valid   <= bool2bit(dec_type = BLK_TERM);
        elsif (in_write = '1') then
            -- Read segment length (zero-terminated).
            dec_data    <= COBS_END;
            dec_rem     <= unsigned(in_data) - 1;
            dec_type    <= BLK_TERM;
            dec_valid   <= bool2bit(dec_type = BLK_TERM);
        end if;
    end if;
end process;

end cobs_decoder;
