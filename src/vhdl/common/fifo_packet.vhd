--------------------------------------------------------------------------
-- Copyright 2019, 2020, 2021 The Aerospace Corporation
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
-- Asynchronous packet FIFO
--
-- This block implements a FIFO for which data is tentatively written on a
-- word-by-word basis. Each complete packet is committed or reverted based
-- on the appropriate strobe, which also marks the final word in the packet.
-- Input is written without flow control; any data which would overflow
-- the buffer instead causes the complete packet to be reverted.  Output
-- uses AXI-style flow control and may be in a different clock domain.
--
-- Input and output word-sizes must be multiples of eight bits; if they
-- are different, please ensure the LCM is reasonable.  (If possible, the
-- the larger size should be a multiple of the smaller.)  Per Ethernet
-- convention, word-size conversion is always handled MSW-first.
--
-- For multi-byte configurations, the NLAST input indicates the location
-- of the final valid byte.  Refer to "fifo_smol_resize" for details.
-- One notable exception: Since a separate "last" strobe is required,
-- the NLAST input is ignored unless that strobe is asserted.
--
-- Optionally, the block can be configured to maintain a single word of
-- metadata associated with each packet.  At the input, this word is
-- latched concurrently with the in_last_commit strobe.  At the output,
-- it is valid for the entire duration of the packet.
--
-- The block also supports an optional "pause" flag, sync'd to out_clk.
-- While asserted, the output will continue a frame-in-progress but will
-- delay starting subsequent frames until the pause flag is lowered.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;

entity fifo_packet is
    generic (
    INPUT_BYTES     : positive;             -- Width of input port
    OUTPUT_BYTES    : positive;             -- Width of output port
    BUFFER_KBYTES   : positive;             -- Buffer size (kilobytes)
    META_WIDTH      : natural := 0;         -- Packet metadata width (optional)
    FLUSH_TIMEOUT   : natural := 0;         -- Stale data timeout (optional)
    MAX_PACKETS     : positive := 64;       -- Maximum queued packets
    MAX_PKT_BYTES   : positive := 1536;     -- Maximum packet size (bytes)
    TEST_MODE       : boolean := false);    -- Enable verification features
    port (
    -- Input port does not use flow control.
    in_clk          : in  std_logic;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_nlast        : in  integer range 0 to INPUT_BYTES := INPUT_BYTES;
    in_pkt_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last_commit  : in  std_logic;
    in_last_revert  : in  std_logic;
    in_write        : in  std_logic;
    in_reset        : out std_logic;        -- Syncronized copy of reset_p
    in_overflow     : out std_logic;        -- Warning strobe (invalid commit)

    -- Output port uses AXI-style flow control.
    out_clk         : in  std_logic;
    out_data        : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    out_nlast       : out integer range 0 to OUTPUT_BYTES;
    out_pkt_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_reset       : out std_logic;        -- Synchronized copy of reset_p
    out_overflow    : out std_logic;        -- Same warning, in out_clk domain
    out_pause       : in  std_logic := '0'; -- Optional: Don't start next packet

    -- Global asynchronous reset.
    reset_p         : in  std_logic);
end fifo_packet;

architecture fifo_packet of fifo_packet is

-- Define FIFO size parameters.
constant INPUT_WIDTH    : natural := 8 * INPUT_BYTES;
constant META_WIDTH_ADJ : natural := int_max(META_WIDTH, 1);
constant FIFO_BYTES     : natural := int_lcm(INPUT_BYTES, OUTPUT_BYTES);
constant FIFO_CWIDTH    : natural := log2_ceil(FIFO_BYTES + 1);
constant FIFO_DWIDTH    : natural := 8 * FIFO_BYTES;
constant FIFO_TOTAL     : natural := FIFO_CWIDTH + FIFO_DWIDTH;
constant FIFO_DEPTH     : natural := (1024*BUFFER_KBYTES) / FIFO_BYTES;
constant INPUT_WMAX     : natural := FIFO_BYTES / INPUT_BYTES - 1;
constant ADDR_WIDTH     : natural := log2_ceil(FIFO_DEPTH);
constant NFREE_FIXED    : natural := 32;
constant MAX_PKT_WORDS  : positive := (MAX_PKT_BYTES + FIFO_BYTES - 1) / FIFO_BYTES;
subtype addr_i is natural range 0 to FIFO_DEPTH-1;
subtype addr_u is unsigned(ADDR_WIDTH-1 downto 0);
subtype words_i is natural range 0 to FIFO_DEPTH;
subtype meta_t is std_logic_vector(META_WIDTH_ADJ-1 downto 0);
subtype nlast_t is std_logic_vector(FIFO_CWIDTH-1 downto 0);
subtype nlast_i is natural range 0 to FIFO_BYTES;
subtype fifo_t is std_logic_vector(FIFO_TOTAL-1 downto 0);

function addr_incr(x : addr_i) return addr_i is
begin
    -- Address increment with wraparound.
    if (x = FIFO_DEPTH-1) then
        return 0;
    else
        return x + 1;
    end if;
end function;

-- Reset signals
signal reset_a      : std_logic;        -- Global reset (asynchronous)
signal reset_i      : std_logic;        -- Global reset (input clock)
signal reset_o      : std_logic;        -- Global reset (output clock)
signal wdog_reset   : std_logic := '0'; -- Flag in output clock

-- State synchronized to main input.
signal free_words   : words_i := FIFO_DEPTH;
signal new_words    : words_i := 1;
signal in_wcount    : integer range 0 to INPUT_WMAX := 0;

-- Write pipeline going to main FIFO.
signal wr_words     : words_i := 0;                 -- Allocate N words from FIFO
signal wr_meta      : meta_t := (others => '0');    -- Latched metadata
signal wr_ovrflow   : std_logic := '0';             -- Flag in input clock
signal wr_commit    : std_logic := '0';             -- Strobe in input clock
signal wr_revert    : std_logic := '0';             -- Strobe in input clock
signal wr_write     : std_logic := '0';             -- Strobe in input clock
signal wr_data      : fifo_t := (others => '0');    -- Data to be written
signal wr_addr      : addr_i := 0;                  -- Current write address
signal wr_ready     : std_logic;
signal wr_safe      : std_logic;
signal revert_addr  : addr_i := 0;                  -- Start of current packet

-- Back-channel for freeing data as it is read.
-- (Strobe event is triggered every NFREE_FIXED words.)
signal free_block_t : std_logic := '0';
signal free_block_i : std_logic := '0';

-- Dual-port block RAM.
signal wr_addr_u    : addr_u;
signal rd_addr_u    : addr_u;
signal rd_addr      : addr_i := 0;
signal rd_data      : fifo_t;
signal rd_nlast_u   : nlast_t;
signal rd_nlast_i   : nlast_i;

-- Output state machine, including word-size conversion.
signal pkt_meta     : meta_t := (others => '0');
signal pkt_valid    : std_logic;
signal rd_avail     : std_logic;
signal rd_start     : std_logic;
signal rd_final     : std_logic;
signal rd_busy      : std_logic := '0';
signal rd_continue  : std_logic;
signal rd_enable    : std_logic;
signal rd_ready     : std_logic;
signal fifo_wr      : std_logic := '0';
signal fifo_hempty  : std_logic;
signal out_valid_i  : std_logic;
signal out_last_i   : std_logic;
signal out_pkt_rd   : std_logic;

begin

-- Synchronize the reset signal with each clock domain.
reset_a <= reset_p or wdog_reset;
u_reset_in : sync_reset
    port map(
    in_reset_p  => reset_a,
    out_reset_p => reset_i,
    out_clk     => in_clk);
u_reset_out : sync_reset
    port map(
    in_reset_p  => reset_a,
    out_reset_p => reset_o,
    out_clk     => out_clk);

-- Top-level status strobes:
in_reset    <= reset_i;
in_overflow <= wr_ovrflow;

u_overflow : sync_pulse2pulse
    port map(
    in_strobe   => wr_ovrflow,
    in_clk      => in_clk,
    out_strobe  => out_overflow,
    out_clk     => out_clk);

-- Optional watchdog timer for undeliverable packets.
-- (Otherwise FIFO can fill up with stale data from other ports.)
gen_wdog : if (FLUSH_TIMEOUT > 0) generate
    p_wdog : process(out_clk)
        variable wdog_count : natural range 0 to FLUSH_TIMEOUT := FLUSH_TIMEOUT;
    begin
        if rising_edge(out_clk) then
            -- Watchdog triggers when countdown reaches zero.
            wdog_reset <= bool2bit(wdog_count = 0);
            -- Reset whenever a packet is read or the buffer is empty.
            if (reset_i = '1' or out_pkt_rd = '1' or out_valid_i = '0') then
                wdog_count := FLUSH_TIMEOUT;    -- Reset to max value.
            elsif (wdog_count > 0) then
                wdog_count := wdog_count - 1;   -- Countdown to zero.
            end if;
        end if;
    end process;
end generate;

-- Auxiliary input counters, including word-size conversion.
p_free : process(in_clk)
    variable wr_nlast : integer range 0 to FIFO_BYTES := 0;
begin
    if rising_edge(in_clk) then
        -- Byte counter is stored alongside each FIFO word:
        --  * 0 = Packet continues in next word.
        --  * Any other value indicates final word with N bytes.
        if (in_last_commit = '0' and in_last_revert = '0') then
            wr_nlast := 0;
        elsif (in_write = '1') then
            wr_nlast := in_wcount * INPUT_BYTES + in_nlast;
        end if;
        wr_data(wr_data'left downto FIFO_DWIDTH) <= i2s(wr_nlast, FIFO_CWIDTH);

        -- Update each part of the data register, MSW-first.
        -- (Note: End of input may not be word-aligned.)
        for n in 0 to INPUT_WMAX loop
            if (in_write = '1' and in_wcount = INPUT_WMAX - n) then
                wr_data((n+1)*INPUT_WIDTH-1 downto
                        (n+0)*INPUT_WIDTH) <= in_data;
            end if;
        end loop;

        -- Update word-size conversion counter.
        if (reset_i = '1') then
            in_wcount <= 0;
        elsif (in_write = '1') then
            if (in_last_commit = '1' or
                in_last_revert = '1' or
                in_wcount = INPUT_WMAX) then
                in_wcount <= 0;
            else
                in_wcount <= in_wcount + 1;
            end if;
        end if;

        -- Latch metadata at end of each valid frame.
        if (META_WIDTH > 0 and in_write = '1' and in_last_commit = '1') then
            wr_meta <= in_pkt_meta;
        end if;

        -- Count words in current frame (sync'd to in_write)
        if (reset_i = '1') then
            new_words <= 1;
        elsif (in_write = '1') then
            if (in_last_commit = '1' or in_last_revert = '1') then
                new_words <= 1;
            elsif (in_wcount = INPUT_WMAX and new_words < FIFO_DEPTH) then
                new_words <= new_words + 1;
            end if;
        end if;

        -- Increment or revert address after a one-cycle delay.
        if (wr_revert = '1') then
            wr_addr <= revert_addr;
        elsif (wr_write = '1') then
            wr_addr <= addr_incr(wr_addr);
        end if;

        -- Update the revert-pointer after each commit.
        if (reset_i = '1') then
            revert_addr <= 0;
        elsif (wr_commit = '1') then
            revert_addr <= addr_incr(wr_addr);
        end if;

        -- Update the free-words counter just after each packet is committed,
        -- and for each batch of words from the freed-memory event.
        if (reset_i = '1') then
            free_words <= FIFO_DEPTH;
        elsif (free_block_i = '1') then
            free_words <= free_words + NFREE_FIXED - wr_words;
        else
            free_words <= free_words - wr_words;
        end if;
    end if;
end process;

-- Decide whether it is safe to write each input word, and when to revert.
p_input : process(in_clk)
    variable ovr_sticky : std_logic := '0';
begin
    if rising_edge(in_clk) then
        -- Set defaults for various strobes.
        wr_write    <= '0';
        wr_commit   <= '0';
        wr_revert   <= '0';
        wr_ovrflow  <= '0';
        wr_words    <= 0;

        -- Sanity-check on unexpected packet-FIFO overflow.
        if (wr_commit = '1') then
            assert (wr_ready = '1')
                report "Internal flow-control violation." severity error;
        end if;

        -- Drive the write, commit, and revert strobes.
        if (reset_i = '1') then
            -- Global reset, clear all counters.
            wr_revert   <= '1';
            ovr_sticky  := '0';
        elsif (in_write = '1') then
            -- Sanity-check on inputs.
            assert (in_last_commit = '0' or in_last_revert = '0')
                report "Cannot simultaneously commit and revert packet." severity error;

            -- Drive the write/commit/revert/overflow strobes.
            -- Note: Updates to "free_words" are one cycle late; count anything we're
            --       currently in the process of allocating during safety checks here.
            if (ovr_sticky = '1' or new_words > MAX_PKT_WORDS or
                new_words + wr_words > free_words) then
                -- Packet-length overflow. Stop writing, revert at end-of-frame.
                wr_revert   <= in_last_commit or in_last_revert;
                wr_ovrflow  <= in_last_commit;
            elsif (in_last_commit = '1' and wr_safe = '1') then
                -- Commit success! Notify output state machine.
                wr_write    <= '1';
                wr_commit   <= '1';
                wr_words    <= new_words;
            elsif (in_last_commit = '1' or in_last_revert = '1') then
                -- Metadata overflow or upstream revert.
                wr_revert   <= '1';
                wr_ovrflow  <= in_last_commit;
            else
                -- Mid-packet, write each completed word.
                wr_write    <= bool2bit(in_wcount = INPUT_WMAX);
            end if;

            -- Overflow flag sticks until end-of-frame.
            -- (This prevents glitches when additional space is freed mid-frame.)
            if (in_last_commit = '1' or in_last_revert = '1') then
                ovr_sticky := '0';
            elsif (new_words + wr_words > free_words) then
                ovr_sticky := '1';
            end if;
        end if;
    end if;
end process;

-- Platform-specific dual-port block RAM for main datapath.
wr_addr_u   <= to_unsigned(wr_addr, ADDR_WIDTH);
rd_addr_u   <= to_unsigned(rd_addr, ADDR_WIDTH);
rd_nlast_u  <= to_01_vec(rd_data(rd_data'left downto FIFO_DWIDTH));
rd_nlast_i  <= u2i(rd_nlast_u);

u_ram : dpram
    generic map(
    AWIDTH  => ADDR_WIDTH,
    DWIDTH  => FIFO_TOTAL,
    SIMTEST => TEST_MODE)
    port map(
    wr_clk  => in_clk,
    wr_addr => wr_addr_u,
    wr_en   => wr_write,
    wr_val  => wr_data,
    rd_clk  => out_clk,
    rd_addr => rd_addr_u,
    rd_en   => rd_enable,
    rd_val  => rd_data);

-- Cross-clock transitions for control and metadata.
-- (Use adjusted width to workaround pathological META_WIDTH = 0 case.)
u_pkt_fifo : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => META_WIDTH_ADJ,
    DEPTH_LOG2  => log2_ceil(MAX_PACKETS))
    port map(
    in_clk      => in_clk,
    in_data     => wr_meta,
    in_valid    => wr_commit,
    in_ready    => wr_ready,
    in_early    => wr_safe,
    out_clk     => out_clk,
    out_data    => pkt_meta,
    out_valid   => pkt_valid,
    out_ready   => rd_start,
    reset_p     => reset_p);

u_free : sync_toggle2pulse
    port map(
    in_toggle   => free_block_t,
    out_strobe  => free_block_i,
    out_clk     => in_clk);

-- Read controller: Wait for pkt_valid from the cross-clock FIFO, then keep
-- reading from DPRAM until end-of-frame marker (i.e., nonzero metadata).
rd_avail    <= pkt_valid and fifo_hempty and not out_pause; -- New packet available?
rd_final    <= fifo_wr and or_reduce(rd_nlast_u);           -- End-of-frame marker?
rd_start    <= rd_avail and (rd_final or not rd_busy);      -- Start next frame?
rd_continue <= rd_busy and not rd_final;                    -- Continue current frame?
rd_ready    <= fifo_hempty and not reset_o;                 -- Ready to accept data?
rd_enable   <= (rd_start or rd_continue) and rd_ready;      -- Read from DPRAM?

p_rd_ctrl : process(out_clk)
    variable free_count : integer range 0 to NFREE_FIXED-1 := NFREE_FIXED-1;
begin
    if rising_edge(out_clk) then
        -- Hold the "busy" flag for the duration of each frame.
        if (reset_o = '1') then
            rd_busy <= '0'; -- FIFO reset
        elsif (rd_start = '1') then
            rd_busy <= '1'; -- Start of new frame
        elsif (rd_final = '1') then
            rd_busy <= '0'; -- End of frame, no more in queue
        end if;

        -- Every time we read, write the result to FIFO on next cycle.
        fifo_wr <= rd_enable;

        -- Increment address each time we read from DPRAM.
        if (reset_o = '1') then
            rd_addr <= 0;
        elsif (rd_enable = '1') then
            rd_addr <= addr_incr(rd_addr);
        end if;

        -- Every N words, let the input controller reuse the freed memory.
        -- (Using fixed-size blocks greatly simplifies clock-crossing logic.)
        if (reset_o = '1') then
            free_count   := NFREE_FIXED - 1;    -- FIFO reset
        elsif (fifo_wr = '1' and free_count > 0) then
            free_count   := free_count - 1;     -- Keep counting...
        elsif (fifo_wr = '1') then
            free_count   := NFREE_FIXED - 1;    -- Rollover event
            free_block_t <= not free_block_t;
        end if;
    end if;
end process;

-- Output flow-control and word-size conversion.
u_out_fifo : entity work.fifo_smol_resize
    generic map(
    IN_BYTES    => FIFO_BYTES,
    OUT_BYTES   => OUTPUT_BYTES)
    port map(
    in_data     => rd_data(FIFO_DWIDTH-1 downto 0),
    in_nlast    => rd_nlast_i,
    in_write    => fifo_wr,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_last    => out_last_i,
    out_valid   => out_valid_i,
    out_read    => out_ready,
    fifo_hempty => fifo_hempty,
    clk         => out_clk,
    reset_p     => reset_o);

-- Separate FIFO for packet metadata, if enabled.
gen_out_meta : if META_WIDTH > 0 generate
    u_out_meta : entity work.fifo_smol_sync
        generic map(
        IO_WIDTH    => META_WIDTH)
        port map(
        in_data     => pkt_meta,
        in_write    => rd_start,
        out_data    => out_pkt_meta,
        out_valid   => open,
        out_read    => out_pkt_rd,
        clk         => out_clk,
        reset_p     => reset_o);
end generate;

-- Drive final outputs.
out_last        <= out_last_i;
out_valid       <= out_valid_i;
out_pkt_rd      <= out_valid_i and out_ready and out_last_i;
out_reset       <= reset_o;

end fifo_packet;
