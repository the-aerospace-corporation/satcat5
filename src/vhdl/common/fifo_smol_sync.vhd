--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Smol Synchronous FIFO
--
-- This is a resource-light FIFO block with first-word fallthrough.
-- The core memory element is an addressable shift-register. On Xilinx
-- platforms this is inferred as SRL16E or similar.  Default depth is
-- 16 words for this reason, but can be increased to 32/64/etc.
--
-- The input stream is always in a strict "write if able" mode.
--
-- The output stream can be treated as a strict "read if able" strobe
-- or as the valid/ready pair of an AXI flow-control handshake.  In the
-- latter case, ERROR_UNDER should be set to false.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity fifo_smol_sync is
    generic (
    IO_WIDTH    : natural ;             -- Word size
    META_WIDTH  : natural := 0;         -- Metadata size (optional)
    DEPTH_LOG2  : positive := 4;        -- FIFO depth = 2^N
    ERROR_UNDER : boolean := false;     -- Treat underflow as error?
    ERROR_OVER  : boolean := true;      -- Treat overflow as error?
    ERROR_PRINT : boolean := true);     -- Print message on error? (sim only)
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
    fifo_empty  : out std_logic;        -- FIFO empty (no data available)
    fifo_hfull  : out std_logic;        -- Half-full flag
    fifo_hempty : out std_logic;        -- Half-empty flag
    fifo_error  : out std_logic;        -- Overflow error strobe
    -- Common
    clk         : in  std_logic;        -- Clock for both ports
    reset_p     : in  std_logic);       -- Active-high sync reset
end fifo_smol_sync;

architecture fifo_smol_sync of fifo_smol_sync is

subtype data_t is std_logic_vector(META_WIDTH+IO_WIDTH downto 0);
type data_array is array(2**DEPTH_LOG2-1 downto 0) of data_t;

subtype addr_t is unsigned(DEPTH_LOG2-1 downto 0);
constant ADDR_MIN : addr_t := (others => '0');
constant ADDR_MAX : addr_t := (others => '1');

signal in_word  : data_t;
signal out_word : data_t;
signal sreg     : data_array := (others => (others => '0'));
signal addr     : addr_t := ADDR_MIN;
signal empty    : std_logic := '1';
signal error    : std_logic := '0';

begin

-- Main shift register does not require reset.
in_word <= in_last & in_meta & in_data;
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
        error <= '0';
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

        -- Detect error conditions.
        if (ERROR_OVER and in_write = '1' and out_read = '0' and addr = ADDR_MAX) then
            if (ERROR_PRINT) then
                report "fifo_smol_sync overflow" severity warning;
            end if;
            error <= '1';
        elsif (ERROR_UNDER and out_read = '1' and empty = '1') then
            if (ERROR_PRINT) then
                report "fifo_smol_sync underflow" severity warning;
            end if;
            error <= '1';
        else
            error <= '0';
        end if;
    end if;
end process;

-- Xilinx SREG primitives are addressable.
out_word    <= sreg(to_integer(addr));

-- Output and status signals are driven by combinational logic.
-- MSB of address makes a good "half full" indicator.
out_last    <= out_word(IO_WIDTH+META_WIDTH);
out_valid   <= not empty;
fifo_full   <= '1' when (addr = ADDR_MAX) else '0';
fifo_empty  <= empty;
fifo_hfull  <= addr(addr'left);
fifo_hempty <= not addr(addr'left);
fifo_error  <= error;

gen_out_data : if IO_WIDTH > 0 generate
    out_data <= out_word(IO_WIDTH-1 downto 0);
end generate;

gen_out_meta : if META_WIDTH > 0 generate
    out_meta <= out_word(IO_WIDTH+META_WIDTH-1 downto IO_WIDTH);
end generate;

end fifo_smol_sync;
