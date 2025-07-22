--------------------------------------------------------------------------
-- Copyright 2019-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- SLIP ENCODER
--
--  This modules takes in a byte of data and outputs a byte or bytes
--  of data corresponding to the Serial Line Internet Protocol
--  encoding. These bytes will be transmitted serially over the UART
--  or SPI.
--
--  SLIP Encoding includes END and ESC bytes (0xC0 and 0xDB) that
--  indicate the last byte in a series of bytes. Therefore, the
--  encoder takes in a "last" bit along with the data.
--
--  Data transfer uses AXI-stream flow control:
--  o in_valid means the upstream source is presenting an input byte.
--  o in_ready means the encoder can accept an input byte.
--  o out_valid means the encoder is presenting an output byte.
--  o out_ready means the downstream sink can accept an output byte.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity slip_encoder is
    generic (
    -- Extra inter-frame token on startup?
    -- (Recommended for most designs to ensure known initial state.)
    START_TOKEN : boolean := true);
    port (
    in_data     : in  byte_t;
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    out_data    : out byte_t;
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    refclk      : in  std_logic;
    reset_p     : in  std_logic);
end slip_encoder;

architecture slip_encoder of slip_encoder is

-- Encoder states for multi-byte sequences:
type encode_state_t is (
    NEXT_IDLE,      -- Idle or final byte in sequence
    NEXT_EOF,       -- Emitting data, next is EOF
    NEXT_ESC_END,   -- Emitting ESC, next is ESC_END
    NEXT_ESC_ESC);  -- Emitting ESC, next is ESC_ESC

function eof_or_idle(eof : boolean) return encode_state_t is
begin
    if eof then
        return NEXT_EOF;
    else
        return NEXT_IDLE;
    end if;
end function;

-- Combinational logic.
signal enc_cken     : std_logic;

-- Encoder state variables.
signal enc_data     : byte_t := SLIP_FEND;
signal enc_state    : encode_state_t := eof_or_idle(START_TOKEN);
signal enc_last     : std_logic := '0';
signal enc_valid    : std_logic := '0';

signal s_out_last   : std_logic := '0';

begin

-- Upstream and downstream flow control
enc_cken  <= out_ready or not enc_valid;
in_ready  <= enc_cken and bool2bit(enc_state = NEXT_IDLE);
out_valid <= enc_valid;
out_data  <= enc_data;
out_last  <= s_out_last;

-- Encoder state machine
p_enc : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            -- Encoder reset
            enc_data    <= SLIP_FEND;
            enc_state   <= eof_or_idle(START_TOKEN);
            enc_last    <= '0';
            enc_valid   <= '0';
            s_out_last  <= '0';
        elsif (enc_cken = '1') then
            -- Move to the next encoder state...
            if (enc_state = NEXT_EOF) then
                -- End-of-frame token.
                enc_data    <= SLIP_FEND;
                enc_state   <= NEXT_IDLE;
                enc_valid   <= '1';
                s_out_last  <= '1';
            elsif (enc_state = NEXT_ESC_END) then
                -- Second half of escape sequence.
                enc_data    <= SLIP_ESC_END;
                enc_state   <= eof_or_idle(enc_last = '1');
                enc_valid   <= '1';
            elsif (enc_state = NEXT_ESC_ESC) then
                -- Second half of escape sequence.
                enc_data    <= SLIP_ESC_ESC;
                enc_state   <= eof_or_idle(enc_last = '1');
                enc_valid   <= '1';
            elsif (in_valid = '0') then
                -- Waiting for next input.
                enc_data    <= SLIP_FEND;
                enc_state   <= NEXT_IDLE;
                enc_last    <= 'X';
                enc_valid   <= '0';
            elsif (in_data = SLIP_FEND) then
                -- Input data requires an escape sequence.
                enc_data    <= SLIP_ESC;
                enc_state   <= NEXT_ESC_END;
                enc_last    <= in_last;
                enc_valid   <= '1';
            elsif (in_data = SLIP_ESC) then
                -- Input data requires an escape sequence.
                enc_data    <= SLIP_ESC;
                enc_state   <= NEXT_ESC_ESC;
                enc_last    <= in_last;
                enc_valid   <= '1';
            else
                -- Ordinary input data.
                enc_data    <= in_data;
                enc_state   <= eof_or_idle(in_last = '1');
                enc_last    <= in_last;
                enc_valid   <= '1';
                s_out_last  <= '0';
            end if;
        end if;
    end if;
end process;

end slip_encoder;
