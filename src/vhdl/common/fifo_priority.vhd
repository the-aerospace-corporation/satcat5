--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Asynchronous packet FIFO w/ priority queueing
--
-- This block is similar to fifo_packet, except that incoming data can
-- be sorted into low-priority or high-priority categories.  Each category
-- continues to operate with separate first-in / first-out queues, but in
-- the final output, high-priority packets will skip ahead of any queued
-- low-priority packets, regardless of original order.
--
-- The "last" strobe is asserted concurrently with the final byte in each
-- frame.  The "keep" and "high-priority" (hipri) flags must be asserted at
-- the same time as "last"; otherwise they are ignored. Output flow control
-- uses standard AXI rules.
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
    INPUT_BYTES     : natural;              -- Width of input port
    BUFF_HI_KBYTES  : natural;              -- High-priority buffer (kilobytes)
    BUFF_LO_KBYTES  : natural;              -- Low-priority buffer (kilobytes)
    MAX_PACKETS     : positive;             -- Maximum queued packets
    MAX_PKT_BYTES   : positive;             -- Maximum packet size (bytes)
    BUFF_FAILOVER   : boolean := true);     -- Allow failover? (see above)
    port (
    -- Input port does not use flow control.
    in_clk          : in  std_logic;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_nlast        : in  integer range 0 to INPUT_BYTES := INPUT_BYTES;
    in_last_keep    : in  std_logic;        -- Keep or revert this packet?
    in_last_hipri   : in  std_logic;        -- High-priority packet?
    in_write        : in  std_logic;
    in_overflow     : out std_logic;        -- Warning strobe (invalid commit)

    -- Output port uses AXI-style flow control.
    out_clk         : in  std_logic;
    out_data        : out std_logic_vector(7 downto 0);
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_hipri       : out std_logic;        -- Identify output stream

    -- Global asynchronous pause and reset.
    async_pause     : in  std_logic;
    reset_p         : in  std_logic);
end fifo_priority;

architecture fifo_priority of fifo_priority is

-- Priority queue enabled?
constant BUFF_HI_ENABLE : boolean := (BUFF_HI_KBYTES > 0);
-- Single-cycle delay for input to low-priority FIFO?
constant LO_DLY_ENABLE  : boolean := BUFF_HI_ENABLE and BUFF_FAILOVER;

-- Synchronize various async inputs.
signal sync_pause       : std_logic;
signal sync_reset       : std_logic;

-- Generate KEEP strobes for each input.
signal in_final         : std_logic;
signal in_keep_hipri    : std_logic;
signal in_keep_lopri    : std_logic;

-- One-cycle delay for the input stream.
signal dly_data         : std_logic_vector(8*INPUT_BYTES-1 downto 0) := (others => '0');
signal dly_nlast        : integer range 0 to INPUT_BYTES := INPUT_BYTES;
signal dly_lo_keep      : std_logic := '0';
signal dly_final        : std_logic := '0';
signal dly_write        : std_logic := '0';

-- Commit/revert and status strobes.
signal lo_select,   hi_select   : std_logic;
signal lo_commit,   hi_commit   : std_logic;
signal lo_revert,   hi_revert   : std_logic;

-- Output streams.
signal strm_sel                 : std_logic := '0';
signal lo_data,     hi_data     : std_logic_vector(7 downto 0) := (others => '0');
signal lo_last,     hi_last     : std_logic := '0';
signal lo_valid,    hi_valid    : std_logic := '0';
signal lo_ready,    hi_ready    : std_logic := '0';
signal lo_overflow, hi_overflow : std_logic := '0';

begin

-- Synchronize the PAUSE flag.
u_pause : sync_buffer
    port map(
    in_flag     => async_pause,
    out_flag    => sync_pause,
    out_clk     => out_clk);

-- Generate KEEP strobes for each input.
in_final      <= in_write and bool2bit(in_nlast > 0);
in_keep_hipri <= in_last_keep and bool2bit(in_last_hipri = '1' and BUFF_HI_ENABLE);
in_keep_lopri <= in_last_keep and bool2bit(in_last_hipri = '0' or not BUFF_HI_ENABLE);

-- Delay inputs to the low-priority FIFO?
gen_dly1 : if LO_DLY_ENABLE generate
    -- Single-cycle delay is required for failover.
    p_delay : process(in_clk)
    begin
        if rising_edge(in_clk) then
            dly_data    <= in_data;
            dly_nlast   <= in_nlast;
            dly_final   <= in_final;
            dly_lo_keep <= in_keep_lopri;
            dly_write   <= in_write;
        end if;
    end process;
end generate;

gen_dly0 : if not LO_DLY_ENABLE generate
    -- No delay required.
    dly_data    <= in_data;
    dly_nlast   <= in_nlast;
    dly_final   <= in_final;
    dly_lo_keep <= in_keep_lopri;
    dly_write   <= in_write;
end generate;

-- Combinational logic for commit/revert and status strobes.
-- Note optional failover for overflow of the high-priority FIFO.
in_overflow <= lo_overflow or bool2bit(hi_overflow = '1' and not BUFF_FAILOVER);
lo_select   <= dly_lo_keep or bool2bit(hi_overflow = '1' and BUFF_FAILOVER);
lo_commit   <= dly_final and lo_select;
lo_revert   <= dly_final and not lo_select;
hi_select   <= in_keep_hipri;
hi_commit   <= in_final and hi_select;
hi_revert   <= in_final and not hi_select;

-- Always instantiate the FIFO for ordinary traffic.
u_fifo_lo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => 1,
    BUFFER_KBYTES   => BUFF_LO_KBYTES,
    MAX_PACKETS     => MAX_PACKETS,
    MAX_PKT_BYTES   => MAX_PKT_BYTES)
    port map(
    in_clk          => in_clk,
    in_data         => dly_data,
    in_nlast        => dly_nlast,
    in_write        => dly_write,
    in_last_commit  => lo_commit,
    in_last_revert  => lo_revert,
    in_overflow     => lo_overflow,
    out_clk         => out_clk,
    out_data        => lo_data,
    out_last        => lo_last,
    out_valid       => lo_valid,
    out_ready       => lo_ready,
    out_pause       => sync_pause,
    out_reset       => sync_reset,
    reset_p         => reset_p);

-- Priority system enabled?
gen_hi : if BUFF_HI_ENABLE generate
    -- Separate FIFO for high-priority traffic.
    u_fifo_hi : entity work.fifo_packet
        generic map(
        INPUT_BYTES     => INPUT_BYTES,
        OUTPUT_BYTES    => 1,
        BUFFER_KBYTES   => BUFF_HI_KBYTES,
        MAX_PACKETS     => MAX_PACKETS,
        MAX_PKT_BYTES   => MAX_PKT_BYTES)
        port map(
        in_clk          => in_clk,
        in_data         => in_data,
        in_nlast        => in_nlast,
        in_write        => in_write,
        in_last_commit  => hi_commit,
        in_last_revert  => hi_revert,
        in_overflow     => hi_overflow,
        out_clk         => out_clk,
        out_data        => hi_data,
        out_last        => hi_last,
        out_valid       => hi_valid,
        out_ready       => hi_ready,
        out_pause       => sync_pause,
        reset_p         => reset_p);

    -- Combine the two packet streams; priority goes to port #0.
    u_combine : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        APPEND_FCS      => false)
        port map(
        in_data(0)      => hi_data,
        in_data(1)      => lo_data,
        in_last(0)      => hi_last,
        in_last(1)      => lo_last,
        in_valid(0)     => hi_valid,
        in_valid(1)     => lo_valid,
        in_ready(0)     => hi_ready,
        in_ready(1)     => lo_ready,
        in_error        => open,
        out_data        => out_data,
        out_last        => out_last,
        out_valid       => out_valid,
        out_ready       => out_ready,
        out_aux         => strm_sel,
        out_pause       => sync_pause,
        clk             => out_clk,
        reset_p         => sync_reset);

    -- Indicate selected stream.
    out_hipri <= not strm_sel;
end generate;

-- Priority system disabled?
gen_no : if not BUFF_HI_ENABLE generate
    -- Connect primary FIFO directly to output.
    out_hipri   <= '0';
    out_data    <= lo_data;
    out_last    <= lo_last;
    out_valid   <= lo_valid;
    lo_ready    <= out_ready;
end generate;

end fifo_priority;
