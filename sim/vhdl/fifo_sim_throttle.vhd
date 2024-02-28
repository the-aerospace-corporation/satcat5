--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Packet FIFO with built-in output throttle
--
-- This block is a thin-wrapper for "fifo_packet" that adds an adjustable
-- throttle at the output for simulation purposes.  It is not intended to
-- be synthesizable.
--
-- Note: Minimum META_WIDTH is 1 to prevent simulation warnings about
--   undriven null signals; leave in_meta/out_meta disconnected if unused.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity fifo_sim_throttle is
    generic (
    INPUT_BYTES     : positive;             -- Width of input port
    OUTPUT_BYTES    : positive;             -- Width of output port
    BUFFER_KBYTES   : positive := 2;        -- Buffer size (kilobytes)
    META_WIDTH      : positive := 1);       -- Packet metadata width (optional)
    port (
    -- Input port does not use flow control.
    in_clk          : in  std_logic;
    in_data         : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_meta         : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_nlast        : in  integer range 0 to INPUT_BYTES := INPUT_BYTES;
    in_write        : in  std_logic;

    -- Output port uses AXI-style flow control.
    out_clk         : in  std_logic;
    out_data        : out std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
    out_meta        : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast       : out integer range 0 to OUTPUT_BYTES;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_reset       : out std_logic;        -- Synchronized copy of reset_p
    out_pause       : in  std_logic := '0'; -- Optional: Don't start next packet
    out_rate        : in  real := 1.0;      -- Max output duty-cycle (0-100%)

    -- Global asynchronous reset.
    reset_p         : in  std_logic);
end fifo_sim_throttle;

architecture fifo_sim_throttle of fifo_sim_throttle is

signal in_commit    : std_logic;
signal mid_data     : std_logic_vector(8*OUTPUT_BYTES-1 downto 0);
signal mid_meta     : std_logic_vector(META_WIDTH-1 downto 0);
signal mid_nlast    : integer range 0 to OUTPUT_BYTES;
signal mid_valid    : std_logic;
signal mid_ready    : std_logic;
signal mid_rden     : std_logic := '0';
signal out_data_i   : std_logic_vector(8*OUTPUT_BYTES-1 downto 0) := (others => '0');
signal out_meta_i   : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal out_nlast_i  : integer range 0 to OUTPUT_BYTES := 0;
signal out_valid_i  : std_logic := '0';
signal out_reset_i  : std_logic;

begin

-- Automatically commit at end-of-frame.
in_commit <= in_write and bool2bit(in_nlast > 0);

-- Inner FIFO.
u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => INPUT_BYTES,
    OUTPUT_BYTES    => OUTPUT_BYTES,
    BUFFER_KBYTES   => BUFFER_KBYTES,
    META_WIDTH      => META_WIDTH)
    port map(
    in_clk          => in_clk,
    in_data         => in_data,
    in_nlast        => in_nlast,
    in_pkt_meta     => in_meta,
    in_last_commit  => in_commit,
    in_last_revert  => '0',
    in_write        => in_write,
    in_reset        => open,
    in_overflow     => open,
    out_clk         => out_clk,
    out_data        => mid_data,
    out_nlast       => mid_nlast,
    out_pkt_meta    => mid_meta,
    out_last        => open,
    out_valid       => mid_valid,
    out_ready       => mid_ready,
    out_reset       => out_reset_i,
    out_overflow    => open,
    out_pause       => out_pause,
    reset_p         => reset_p);

-- Output stage and flow-control randomization.
mid_ready <= mid_rden and (out_ready or not out_valid_i);

p_out : process(out_clk)
    variable seed1, seed2 : positive := 18957091;
    variable rand : real := 0.0;
begin
    if rising_edge(out_clk) then
        -- Buffer for output.
        if (out_reset_i = '1') then
            out_data_i  <= (others => '0');
            out_meta_i  <= (others => '0');
            out_nlast_i <= 0;
            out_valid_i <= '0'; -- Global reset
        elsif (mid_valid = '1' and mid_ready = '1') then
            out_data_i  <= mid_data;
            out_meta_i  <= mid_meta;
            out_nlast_i <= mid_nlast;
            out_valid_i <= '1'; -- New output data
        elsif (out_ready = '1') then
            out_valid_i <= '0'; -- Output consumed
        end if;

        -- Flow-control randomization.
        uniform(seed1, seed2, rand);
        mid_rden <= bool2bit(rand < out_rate) and not (out_pause or out_reset_i);
    end if;
end process;

-- Drive final outputs.
out_data    <= out_data_i;
out_meta    <= out_meta_i;
out_nlast   <= out_nlast_i;
out_valid   <= out_valid_i;
out_reset   <= out_reset_i;

end fifo_sim_throttle;
