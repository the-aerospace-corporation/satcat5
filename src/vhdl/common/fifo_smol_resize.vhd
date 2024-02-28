--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Word-resizing FIFO
--
-- This block implements a small FIFO where the input word size may be
-- different from the output word size.  It automatically adjusts to
-- up-sizing, same-sizing, or down-sizing modes.  The flow-control model
-- is the same as fifo_smol_sync: unconditional input, AXI output.
--
-- In all cases, an intermediate FIFO operates at a word size equal to
-- the least common multiple (LCM) of the input and output word sizes, and
-- allows frames to be split on any byte boundary.  The FIFO depth is
-- expressed in terms of these LCM words.  (Default 2^4 = 16 LCM words.)
--
-- The status flags (empty, full, half-full, etc.) reflect the state of this
-- intermediate FIFO.  They do not reflect partial LCM words that may be
-- held in the input and output stages.  The fifo_full flag, for example,
-- indicates that the next write COULD overflow, but does not guarantee this.
-- Similarly, writing a single input word may or may not cause fifo_empty
-- to be deasserted.
--
-- Multi-word inputs and outputs follow the SatCat5 convention:
--  * The "NLAST" field is zero when a frame has more data.  Otherwise,
--    index N indicates that there are N valid bytes in the final word.
--  * Data is packed MSW-first and left-aligned. (i.e., Partial words
--    have data in the MSBs and should ignore junk in the LSBs.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_smol_resize is
    generic (
    IN_BYTES    : positive;             -- Width of input port
    OUT_BYTES   : positive;             -- Width of output port
    DEPTH_LOG2  : positive := 4;        -- FIFO depth = 2^N LCM words (see top)
    ERROR_UNDER : boolean := false;     -- Treat underflow as error?
    ERROR_OVER  : boolean := true;      -- Treat overflow as error?
    ERROR_PRINT : boolean := true);     -- Print message on error? (sim only)
    port (
    -- Input port
    in_data     : in  std_logic_vector(8*IN_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IN_BYTES := IN_BYTES;
    in_write    : in  std_logic;        -- Write new data word (unless full)
    -- Output port
    out_data    : out std_logic_vector(8*OUT_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to OUT_BYTES;
    out_last    : out std_logic;        -- Last word in frame
    out_valid   : out std_logic;        -- Data available to be read
    out_read    : in  std_logic;        -- Consume current word (if any)
    -- Status signals (each is optional)
    fifo_full   : out std_logic;        -- FIFO full (write may overflow)
    fifo_empty  : out std_logic;        -- FIFO empty (no data available)
    fifo_hfull  : out std_logic;        -- Half-full flag
    fifo_hempty : out std_logic;        -- Half-empty flag
    fifo_error  : out std_logic;        -- Overflow error strobe
    -- Common
    clk         : in  std_logic;        -- Clock for both ports
    reset_p     : in  std_logic);       -- Active-high sync reset
end fifo_smol_resize;

architecture fifo_smol_resize of fifo_smol_resize is

constant IN_WIDTH   : positive := 8 * IN_BYTES;
constant OUT_WIDTH  : positive := 8 * OUT_BYTES;
constant FIFO_BYTES : positive := int_lcm(IN_BYTES, OUT_BYTES);
constant FIFO_WIDTH : positive := 8 * FIFO_BYTES;
constant FIFO_LSIZE : positive := log2_ceil(FIFO_BYTES + 1);
subtype byte_count  is integer range 0 to FIFO_BYTES;
subtype fifo_meta   is std_logic_vector(FIFO_LSIZE-1 downto 0);
subtype fifo_word   is std_logic_vector(FIFO_WIDTH-1 downto 0);

-- Input stage
signal fin_data     : fifo_word := (others => '0');
signal fin_nlast    : byte_count := 0;
signal fin_meta     : fifo_meta;
signal fin_write    : std_logic := '0';

-- Output stage
signal fout_data    : fifo_word;
signal fout_nlast   : byte_count;
signal fout_meta    : fifo_meta;
signal fout_valid   : std_logic;
signal fout_read    : std_logic;

-- Internal FIFO status
signal mid_full     : std_logic;
signal mid_empty    : std_logic;
signal mid_hfull    : std_logic;
signal mid_hempty   : std_logic;
signal mid_error    : std_logic;

begin

-- Input stage:
gen_input_resize : if IN_BYTES < FIFO_BYTES generate
    -- Accumulate every N input words into one FIFO word.
    p_resize : process(clk)
        constant WMAX   : natural := FIFO_BYTES / IN_BYTES - 1;
        variable wcount : integer range 0 to WMAX := 0;
    begin
        if rising_edge(clk) then
            -- Update each part of the data register, MSW-first.
            -- (Note: End of input may not be word-aligned.)
            for n in 0 to WMAX loop
                if (in_write = '1' and wcount = WMAX-n) then
                    fin_data((n+1)*IN_WIDTH-1 downto n*IN_WIDTH) <= in_data;
                end if;
            end loop;

            -- Write each word on end-of-frame or rollover.
            if (reset_p = '1') then
                fin_nlast   <= 0;
                fin_write   <= '0';             -- FIFO reset
            elsif (in_write = '1' and in_nlast > 0) then
                fin_nlast   <= IN_BYTES * wcount + in_nlast;
                fin_write   <= '1';             -- End of frame
            else
                fin_nlast   <= 0;               -- Normal write
                fin_write   <= in_write and bool2bit(wcount = WMAX);
            end if;

            -- Update the running word-counter.
            if (reset_p = '1') then
                wcount := 0;                    -- FIFO reset
            elsif (in_write = '1') then
                if (in_nlast > 0 or wcount = WMAX) then
                    wcount := 0;                -- End of frame or rollover
                else
                    wcount := wcount + 1;       -- Normal increment
                end if;
            end if;
        end if;
    end process;
end generate;

gen_input_simple : if IN_BYTES = FIFO_BYTES generate
    -- Simple bypass for equal-size case.
    fin_data    <= in_data;
    fin_nlast   <= in_nlast;
    fin_write   <= in_write;
end generate;

-- Metadata format conversion.
fin_meta    <= i2s(fin_nlast, FIFO_LSIZE);
fout_nlast  <= u2i(fout_meta);

-- Underlying FIFO.
-- (All status flags are forwarded verbatim.)
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => FIFO_WIDTH,
    META_WIDTH  => FIFO_LSIZE,
    DEPTH_LOG2  => DEPTH_LOG2,
    ERROR_UNDER => ERROR_UNDER,
    ERROR_OVER  => ERROR_OVER,
    ERROR_PRINT => ERROR_PRINT)
    port map(
    in_data     => fin_data,
    in_meta     => fin_meta,
    in_write    => fin_write,
    out_data    => fout_data,
    out_meta    => fout_meta,
    out_valid   => fout_valid,
    out_read    => fout_read,
    fifo_full   => mid_full,
    fifo_empty  => mid_empty,
    fifo_hfull  => mid_hfull,
    fifo_hempty => mid_hempty,
    fifo_error  => mid_error,
    clk         => clk,
    reset_p     => reset_p);

-- Most status flags are forwarded verbatim.
fifo_full   <= mid_full;
fifo_hfull  <= mid_hfull;
fifo_hempty <= mid_hempty;
fifo_error  <= mid_error;

-- Output stage:
gen_output_resize : if OUT_BYTES < FIFO_BYTES generate
    b_resize : block
        constant WMAX   : natural := FIFO_BYTES / OUT_BYTES - 1;
        -- Combinational logic for FIFO.
        signal widx     : integer range 0 to WMAX := 0;
        signal wfinal   : std_logic;
        -- One-word output buffer.
        signal wdata    : std_logic_vector(OUT_WIDTH-1 downto 0);
        signal wnlast   : integer range 0 to OUT_BYTES := 0;
        signal wlast    : std_logic := '0';
        signal wvalid   : std_logic := '0';
    begin
        -- Top-level outputs.
        out_data    <= wdata;
        out_nlast   <= wnlast;
        out_last    <= wlast;
        out_valid   <= wvalid;
        fifo_empty  <= mid_empty and not wvalid;

        -- Combinational logic for the upstream FIFO.
        wfinal <= '0' when (fout_valid = '0')                   -- Idle
             else bool2bit(widx = WMAX) when (fout_nlast = 0)   -- Normal word
             else bool2bit((widx+1)*OUT_BYTES >= fout_nlast);   -- End of frame
        fout_read <= wfinal and (out_read or not wvalid);       -- Consume word?

        -- Split each FIFO word into N output words.
        p_resize : process(clk)
            variable tmp_idx : natural;
        begin
            if rising_edge(clk) then
                -- Buffer the outgoing data.
                if (out_read = '1' or wvalid = '0') then
                    tmp_idx  := (WMAX-widx) * OUT_WIDTH;
                    wdata <= fout_data(tmp_idx+OUT_WIDTH-1 downto tmp_idx);
                    if (wfinal = '1' and fout_nlast > 0) then
                        wlast   <= '1';     -- End of frame
                        wnlast  <= fout_nlast - widx * OUT_BYTES;
                    else
                        wlast   <= '0';     -- Normal data
                        wnlast  <= 0;
                    end if;
                end if;

                -- Update the word-selection state.
                if (reset_p = '1') then
                    wvalid  <= '0';     -- FIFO reset
                    widx    <= 0;
                elsif (out_read = '1' or wvalid = '0') then
                    if (wfinal = '1') then
                        wvalid  <= '1'; -- End of word
                        widx    <= 0;
                    elsif (fout_valid = '1') then
                        wvalid  <= '1'; -- Normal read
                        widx    <= widx + 1;
                    else
                        wvalid  <= '0'; -- No new data
                    end if;
                end if;
            end if;
        end process;
    end block;
end generate;

gen_output_simple : if OUT_BYTES = FIFO_BYTES generate
    -- Simple bypass for equal-size case.
    out_data    <= fout_data;
    out_nlast   <= fout_nlast;
    out_last    <= bool2bit(fout_nlast > 0);
    out_valid   <= fout_valid;
    fifo_empty  <= mid_empty;
    fout_read   <= out_read;
end generate;

end fifo_smol_resize;
