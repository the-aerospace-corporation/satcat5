--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Asynchronous packet FIFO w/ priority queueing
--
-- This block is similar to fifo_packet, except that incoming data can
-- be sorted into low-priority or high-priority categories.  Each category
-- continues to operate with separate first-in / first-out queues, but in
-- the final output, high-priority packets will skip ahead of any queued
-- low-priority packets, regardless of original order.
--
-- The "nlast" indicator is asserted concurrently with the final word in each
-- frame.  (i.e., Any nonzero value indicates the end of the frame.)  In all
-- configurations, packet metadata (in_meta), the "keep" flag (in_last_keep),
-- and the "high-priority" flag (in_last_hipri) must be presented concurrently
-- with the end of the frame.
--
-- The optional "in_precommit" signal allows latency reduction in some cases,
-- by enabling cut-through.  See "fifo_packet.vhd" for additional requirements.
--
-- Output flow control uses standard AXI rules.  Packet metadata is presented
-- and held constant for the entire duration of each output frame.
--
-- Internally, the implementation is a wrapper for two fifo_packet instances,
-- with priority selection at the output.  Typically, the high-priority queue
-- is much smaller but is not used for bulk traffic, so there should rarely
-- be more than a handful of short frames waiting in that queue.
--
-- If BUFF_HI_KBYTES = 0, then the second FIFO is not instantiated.  The block
-- effectively reverts to regular fifo_packet behavior with no prioritization.
--
-- Optionally, high-priority frames that cannot fit in the high-priority queue
-- can "failover" to the low-priority queue.  This prevents a packet drop, but
-- also means that the packet will be delivered much later than expected.  (And
-- likely out-of-sequence compared to others in the same stream.)  This feature
-- is enabled by default.
--
-- (Unless BUFF_HI_KBYTES = 0, in which case it effectively reverts to basic
--  fifo_packet behavior with no prioritization.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;

entity fifo_priority is
    generic (
    INPUT_BYTES     : positive;             -- Width of input port
    OUTPUT_BYTES    : positive := 1;        -- Width of output port
    META_WIDTH      : natural := 0;         -- Width of packet metadata
    BUFF_HI_KBYTES  : natural;              -- High-priority buffer (kilobytes)
    BUFF_LO_KBYTES  : natural;              -- Low-priority buffer (kilobytes)
    MAX_PACKETS     : positive;             -- Maximum queued packets
    MAX_PKT_BYTES   : positive;             -- Maximum packet size (bytes)
    BUFF_FAILOVER   : boolean := true);     -- Allow failover? (see above)
    port (
    -- Input port does not use flow control.
    in_clk          : in  std_logic;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_meta         : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_nlast        : in  integer range 0 to INPUT_BYTES := INPUT_BYTES;
    in_precommit    : in  std_logic := '1'; -- Optional early-commit flag
    in_last_keep    : in  std_logic;        -- Keep or revert this packet?
    in_last_hipri   : in  std_logic;        -- High-priority packet?
    in_write        : in  std_logic;
    in_overflow     : out std_logic;        -- Warning strobe (invalid commit)
    in_reset        : out std_logic;        -- Reset sync'd to in_clk

    -- Output port uses AXI-style flow control.
    out_clk         : in  std_logic;
    out_data        : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    out_meta        : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast       : out integer range 0 to OUTPUT_BYTES;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_hipri       : out std_logic;        -- Identify output stream
    out_reset       : out std_logic;        -- Reset sync'd to out_clk

    -- Global asynchronous pause and reset.
    async_pause     : in  std_logic;
    reset_p         : in  std_logic);
end fifo_priority;

architecture fifo_priority of fifo_priority is

-- Priority queue enabled?
constant BUFF_HI_ENABLE : boolean := (BUFF_HI_KBYTES > 0);
-- Single-cycle delay for input to low-priority FIFO?
constant LO_DLY_ENABLE  : boolean := BUFF_HI_ENABLE and BUFF_FAILOVER;

-- Local type definitions
subtype inword_t is std_logic_vector(8*INPUT_BYTES-1 downto 0);
subtype outword_t is std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);

-- Synchronize various async inputs.
signal sync_pause       : std_logic;
signal sync_reset_i     : std_logic;
signal sync_reset_o     : std_logic;

-- Generate KEEP strobes for each input.
signal in_final         : std_logic;
signal in_prefinal      : std_logic;
signal hi_precommit     : std_logic;
signal lo_precommit     : std_logic;

-- One-cycle delay for the input stream.
signal dly_data         : inword_t := (others => '0');
signal dly_meta         : meta_t := (others => '0');
signal dly_nlast        : integer range 0 to INPUT_BYTES := INPUT_BYTES;
signal dly_precommit    : std_logic := '0';
signal dly_final        : std_logic := '0';
signal dly_write        : std_logic := '0';

-- Commit/revert and status strobes.
signal lo_select,   hi_select   : std_logic;
signal lo_commit,   hi_commit   : std_logic;
signal lo_revert,   hi_revert   : std_logic;

-- Output streams.
signal strm_sel                 : std_logic := '0';
signal lo_data,     hi_data     : outword_t := (others => '0');
signal lo_meta,     hi_meta     : meta_t := (others => '0');
signal lo_nlast,    hi_nlast    : integer range 0 to OUTPUT_BYTES := 0;
signal lo_valid,    hi_valid    : std_logic := '0';
signal lo_ready,    hi_ready    : std_logic := '0';
signal lo_overflow, hi_overflow : std_logic := '0';

begin

-- Top-level output signals.
in_reset    <= sync_reset_i;
out_reset   <= sync_reset_o;

-- Synchronize the PAUSE flag.
u_pause : sync_buffer
    port map(
    in_flag     => async_pause,
    out_flag    => sync_pause,
    out_clk     => out_clk);

-- Generate KEEP strobes for each input.
in_final      <= in_write and bool2bit(in_nlast > 0);
in_prefinal   <= (in_final or in_precommit) and in_last_keep;
hi_precommit  <= in_prefinal and bool2bit(in_last_hipri = '1' and BUFF_HI_ENABLE);
lo_precommit  <= in_prefinal and bool2bit(in_last_hipri = '0' or not BUFF_HI_ENABLE);

-- Delay inputs to the low-priority FIFO?
gen_dly1 : if LO_DLY_ENABLE generate
    -- Single-cycle delay is required for failover.
    p_delay : process(in_clk)
    begin
        if rising_edge(in_clk) then
            dly_data    <= in_data;
            dly_meta    <= in_meta;
            dly_nlast   <= in_nlast;
            dly_final   <= in_final;
            dly_write   <= in_write;
            dly_precommit <= lo_precommit;
        end if;
    end process;
end generate;

gen_dly0 : if not LO_DLY_ENABLE generate
    -- No delay required.
    dly_data    <= in_data;
    dly_meta    <= in_meta;
    dly_nlast   <= in_nlast;
    dly_final   <= in_final;
    dly_write   <= in_write;
    dly_precommit <= lo_precommit;
end generate;

-- Combinational logic for commit/revert and status strobes.
-- Note optional failover for overflow of the high-priority FIFO.
in_overflow <= lo_overflow or bool2bit(hi_overflow = '1' and not BUFF_FAILOVER);
lo_select   <= dly_precommit or bool2bit(hi_overflow = '1' and BUFF_FAILOVER);
lo_commit   <= dly_final and lo_select;
lo_revert   <= dly_final and not lo_select;
hi_select   <= hi_precommit;
hi_commit   <= in_final and hi_precommit;
hi_revert   <= in_final and not hi_precommit;

-- Always instantiate the FIFO for ordinary traffic.
u_fifo_lo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    META_WIDTH      => META_WIDTH,
    BUFFER_KBYTES   => BUFF_LO_KBYTES,
    MAX_PACKETS     => MAX_PACKETS,
    MAX_PKT_BYTES   => MAX_PKT_BYTES)
    port map(
    in_clk          => in_clk,
    in_data         => dly_data,
    in_nlast        => dly_nlast,
    in_pkt_meta     => dly_meta,
    in_precommit    => dly_precommit,
    in_write        => dly_write,
    in_last_commit  => lo_commit,
    in_last_revert  => lo_revert,
    in_overflow     => lo_overflow,
    in_reset        => sync_reset_i,
    out_clk         => out_clk,
    out_data        => lo_data,
    out_pkt_meta    => lo_meta,
    out_nlast       => lo_nlast,
    out_valid       => lo_valid,
    out_ready       => lo_ready,
    out_pause       => sync_pause,
    out_reset       => sync_reset_o,
    reset_p         => reset_p);

-- Priority system enabled?
gen_hi : if BUFF_HI_ENABLE generate
    -- Separate FIFO for high-priority traffic.
    u_fifo_hi : entity work.fifo_packet
        generic map(
        INPUT_BYTES     => INPUT_BYTES,
        OUTPUT_BYTES    => OUTPUT_BYTES,
        META_WIDTH      => META_WIDTH,
        BUFFER_KBYTES   => BUFF_HI_KBYTES,
        MAX_PACKETS     => MAX_PACKETS,
        MAX_PKT_BYTES   => MAX_PKT_BYTES)
        port map(
        in_clk          => in_clk,
        in_data         => in_data,
        in_nlast        => in_nlast,
        in_write        => in_write,
        in_pkt_meta     => in_meta,
        in_precommit    => hi_precommit,
        in_last_commit  => hi_commit,
        in_last_revert  => hi_revert,
        in_overflow     => hi_overflow,
        out_clk         => out_clk,
        out_data        => hi_data,
        out_pkt_meta    => hi_meta,
        out_nlast       => hi_nlast,
        out_valid       => hi_valid,
        out_ready       => hi_ready,
        out_pause       => sync_pause,
        reset_p         => reset_p);

    -- Combine the two packet streams; priority goes to port #0.
    u_combine : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        IO_BYTES        => OUTPUT_BYTES,
        META_WIDTH      => META_WIDTH,
        APPEND_FCS      => false)
        port map(
        in0_data        => hi_data,
        in1_data        => lo_data,
        in0_meta        => hi_meta,
        in1_meta        => lo_meta,
        in0_nlast       => hi_nlast,
        in1_nlast       => lo_nlast,
        in_valid(0)     => hi_valid,
        in_valid(1)     => lo_valid,
        in_ready(0)     => hi_ready,
        in_ready(1)     => lo_ready,
        in_error        => open,
        out_data        => out_data,
        out_meta        => out_meta,
        out_nlast       => out_nlast,
        out_last        => out_last,
        out_valid       => out_valid,
        out_ready       => out_ready,
        out_aux         => strm_sel,
        out_pause       => sync_pause,
        clk             => out_clk,
        reset_p         => sync_reset_o);

    -- Indicate selected stream.
    out_hipri <= not strm_sel;
end generate;

-- Priority system disabled?
gen_no : if not BUFF_HI_ENABLE generate
    -- Connect primary FIFO directly to output.
    out_hipri   <= '0';
    out_data    <= lo_data;
    out_meta    <= lo_meta;
    out_nlast   <= lo_nlast;
    out_last    <= bool2bit(lo_nlast > 0);
    out_valid   <= lo_valid;
    lo_ready    <= out_ready;
end generate;

end fifo_priority;
