--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- HDLC Encoder
--
-- This module implements a simple version of the synchronous (bit stuffing)
-- HDLC framing protocol.
--
-- HDLC frame format:
-- [ FLAG     ][ ADDRESS  ][ CONTROL  ][ INFO     ][ FCS     ][ FLAG     ]
-- [ 01111110 ][ 0+ bytes ][ 0+ bytes ][ 1+ bytes ][ 2 bytes ][ 01111110 ]
--
--  Features/limitations:
--      * ADDRESS and CONTROL fields are NOT implemented.
--      * Frame is transmitted from left to right, with each field transmitted
--        most significant byte first.
--      * Bit order is configurable.
--      * If FRAME_BYTES is positive, the INFO field is split into frames of a
--        fixed number of bytes. If in_last is asserted early, the INFO field
--        will be zero padded.
--      * If FRAME_BYTES is zero, the INFO field is variable length and relies
--        on the in_last signal to denote the end of a frame.
--      * A 16 bit FCS (CRC-CCITT) is appended to each frame.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity hdlc_encoder is
    generic (
    FRAME_BYTES : natural := 0;      -- bytes per frame excluding flags/FCS
    MSB_FIRST   : boolean := false); -- false for LSb first
    port (
    in_data   : in  byte_t;
    in_valid  : in  std_logic;
    in_last   : in  std_logic;
    in_ready  : out std_logic;

    out_data  : out std_logic;
    out_valid : out std_logic;
    out_last  : out std_logic; -- Asserted on last bit of end flag.
    out_ready : in  std_logic;

    clk       : in  std_logic;
    reset_p   : in  std_logic);
end hdlc_encoder;

architecture hdlc_encoder of hdlc_encoder is

constant MAX_ONES  : integer := 5;
constant MAX_IDX   : integer := byte_t'length - 1;
constant CRC_BYTES : integer := crc16_word_t'length / 8;

type state_t is (
    START_FLAG,
    DATA, -- Address, Control, or Info field
    PAD,
    FCS,
    END_FLAG);

-- State machine signals
signal state       : state_t;
signal next_state  : state_t := START_FLAG;
signal state_en    : std_logic;
signal crc_result  : crc16_word_t;

-- Encoder signals
signal enc_in_data   : byte_t;
signal enc_in_valid  : std_logic := '0';
signal enc_in_last   : std_logic := '0';
signal enc_in_ready  : std_logic;
signal enc_en        : std_logic;
signal enc_done      : std_logic;
signal init_idx      : integer range 0 to MAX_IDX;
signal idx           : integer range 0 to MAX_IDX;
signal ones_count    : integer range 0 to MAX_ONES := 0;
signal enc_out_valid : std_logic := '0';

begin

gen_msb : if MSB_FIRST generate
    init_idx <= MAX_IDX;
end generate;

gen_lsb : if not MSB_FIRST generate
    init_idx <= 0;
end generate;

state_en <= enc_in_ready or not enc_in_valid;
in_ready <= state_en and bool2bit(next_state = DATA);

-- State machine for next byte, and doing byte-at-a-time CRC calculation
p_state : process(clk)
    variable first_crc  : std_logic := '1';
    variable data_count : integer range 0 to FRAME_BYTES := 0;
    variable crc_count  : integer range 0 to CRC_BYTES  := 0;
    variable crc_byte   : byte_t;

    procedure encode_next_byte(data       : byte_t;
                               valid      : std_logic;
                               last       : std_logic;
                               update_crc : boolean) is
    begin
        enc_in_data  <= data;
        enc_in_valid <= valid;
        enc_in_last  <= last;

        if update_crc then
            if (valid = '1') then
                if (first_crc = '1') then
                    crc_result <= crc16_next(CRC16_INIT, data);
                    first_crc  := '0';
                else
                    crc_result <= crc16_next(crc_result, data);
                end if;
            end if;
        else
            first_crc := '1';
        end if;
    end procedure;

begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            next_state   <= START_FLAG;
            enc_in_valid <= '0';
            enc_in_last  <= '0';
            first_crc    := '1';
            data_count   := 0;
            crc_count    := 0;
        else
            if (state_en = '1') then
                state <= next_state; -- Update current state for p_enc

                case next_state is
                when START_FLAG =>
                    -- Send frame delimeter to encoder
                    encode_next_byte(HDLC_FLAG, '1', '0', false);

                    -- Select next state
                    next_state <= DATA;
                when DATA =>
                    -- Send input data to encoder
                    encode_next_byte(in_data, in_valid, '0', true);

                    if (in_valid = '1') then
                        -- Select next state
                        if (FRAME_BYTES = 0) then
                            -- Variable length frame
                            if (in_last = '1') then
                                next_state <= FCS;
                            end if;
                        else
                            -- Fixed length frame
                            data_count := data_count + 1;
                            if (data_count = FRAME_BYTES) then
                                data_count := 0;
                                next_state <= FCS;
                            elsif (in_last = '1') then
                                next_state <= PAD;
                            end if;
                        end if;
                    end if;
                when PAD =>
                    -- Send zeros to encoder
                    encode_next_byte(x"00", '1', '0', true);

                    -- Select next state
                    data_count := data_count + 1;
                    if (data_count = FRAME_BYTES) then
                        data_count := 0;
                        next_state <= FCS;
                    end if;
                when FCS =>
                    -- Send a byte of CRC to encoder
                    crc_byte := crc_result(8*(CRC_BYTES-crc_count)-1 downto
                                           8*(CRC_BYTES-(crc_count+1)));
                    encode_next_byte(crc_byte, '1', '0', false);

                    -- Select next state
                    crc_count := crc_count + 1;
                    if (crc_count = CRC_BYTES) then
                        crc_count  := 0;
                        next_state <= END_FLAG;
                    end if;
                when END_FLAG =>
                    -- Send frame delimeter to encoder
                    encode_next_byte(HDLC_FLAG, '1', '1', false);

                    -- Select next state
                    next_state <= START_FLAG;
                end case;
            end if;
        end if;
    end if;
end process;

enc_en       <= out_ready or not enc_out_valid;
enc_done     <= bool2bit(idx = (MAX_IDX - init_idx))
            and bool2bit(ones_count < MAX_ONES);
enc_in_ready <= enc_en and enc_done;

out_valid <= enc_out_valid;

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

    function inc_idx(idx : integer) return integer is
        variable new_idx : integer range 0 to MAX_IDX;
    begin
        if (idx = MAX_IDX) then
            new_idx := 0;
        else
            new_idx := idx + 1;
        end if;
        return new_idx;
    end function;

    function handle_idx(idx : integer) return integer is
    begin
        if MSB_FIRST then
            return dec_idx(idx);
        else
            return inc_idx(idx);
        end if;
    end function;
begin
    if rising_edge(clk) then
        -- Set valid and last
        if (reset_p = '1') then
            enc_out_valid <= '0';
            out_last <= '0';
        elsif (enc_en = '1') then
            enc_out_valid <= enc_in_valid;
            out_last <= enc_in_last and enc_done;
        end if;

        -- Set data
        if (reset_p = '1') then
            ones_count    <= 0;
            idx           <= init_idx;
        elsif (enc_en = '1') and (enc_in_valid = '1') then
            if (state = START_FLAG) or (state = END_FLAG) then
                -- Delimeter bit; reset ones count
                out_data   <= enc_in_data(idx);
                ones_count <= 0;
                idx        <= handle_idx(idx);
            elsif (ones_count = MAX_ONES) then
                -- Bit stuff; don't adjust index
                out_data   <= '0';
                ones_count <= 0;
            else
                -- Regular output; check ones and adjust index
                out_data <= enc_in_data(idx);

                if (enc_in_data(idx) = '1') then
                    ones_count <= ones_count + 1;
                else
                    ones_count <= 0;
                end if;

                idx <= handle_idx(idx);
            end if;
        end if;
    end if;
end process;

end hdlc_encoder;
