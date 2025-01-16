--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Combined queue-depth and queue-selector
--
-- This block accepts an input stream and a status indicator for each
-- output queue.  For each unicast packet in the stream, it selects the
-- depth indicator from the appropriate output queue.  Matched delay is
-- provided for packet data and metadata.
--
-- The queue monitoring function is performed by the "router2_qdepth" block.
-- (See that block for documentation of the various filter parameters.)
-- The status output is used by blocks such as "router_ecn_red".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.round;
use     work.common_functions.all;

entity router2_qsel is
    generic (
    IO_BYTES    : positive;         -- Width of datapath
    META_WIDTH  : natural;          -- Additional packet metadata?
    PORT_COUNT  : positive;         -- Number of output ports
    REFCLK_HZ   : positive;         -- Reference clock rate (Hz)
    T0_MSEC     : real := 10.0;     -- Time window for minimum
    T1_MSEC     : real := 40.0;     -- Time constant for averaging
    SUB_LSB     : boolean := true); -- Enable sub-LSB accumulators?
    port (
    -- Concatenated queue-depth from each egress FIFO.
    raw_qdepth  : in  unsigned(8*PORT_COUNT-1 downto 0);
    -- Input data stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_pdst     : in  std_logic_vector(PORT_COUNT-1 downto 0);
    in_write    : in  std_logic;
    -- Output data stream
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_write   : out std_logic;
    out_qdepth  : out unsigned(7 downto 0);
    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_qsel;

architecture router2_qsel of router2_qsel is

-- Queue depth filtering and selection.
signal filt_qdepth  : unsigned(8*PORT_COUNT-1 downto 0);
signal dly_qdepth   : unsigned(7 downto 0) := (others => '0');

-- Matched delays for other signals.
signal dly_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal dly_meta     : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal dly_nlast    : integer range 0 to IO_BYTES := 0;
signal dly_write    : std_logic := '0';

begin

-- Instantiate each queue-depth filter.
-- (Use the destination mask as a per-port output enable.)
gen_filter : for n in in_pdst'range generate
    u_qdepth : entity work.router2_qdepth
        generic map(
        REFCLK_HZ   => REFCLK_HZ,
        T0_MSEC     => T0_MSEC,
        T1_MSEC     => T1_MSEC,
        SUB_LSB     => SUB_LSB)
        port map(
        in_qdepth   => raw_qdepth(8*n+7 downto 8*n),
        out_qdepth  => filt_qdepth(8*n+7 downto 8*n),
        out_enable  => in_pdst(n),
        clk         => clk,
        reset_p     => reset_p);
end generate;

-- Matched delay.
p_qdepth : process(clk)
    variable accum : unsigned(7 downto 0);
begin
    if rising_edge(clk) then
        -- Calculate bitwise-OR of filtered status word.
        accum := (others => '0');
        for n in in_pdst'range loop
            accum := accum or filt_qdepth(8*n+7 downto 8*n);
        end loop;

        -- Unicast packets have exactly one destination set.
        if (count_ones(in_pdst) = 1) then
            dly_qdepth <= accum;
        else
            dly_qdepth <= (others => '0');
        end if;

        -- Matched delay for other signals.
        dly_data    <= in_data;
        dly_meta    <= in_meta;
        dly_nlast   <= in_nlast;
        dly_write   <= in_write and not reset_p;
    end if;
end process;

-- Drive the final outputs.
out_data    <= dly_data;
out_meta    <= dly_meta;
out_nlast   <= dly_nlast;
out_write   <= dly_write;
out_qdepth  <= dly_qdepth;

end router2_qsel;
