--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Packet-header augmentation for out-of-order parsing of byte-streams
--
-- In many stream-processing tasks on packet headers, it is necessary
-- to view inputs from later in the stream in order to process a given
-- output word. Updating the 1st byte of a 2-byte checksum field, for
-- example, requires knowledge of the second byte to recalculate both.
--
-- This module is designed to fulfill that need. It accepts a stream
-- with IN_BYTES per clock and writes it to a shift register, delaying
-- the output enough to "predict" the next few bytes.  Each output has
-- a nominal width of OUT_BYTES but advances by only IN_BYTES per cycle.
--
-- Example with IN_BYTES = 3, OUT_BYTES = 4:
--  Input:  0x010203,   0x040506,   0x070809
--  Output: 0x01020304, 0x04050607, 0x07080900
--  Nlast:  0,          0,          3 (end-of-frame)
--  Note trailing bytes after end-of-frame are zeroized.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity packet_augment is
    generic (
    IN_BYTES    : positive;         -- Input width
    OUT_BYTES   : positive;         -- Output width (w/ preview)
    DEPTH_LOG2  : positive := 4);   -- FIFO depth = 2^N
    port (
    -- Input stream uses AXI flow-control.
    in_data     : in  std_logic_vector(8*IN_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IN_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    -- Output stream uses AXI flow-control.
    out_data    : out std_logic_vector(8*OUT_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IN_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end packet_augment;

architecture packet_augment of packet_augment is

constant IN_WIDTH   : natural := 8 * IN_BYTES;
constant FIFO_QTR   : natural := 2**(DEPTH_LOG2-2);
constant SREG_WORDS : natural := div_ceil(OUT_BYTES, IN_BYTES);
constant SREG_BYTES : natural := IN_BYTES * SREG_WORDS;

subtype fifo_t is std_logic_vector(8*OUT_BYTES-1 downto 0);
subtype sreg_t is std_logic_vector(8*SREG_BYTES-1 downto 0);
subtype nlast_t is integer range 0 to IN_BYTES;
subtype bit_array is std_logic_vector(SREG_WORDS downto 1);
type nlast_array is array(SREG_WORDS downto 1) of nlast_t;

function eof_mask(nlast : integer) return fifo_t is
    variable tmp : fifo_t := (others => '1');
begin
    for n in tmp'range loop
        tmp(tmp'left-n) := bool2bit((nlast = 0) or (n < 8*nlast));
    end loop;
    return tmp;
end function;

-- Shift register for delayed inputs and associated metadata.
signal sreg_data    : sreg_t := (others => '0');
signal sreg_nlast   : nlast_array := (others => 0);
signal sreg_valid   : bit_array := (others => '0');
signal sreg_write   : bit_array := (others => '0');

-- Skid buffer for input and output flow control.
signal fifo_data    : fifo_t;
signal fifo_mask    : fifo_t;
signal fifo_hempty  : std_logic;
signal fifo_qempty  : std_logic;
signal in_ready_i   : std_logic;

begin

-- Upstream flow control: Worst-case skid-buffer requirement is set by
-- shift-register depth, use 1/2 or 3/4 threshold appropriately.
in_ready_i    <= fifo_qempty when (SREG_WORDS <= FIFO_QTR) else fifo_hempty;
in_ready      <= in_ready_i;

-- The first shift-register stage is the raw input.
sreg_data(8*IN_BYTES-1 downto 0) <= in_data;
sreg_nlast(1) <= in_nlast;
sreg_valid(1) <= in_valid and in_ready_i;
sreg_write(1) <= in_valid and in_ready_i;

-- Instantiate remaining shift-register stages.
-- Per-stage write strobes ensure packet data remains contiguous,
-- while also allowing the trailing end-of-frame to flush correctly.
gen_sreg : for n in 2 to SREG_WORDS generate
    sreg_write(n) <= sreg_valid(n) and bool2bit(sreg_write(n-1) = '1' or sreg_nlast(n) > 0);

    p_sreg : process(clk)
    begin
        if rising_edge(clk) then
            -- Write strobe from previous stage?
            if (sreg_write(n-1) = '1') then
                sreg_data(n*IN_WIDTH-1 downto (n-1)*IN_WIDTH)
                    <= sreg_data((n-1)*IN_WIDTH-1 downto (n-2)*IN_WIDTH);
                sreg_nlast(n) <= sreg_nlast(n-1);
            end if;
            -- The "valid" flag indicates whether each stage contains data.
            if (reset_p = '1') then
                sreg_valid(n) <= '0';   -- System reset
            elsif (sreg_write(n-1) = '1') then
                sreg_valid(n) <= '1';   -- Incoming write
            elsif (sreg_write(n) = '1') then
                sreg_valid(n) <= '0';   -- Transfer to next stage
            end if;
        end if;
    end process;
end generate;

-- Mask data after end-of-frame.
fifo_data <= sreg_data(sreg_data'left downto 8*(SREG_BYTES-OUT_BYTES));
fifo_mask <= fifo_data and eof_mask(sreg_nlast(SREG_WORDS));

-- Skid-buffer for input and output flow-control.
-- (This breaks the long combinational logic chains of "sreg_write".)
u_fifo : entity work.fifo_smol_bytes
    generic map(
    IO_BYTES    => OUT_BYTES,
    DEPTH_LOG2  => DEPTH_LOG2)
    port map(
    in_data     => fifo_mask,
    in_nlast    => sreg_nlast(SREG_WORDS),
    in_write    => sreg_write(SREG_WORDS),
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_read    => out_ready,
    fifo_hempty => fifo_hempty,
    fifo_qempty => fifo_qempty,
    clk         => clk,
    reset_p     => reset_p);

end packet_augment;
