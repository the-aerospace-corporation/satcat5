--------------------------------------------------------------------------
-- Copyright 2024-2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- HDLC Decoder
--
-- This module decodes a simple version of the synchronous (bit stuffing) HDLC
-- framing protocol. See hdlc_encoder.vhd for features and limitations.
--

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity hdlc_decoder is
    generic(
    BUFFER_KBYTES : positive;          -- Packet FIFO size (kilobytes)
    MSB_FIRST     : boolean := false); -- false for LSb first
    port(
    in_data   : in  std_logic;
    in_write  : in  std_logic;

    out_data  : out byte_t;
    out_write : out std_logic;
    out_last  : out std_logic;

    clk       : in  std_logic;
    reset_p   : in  std_logic);
end hdlc_decoder;

architecture hdlc_decoder of hdlc_decoder is

constant MAX_ONES : integer := 5;
constant MAX_IDX  : integer := byte_t'length - 1;

-- Decoded bytes
signal dec_data    : byte_t;
signal dec_write   : std_logic := '0';
signal dec_delim   : std_logic := '0';

-- Buffer 3 bytes to detect EOF and check 16 bit CRC
signal buff_data  : byte_array_t(2 downto 0) := (others => (others => '0'));
signal buff_write : std_logic_vector(2 downto 0) := (others => '0');
signal buff_delim : std_logic_vector(2 downto 0) := (others => '0');

signal crc_result  : crc16_word_t;
signal crc_ok      : std_logic := '0';

-- FIFO packet input
signal pkt_data   : byte_t;
signal pkt_write  : std_logic := '0';
signal pkt_last   : std_logic := '0';
signal pkt_commit : std_logic := '0';
signal pkt_revert : std_logic := '0';

begin

p_decode : process(clk)
    variable init_idx   : integer range 0 to MAX_IDX;
    variable idx        : integer range 0 to MAX_IDX;
    variable ones_count : integer range 0 to MAX_ONES := 0;
    variable delim_sreg : byte_t := (others => '0');

    -- Decrement index
    impure function dec_idx(idx : integer) return integer is
        variable new_idx : integer range 0 to MAX_IDX;
    begin
        if (idx = 0) then
            dec_write <= '1'; -- Last bit in byte
            new_idx   := MAX_IDX;
        else
            new_idx   := idx - 1;
        end if;
        return new_idx;
    end function;

    -- Increment index
    impure function inc_idx(idx : integer) return integer is
        variable new_idx : integer range 0 to MAX_IDX;
    begin
        if (idx = MAX_IDX) then
            dec_write <= '1'; -- Last bit in byte
            new_idx   := 0;
        else
            new_idx   := idx + 1;
        end if;
        return new_idx;
    end function;

    -- Decide how to handle index based on MSB_FIRST
    impure function handle_idx(idx : integer) return integer is
    begin
        if MSB_FIRST then
            return dec_idx(idx);
        else
            return inc_idx(idx);
        end if;
    end function;
begin
    if rising_edge(clk) then
        dec_write <= '0';
        dec_delim <= '0';

        if (reset_p = '1') then
            if MSB_FIRST then
                init_idx := MAX_IDX;
            else
                init_idx := 0;
            end if;

            idx        := init_idx;
            ones_count := 0;
            delim_sreg := (others => '0');
        elsif (in_write = '1') then
            delim_sreg    := shift_left(delim_sreg, 1);
            delim_sreg(0) := in_data;
            if (delim_sreg = HDLC_FLAG) then
                -- Flag detected frame delimeter
                dec_data   <= HDLC_FLAG;
                dec_delim  <= '1';
                idx        := init_idx;
                ones_count := 0;
            elsif (ones_count = MAX_ONES) then
                -- Skip stuffed bit
                ones_count := 0;
            else
                -- Insert bit
                dec_data(idx) <= in_data;

                if (in_data = '1') then
                    ones_count := ones_count + 1;
                else
                    ones_count := 0;
                end if;

                -- Increment/decrement index & set dec_write
                idx := handle_idx(idx);
            end if;
        end if;
    end if;
end process;

p_buffer : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            buff_data  <= (others => (others => '0'));
            buff_write <= (others => '0');
            buff_delim <= (others => '0');
        elsif (dec_write = '1') or (dec_delim = '1') then
            buff_data  <= buff_data(1 downto 0) & dec_data;
            buff_write <= buff_write(1 downto 0) & dec_write;
            buff_delim <= buff_delim(1 downto 0) & dec_delim;
        end if;
    end if;
end process;

p_crc : process(clk)
begin
    if rising_edge(clk) then
        if (dec_write = '1') and (buff_write(1) = '1') then
            if (buff_delim(2) = '1') then
                crc_result <= crc16_next(CRC16_INIT, buff_data(1));
            else
                crc_result <= crc16_next(crc_result, buff_data(1));
            end if;
        end if;

        crc_ok <= bool2bit(buff_data(1) = crc_result(15 downto 8)) and
                  bool2bit(buff_data(0) = crc_result(7 downto 0));
    end if;
end process;

pkt_data   <= buff_data(2);
pkt_write  <= (dec_write or dec_delim)
          and buff_write(2)
          and not or_reduce(buff_delim);

pkt_last   <= pkt_write and dec_delim;
pkt_commit <= pkt_last  and crc_ok;
pkt_revert <= pkt_last  and not crc_ok;

u_pkt : entity work.fifo_packet
    generic map(
    INPUT_BYTES   => 1,
    OUTPUT_BYTES  => 1,
    BUFFER_KBYTES => BUFFER_KBYTES)
    port map(
    in_clk         => clk,
    in_data        => pkt_data,
    in_last_commit => pkt_commit,
    in_last_revert => pkt_revert,
    in_write       => pkt_write,
    in_overflow    => open,
    out_clk        => clk,
    out_data       => out_data,
    out_last       => out_last,
    out_valid      => out_write,
    out_ready      => '1',
    out_overflow   => open,
    reset_p        => reset_p);

end hdlc_decoder;
