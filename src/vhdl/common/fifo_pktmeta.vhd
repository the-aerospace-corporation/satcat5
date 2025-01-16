--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Synchronous packet metadata FIFO
--
-- In some cases, packet metadata cannot be fully determined until the
-- entire packet is processed, such as the length of an incoming packet.
--
-- However, downstream blocks may need access to that metadata at the
-- *beginning* of the packet, in order to perform their own processing.
-- This FIFO resolves that conundrum by buffering a full frame of data,
-- operating a smaller FIFO for packet metadata, and blocking reads
-- until both streams are ready.
--
-- Since this FIFO may be used in different circumstances, the input
-- accepts either "write" or "valid/ready" flow control signals.
-- Choose one or the other; do not use both simultaneously.
--
-- The output always uses AXI-stream "valid/ready" signals, but can be
-- readily converted to "write" mode by tying "ready" to constant '1'.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity fifo_pktmeta is
    generic (
    IO_BYTES    : positive;             -- Width of datapath
    META_WIDTH  : natural := 0;         -- Optional metadata
    ALLOW_JUMBO : boolean := false;     -- Allow jumbo frames?
    ALLOW_RUNT  : boolean := false);    -- Allow runt frames?
    port (
    -- Input data stream (metadata sampled at end of frame)
    -- Note: Use "in_write" or "in_valid/in_ready", never both.
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic := '0';
    in_valid    : in  std_logic := '0';
    in_ready    : out std_logic;
    in_error    : out std_logic;    -- Optional
    -- Output data stream (metadata ready at start of frame)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_pktlen  : out unsigned(15 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;
    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end fifo_pktmeta;

architecture fifo_pktmeta of fifo_pktmeta is

-- Primary FIFO depth is equal to the maximum Ethernet frame size
-- (usually 1536 bytes), plus 10% margin, rounded up to the next power of two.
function depth_data_log2 return positive is
begin
    if ALLOW_JUMBO then
        return log2_ceil(div_ceil(11*MAX_JUMBO_BYTES, 10*IO_BYTES));
    else
        return log2_ceil(div_ceil(11*MAX_FRAME_BYTES, 10*IO_BYTES));
    end if;
end function;

-- Metadata FIFO depth is equal to the primary FIFO depth divided
-- by the minimum legal Ethernet frame size (usually 64 bytes).
function depth_meta_log2 return positive is
    constant FIFO_WORDS : integer := 2**depth_data_log2;
    constant FULL_WORDS : positive := div_ceil(MIN_FRAME_BYTES, IO_BYTES);
    constant RUNT_WORDS : positive := div_ceil(MIN_RUNT_BYTES, IO_BYTES);
begin
    if ALLOW_RUNT then
        return log2_ceil(div_ceil(FIFO_WORDS, RUNT_WORDS));
    else
        return log2_ceil(div_ceil(FIFO_WORDS, FULL_WORDS));
    end if;
end function;

-- Total width of internally-generated metadata:
constant NLAST_WIDTH : positive := log2_ceil(IO_BYTES+1);
constant IMETA_WIDTH : positive := NLAST_WIDTH + 16;

-- Internal state:
signal in_count_d   : unsigned(15 downto 0);
signal in_count_q   : unsigned(15 downto 0) := (others => '0');
signal in_ready_i   : std_logic;
signal data_error   : std_logic;
signal data_last    : std_logic;
signal data_ready   : std_logic;
signal data_valid   : std_logic;
signal data_write   : std_logic;
signal meta_din     : std_logic_vector(IMETA_WIDTH-1 downto 0);
signal meta_dout    : std_logic_vector(IMETA_WIDTH-1 downto 0);
signal meta_error   : std_logic;
signal meta_nlast   : unsigned(NLAST_WIDTH-1 downto 0);
signal meta_ready   : std_logic;
signal meta_valid   : std_logic;
signal out_last     : std_logic;

begin

-- Top-level interface conversions:
in_count_d  <= in_count_q + in_nlast;
data_last   <= data_write and bool2bit(in_nlast > 0);
data_write  <= (in_write) or (in_valid and in_ready_i);
in_ready    <= in_ready_i;
in_error    <= data_error or meta_error;
meta_din    <= i2s(in_nlast, NLAST_WIDTH) & std_logic_vector(in_count_d);
meta_nlast  <= unsigned(meta_dout(NLAST_WIDTH+15 downto 16));
out_nlast   <= to_integer(meta_nlast) when (out_last = '1') else 0;
out_pktlen  <= unsigned(meta_dout(15 downto 0));

-- Count length of each input frame:
p_count : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            in_count_q <= (others => '0');          -- Global reset
        elsif (data_last = '1') then
            in_count_q <= (others => '0');          -- Start new frame
        elsif (data_write = '1') then
            in_count_q <= in_count_q + IO_BYTES;    -- Running count
        end if;
    end if;
end process;

-- Bulk data FIFO:
u_data : entity work.fifo_large_sync
    generic map(
    FIFO_DEPTH  => 2**depth_data_log2,
    FIFO_WIDTH  => 8*IO_BYTES)
    port map(
    in_data     => in_data,
    in_last     => data_last,
    in_write    => in_write,
    in_valid    => in_valid,
    in_ready    => in_ready_i,
    in_error    => data_error,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => data_valid,
    out_ready   => data_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Metadata FIFO:
u_meta : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => IMETA_WIDTH,
    META_WIDTH  => META_WIDTH,
    DEPTH_LOG2  => depth_meta_log2)
    port map(
    in_data     => meta_din,
    in_meta     => in_meta,
    in_write    => data_last,
    out_data    => meta_dout,
    out_meta    => out_meta,
    out_valid   => meta_valid,
    out_read    => meta_ready,
    fifo_error  => meta_error,
    clk         => clk,
    reset_p     => reset_p);

-- Flow control interlock: Withhold output until both are ready.
data_ready  <= data_valid and meta_valid and out_ready;
meta_ready  <= data_ready and out_last;
out_valid   <= data_valid and meta_valid;

end fifo_pktmeta;
