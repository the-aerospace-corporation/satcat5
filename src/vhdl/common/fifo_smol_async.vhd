--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- LUTRAM-based asynchronous FIFO
--
-- This is a lightweight FIFO block based on the platform-specific
-- LUTRAM primitive.  It provides separate read/write clock domains,
-- with AXI flow-control on each ports.
--
-- To allow alternate flow-control systems, the input port also provides
-- an "early" strobe.  When asserted, it is safe to write two consecutive
-- words to the FIFO.  (i.e., It is equivalent to a guarantee that the
-- "ready" strobe will also be asserted on the next clock cycle.
--
-- Maximum recommended size is 2^7 = 128 words.  Above that limit,
-- it is better to use a BRAM-based implementation.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity fifo_smol_async is
    generic (
    IO_WIDTH    : natural;              -- Word size
    META_WIDTH  : natural := 0;         -- Metadata size (optional)
    -- FIFO depth = 2^N words (default size is platform-specific)
    DEPTH_LOG2  : positive := PREFER_DPRAM_AWIDTH);
    port (
    -- Input port
    in_clk      : in  std_logic;
    in_data     : in  std_logic_vector(IO_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last     : in  std_logic := '0'; -- Last word in frame (OPTIONAL)
    in_valid    : in  std_logic;
    in_ready    : out std_logic;
    in_early    : out std_logic;        -- Guarantee next-cycle ready?

    -- Output port
    out_clk     : in  std_logic;
    out_data    : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last    : out std_logic;        -- Last word in frame (OPTIONAL)
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Shared asynchronous reset.
    reset_p     : in  std_logic);
end fifo_smol_async;

architecture fifo_smol_async of fifo_smol_async is

-- FIFO word is concatentation of data, metadata, and last flag.
subtype data_t is std_logic_vector(IO_WIDTH + META_WIDTH downto 0);

-- All addresses are N-bit Gray-codes, so that delay differences in
-- asynchronous sampling never result in an error.
-- (i.e., Might get the "early" or "late" version but both are valid.)
constant DEPTH : positive := 2**DEPTH_LOG2;
subtype addr_t is unsigned(DEPTH_LOG2-1 downto 0);
type addr_table is array(DEPTH-1 downto 0) of addr_t;

-- Gray-code indexing (aka reflected binary code)
function idx2gray(n: natural) return addr_t is
    constant n0 : addr_t := to_unsigned(n, DEPTH_LOG2);
    constant n1 : addr_t := shift_right(n0, 1);
    constant gr : addr_t := n0 xor n1;
begin
    return gr;
end function;

-- Construct an increment-by-one lookup table.
function create_incr_table return addr_table is
    variable n0, n1 : addr_t := (others => '0');
    variable table  : addr_table;
begin
    for n in 0 to DEPTH-1 loop
        n0 := idx2gray(n);
        n1 := idx2gray((n+1) mod DEPTH);
        table(to_integer(n0)) := n1;
    end loop;
    return table;
end function;

constant incr_table : addr_table := create_incr_table;

-- Write-side control.
signal wr_reset : std_logic;                    -- Sync reset
signal wr_full  : std_logic := '0';             -- FIFO full?
signal wr_afull : std_logic := '0';             -- FIFO almost-full?
signal wr_data  : data_t;                       -- Data + metadata
signal wr_addr  : addr_t := (others => '0');    -- Write address
signal wr_next1 : addr_t := (others => '0');    -- Write address + 1
signal wr_next2 : addr_t;                       -- Write address + 2
signal wr_limit : addr_t;                       -- Sync'd read address
signal wr_incr  : std_logic;                    -- Write-enable

-- Read-side control.
signal rd_reset : std_logic;                    -- Sync reset
signal rd_valid : std_logic := '0';             -- FIFO non-empty?
signal rd_data  : data_t;                       -- Data + metadata
signal rd_addr  : addr_t := (others => '0');    -- Read address
signal rd_next  : addr_t;                       -- Read address + 1
signal rd_limit : addr_t;                       -- Sync'd write address
signal rd_incr  : std_logic;                    -- Read-enable

begin

-- Generate synchronous reset strobes.
u_rst_wr : sync_reset
    generic map(HOLD_MIN => 3)
    port map(
    in_reset_p  => reset_p,
    out_reset_p => wr_reset,
    out_clk     => in_clk);
u_rst_rd : sync_reset
    generic map(HOLD_MIN => 3)
    port map(
    in_reset_p  => reset_p,
    out_reset_p => rd_reset,
    out_clk     => out_clk);

-- Write-side control.
wr_data  <= in_last & in_meta & in_data;
wr_next1 <= incr_table(to_integer(wr_addr));
wr_next2 <= incr_table(to_integer(wr_next1));
wr_incr  <= in_valid and not wr_full;

p_wr : process(in_clk, wr_reset)
begin
    if (wr_reset = '1') then
        wr_addr  <= (others => '0');
        wr_full  <= '0';
        wr_afull <= '0';
    elsif rising_edge(in_clk) then
        if (wr_incr = '1') then
            wr_addr  <= wr_next1;
            wr_full  <= bool2bit(wr_next1 = wr_limit);
            wr_afull <= bool2bit(wr_next1 = wr_limit)
                     or bool2bit(wr_next2 = wr_limit);
        elsif (wr_addr /= wr_limit) then
            wr_full  <= '0';
            wr_afull <= bool2bit(wr_next1 = wr_limit);
        end if;
    end if;
end process;

-- Memory block is implemented using LUTRAM.
u_lutram : dpram
    generic map(
    AWIDTH  => DEPTH_LOG2,
    DWIDTH  => IO_WIDTH + META_WIDTH + 1)
    port map(
    wr_clk  => in_clk,
    wr_addr => wr_addr,
    wr_en   => wr_incr,
    wr_val  => wr_data,
    rd_clk  => out_clk,
    rd_addr => rd_next,
    rd_val  => rd_data);

-- Cross-clock synchronization of each address word.
gen_sync : for n in wr_addr'range generate
    u_r2w : sync_buffer
        port map(
        in_flag     => rd_addr(n),
        out_flag    => wr_limit(n),
        out_clk     => in_clk);
    u_w2r : sync_buffer
        port map(
        in_flag     => wr_addr(n),
        out_flag    => rd_limit(n),
        out_clk     => out_clk);
end generate;

-- Read-side control.
rd_incr <= rd_valid and out_ready;
rd_next <= incr_table(to_integer(rd_addr)) when (rd_incr = '1') else rd_addr;

p_rd : process(out_clk, rd_reset)
begin
    if (rd_reset = '1') then
        rd_addr  <= (others => '0');
        rd_valid <= '0';
    elsif rising_edge(out_clk) then
        rd_addr  <= rd_next;
        if (rd_incr = '1') then 
            rd_valid <= bool2bit(rd_next /= rd_limit);
        elsif (rd_addr /= rd_limit) then
            rd_valid <= '1';
        end if;
    end if;
end process;

-- Drive top-level outputs.
in_ready    <= not (wr_reset or wr_full);
in_early    <= not (wr_reset or wr_afull);
out_last    <= rd_data(META_WIDTH+IO_WIDTH);
out_valid   <= rd_valid;

gen_out_data : if IO_WIDTH > 0 generate
    out_data <= rd_data(IO_WIDTH-1 downto 0);
end generate;

gen_out_meta : if META_WIDTH > 0 generate
    out_meta <= rd_data(META_WIDTH+IO_WIDTH-1 downto IO_WIDTH);
end generate;

end fifo_smol_async;
