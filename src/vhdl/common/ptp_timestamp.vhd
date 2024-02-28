--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Apply start-of-frame timestamps for the Precision Time Protocol (PTP)
--
-- Given a data stream and a time reference, this block applies a timestamp
-- at the start of each observed frame.  The same block can be used for both
-- ingress and egress timestamps, to measure elapsed time.  If provided with
-- a reference (in_tref), it will add that value to the output timestamp.
--
-- Timestamps are stored in a small FIFO to handle cases where there is
-- a pipeline delay between measuring and consuming each timestamp.
-- Including this FIFO, worst-case latency is two clock cycles.
--
-- If ConfigBus is enabled, port configuration logic can set a fixed offset
-- that is added to each timestamp value.  The single read-write register
-- is a signed 32-bit integer where each LSB is 2^-16 nanoseconds.  This
-- allows for precise calibration of various fixed delays.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_timestamp is
    generic (
    IO_BYTES    : positive;
    PTP_STRICT  : boolean := false;
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Information from the port.
    in_tnow     : in  tstamp_t;     -- Time counter (see ptp_counter_sync)
    in_adjust   : in  std_logic;    -- Timestamp adjustment required?
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic;    -- New-data strobe
    -- Optional reference is added to TNOW.
    in_tref     : in  tstamp_t := TSTAMP_DISABLED;
    -- Timestamp metadata for the packet FIFO.
    out_tstamp  : out tstamp_t;     -- Packet timestamp
    out_error   : out std_logic;    -- Valid timestamp?
    out_valid   : out std_logic;    -- AXI flow-control
    out_ready   : in  std_logic;    -- AXI flow-control
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- Clock and reset
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_timestamp;

architecture ptp_timestamp of ptp_timestamp is

signal in_first     : std_logic := '1';
signal in_error     : std_logic;
signal fifo_din     : tstamp_t := (others => '0');
signal fifo_error   : std_logic := '0';
signal fifo_write   : std_logic := '0';
signal fifo_dout    : std_logic_vector(TSTAMP_WIDTH-1 downto 0);
signal cfg_word     : cfgbus_word := (others => '0');
signal cfg_offset   : tstamp_t := (others => '0');

begin

-- Detect missing timestamps.
in_error <= in_adjust and bool2bit(in_tnow = TSTAMP_DISABLED);

-- Track start-of-frame and add offset, if applicable.
p_tstamp : process(clk)
begin
    if rising_edge(clk) then
        -- Update the start-of-frame indicator.
        if (reset_p = '1') then
            in_first <= '1';                    -- Global reset, next is SOF
        elsif (in_write = '1') then
            in_first <= bool2bit(in_nlast > 0); -- End of frame, next is SOF
        end if;

        -- Apply software offset and calculate difference, if applicable.
        if (in_adjust = '0') then
            fifo_din <= (others => 'X');        -- Unused / don't-care
        elsif (in_error = '1' and not PTP_STRICT) then
            fifo_din <= in_tref;                -- Attempt as-is propagation?
        else
            fifo_din <= in_tref + in_tnow + cfg_offset;
        end if;
        fifo_error <= in_error and bool2bit(PTP_STRICT);

        -- Timestamp is written to FIFO at the start of each frame.
        fifo_write <= in_write and in_first and not reset_p;
    end if;
end process;

-- Timestamp FIFO.
u_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => TSTAMP_WIDTH)
    port map(
    in_data     => std_logic_vector(fifo_din),
    in_last     => fifo_error,
    in_write    => fifo_write,
    out_data    => fifo_dout,
    out_last    => out_error,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

out_tstamp <= unsigned(fifo_dout);

-- Sign extension from 32-bits to TSTAMP_WIDTH.
cfg_offset <= unsigned(resize(signed(cfg_word), TSTAMP_WIDTH));

-- ConfigBus interface.
u_cfg : cfgbus_register_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR,
    WR_ATOMIC   => true)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    sync_clk    => clk,
    sync_val    => cfg_word);

end ptp_timestamp;
