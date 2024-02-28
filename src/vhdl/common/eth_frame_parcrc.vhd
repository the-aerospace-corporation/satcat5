--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Parallel calculation of Ethernet CRC/FCS
--
-- Given a stream of frames, calculate the Ethernet CRC32 using a variant
-- of the "slice-by-N" algorithm, which extends the Sarwate lookup table
-- algorithm to handle multiple parallel bytes.
--
-- For an accessible description of the algorithm, refer to:
--  * Stephan Brumme, "Fast CRC32"
--      https://create.stephan-brumme.com/crc32/#slicing-by-8-overview
--
-- For more formal explorations of this algorithm on FPGAs:
--  * Kounavis and Berry, "Novel Table Lookup-Based Algorithms
--      for High-Performance CRC Generation", IEEE-ToC 2008.
--      https://ieeexplore.ieee.org/document/4531728
--  * Akagic and Amano, "Performance Evaluation of Multiple Lookup Tables
--      Algorithms for generating CRC on an FPGA", IEEE-ISAS 2011.
--      https://ieeexplore.ieee.org/abstract/document/5960941
--  * Indu and Manu, "Cyclic Redundancy Check Generation Using Multiple
--      Lookup Table Algorithms", IJMER 2012.
--      https://www.ijmer.com/papers/Vol2_Issue4/CO2424452451.pdf
--
-- The algorithm uses an array of 256-word by 32-bit lookup tables that
-- is amenable to parallel implementation using either BRAM or LUTRAM on
-- most FPGA platforms, and scales to very high throughput.
--
-- The "slice-by-N" algorithm requires a fixed word size.  Since our input
-- is not typically aligned to the word size, we augment a standard slice-
-- by-N closed-loop feedback stage with a series of shorter feedforward
-- updates to handle the trailing "ragged end" of each frame.
--
-- Each stage of this pipeline is another instance of the "slice-by-N"
-- algorithm, but with a different increment size.  Since the first stage
-- requires closed-loop feedback in a single cycle, it must always process
-- the full word size.  The following stages contain a radix-2 tree where
-- each stage can be enabled or bypassed, to allow incremental consumption
-- of any trailing word without compromising throughput.  For example:
--  * IO_BYTES = 8 --> Closed-loop 8, Feedforward 4, 2, 1
--  * IO_BYTES = 12 --> Closed-loop 12, Feedfoward 8, 4, 2, 1
--
-- Flow-control is feedforward (i.e., write-strobe only, no backpressure),
-- with a fixed latency of 1 + log2_ceil(IO_BYTES) clock cycles.  The
-- design can handle a full packet every clock with no required inter-frame
-- gaps.  A matched-delay copy of the original input is provided at the
-- output, with the frame's CRC32 provided in sync with the LAST strobe.
--
-- An optional "in_error" strobe can be asserted at any point during the
-- input frame to set the "out_error" flag for the rest of the frame.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_parcrc is
    generic (
    IO_BYTES    : positive);    -- I/O width for frame data
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
end eth_frame_parcrc;

architecture eth_frame_parcrc of eth_frame_parcrc is

-- Local type definitions
type crc_table_t is array(0 to 255) of crc_word_t;
type crc_tables_t is array(natural range<>) of crc_table_t;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;
constant FCS_BYTES : integer := 4;
constant XOR_BYTES : integer := int_max(FCS_BYTES, IO_BYTES);
constant CRC_STAGES : integer := log2_ceil(IO_BYTES);

-- Helper type for the pipeline outputs.
type stage_t is record
    rdata   : data_t;       -- Original input data
    sdata   : data_t;       -- Shifted input data
    nlast   : last_t;       -- End-of-frame indicator
    crc     : crc_word_t;   -- Checksum register for this stage
    error   : std_logic;    -- Sticky frame-error flag
    wren    : std_logic;    -- Clock enable / new-data strobe
end record;

type stage_array is array(0 to CRC_STAGES) of stage_t;

constant STAGE_RST : stage_t := (
    rdata   => (others => '0'),
    sdata   => (others => '0'),
    nlast   => 0,
    crc     => CRC_INIT,
    error   => '0',
    wren    => '0');

-- Create lookup table for Sarwate's algorithm.
function gen_table_sarwate(poly : crc_word_t) return crc_table_t is
    variable accum, bmask : crc_word_t := (others => '0');
    variable crctbl : crc_table_t := (others => (others => '0'));
begin
    for x in 0 to 255 loop
        accum := i2s(x, 32);
        for i in 0 to 7 loop
            bmask := (others => accum(0));
            accum := shift_right(accum, 1) xor (poly and bmask);
        end loop;
        crctbl(x) := accum;
    end loop;
    return crctbl;
end function;

-- Generate table for the IEEE 802.3 polynomial.
constant TABLE_REF : crc_table_t := gen_table_sarwate(x"EDB88320");

-- Increment a lookup table entry with a trailing zero byte.
function table_incr(prev : crc_word_t) return crc_word_t is
    constant tmp : crc_word_t :=
        shift_right(prev, 8) xor TABLE_REF(u2i(prev(7 downto 0)));
begin
    return tmp;
end function;

-- Build a full set of "slice-by-N" lookup tables.
function gen_crc_tables(n : positive) return crc_tables_t is
    -- Index 0 = Table for first of N bytes,
    -- Index 1 = Table for second of N bytes...
    variable crctbl : crc_tables_t(0 to n-1);
begin
    -- Last-byte iteration is just the Sarwate loop table.
    crctbl(n-1) := TABLE_REF;
    -- Each subsequent iteration adds a trailing zero byte.
    -- (i.e., Transforming the table for "ABC" into the table for "ABC0".)
    for m in n-1 downto 1 loop
        for x in 0 to 255 loop
            crctbl(m-1)(x) := table_incr(crctbl(m)(x));
        end loop;
    end loop;
    return crctbl;
end function;

-- Convert the first N bytes of input vector to canonical form.
function convert_input(x:std_logic_vector; n:positive) return std_logic_vector is
    variable tmp : std_logic_vector(8*n-1 downto 0) := (others => '0');
begin
    for b in tmp'range loop
        tmp(b) := x(x'left-7 - 8*(b/8) + (b mod 8));
    end loop;
    return tmp;
end function;

-- Get the N least-significant bytes from CRC, zero-pad as needed.
function convert_crc(x:crc_word_t; n:positive) return std_logic_vector is
    variable tmp : std_logic_vector(8*n-1 downto 0) := (others => '0');
begin
    if (n >= 4) then
        tmp(31 downto 0) := x;
    else
        tmp := x(8*n-1 downto 0);
    end if;
    return tmp;
end function;

-- How many byte-lanes in the Nth pipeline stage? (0 = final output)
-- First stage (n = CRC_STAGES) handles full-size words only.  All
-- subsequent stages are fixed-size feedforward logic to handle any
-- trailing partial words, 2^n bytes at a time.
-- e.g., For IO_BYTES = 8: N = 8, 4, 2, 1
-- e.g., For IO_BYTES = 12: N = 12, 8, 4, 2, 1
function stage_size(n : integer) return positive is
begin
    if (n >= CRC_STAGES) then
        return IO_BYTES;
    else
        return 2**n;
    end if;
end function;

-- Local signals
signal in_first     : std_logic := '1';
signal fcs_stage    : stage_array := (others => STAGE_RST);

begin

-- Track the first word in each input frame.
p_first : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            in_first <= '1';
        elsif (in_write = '1') then
            in_first <= bool2bit(in_nlast > 0);
        end if;
    end if;
end process;

-- Generate each pipeline stage.
-- Note: Pipeline stages at P = CRC_STAGES and ends at P = 0.
gen_stage : for p in 0 to CRC_STAGES generate
    p_crc : process(clk)
        -- Create lookup tables for this stage.
        constant NBYTES  : positive := stage_size(p);
        constant CRC_TBL : crc_tables_t := gen_crc_tables(NBYTES);
        -- Temporary variables used for combinational logic ONLY.
        variable tmp_len : unsigned(CRC_STAGES downto 0);
        variable tmp_en  : std_logic;
        variable tmp_err : std_logic;
        variable tmp_crc : crc_word_t;
        variable tmp_dat : data_t;
        variable tmp_xor : std_logic_vector(8*NBYTES-1 downto 0);
        variable tmp_idx : integer range 0 to 255;
        -- Cumulative XOR for the output from this stage.
        variable crc_out : crc_word_t;
    begin
        if rising_edge(clk) then
            -- Extract input vectors for this stage.
            if (p = CRC_STAGES) then
                -- First stage needs to check for start-of-frame.
                tmp_len := (others => '0'); -- Unused
                tmp_en  := in_write and bool2bit(in_nlast = 0 or in_nlast = IO_BYTES);
                tmp_dat := in_data;
                if (in_first = '1') then
                    tmp_crc := CRC_INIT;
                    tmp_err := in_error and in_write;
                else
                    tmp_crc := fcs_stage(p).crc;
                    tmp_err := fcs_stage(p).error or (in_error and in_write);
                end if;
            else
                -- Feedforward stage.
                tmp_len := to_unsigned(fcs_stage(p+1).nlast, CRC_STAGES+1);
                tmp_en  := bool2bit(tmp_len < IO_BYTES) and tmp_len(p);
                tmp_dat := fcs_stage(p+1).sdata;
                tmp_crc := fcs_stage(p+1).crc;
                tmp_err := 'X';  -- Unused
            end if;

            -- Format conversion of input and CRC fields, then XOR.
            tmp_xor := convert_input(tmp_dat, NBYTES) xor convert_crc(tmp_crc, NBYTES);

            -- If enabled, CRC calculation for the next NBYTES of input.
            if (tmp_en = '1') then
                -- Shift the input CRC (may be constant zero if NBYTES >= 4).
                crc_out := shift_right(tmp_crc, 8*NBYTES);
                -- Table lookup for each byte with XOR reduction.
                for m in 0 to NBYTES-1 loop
                    tmp_idx := u2i(tmp_xor(8*m+7 downto 8*m));
                    crc_out := crc_out xor CRC_TBL(m)(tmp_idx);
                end loop;
            else
                -- This stage is bypassed.
                crc_out := tmp_crc;
            end if;

            -- Drive output for this stage.
            if (p = CRC_STAGES) then
                -- First stage
                fcs_stage(p) <= (
                    rdata   => in_data,
                    sdata   => in_data,
                    nlast   => in_nlast,
                    crc     => crc_out,
                    error   => tmp_err,
                    wren    => in_write and not reset_p);
            elsif (tmp_en = '1') then
                -- Feedforward stage (enabled)
                fcs_stage(p) <= (
                    rdata   => fcs_stage(p+1).rdata,
                    sdata   => shift_left(fcs_stage(p+1).sdata, 8*NBYTES),
                    nlast   => fcs_stage(p+1).nlast,
                    crc     => crc_out,
                    error   => fcs_stage(p+1).error,
                    wren    => fcs_stage(p+1).wren and not reset_p);
            else
                -- Feedforward stage (passthrough)
                fcs_stage(p) <= (
                    rdata   => fcs_stage(p+1).rdata,
                    sdata   => fcs_stage(p+1).sdata,
                    nlast   => fcs_stage(p+1).nlast,
                    crc     => crc_out,
                    error   => fcs_stage(p+1).error,
                    wren    => fcs_stage(p+1).wren and not reset_p);
            end if;
        end if;
    end process;
end generate;

-- Early copy of output stream.
gen_dly0 : if (CRC_STAGES = 0) generate
    dly_data    <= in_data;
    dly_nlast   <= in_nlast;
    dly_write   <= in_write;
end generate;

gen_dly1 : if (CRC_STAGES > 0) generate
    dly_data    <= fcs_stage(1).rdata;
    dly_nlast   <= fcs_stage(1).nlast;
    dly_write   <= fcs_stage(1).wren;
end generate;

-- Final output conversion.
out_data  <= fcs_stage(0).rdata;
out_crc   <= not endian_swap(fcs_stage(0).crc);
out_res   <= flip_word(fcs_stage(0).crc);
out_error <= fcs_stage(0).error;
out_nlast <= fcs_stage(0).nlast;
out_write <= fcs_stage(0).wren;

end eth_frame_parcrc;
