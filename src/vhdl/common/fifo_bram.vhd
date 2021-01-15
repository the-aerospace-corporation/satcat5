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
-- Simple BRAM FIFO
--
-- This is a simple FIFO for an input with no flow control and an output
-- with AXI valid/ready flow control.
--
-- Safety checks ensure overflow data is discarded safely.  For improved
-- timing, these can be disabled, but behavior on overflow is undefined.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_bram is
    generic (
    -- Maximum auxiliary packet size (bytes).
    FIFO_WIDTH  : integer;
    FIFO_DEPTH  : integer;
    -- Enable strict overflow error checks.
    FIFO_STRICT : boolean := false;
    -- Enable simulation warnings on overflow.
    OVR_WARNING : boolean := true);
    port (
    -- Primary input port (no flow control)
    in_data     : in  std_logic_vector(FIFO_WIDTH-1 downto 0);
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- Buffered output port (AXI flow control)
    out_data    : out std_logic_vector(FIFO_WIDTH-1 downto 0);
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- FIFO status signals
    fifo_error  : out std_logic;
    fifo_empty  : out std_logic;
    fifo_full   : out std_logic;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end fifo_bram;

architecture fifo_bram of fifo_bram is

-- Define FIFO size parameters.
constant FIFO_AWIDTH    : integer := log2_ceil(FIFO_DEPTH);
subtype fifo_addr_t is unsigned(FIFO_AWIDTH-1 downto 0);
subtype fifo_word_t is std_logic_vector(FIFO_WIDTH downto 0);

-- Status flags
signal fifo_error_i     : std_logic := '0';
signal fifo_empty_i     : std_logic := '1';
signal fifo_full_i      : std_logic := '0';

-- Primary input FIFO.
signal fifo_wr_addr     : fifo_addr_t := (others => '0');
signal fifo_wr_word     : fifo_word_t := (others => '0');
signal fifo_wr_safe     : std_logic;
signal fifo_wr_en       : std_logic;
signal fifo_rd_addr_d   : fifo_addr_t := (others => '0');
signal fifo_rd_addr_q   : fifo_addr_t := (others => '0');
signal fifo_rd_word     : fifo_word_t := (others => '0');
signal fifo_rd_next     : std_logic := '0';

begin

-- Drive top-level outputs.
out_data    <= fifo_rd_word(FIFO_WIDTH-1 downto 0);
out_last    <= fifo_rd_word(FIFO_WIDTH);
out_valid   <= not fifo_empty_i;
fifo_error  <= fifo_error_i;
fifo_empty  <= fifo_empty_i;
fifo_full   <= fifo_full_i;

-- Safety checks stop writes on overflow (optional)
fifo_wr_safe <= fifo_rd_next or not fifo_full_i;
fifo_wr_en   <= (in_write and fifo_wr_safe) when FIFO_STRICT else in_write;

-- Inferred dual-port block RAM for the input FIFO.
fifo_wr_word   <= in_last & in_data;
fifo_rd_next   <= out_ready and not fifo_empty_i;
fifo_rd_addr_d <= fifo_rd_addr_q + u2i(fifo_rd_next);

p_ram : process(clk)
    type fifo_ram_t is array(0 to 2**FIFO_AWIDTH-1) of fifo_word_t;
    variable dp_ram : fifo_ram_t := (others => (others => '0'));
begin
    if rising_edge(clk) then
        if (fifo_wr_en = '1') then
            dp_ram(to_integer(fifo_wr_addr)) := fifo_wr_word;
        end if;
        fifo_rd_word <= dp_ram(to_integer(fifo_rd_addr_d));
    end if;
end process;

-- Primary input FIFO control logic.
p_fifo : process(clk)
begin
    if rising_edge(clk) then
        -- Write address increments after writing each word.
        if (reset_p = '1') then
            fifo_wr_addr <= (others => '0');
        elsif (fifo_wr_en = '1') then
            fifo_wr_addr <= fifo_wr_addr + 1;
        end if;

        -- Read address increments after reading each word.
        if (reset_p = '1') then
            fifo_rd_addr_q <= (others => '0');
        else
            fifo_rd_addr_q <= fifo_rd_addr_d;
        end if;

        -- Precalculate the full and empty flags for better timing.
        if (reset_p = '1') then
            fifo_empty_i <= '1';
            fifo_full_i  <= '0';
        elsif (fifo_wr_en = '1' and fifo_rd_next = '0') then
            fifo_empty_i <= '0';
            fifo_full_i  <= bool2bit(fifo_wr_addr+1 = fifo_rd_addr_q);
        elsif (fifo_wr_en = '0' and fifo_rd_next = '1') then
            fifo_empty_i <= bool2bit(fifo_wr_addr = fifo_rd_addr_q+1);
            fifo_full_i  <= '0';
        end if;

        -- Check for overflow condition.
        if (in_write = '1' and fifo_rd_next = '0' and fifo_full_i = '1') then
            if (OVR_WARNING) then
                report "FIFO overflow" severity warning;
            end if;
            fifo_error_i <= '1';
        else
            fifo_error_i <= '0';
        end if;
    end if;
end process;

end fifo_bram;
