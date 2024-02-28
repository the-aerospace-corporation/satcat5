--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Multi-byte wrapper for "fifo_smol_sync"
--
-- This wrapper provides format conversion for the "NLAST" signal used
-- in multi-byte pipelines throughout SatCat5.  For more information
-- on this convention, refer to "fifo_packet.vhd".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_smol_bytes is
    generic (
    IO_BYTES    : natural;              -- Word size (in bytes)
    META_WIDTH  : natural := 0;         -- Metadata size (optional)
    DEPTH_LOG2  : positive := 4;        -- FIFO depth = 2^N
    ERROR_UNDER : boolean := false;     -- Treat underflow as error?
    ERROR_OVER  : boolean := true;      -- Treat overflow as error?
    ERROR_PRINT : boolean := true);     -- Print message on error? (sim only)
    port (
    -- Input port
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic;        -- Write new data word (unless full)
    -- Output port
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
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
end fifo_smol_bytes;

architecture fifo_smol_bytes of fifo_smol_bytes is

constant NLAST_WIDTH : positive := log2_ceil(IO_BYTES+1);
constant META_TOTAL  : positive := META_WIDTH + NLAST_WIDTH;

signal in_meta_ext  : std_logic_vector(META_TOTAL-1 downto 0);
signal out_meta_ext : std_logic_vector(META_TOTAL-1 downto 0);

begin

-- Concatenate "IN_NLAST" field with other metadata.
in_meta_ext <= i2s(in_nlast, NLAST_WIDTH) & in_meta;

-- Wrapped FIFO block.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8*IO_BYTES,
    META_WIDTH  => META_TOTAL,
    DEPTH_LOG2  => DEPTH_LOG2,
    ERROR_UNDER => ERROR_UNDER,
    ERROR_OVER  => ERROR_OVER,
    ERROR_PRINT => ERROR_PRINT)
    port map(
    in_data     => in_data,
    in_meta     => in_meta_ext,
    in_write    => in_write,
    out_data    => out_data,
    out_meta    => out_meta_ext,
    out_valid   => out_valid,
    out_read    => out_read,
    fifo_full   => fifo_full,
    fifo_empty  => fifo_empty,
    fifo_hfull  => fifo_hfull,
    fifo_hempty => fifo_hempty,
    fifo_error  => fifo_error,
    clk         => clk,
    reset_p     => reset_p);

-- Separate NLAST and metadata fields from output.
out_nlast   <= u2i(out_meta_ext(META_TOTAL-1 downto META_WIDTH));
out_meta    <= out_meta_ext(META_WIDTH-1 downto 0);

end fifo_smol_bytes;
