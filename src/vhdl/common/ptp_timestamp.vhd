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
-- a reference (ref_time), it will add that value to the output timestamp.
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
    PTP_DOPPLER : boolean := false;
    PTP_STRICT  : boolean := false;
    RELAX_TFREQ : boolean := true;
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Information from the port.
    in_tnow     : in  tstamp_t;     -- Time counter (see ptp_counter_sync)
    in_tfreq    : in  tfreq_t;      -- Normalized frequency offset
    in_adj_time : in  std_logic;    -- Timestamp adjustment required?
    in_adj_freq : in  std_logic;    -- Frequency adjustment required?
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic;    -- New-data strobe
    -- Optional reference is added to TNOW or TFREQ.
    ref_time    : in  tstamp_t := TSTAMP_ZERO;
    ref_freq    : in  tfreq_t := TFREQ_ZERO;
    -- Timestamp metadata for the packet FIFO.
    out_tstamp  : out tstamp_t;     -- Packet timestamp
    out_tfreq   : out tfreq_t;      -- Packet frequency offset
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
signal miss_tnow    : std_logic;
signal miss_tfreq   : std_logic;
signal fifo_in_time : tstamp_t := (others => '0');
signal fifo_in_freq : tfreq_t := (others => '0');
signal fifo_error   : std_logic := '0';
signal fifo_write   : std_logic := '0';
signal fifo_out_time: std_logic_vector(TSTAMP_WIDTH-1 downto 0);
signal fifo_out_freq: std_logic_vector(TFREQ_WIDTH-1 downto 0);
signal cfg_word     : cfgbus_word := (others => '0');
signal cfg_offset   : tstamp_t := (others => '0');

begin

-- Detect missing timestamps.
miss_tnow   <= bool2bit(in_adj_time = '1' and in_tnow = TSTAMP_DISABLED);
miss_tfreq  <= bool2bit(in_adj_freq = '1' and in_tfreq = TFREQ_DISABLED);

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
        -- (Equivalent logic for timestamp and frequency changes.)
        if (in_adj_time = '0') then
            fifo_in_time <= (others => 'X');    -- Unused / don't-care
        elsif (miss_tnow = '1' and not PTP_STRICT) then
            fifo_in_time <= ref_time;            -- Attempt as-is propagation?
        else
            fifo_in_time <= ref_time + in_tnow + cfg_offset;
        end if;

        if (in_adj_freq = '0') then
            fifo_in_freq <= (others => 'X');    -- Unused / don't-care
        elsif (miss_tfreq = '1' and not PTP_STRICT) then
            fifo_in_freq <= ref_freq;           -- Attempt as-is propagation?
        else
            fifo_in_freq <= ref_freq + in_tfreq;
        end if;

        -- Error strobe if either tag is missing in strict mode.
        fifo_error <= bool2bit(PTP_STRICT) and (miss_tnow or miss_tfreq);

        -- Timestamp is written to FIFO at the start of each frame.
        fifo_write <= in_write and in_first and not reset_p;
    end if;
end process;

-- Timestamp FIFO.
-- Note: Frequency is slow-varying; with low impact if it's off by a few
--  clock cycles. Allow users to save resources by setting RELAX_TFREQ.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => TSTAMP_WIDTH,
    META_WIDTH  => TFREQ_WIDTH)
    port map(
    in_data     => std_logic_vector(fifo_in_time),
    in_meta     => std_logic_vector(fifo_in_freq),
    in_last     => fifo_error,
    in_write    => fifo_write,
    out_data    => fifo_out_time,
    out_meta    => fifo_out_freq,
    out_last    => out_error,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

out_tstamp  <= unsigned(to_01_vec(fifo_out_time));
out_tfreq   <= fifo_in_freq when RELAX_TFREQ
          else signed(to_01_vec(fifo_out_freq));

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
