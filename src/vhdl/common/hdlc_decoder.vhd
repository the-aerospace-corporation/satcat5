--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
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
    USE_ADDRESS : boolean := false);
    port(
    in_data     : in  std_logic;
    in_write    : in  std_logic;

    out_data    : out byte_t;
    out_write   : out std_logic;
    out_last    : out std_logic;
    out_error   : out std_logic;
    out_addr    : out byte_t;

    clk         : in  std_logic;
    reset_p     : in  std_logic);
end hdlc_decoder;

architecture hdlc_decoder of hdlc_decoder is

constant MAX_ONES : integer := 5;
constant MAX_IDX  : integer := byte_t'length - 1;

signal dec_data    : byte_t;
signal dec_write   : std_logic := '0';
signal dec_delim   : std_logic := '0';

signal dly1_data   : byte_t;
signal dly1_write  : std_logic := '0';
signal dly1_delim  : std_logic := '0';

signal dly2_data   : byte_t;
signal dly2_write  : std_logic := '0';
signal dly2_delim  : std_logic := '0';

signal dly3_data   : byte_t;
signal dly3_write  : std_logic := '0';
signal dly3_delim  : std_logic := '0';

signal s_out_write : std_logic := '0';
signal s_out_last  : std_logic := '0';
signal s_out_error : std_logic := '0';
signal s_out_addr  : byte_t;

signal crc_result  : crc16_word_t;
signal crc_ok      : std_logic := '0';

begin

s_out_write <= (dec_write or dec_delim) and dly3_write;
s_out_last  <= s_out_write and dec_delim;
s_out_error <= s_out_last and not crc_ok;

out_data  <= dly3_data;
out_write <= s_out_write and not (dly1_delim or dly2_delim or  dly3_delim);
out_last  <= s_out_last;
out_error <= s_out_error;
out_addr  <= s_out_addr;

p_reg : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            dly3_write  <= '0';
            dly3_delim  <= '0';
            dly2_write  <= '0';
            dly2_delim  <= '0';
            dly1_write  <= '0';
            dly1_delim  <= '0';
        elsif (dec_write = '1') or (dec_delim = '1') then
            dly1_data  <= dec_data;
            dly1_write <= dec_write;
            dly1_delim <= dec_delim;

            dly2_data  <= dly1_data;
            dly2_write <= dly1_write;
            dly2_delim <= dly1_delim;

            dly3_data  <= dly2_data;
            dly3_write <= dly2_write;
            dly3_delim <= dly2_delim;

            if USE_ADDRESS and dly3_delim = '1' and dly2_delim = '0' then
                dly3_write <= '0';
                s_out_addr <= dly2_data;
            end if;
        end if;
    end if;
end process;

p_decode : process(clk)
    variable delim_sreg : byte_t := (others => '0');
    variable idx        : integer range 0 to MAX_IDX  := MAX_IDX;
    variable ones_count : integer range 0 to MAX_ONES := 0;
begin
    if rising_edge(clk) then
        dec_write <= '0';
        dec_delim <= '0';

        if (reset_p = '1') then
            delim_sreg := (others => '0');
            idx        := MAX_IDX;
            ones_count := 0;
        elsif (in_write = '1') then
            delim_sreg    := shift_left(delim_sreg, 1);
            delim_sreg(0) := in_data;
            if (delim_sreg = HDLC_DELIM) then
                -- Flag detected frame delimeter
                dec_data   <= HDLC_DELIM;
                dec_delim  <= '1';
                idx        := MAX_IDX;
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

                if (idx = 0) then
                    -- Last bit in byte
                    dec_write <= '1';
                    idx := MAX_IDX;
                else
                    idx := idx - 1;
                end if;
            end if;
        end if;
    end if;
end process;

p_crc : process(clk)
begin
    if rising_edge(clk) then
        if (dec_write = '1') and (dly2_write = '1') then
            if (dly3_delim = '1') then
                crc_result <= crc16_next(CRC16_INIT, dly2_data);
            else
                crc_result <= crc16_next(crc_result, dly2_data);
            end if;
        end if;

        crc_ok <= bool2bit(dly2_data = crc_result(15 downto 8)) and
                  bool2bit(dly1_data = crc_result(7 downto 0));
    end if;
end process;

end hdlc_decoder;
