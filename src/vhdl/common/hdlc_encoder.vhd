--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- HDLC Encoder
--
-- This module implements a simple version of the synchronous (bit stuffing)
-- HDLC framing protocol.
--
--  Features/limitations:
--      * Optional address field
--      * No control field
--      * Information field is optionally padded to a configurable block size
--      * 16 bit FCS (CRC-CCITT)
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity hdlc_encoder is
    generic (
    USE_ADDRESS  : boolean := false; -- Prepend in_addr?
    BLOCK_BYTES  : integer := -1);   -- If > 0 enable padding
    port (
    in_data     : in  byte_t;
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_addr     : in  byte_t := x"03"; -- Optional address
    in_ready    : out std_logic;

    out_data    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    clk         : in  std_logic;
    reset_p     : in  std_logic);
end hdlc_encoder;

architecture hdlc_encoder of hdlc_encoder is

constant MAX_ONES  : integer := 5;
constant MAX_IDX   : integer := byte_t'length - 1;

type state_t is (
    DELIM,
    ADDR,
    DATA,
    PAD,
    CRC);

signal state      : state_t;
signal next_state : state_t   := DELIM;
signal state_en   : std_logic := '0';

signal crc_result : crc16_word_t;

signal enc_in_data  : byte_t;
signal enc_in_valid : std_logic := '0';

signal idx : integer range 0 to MAX_IDX := MAX_IDX;

signal ones_count : integer range 0 to MAX_ONES := 0;

signal enc_out_data  : std_logic;
signal enc_out_valid : std_logic;

begin

-- Connect outputs
out_data  <= enc_out_data;
out_valid <= enc_out_valid;

state_en  <= bool2bit(idx = 0) and
             bool2bit(ones_count < MAX_ONES) and
             out_ready;
in_ready  <= '1' when (state_en = '1' and next_state = DATA) else
             (not enc_in_valid);

-- State machine for next byte, and doing byte-at-a-time CRC calculation
p_state : process(clk)
    variable first_byte : std_logic := '1';
    variable byte_count : integer := 0;
    variable crc_sel    : integer range 0 to 1 := 1;
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            enc_in_valid <= '0';
            next_state   <= DELIM;
            first_byte   := '1';
            byte_count   := 0;
            crc_sel      := 1;
        else
            if (state_en = '1') or (enc_in_valid = '0') then
                state <= next_state; -- Update current state for p_enc

                case next_state is
                when DELIM =>
                    -- Send frame delimeter to encoder
                    enc_in_data  <= HDLC_DELIM;
                    enc_in_valid <= '1';
                    first_byte   := '1';

                    -- Select next state
                    if USE_ADDRESS then
                        next_state <= ADDR;
                    else
                        next_state <= DATA;
                    end if;
                when ADDR =>
                    -- Send address field to encoder
                    enc_in_data  <= in_addr;
                    enc_in_valid <= '1';

                    -- Update CRC
                    crc_result   <= crc16_next(CRC16_INIT, in_addr);
                    first_byte   := '0';

                    -- Select next state
                    next_state   <= DATA;
                when DATA =>
                    -- Send input data to encoder
                    enc_in_data  <= in_data;
                    enc_in_valid <= in_valid;

                    if (in_valid = '1') then
                        -- Update CRC
                        if (first_byte = '1') then
                            crc_result <= crc16_next(CRC16_INIT, in_data);
                            first_byte := '0';
                        else
                            crc_result <= crc16_next(crc_result, in_data);
                        end if;

                        -- Increment byte count
                        byte_count := byte_count + 1;
                    end if;

                    -- Select next state
                    if (BLOCK_BYTES > 0) then
                        if (byte_count = BLOCK_BYTES) then
                            byte_count := 0;
                            next_state <= CRC;
                        elsif (in_last = '1') and (in_valid = '1') then
                            next_state <= PAD;
                        else
                            next_state <= DATA;
                        end if;
                    elsif (in_last = '1') and (in_valid = '1') then
                        next_state <= CRC;
                    else
                        next_state <= DATA;
                    end if;
                when PAD =>
                    -- Send zero padding to encoder
                    enc_in_data  <= (others => '0');
                    enc_in_valid <= '1';

                    -- Update CRC
                    crc_result <= crc16_next(crc_result, (others => '0'));

                    -- Increment byte count
                    byte_count := byte_count + 1;

                    -- Select next state
                    if (byte_count = BLOCK_BYTES) then
                        byte_count := 0;
                        next_state <= CRC;
                    else
                        next_state <= PAD;
                    end if;
                when CRC =>
                    -- Send a byte of CRC to encoder
                    enc_in_data <= crc_result(8*crc_sel + 7 downto 8*crc_sel);
                    enc_in_valid <= '1';

                    -- Select next state
                    if (crc_sel = 0) then
                        crc_sel := 1;
                        next_state <= DELIM;
                    else
                        crc_sel := 0;
                        next_state <= CRC;
                    end if;
                end case;
            end if;
        end if;
    end if;
end process;

-- Bit-by-bit encoder
p_enc : process(clk)
    function dec_idx(idx : integer) return integer is
        variable new_idx : integer range 0 to MAX_IDX;
    begin
        if (idx = 0) then
            new_idx := MAX_IDX;
        else
            new_idx := idx - 1;
        end if;
        return new_idx;
    end function;
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            enc_out_valid <= '0';
            idx           <= MAX_IDX;
            ones_count    <= 0;
        elsif (enc_in_valid = '1') then
            if (out_ready = '1') or (enc_out_valid = '0') then
                enc_out_valid <= '1';

                if (state = DELIM) then
                    enc_out_data <= enc_in_data(idx);
                    ones_count   <= 0;
                    idx          <= dec_idx(idx);
                else
                    --Encoding
                    if (ones_count = MAX_ONES) then
                        -- Bit stuff; don't decrement index
                        enc_out_data <= '0';
                        ones_count   <= 0;
                    else
                        -- Regular output
                        enc_out_data <= enc_in_data(idx);
                        idx          <= dec_idx(idx);

                        if (enc_in_data(idx) = '1') then
                            ones_count <= ones_count + 1;
                        else
                            ones_count <= 0;
                        end if;
                    end if;
                end if;
            end if;
        else
            enc_out_valid <= '0';
        end if;
    end if;
end process;

end hdlc_encoder;
