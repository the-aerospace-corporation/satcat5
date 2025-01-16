--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Smol Synchronous FIFO
--
-- This is a resource-light FIFO block with first-word fallthrough.  The
-- core memory element is selectable, defaulting to one that is optimized
-- for the target platform.  The default depth is 16 words.  The size can
-- be incresed to 32, 64, or 128 words as needed.  For larger sizes, please
-- consider using "fifo_large_sync" for a more efficient implementation.
--
-- Data, metadata, and the last strobe are stored on a word-by-word basis.
-- They are treated as a single atomic word internally, but split for easy
-- integration in various use-cases.  If any of these signals is not used,
-- leave it disconnected and set width to zero if applicable.
--
-- On most Xilinx platforms, the default implementation uses SRL16E or SRL32
-- (i.e., an addressable shift-register).  On other platforms, the default
-- memory element is a small block-RAM acting as a circular buffer.  The
-- black-box behavior is identical except that SRAM mode has a two-cycle
-- minimum pipeline delay, and SREG mode accepts simultaneous read+write
-- while full.  Note that "fifo_empty" is *not* the inverse of "out_valid".
--
-- The input stream is always in a strict "write if able" mode.  Users may
-- use "fifo_hfull" of "fifo_full" status indicators to provide backpressure.
-- Overflow data is dropped.  If the "ERROR_OVER" flag is set (default true),
-- then overflow events also strobe "fifo_error".
--
-- The output stream defaults to an AXI flow-control handshake, which is
-- equivalent to a "read if able" strobe.  If the "ERROR_UNDER" FLAG is
-- set (default false), then "out_read" is instead treated as a strict
-- "read" strobe that asserts "fifo_error" on an underflow event.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.dpram;
use     work.common_primitives.PREFER_FIFO_SREG;

entity fifo_smol_sync is
    generic (
    IO_WIDTH    : natural;              -- Word size
    META_WIDTH  : natural := 0;         -- Metadata size (optional)
    DEPTH_LOG2  : positive := 4;        -- FIFO depth = 2^N
    ERROR_UNDER : boolean := false;     -- Treat underflow as error?
    ERROR_OVER  : boolean := true;      -- Treat overflow as error?
    ERROR_PRINT : boolean := true;      -- Print message on error? (sim only)
    FIFO_SREG   : boolean := PREFER_FIFO_SREG;
    SIMTEST     : boolean := false);    -- Formal verification mode?
    port (
    -- Input port
    in_data     : in  std_logic_vector(IO_WIDTH-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last     : in  std_logic := '0'; -- Last word in frame (OPTIONAL)
    in_write    : in  std_logic;        -- Write new data word (unless full)
    -- Output port
    out_data    : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_last    : out std_logic;        -- Last word in frame (OPTIONAL)
    out_valid   : out std_logic;        -- Data available to be read
    out_read    : in  std_logic;        -- Consume current word (if any)
    -- Status signals (each is optional)
    fifo_full   : out std_logic;        -- FIFO full (write may overflow)
    fifo_empty  : out std_logic;        -- FIFO empty (no pipelined data)
    fifo_hfull  : out std_logic;        -- Half-full flag (n > N/2)
    fifo_hempty : out std_logic;        -- Half-empty flag (n <= N/2)
    fifo_qfull  : out std_logic;        -- Three-quarters-full flag (n > 3N/4)
    fifo_qempty : out std_logic;        -- Three-quarters-empty flag (n <= 3N/4)
    fifo_error  : out std_logic;        -- Overflow error strobe
    -- Common
    clk         : in  std_logic;        -- Clock for both ports
    reset_p     : in  std_logic);       -- Active-high sync reset
end fifo_smol_sync;

architecture fifo_smol_sync of fifo_smol_sync is

subtype data_t is std_logic_vector(META_WIDTH+IO_WIDTH downto 0);

subtype addr_t is unsigned(DEPTH_LOG2-1 downto 0);
constant ADDR_MIN : addr_t := (others => '0');
constant ADDR_MAX : addr_t := (others => '1');

signal in_word  : data_t;
signal out_word : data_t := (others => '0');
signal empty    : std_logic := '1';
signal error    : std_logic := '0';
signal hfull    : std_logic := '0';
signal qfull    : std_logic := '0';
signal full     : std_logic := '0';
signal valid    : std_logic := '0';

begin

-- Shared logic for all implementations.
in_word     <= in_last & in_meta & in_data;
out_last    <= out_word(IO_WIDTH+META_WIDTH);
out_valid   <= valid;
fifo_full   <= full;
fifo_empty  <= empty;
fifo_hfull  <= hfull;
fifo_hempty <= not hfull;
fifo_qfull  <= qfull;
fifo_qempty <= not qfull;
fifo_error  <= error;

gen_out_data : if IO_WIDTH > 0 generate
    out_data <= out_word(IO_WIDTH-1 downto 0);
end generate;

gen_out_meta : if META_WIDTH > 0 generate
    out_meta <= out_word(IO_WIDTH+META_WIDTH-1 downto IO_WIDTH);
end generate;

-- Detect error conditions.
p_error : process(clk)
    variable allow_wr : boolean := false;
begin
    if rising_edge(clk) then
        -- Note: SREG mode allows simultaneous read+write while full.
        allow_wr := (full = '0') or (FIFO_SREG and out_read = '1');
        if (ERROR_OVER and in_write = '1' and not allow_wr) then
            if (ERROR_PRINT) then
                report "fifo_smol_sync overflow" severity warning;
            end if;
            error <= '1';
        elsif (ERROR_UNDER and out_read = '1' and valid = '0') then
            if (ERROR_PRINT) then
                report "fifo_smol_sync underflow" severity warning;
            end if;
            error <= '1';
        else
            error <= '0';
        end if;
    end if;
end process;


------------------- FIFO logic for shift-register mode -------------------
gen_sreg : if FIFO_SREG generate
    blk_sreg : block
        type data_array is array(2**DEPTH_LOG2-1 downto 0) of data_t;
        signal sreg : data_array := (others => (others => '0'));
        signal addr : addr_t := ADDR_MIN;
    begin
        -- Main shift register does not require reset.
        p_sreg : process(clk)
        begin
            if rising_edge(clk) then
                -- Update contents on valid writes only.
                if (in_write = '1' and (out_read = '1' or addr /= ADDR_MAX)) then
                    sreg <= sreg(sreg'left-1 downto 0) & in_word;
                end if;
            end if;
        end process;

        -- All other control state responds to reset.
        -- Note: Empty state and single item in FIFO both have address = 0:
        --  FIFO count  0 1 2 3 4 5 6 7 8...
        --  Empty flag  1 0 0 0 0 0 0 0 0...
        --  Address     0 0 1 2 3 4 5 6 7...
        p_addr : process(clk)
        begin
            if rising_edge(clk) then
                if (reset_p = '1') then
                    addr  <= ADDR_MIN;
                    empty <= '1';
                elsif (in_write = '1' and (out_read = '0' or empty = '1')) then
                    -- Write without read: Clear empty before incrementing address.
                    if (empty = '1') then
                        empty <= '0';
                    elsif (addr /= ADDR_MAX) then
                        addr <= addr + 1;
                    end if;
                elsif (out_read = '1' and in_write = '0')  then
                    -- Read without write: Decrement address before setting empty.
                    if (addr /= ADDR_MIN) then
                        addr <= addr - 1;
                    else
                        empty <= '1';
                    end if;
                end if;
            end if;
        end process;

        -- Use the addressable SREG primitive.
        out_word <= sreg(to_integer(addr));

        -- Combinational logic for various status indicators.
        hfull <= addr(addr'left);
        qfull <= addr(addr'left) and addr(addr'left-1);
        full  <= bool2bit(addr = ADDR_MAX);
        valid <= not empty;
    end block;
end generate;

--------------------- FIFO logic for block-RAM mode ----------------------
gen_bram : if not FIFO_SREG generate
    blk_bram : block
        constant DCOUNT : natural := 2**DEPTH_LOG2;
        constant HCOUNT : natural := DCOUNT - DCOUNT / 2;
        constant QCOUNT : natural := DCOUNT - DCOUNT / 4;
        signal delta, rd_addr_d, wr_addr_d : addr_t;
        signal rd_addr_q, wr_addr_q : addr_t := ADDR_MIN;
        signal rd_en, wr_en, wr_dly : std_logic := '0';
    begin
        -- Combinational control logic.
        -- Note: Disable write-while-full for cross-platform compatibility.
        -- (Simultaneous read/write to the same address is undefined.)
        rd_addr_d <= rd_addr_q + u2i(rd_en);
        wr_addr_d <= wr_addr_q + u2i(wr_en);
        wr_en <= in_write and not full;
        rd_en <= out_read and valid;
        delta <= wr_addr_d + not rd_addr_d; -- Difference -1

        -- Instantiate platform-specific RAM block.
        u_bram : dpram
            generic map(
            AWIDTH  => DEPTH_LOG2,
            DWIDTH  => in_word'length,
            SIMTEST => SIMTEST)
            port map(
            wr_clk  => clk,
            wr_addr => wr_addr_q,
            wr_en   => wr_en,
            wr_val  => in_word,
            wr_rval => open,
            rd_clk  => clk,
            rd_addr => rd_addr_d,
            rd_val  => out_word);

        -- Control state for the circular buffer.
        p_addr : process(clk)
        begin
            if rising_edge(clk) then
                -- Read and write address increment after each word.
                if (reset_p = '1') then
                    rd_addr_q <= ADDR_MIN;
                    wr_addr_q <= ADDR_MIN;
                    wr_dly    <= '0';
                else
                    rd_addr_q <= rd_addr_d;
                    wr_addr_q <= wr_addr_d;
                    wr_dly    <= wr_en;
                end if;

                -- Delay VALID indicator for cross-platform compatibility.
                -- (Simultaneous read/write to the same address is undefined.)
                if (reset_p = '1') then
                    valid <= '0';
                elsif (wr_dly = '1' and rd_en = '0') then
                    valid <= '1';
                elsif (wr_dly = '0' and rd_en = '1') then
                    valid <= bool2bit(wr_addr_q /= rd_addr_d);
                end if;

                -- All other status indicators use the prompt write-enable.
                -- Note: DELTA = ADDR_MAX may indicate full or empty due to
                --- wraparound. Use read/write context to determine which.
                if (reset_p = '1') then
                    empty <= '1';
                    hfull <= '0';
                    qfull <= '0';
                    full  <= '0';
                elsif (wr_en = '1' and rd_en = '0') then
                    empty <= '0';
                    hfull <= bool2bit(delta >= HCOUNT);
                    qfull <= bool2bit(delta >= QCOUNT);
                    full  <= bool2bit(delta = ADDR_MAX);
                elsif (wr_en = '0' and rd_en = '1') then
                    empty <= bool2bit(delta = ADDR_MAX);
                    hfull <= bool2bit(delta >= HCOUNT and delta /= ADDR_MAX);
                    qfull <= bool2bit(delta >= QCOUNT and delta /= ADDR_MAX);
                    full  <= '0';
                end if;
            end if;
        end process;
    end block;
end generate;

end fifo_smol_sync;
