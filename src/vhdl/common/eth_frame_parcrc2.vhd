--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Parallel or single-byte calculation of Ethernet CRC/FCS
--
-- This block is a drop-in-replacement for the "eth_frame_parcrc" block.
-- It is identical in function, but it automatically reverts to a simpler
-- byte-at-a-time algorithm if IO_BYTES=1.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_parcrc2 is
    generic (
    IO_BYTES    : positive := 1);   -- I/O width for frame data
    port (
    -- Input data stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES := 0;
    in_write    : in  std_logic;
    in_error    : in  std_logic := '0';

    -- Early copy of output stream
    dly_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    dly_nlast   : out integer range 0 to IO_BYTES;
    dly_write   : out std_logic;

    -- Output is delayed input stream + calculated FCS.
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_crc     : out crc_word_t;   -- Normal format for FCS
    out_res     : out crc_word_t;   -- Residue format for verification
    out_error   : out std_logic;
    out_nlast   : out integer range 0 to IO_BYTES;
    out_write   : out std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_parcrc2;

architecture eth_frame_parcrc2 of eth_frame_parcrc2 is

-- Intermediate variables used for single-byte mode.
signal crc_result   : crc_word_t := CRC_INIT;
signal crc_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal crc_nlast    : integer range 0 to IO_BYTES := 0;
signal crc_error    : std_logic := '0';
signal crc_write    : std_logic := '0';

begin

-- Use the simpler algorithm?
gen0 : if IO_BYTES = 1 generate
    -- No delay necessary for the "early" signals.
    dly_data    <= in_data;
    dly_nlast   <= in_nlast;
    dly_write   <= in_write;
    
    -- Byte-at-a-time CRC calculation.
    p_crc : process(clk)
        variable first_byte : std_logic := '1';
    begin
        if rising_edge(clk) then
            -- Matched-delay buffer.
            crc_data  <= in_data;
            crc_error <= in_error;
            crc_nlast <= in_nlast;
            crc_write <= in_write;
    
            -- Update CRC whenever we receive new data.
            if (in_write = '1') then
                if (first_byte = '1') then
                    crc_result <= crc_next(CRC_INIT, in_data);
                else
                    crc_result <= crc_next(crc_result, in_data);
                end if;
            end if;
    
            -- Set the "first-byte" flag after reset or end-of-frame.
            if (reset_p = '1') then
                first_byte := '1';
            elsif (in_write = '1') then
                first_byte := bool2bit(in_nlast > 0);
            end if;
        end if;
    end process;
    
    -- Final output conversion.
    out_data  <= crc_data;
    out_crc   <= flip_bits_each_byte(not crc_result);
    out_res   <= crc_result;
    out_error <= crc_error;
    out_nlast <= crc_nlast;
    out_write <= crc_write;
end generate;

-- Use the parallel algorithm?
gen1 : if IO_BYTES > 1 generate
    u_crc : entity work.eth_frame_parcrc
        generic map(IO_BYTES => IO_BYTES)
        port map(
        in_data     => in_data,
        in_nlast    => in_nlast,
        in_write    => in_write,
        in_error    => in_error,
        dly_data    => dly_data,
        dly_nlast   => dly_nlast,
        dly_write   => dly_write,
        out_data    => out_data,
        out_crc     => out_crc,
        out_res     => out_res,
        out_error   => out_error,
        out_nlast   => out_nlast,
        out_write   => out_write,
        clk         => clk,
        reset_p     => reset_p);
end generate;

end eth_frame_parcrc2;
