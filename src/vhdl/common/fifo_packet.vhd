--------------------------------------------------------------------------
-- Copyright 2019, 2020 The Aerospace Corporation
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
-- Input and output word-sizes must be multiples of eight bits; if they
-- are different, the larger must be a multiple of the smaller.  Per
-- Ethernet convention, word-size conversion is always handled MSW-first.
--
-- Optionally, the block can be configured to maintain a single word of
-- metadata associated with each packet.  At the input, this word is
-- latched concurrently with the in_last_commit strobe.  At the output,
-- it is valid for the entire duration of the packet.
--
-- The block also supports an asynchronous "pause" flag.  While asserted,
-- the output will continue a frame-in-progress but will delay starting
-- subsequent frames until the pause flag is lowered.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.synchronization.all;

entity fifo_packet is
    generic (
    INPUT_BYTES     : natural;          -- Width of input port
    OUTPUT_BYTES    : natural;          -- Width of output port
    BUFFER_KBYTES   : natural;          -- Buffer size (kilobytes)
    META_WIDTH      : natural := 0;     -- Packet metadata width (optional)
    FLUSH_TIMEOUT   : natural := 0;     -- Stale data timeout (optional)
    MAX_PACKETS     : natural := 64;    -- Maximum queued packets
    MAX_PKT_BYTES   : natural := 1536); -- Maximum packet size (bytes)
    port (
    -- Input port does not use flow control.
    -- Note: Input/output byte-count (bcount) is actually N-1.
    in_clk          : in  std_logic;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_bcount       : in  integer range 0 to INPUT_BYTES-1 := INPUT_BYTES-1;
    in_pkt_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last_commit  : in  std_logic;
    in_last_revert  : in  std_logic;
    in_write        : in  std_logic;
    in_overflow     : out std_logic;        -- Warning strobe (invalid commit)

    -- Output port uses AXI-style flow control.
    out_clk         : in  std_logic;
    out_data        : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    out_bcount      : out integer range 0 to OUTPUT_BYTES-1;
    out_pkt_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_overflow    : out std_logic;        -- Same warning, in out_clk domain
    out_pause       : in  std_logic := '0'; -- Optional: Don't start next packet

    -- Global asynchronous reset.
    reset_p         : in  std_logic);
end fifo_packet;

architecture fifo_packet of fifo_packet is

-- Define FIFO size parameters.
constant FREE_MARGIN    : natural := 0; -- Almost-full margin of N words.
constant INPUT_WIDTH    : natural := 8 * INPUT_BYTES;
constant OUTPUT_WIDTH   : natural := 8 * OUTPUT_BYTES;
constant FIFO_BYTES     : natural := int_max(INPUT_BYTES, OUTPUT_BYTES);
constant FIFO_WIDTH     : natural := 8 * FIFO_BYTES;
constant FIFO_DEPTH     : natural := (1024*BUFFER_KBYTES) / FIFO_BYTES;
constant INPUT_RATIO    : natural := FIFO_BYTES / INPUT_BYTES;
constant OUTPUT_RATIO   : natural := FIFO_BYTES / OUTPUT_BYTES;
constant NBYTES_WIDTH   : natural := log2_ceil(MAX_PKT_BYTES+INPUT_BYTES);
constant BCOUNT_WIDTH   : natural := log2_ceil(OUTPUT_BYTES);
constant PFIFO_WIDTH    : natural := NBYTES_WIDTH + META_WIDTH;
constant MAX_PKT_WORDS  : natural := (MAX_PKT_BYTES + FIFO_BYTES - 1) / FIFO_BYTES;
subtype addr_t is natural range 0 to FIFO_DEPTH-1;
subtype nwords_t is natural range 0 to FIFO_DEPTH;
subtype nbytes_t is unsigned(NBYTES_WIDTH-1 downto 0);
subtype pfifo_t is std_logic_vector(PFIFO_WIDTH-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype word_t is std_logic_vector(FIFO_WIDTH-1 downto 0);

-- Define various utility functions:
function get_bcount(x : std_logic_vector) return integer is
begin
    -- Extract the byte-count field from the final FIFO word.
    if (BCOUNT_WIDTH > 0) then
        return u2i(to_01_vec(x));
    else
        return OUTPUT_BYTES-1;
    end if;
end function;

function addr_incr(x : addr_t) return addr_t is
begin
    -- Address increment with wraparound.
    if (x = FIFO_DEPTH-1) then
        return 0;
    else
        return x + 1;
    end if;
end function;

-- Input state machine, including word-size conversion.
constant IN_FREE_MAX : nwords_t := FIFO_DEPTH - FREE_MARGIN;
signal in_free_words    : nwords_t := IN_FREE_MAX;
signal in_new_words     : nwords_t := 1;
signal in_new_bytes     : nbytes_t := (others => '0');
signal in_wcount        : integer range 0 to INPUT_RATIO-1 := 0;
signal overflow_flag    : std_logic := '0'; -- Persistent flag
signal overflow_str     : std_logic := '0'; -- Strobe in input clock
signal overflow_tog     : std_logic := '0'; -- Toggle in input clock
signal commit_en        : std_logic := '0';
signal revert_en        : std_logic := '0';
signal revert_addr      : addr_t := 0;
signal wdog_reset       : std_logic := '0'; -- Flag in input clock

-- Dual-port block RAM.
type dp_ram_t is array(0 to FIFO_DEPTH-1) of word_t;
shared variable dp_ram  : dp_ram_t := (others => (others => '0'));
signal write_addr       : addr_t := 0;
signal write_data       : word_t := (others => '0');
signal write_en         : std_logic := '0';
signal read_addr        : addr_t := 0;
signal read_data        : word_t := (others => '0');

-- Clock-domain transition.
signal reset_a          : std_logic;            -- Global reset (asynchronous)
signal reset_i          : std_logic;            -- Global reset (input clock)
signal reset_o          : std_logic;            -- Global reset (output clock)
signal xwr_nwords       : nwords_t := 0;        -- Transfer N words to output
signal xwr_nbytes       : nbytes_t := (others => '0');  -- Transfer N bytes to output
signal xwr_meta         : meta_t := (others => '0');    -- Latched metadata
signal xwr_toggle       : std_logic := '0';     -- Toggle in input clock
signal xwr_strobe       : std_logic;            -- Strobe in output clock
signal xwr_full         : std_logic;            -- Flag in input clock
signal xrd_nwords       : nwords_t := 0;        -- Free N words from input
signal xrd_toggle       : std_logic := '0';     -- Toggle in output clock
signal xrd_strobe       : std_logic;            -- Strobe in input clock
signal xrd_pause        : std_logic;            -- Flag in output clock

-- A small FIFO for the length of each stored packet.
signal pkt_fifo_iraw    : pfifo_t;
signal pkt_fifo_oraw    : pfifo_t;
signal pkt_fifo_meta    : meta_t;
signal pkt_fifo_len     : nbytes_t;
signal pkt_fifo_rd      : std_logic := '0';
signal pkt_fifo_valid   : std_logic;
signal pkt_fifo_full    : std_logic;

-- Output state machine, including word-size conversion.
signal read_wcount      : integer range 0 to OUTPUT_RATIO-1 := 0;
signal read_wcount_d    : integer range 0 to OUTPUT_RATIO-1 := 0;
signal read_bcount      : nbytes_t := (others => '0');
signal read_meta        : meta_t := (others => '0');
signal fifo_data        : std_logic_vector(OUTPUT_WIDTH-1 downto 0) := (others => '0');
signal fifo_bcount      : integer range 0 to OUTPUT_BYTES-1 := OUTPUT_BYTES-1;
signal fifo_bvec        : std_logic_vector(BCOUNT_WIDTH-1 downto 0);
signal fifo_last        : std_logic := '0';
signal fifo_wr          : std_logic := '0';
signal fifo_hfull       : std_logic;
signal out_bvec         : std_logic_vector(BCOUNT_WIDTH-1 downto 0);
signal out_meta_i       : meta_t := (others => '0');
signal out_valid_i      : std_logic;
signal out_last_i       : std_logic;

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

-- Optional watchdog timer for undeliverable packets.
-- (Otherwise FIFO can fill up with stale data from other ports.)
gen_wdog : if (FLUSH_TIMEOUT > 0) generate
    p_wdog : process(in_clk)
        variable wdog_count : natural range 0 to FLUSH_TIMEOUT := FLUSH_TIMEOUT;
    begin
        if rising_edge(in_clk) then
            -- Watchdog triggers when countdown reaches zero.
            wdog_reset <= bool2bit(wdog_count = 0);
            -- Reset whenever a packet is read or the buffer is empty.
            if (reset_i = '1' or xrd_strobe = '1' or in_free_words = IN_FREE_MAX) then
                wdog_count := FLUSH_TIMEOUT;    -- Reset to max value.
            elsif (wdog_count > 0) then
                wdog_count := wdog_count - 1;   -- Countdown to zero.
            end if;
        end if;
    end process;
end generate;

-- Auxiliary input counters, including word-size conversion.
p_free : process(in_clk)
    variable xfer_free : nwords_t := 0;
begin
    if rising_edge(in_clk) then
        -- Update each part of the data register, MSW-first.
        -- (Note: End of input may not be word-aligned.)
        for n in 0 to INPUT_RATIO-1 loop
            if (in_write = '1' and in_wcount = n) then
                write_data(FIFO_WIDTH-n*INPUT_WIDTH-1
                    downto FIFO_WIDTH-(n+1)*INPUT_WIDTH) <= in_data;
            end if;
        end loop;

        -- Update word-size conversion counter.
        if (reset_i = '1') then
            in_wcount <= 0;
        elsif (in_write = '1') then
            if (in_last_commit = '1' or
                in_last_revert = '1' or
                in_wcount = INPUT_RATIO-1) then
                in_wcount <= 0;
            else
                in_wcount <= in_wcount + 1;
            end if;
        end if;

        -- Count bytes in current frame.
        -- Note: Reported size lags by one input word.
        -- TODO: Add a "first" flag? Otherwise ports coming out of
        --       reset may truncate first part of frame.
        if (reset_i = '1') then
            in_new_words <= 1;
            in_new_bytes <= (others => '0');
        elsif (in_write = '1') then
            if (in_last_commit = '1' or in_last_revert = '1') then
                -- Reset for start of next packet.  (One-word lag.)
                in_new_words <= 1;
                in_new_bytes <= (others => '0');
            elsif (in_wcount = INPUT_RATIO-1) then
                -- Continue accumulating (complete word).
                in_new_words <= in_new_words + 1;
                in_new_bytes <= in_new_bytes + INPUT_BYTES;
            else
                -- Continue accumulating (partial word).
                in_new_bytes <= in_new_bytes + INPUT_BYTES;
            end if;
        end if;

        -- Increment or revert address after a one-cycle delay.
        if (revert_en = '1') then
            write_addr <= revert_addr;
        elsif (write_en = '1') then
            write_addr <= addr_incr(write_addr);
        end if;

        -- Update the revert-pointer after each commit.
        if (reset_i = '1') then
            revert_addr <= 0;
        elsif (commit_en = '1') then
            revert_addr <= addr_incr(write_addr);
        end if;

        -- Update the free-words counter just after each packet is committed,
        -- or after the output reports a packet has been released.
        if (reset_i = '1') then
            in_free_words <= IN_FREE_MAX;
        elsif (commit_en = '1') then
            in_free_words <= in_free_words + xfer_free - xwr_nwords;
        else
            in_free_words <= in_free_words + xfer_free;
        end if;

        if (xrd_strobe = '1') then
            xfer_free := xrd_nwords;
        else
            xfer_free := 0;
        end if;
    end if;
end process;

-- Main input packet state machine.
in_overflow <= overflow_str;

u_overflow : sync_toggle2pulse
    port map(
    in_toggle   => overflow_tog,
    out_strobe  => out_overflow,
    out_clk     => out_clk);

p_input : process(in_clk)
begin
    if rising_edge(in_clk) then
        overflow_str <= '0';
        write_en    <= '0';
        commit_en   <= '0';
        revert_en   <= '0';

        if (reset_i = '1') then
            -- Global reset, clear all counters.
            revert_en       <= '1';
            xwr_nwords      <= 0;
            xwr_nbytes      <= (others => '0');
            xwr_meta        <= (others => '0');
            xwr_toggle      <= '0';
            overflow_flag   <= '0';
        elsif (in_write = '1') then
            -- Sanity-check on inputs.
            assert (in_last_commit = '1' or in_last_revert = '1' or in_bcount = INPUT_BYTES-1)
                report "Invalid mid-frame byte count." severity error;
            assert (in_last_commit = '0' or in_last_revert = '0')
                report "Cannot simultaneously commit and revert packet." severity error;
            -- Should we write the next word?
            if (overflow_flag = '0') then
                write_en <= in_last_commit or bool2bit(in_wcount = INPUT_RATIO-1);
            end if;
            -- Update each counter as appropriate...
            if (in_last_commit = '1' and overflow_flag = '0' and xwr_full = '0') then
                -- Commit success! Notify output state machine.
                commit_en       <= '1';
                xwr_nwords      <= in_new_words;
                xwr_nbytes      <= in_new_bytes + in_bcount + 1;
                xwr_meta        <= in_pkt_meta;
                xwr_toggle      <= not xwr_toggle;
                overflow_flag   <= '0';
            elsif (in_last_commit = '1' or in_last_revert = '1') then
                -- Revert or commit failure (overflow).
                if (in_last_commit = '1') then
                    overflow_str <= '1';
                    overflow_tog <= not overflow_tog;
                end if;
                revert_en       <= '1';
                overflow_flag   <= '0';
            elsif (in_new_words >= in_free_words or in_new_words >= MAX_PKT_WORDS) then
                -- Set overflow flag, persists to end of frame.
                overflow_flag   <= '1';
            end if;
        end if;
    end if;
end process;

-- Inferred dual-port block RAM.
p_ram_in : process(in_clk)
begin
    if rising_edge(in_clk) then
        if (write_en = '1') then
            dp_ram(write_addr) := write_data;
        end if;
    end if;
end process;

p_ram_out : process(out_clk)
begin
    if rising_edge(out_clk) then
        read_data <= dp_ram(read_addr);
    end if;
end process;

-- Clock-domain transition.
u_hs_xwr : sync_toggle2pulse
    port map(
    in_toggle   => xwr_toggle,
    out_strobe  => xwr_strobe,
    out_clk     => out_clk,
    reset_p     => reset_o);
u_hs_xrd : sync_toggle2pulse
    port map(
    in_toggle   => xrd_toggle,
    out_strobe  => xrd_strobe,
    out_clk     => in_clk,
    reset_p     => reset_i);
u_hs_full : sync_buffer
    port map(
    in_flag     => pkt_fifo_full,
    out_flag    => xwr_full,
    out_clk     => in_clk);
u_hs_pause : sync_buffer
    port map(
    in_flag     => out_pause,
    out_flag    => xrd_pause,
    out_clk     => out_clk);

-- A small FIFO for the length and metadata of each stored packet.
pkt_fifo_iraw   <= std_logic_vector(xwr_nbytes) & xwr_meta;
pkt_fifo_len    <= unsigned(pkt_fifo_oraw(PFIFO_WIDTH-1 downto META_WIDTH));
pkt_fifo_meta   <= pkt_fifo_oraw(META_WIDTH-1 downto 0);

u_pkt_fifo : entity work.fifo_smol
    generic map(
    IO_WIDTH    => META_WIDTH + NBYTES_WIDTH,
    DEPTH_LOG2  => log2_ceil(MAX_PACKETS)) -- Depth = 2^N
    port map(
    in_data     => pkt_fifo_iraw,
    in_write    => xwr_strobe,
    out_data    => pkt_fifo_oraw,
    out_valid   => pkt_fifo_valid,
    out_read    => pkt_fifo_rd,
    fifo_full   => pkt_fifo_full,
    reset_p     => reset_o,
    clk         => out_clk);

-- Output state machine, including word-size conversion.
p_output : process(out_clk)
    variable read_wlen      : nwords_t := 1;
    variable early_wr       : std_logic := '0';
    variable early_last     : std_logic := '0';
    variable early_bcount   : integer range 0 to OUTPUT_BYTES-1 := 0;
begin
    if rising_edge(out_clk) then
        -- MUX for word-size conversion (MSW-first), plus matched
        -- delay for last-strobe, byte-count, and write strobe.
        fifo_data   <= read_data(FIFO_WIDTH-OUTPUT_WIDTH*read_wcount_d-1
                          downto FIFO_WIDTH-OUTPUT_WIDTH*(read_wcount_d+1));
        fifo_last   <= early_last;
        fifo_bcount <= early_bcount;
        fifo_wr     <= early_wr;

        -- Drive the byte-count indicator and last-word strobe.
        -- Note: This is sync'd to read_addr, which is one cycle early.
        early_wr := bool2bit(read_bcount /= 0) and not fifo_hfull;
        if (read_bcount > OUTPUT_BYTES) then
            early_last   := '0';     -- Normal word
            early_bcount := OUTPUT_BYTES-1;
        elsif (read_bcount > 0) then
            early_last   := '1';     -- Final word
            early_bcount := to_integer(read_bcount-1);
        else
            early_last   := '0';     -- Idle
            early_bcount := 0;
        end if;
        read_wcount_d <= read_wcount;

        -- Update the per-packet byte counter and metadata.
        if (reset_o = '1') then
            -- Global reset.
            read_bcount <= (others => '0');
            read_meta   <= (others => '0');
        elsif (pkt_fifo_rd = '1') then
            -- Start of new packet.
            read_bcount <= pkt_fifo_len;
            read_meta   <= pkt_fifo_meta;
        elsif (fifo_hfull = '0') then
            -- Countdown to zero as we read each word.
            if (read_bcount > OUTPUT_BYTES) then
                read_bcount <= read_bcount - OUTPUT_BYTES;
            else
                read_bcount <= (others => '0');
            end if;
        end if;

        -- Read packet FIFO once data is available and current packet is
        -- done or about to finish.  One-cycle lag OK, avoid double-reads.
        -- Note: Pause flag delays start of next packet, no effect mid-packet.
        if (pkt_fifo_valid = '1' and read_bcount <= OUTPUT_BYTES) then
            pkt_fifo_rd <= not (pkt_fifo_rd or fifo_hfull or xrd_pause);
        else
            pkt_fifo_rd <= '0';
        end if;

        -- Increment read address and other counters.
        if (reset_o = '1') then
            -- Global reset.
            read_addr   <= 0;
            read_wcount <= 0;
            read_wlen   := 0;
            xrd_nwords  <= 0;
            xrd_toggle  <= '0';
        elsif (read_bcount = 0 or fifo_hfull = '1') then
            -- Idle / waiting for output FIFO.
            null;
        elsif (read_bcount <= OUTPUT_BYTES) then
            -- Last word in packet, signal source and get ready for next.
            read_addr   <= addr_incr(read_addr);    -- Move to start of next packet
            xrd_nwords  <= read_wlen + 1;           -- Free memory, including current word
            xrd_toggle  <= not xrd_toggle;
            read_wcount <= 0;
            read_wlen   := 0;
        else
            -- Transfer next word in packet.
            if (read_wcount /= OUTPUT_RATIO-1) then
                read_wcount <= read_wcount + 1;
            else
                read_wcount <= 0;
                read_addr   <= addr_incr(read_addr);
                read_wlen   := read_wlen + 1;
            end if;
        end if;

        -- Secondary buffer for metadata word is latched at packet boundary.
        if ((out_valid_i = '0') or
            (out_valid_i = '1' and out_ready = '1' and out_last_i = '1')) then
            out_meta_i <= read_meta;
        end if;
    end if;
end process;

-- Another small FIFO handles output flow control.
-- (Otherwise, we would have a few cycles of latency.)
fifo_bvec   <= i2s(fifo_bcount, BCOUNT_WIDTH);

u_out_fifo : entity work.fifo_smol
    generic map(
    IO_WIDTH    => OUTPUT_WIDTH,
    META_WIDTH  => BCOUNT_WIDTH,
    DEPTH_LOG2  => 4)   -- FIFO depth = 2^N
    port map(
    in_data     => fifo_data,
    in_meta     => fifo_bvec,
    in_last     => fifo_last,
    in_write    => fifo_wr,
    out_data    => out_data,
    out_meta    => out_bvec,
    out_last    => out_last_i,
    out_valid   => out_valid_i,
    out_read    => out_ready,
    fifo_hfull  => fifo_hfull,
    reset_p     => reset_o,
    clk         => out_clk);

out_bcount      <= get_bcount(out_bvec);
out_pkt_meta    <= out_meta_i;
out_last        <= out_last_i;
out_valid       <= out_valid_i;

end fifo_packet;
