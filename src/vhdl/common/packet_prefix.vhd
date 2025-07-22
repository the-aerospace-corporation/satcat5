--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Prepends a packet with a byte.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.eth_frame_common.all;

entity packet_prefix is
    generic (
    PREFIX : byte_t := X"03");
    port (
    in_data   : in  byte_t;
    in_last   : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;

    out_data  : out byte_t;
    out_last  : out std_logic;
    out_valid : out std_logic := '0';
    out_ready : in  std_logic;

    refclk    : in  std_logic;
    reset_p   : in  std_logic);
end packet_prefix;

architecture packet_prefix of packet_prefix is

signal i_out_valid : std_logic := '0';
signal stream_en   : std_logic;
signal i_in_ready  : std_logic;
signal prepend     : boolean := true;
signal tmp_data    : byte_t;
signal tmp_valid   : std_logic := '0';
signal tmp_last    : std_logic;

begin

stream_en  <= out_ready or not i_out_valid;
i_in_ready <= stream_en and not tmp_valid;
in_ready   <= i_in_ready;
out_valid  <= i_out_valid;

p_prefix : process(refclk)
    variable v_out_valid : std_logic := '0';
    variable v_out_last  : std_logic := '0';
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            prepend     <= true;
            tmp_valid   <= '0';
            i_out_valid <= '0';
            v_out_valid := '0';
            v_out_last  := '0';
        elsif (stream_en = '1') then
            if prepend then
                -- Buffer the input
                if (tmp_valid = '0') then
                    tmp_data  <= in_data;
                    tmp_valid <= in_valid;
                    tmp_last  <= in_last;
                end if;

                -- Output prefix
                out_data    <= PREFIX;
                v_out_valid := '1';
                v_out_last  := '0';
                prepend     <= false;
            elsif (tmp_valid = '1') then
                -- Output buffer
                out_data    <= tmp_data;
                v_out_valid := tmp_valid;
                v_out_last  := tmp_last;
                -- Reset buffer
                tmp_valid   <= '0';
            else
                -- Output intput
                out_data    <= in_data;
                v_out_valid := in_valid;
                v_out_last  := in_last;
            end if;

            prepend     <= (v_out_valid = '1' and v_out_last = '1');
            i_out_valid <= v_out_valid;
            out_last    <= v_out_last;
        end if;
    end if;
end process;

end packet_prefix;
