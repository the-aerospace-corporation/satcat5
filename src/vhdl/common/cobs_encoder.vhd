--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Constant Overhead Byte Stuffing (COBS) Encoder
--
-- Consistent Overhead Byte Stuffing (COBS) is a packet-delimiting protocol.
-- Its function is similar to SLIP, with equivalent *average* overhead but
-- much better worst-case: just ceil(n/254) additional bytes vs. SLIP's
-- potential to double packet length in extreme cases. See "slip_encoder.vhd".
--
-- This block accepts a packetized stream of bytes, and emits a COBS-encoded
-- stream of bytes, using AXI valid/ready strobes forflow control on each side.
-- Encoding uses a three-step process:
--  * Data is written to a lookahead state-machine to determine segment lengths.
--  * Data and segment-length metadata are routed through separate FIFOs.
--  * The two streams are recombined by an encoder state machine.
-- This ensures full throughput for all possible input sequences.
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

entity cobs_encoder is
    port (
    in_data     : in  byte_t;
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    out_data    : out byte_t;
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    clk         : in  std_logic;
    reset_p     : in  std_logic);
end cobs_encoder;

architecture cobs_encoder of cobs_encoder is

constant COBS_END   : byte_t := x"00";
constant COUNT_MAX  : byte_u := x"FD";
type blk_state is (BLK_FIRST, BLK_DATA, BLK_LONG, BLK_FINAL);
subtype meta_t is std_logic_vector(1 downto 0);

-- Lookahead state machine.
signal in_ready_i   : std_logic;
signal look_count   : byte_u := (others => '0');
signal look_meta    : meta_t;
signal look_incr    : std_logic;
signal look_write   : std_logic;

-- Data and segment-length FIFOs.
signal dly_data     : byte_t;
signal dly_last     : std_logic;
signal dly_valid    : std_logic;
signal dly_read     : std_logic;
signal len_word     : byte_t;
signal len_meta     : meta_t;
signal len_count    : byte_u;
signal len_valid    : std_logic;
signal len_read     : std_logic;

-- Encoder state machine.
signal enc_state    : blk_state := BLK_FIRST;
signal enc_count    : byte_u := (others => '0');
signal enc_data     : byte_t := (others => '0');
signal enc_valid    : std_logic := '0';
signal enc_next     : std_logic;

begin

-- Lookahead state machine, counts the run-length of each segment.
-- A segment ends at a zero byte, a run of 254 nonzero bytes, or end-of-frame.
look_incr   <= in_valid and in_ready_i;
look_meta   <= (0 => in_last, 1 => in_valid and bool2bit(in_data = COBS_END));
look_write  <= look_incr and bool2bit(
    (in_data = COBS_END) or (look_count = COUNT_MAX) or (in_last = '1'));

p_lookahead : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1' or look_write = '1') then
            look_count <= (others => '0');
        elsif (look_incr = '1') then
            look_count <= look_count + 1;
        end if;
    end if;
end process;

-- Separate data and segment-length FIFOs.
-- Note: Both FIFOs are the same size to handle the pathological case of a
-- long segment followed by many short segments (e.g., 254, 1, 1, 1, ...)
u_data : entity work.fifo_large_sync
    generic map(
    FIFO_DEPTH  => 256,
    FIFO_WIDTH  => 8)
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_valid    => in_valid,
    in_ready    => in_ready_i,
    out_data    => dly_data,
    out_last    => dly_last,
    out_valid   => dly_valid,
    out_ready   => dly_read,
    clk         => clk,
    reset_p     => reset_p);

u_meta : entity work.fifo_large_sync
    generic map(
    FIFO_DEPTH  => 256,
    FIFO_WIDTH  => 8,
    META_WIDTH  => len_meta'length)
    port map(
    in_data     => std_logic_vector(look_count),
    in_meta     => look_meta,
    in_write    => look_write,
    out_data    => len_word,
    out_meta    => len_meta,
    out_valid   => len_valid,
    out_ready   => len_read,
    clk         => clk,
    reset_p     => reset_p);

-- Encoder state machine.
enc_next <= (out_ready or not enc_valid) and bool2bit(
    (enc_state = BLK_FINAL) or
    (dly_valid = '1' and dly_last = '1') or
    (dly_valid = '1' and len_valid = '1') or
    (dly_valid = '1' and enc_count > 0));
dly_read <= enc_next and bool2bit(enc_state = BLK_DATA);
len_read <= enc_next and bool2bit((enc_state = BLK_FIRST) or (enc_state = BLK_LONG)
    or (enc_state = BLK_DATA and dly_valid = '1' and dly_data = COBS_END));
len_count <= unsigned(len_word);

p_encode : process(clk)
    function seg_len(x: byte_u; y: meta_t) return byte_u is
    begin
        return x; --??? + u2i(y = "00");
    end function;

    function seg_tok(x: byte_u; y: meta_t) return byte_t is
    begin
        if (x = COUNT_MAX and y(1) = '0') then
            return std_logic_vector(x + 2);     -- Max-length segment
        elsif (y = "01") then
            return std_logic_vector(x + 2);     -- Final segment
        else
            return std_logic_vector(x + 1);     -- Normal segment
        end if;
    end function;
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            -- System reset.
            enc_state   <= BLK_FIRST;
            enc_count   <= (others => '0');
            enc_data    <= (others => '0');
            enc_valid   <= '0';
        elsif (enc_next = '1') then
            -- Generate the next output byte.
            if (enc_state = BLK_FIRST or enc_state = BLK_LONG) then
                -- Start of first segment, or token insertion after a long run.
                enc_state   <= BLK_DATA;       -- Read N data bytes
                enc_count   <= seg_len(len_count, len_meta);
                enc_data    <= seg_tok(len_count, len_meta);
            elsif (enc_state = BLK_DATA and dly_last = '1') then
                -- End of frame. Special case if it's a zero token.
                assert (enc_count = 0)
                    report "Termination length mismatch." severity error;
                enc_state   <= BLK_FINAL;
                enc_count   <= (others => '0');
                if (dly_data = COBS_END) then
                    enc_data <= x"01";
                else
                    enc_data <= dly_data;
                end if;
            elsif (enc_state = BLK_DATA and dly_data = COBS_END) then
                -- Replace each zero token with the segment length.
                assert (enc_count = 0)
                    report "Segment length mismatch." severity error;
                enc_count   <= seg_len(len_count, len_meta);
                enc_data    <= seg_tok(len_count, len_meta);
            elsif (enc_state = BLK_DATA) then
                -- Continue reading normal data.
                enc_data    <= dly_data;
                if (enc_count > 0) then
                    enc_count <= enc_count - 1;
                else
                    enc_state <= BLK_LONG;
                end if;
            elsif (enc_state = BLK_FINAL) then
                -- Append end-of-frame token and revert to idle.
                enc_state   <= BLK_FIRST;
                enc_count   <= (others => '0');
                enc_data    <= COBS_END;
            end if;
            enc_valid <= '1';
        elsif (out_ready = '1') then
            -- Consume output byte without generating.
            enc_valid <= '0';
        end if;
    end if;
end process;

-- Drive top-level outputs.
in_ready    <= in_ready_i;
out_data    <= enc_data;
out_last    <= enc_valid and bool2bit(enc_data = COBS_END);
out_valid   <= enc_valid;

end cobs_encoder;
