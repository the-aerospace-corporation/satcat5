--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Large synchronous FIFO
--
-- This block is a synchronous FIFO, suitable for depths of a few hundred
-- or a few thousand words, depending on available FPGA memory.
--
-- The input has no flow-control (write/last only), and the output has AXI
-- valid/ready flow control.  Implementation uses the DPRAM cross-platform
-- primitive (typically implemented as block-RAM), with control logic acting
-- as circular-buffer (aka ring-buffer).
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity fifo_large_sync is
    generic (
    -- Maximum auxiliary packet size (bytes).
    FIFO_DEPTH  : positive;
    FIFO_WIDTH  : positive;
    META_WIDTH  : natural := 0;
    -- Formal verification mode? (See common_primitives)
    SIMTEST     : boolean := false);
    port (
    -- Primary input port (no flow control)
    in_data     : in  std_logic_vector(FIFO_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last     : in  std_logic;
    in_write    : in  std_logic;
    in_error    : out std_logic;    -- Optional

    -- Buffered output port (AXI flow control)
    out_data    : out std_logic_vector(FIFO_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end fifo_large_sync;

architecture fifo_large_sync of fifo_large_sync is

-- Define FIFO size parameters.
constant FIFO_AWIDTH    : integer := log2_ceil(FIFO_DEPTH);
constant FIFO_DWIDTH    : integer := 1 + FIFO_WIDTH + META_WIDTH;
subtype fifo_addr_t is unsigned(FIFO_AWIDTH-1 downto 0);
subtype fifo_word_t is std_logic_vector(FIFO_DWIDTH-1 downto 0);

-- Status flags
signal fifo_error       : std_logic := '0';
signal fifo_empty       : std_logic := '1';
signal fifo_full        : std_logic := '0';

-- Primary input FIFO.
signal fifo_wr_addr     : fifo_addr_t := (others => '0');
signal fifo_wr_word     : fifo_word_t := (others => '0');
signal fifo_wr_safe     : std_logic;
signal fifo_wr_en_d     : std_logic;
signal fifo_wr_en_q     : std_logic := '0';
signal fifo_rd_addr_d   : fifo_addr_t := (others => '0');
signal fifo_rd_addr_q   : fifo_addr_t := (others => '0');
signal fifo_rd_word     : fifo_word_t := (others => '0');
signal fifo_rd_next     : std_logic := '0';

begin

-- Drive top-level outputs.
in_error    <= fifo_error;
out_data    <= fifo_rd_word(FIFO_WIDTH-1 downto 0);
out_meta    <= fifo_rd_word(META_WIDTH+FIFO_WIDTH-1 downto FIFO_WIDTH);
out_last    <= fifo_rd_word(META_WIDTH+FIFO_WIDTH);
out_valid   <= not fifo_empty;

-- Platform-specific dual-port block RAM.
fifo_wr_en_d   <= in_write;
fifo_wr_word   <= in_last & in_meta & in_data;
fifo_rd_next   <= out_ready and not fifo_empty;
fifo_rd_addr_d <= fifo_rd_addr_q + u2i(fifo_rd_next);

u_ram : dpram
    generic map(
    AWIDTH  => FIFO_AWIDTH,
    DWIDTH  => FIFO_DWIDTH,
    SIMTEST => SIMTEST)
    port map(
    wr_clk  => clk,
    wr_addr => fifo_wr_addr,
    wr_en   => fifo_wr_en_d,
    wr_val  => fifo_wr_word,
    rd_clk  => clk,
    rd_addr => fifo_rd_addr_d,
    rd_val  => fifo_rd_word);

-- Primary input FIFO control logic.
p_fifo : process(clk)
begin
    if rising_edge(clk) then
        -- Write address increments after writing each word.
        if (reset_p = '1') then
            fifo_wr_addr <= (others => '0');
        elsif (fifo_wr_en_d = '1') then
            fifo_wr_addr <= fifo_wr_addr + 1;
        end if;

        -- Read address increments after reading each word.
        -- Delay write-enable for cross-platform compatibility; behavior of
        -- simultaneous read/write to the same address is undefined.
        if (reset_p = '1') then
            fifo_rd_addr_q <= (others => '0');
            fifo_wr_en_q   <= '0';
        else
            fifo_rd_addr_q <= fifo_rd_addr_d;
            fifo_wr_en_q   <= fifo_wr_en_d;
        end if;

        -- Precalculate the full and empty flags for better timing.
        if (reset_p = '1') then
            fifo_empty  <= '1';
            fifo_full   <= '0';
        elsif (fifo_wr_en_q = '1' and fifo_rd_next = '0') then
            fifo_empty  <= '0';
            fifo_full   <= bool2bit(fifo_wr_addr = fifo_rd_addr_d);
        elsif (fifo_wr_en_q = '0' and fifo_rd_next = '1') then
            fifo_empty  <= bool2bit(fifo_wr_addr = fifo_rd_addr_d);
            fifo_full   <= '0';
        end if;

        -- Check for overflow condition.
        if (fifo_wr_en_q = '1' and fifo_rd_next = '0' and fifo_full = '1') then
            report "FIFO overflow" severity warning;
            fifo_error <= '1';
        else
            fifo_error <= '0';
        end if;
    end if;
end process;

end fifo_large_sync;
