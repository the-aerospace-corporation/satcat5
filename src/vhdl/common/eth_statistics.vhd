--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Stream traffic statistics
--
-- This module maintains counters for the following traffic statistics:
--   * Broadcast bytes received (from device to switch)
--   * Broadcast frames received
--   * Total bytes received (from device to switch)
--   * Total frames received
--   * Total bytes sent (from switch to device)
--   * Total frames sent
--
-- The interface is a passive "tap" off the flow-control signals going
-- to and from each port (i.e., rx_data, tx_data, tx_ctrl).  It does
-- not require control; it merely monitors passively.
--
-- To facilitate clock-domain crossing, counter values are latched by
-- a toggle signal. Once updated, the values are frozen until the next
-- toggle signal; this allows a safe quasi-static transition to any
-- other clock domain. Each strobe also resets the working counters for
-- the next reporting interval.
--
-- This block pairs well with the config_send_status block, for example,
-- to send once per second statistics on switch traffic for each port.
-- It is also used inside config_stats_axi and config_stats_uart.
--
-- By default, counters saturate at 2^COUNT_WIDTH-1.  This safety feature
-- can be disabled to assist with timing closure if needed.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer_slv;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_statistics is
    generic (
    IO_BYTES    : positive;     -- Max bytes per clock
    COUNT_WIDTH : positive;     -- Width of each statistics counter
    SAFE_COUNT  : boolean);     -- Safe counters (no overflow)
    port (
    -- Statistics interface (bytes received/sent, frames received/sent
    stats_req_t : in  std_logic;        -- Toggle to request next block
    bcst_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    bcst_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_frames : out unsigned(COUNT_WIDTH-1 downto 0);

    -- Port status-reporting.
    port_rate   : in  port_rate_t;
    port_status : in  port_status_t;
    status_clk  : in  std_logic;
    status_word : out cfgbus_word;

    -- Error counters.
    err_port    : in  port_error_t;
    err_mii     : out byte_u;
    err_ovr_tx  : out byte_u;
    err_ovr_rx  : out byte_u;
    err_pkt     : out byte_u;
    err_ptp_tx  : out byte_u;
    err_ptp_rx  : out byte_u;

    -- Traffic stream to be monitored.
    rx_reset_p  : in  std_logic;
    rx_clk      : in  std_logic;
    rx_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    rx_nlast    : in  integer range 0 to IO_BYTES;
    rx_write    : in  std_logic;

    tx_reset_p  : in  std_logic;
    tx_clk      : in  std_logic;
    tx_nlast    : in  integer range 0 to IO_BYTES;
    tx_write    : in  std_logic);
end eth_statistics;

architecture eth_statistics of eth_statistics is

subtype counter_t is unsigned(COUNT_WIDTH-1 downto 0);
constant COUNT_ZERO     : counter_t := to_unsigned(0, COUNT_WIDTH);
constant COUNT_ONE      : counter_t := to_unsigned(1, COUNT_WIDTH);
constant BYTE_ZERO      : byte_u := to_unsigned(0, 8);
constant BYTE_ONE       : byte_u := to_unsigned(1, 8);

-- Increment counter with polling.
function accumulator(
    acc: counter_t;     -- Accumulator value
    inc: counter_t;     -- Increment value
    rst: std_logic;     -- Global reset
    rd:  std_logic;     -- Read/consume counter
    en:  std_logic)     -- Increment enable
    return counter_t is
begin
    if (rst = '1') then
        return COUNT_ZERO;                          -- Reset
    elsif (rd = '1' and en = '0') then
        return COUNT_ZERO;                          -- Consumed
    elsif (rd = '1' and en = '1') then
        return inc;                                 -- Consumed + add
    elsif (en = '1' and SAFE_COUNT) then
        return saturate_add(acc, inc, COUNT_WIDTH); -- Safe add
    elsif (en = '1') then
        return acc + inc;                           -- Unsafe add
    else
        return acc;                                 -- No change
    end if;
end function;

function accum_err(
    acc: byte_u;        -- Accumulator value
    inc: std_logic;     -- Increment enable
    rd:  std_logic)     -- Read/consume counter
    return byte_u is
begin
    if (rd = '1' and inc = '0') then
        return BYTE_ZERO;                           -- Consumed
    elsif (rd = '1') then
        return BYTE_ONE;                            -- Cosumed + add
    elsif (inc = '1' and SAFE_COUNT) then
        return saturate_add(acc, BYTE_ONE, 8);      -- Safe add
    elsif (inc = '1') then
        return acc + BYTE_ONE;                      -- Unsafe add
    else
        return acc;                                 -- No change
    end if;
end function;

-- Combinational logic for next-byte and last-byte strobes.
signal rx_isff          : std_logic_vector(IO_BYTES-1 downto 0) := (others => '0');
signal rx_eof,  tx_eof  : std_logic := '0';         -- Counter clock enable
signal rx_last, tx_last : std_logic := '0';         -- Last word in frame
signal rx_incr, tx_incr : counter_t := COUNT_ZERO;  -- Valid bytes in word

-- Working counters for moment-to-moment updates.
signal wrk_bcst_bytes   : counter_t := (others => '0');
signal wrk_bcst_frames  : counter_t := (others => '0');
signal wrk_rcvd_bytes   : counter_t := (others => '0');
signal wrk_rcvd_frames  : counter_t := (others => '0');
signal wrk_sent_bytes   : counter_t := (others => '0');
signal wrk_sent_frames  : counter_t := (others => '0');
signal wrk_err_mii      : byte_u := (others => '0');
signal wrk_err_ovr_tx   : byte_u := (others => '0');
signal wrk_err_ovr_rx   : byte_u := (others => '0');
signal wrk_err_pkt      : byte_u := (others => '0');
signal wrk_err_ptp_tx   : byte_u := (others => '0');
signal wrk_err_ptp_rx   : byte_u := (others => '0');

-- Latched values for clock-domain crossing.
signal lat_bcst_bytes   : counter_t := (others => '0');
signal lat_bcst_frames  : counter_t := (others => '0');
signal lat_rcvd_bytes   : counter_t := (others => '0');
signal lat_rcvd_frames  : counter_t := (others => '0');
signal lat_sent_bytes   : counter_t := (others => '0');
signal lat_sent_frames  : counter_t := (others => '0');
signal lat_err_mii      : byte_u := (others => '0');
signal lat_err_ovr_tx   : byte_u := (others => '0');
signal lat_err_ovr_rx   : byte_u := (others => '0');
signal lat_err_pkt      : byte_u := (others => '0');

-- Clock crossing.
signal stats_req_rx     : std_logic;
signal stats_req_tx     : std_logic;
signal stats_req_st     : std_logic;
signal evt_mii_err      : std_logic;
signal evt_ovr_tx       : std_logic;
signal evt_ovr_rx       : std_logic;
signal evt_pkt_err      : std_logic;
signal evt_ptp_tx_err   : std_logic;
signal evt_ptp_rx_err   : std_logic;
signal status_async     : cfgbus_word;

begin

-- Drive top-level outputs.
bcst_bytes  <= lat_bcst_bytes;
bcst_frames <= lat_bcst_frames;
rcvd_bytes  <= lat_rcvd_bytes;
rcvd_frames <= lat_rcvd_frames;
sent_bytes  <= lat_sent_bytes;
sent_frames <= lat_sent_frames;
err_mii     <= lat_err_mii;
err_ovr_tx  <= lat_err_ovr_tx;
err_ovr_rx  <= lat_err_ovr_rx;
err_pkt     <= lat_err_pkt;

-- Receive clock domain.
p_stats_rx : process(rx_clk)
    function is_byte_ff(x : std_logic_vector; b : integer) return std_logic is
        variable tmp : byte_t := x(x'left-8*b downto x'left-8*b-7);
    begin
        return bool2bit(tmp = x"FF");
    end function;

    constant WCOUNT_MAX : positive := div_ceil(ETH_HDR_SRCMAC, IO_BYTES);
    variable frm_wcount : integer range 0 to WCOUNT_MAX := 0;
    variable frm_bytes  : counter_t := COUNT_ZERO;
    variable is_bcast   : std_logic := '1';
begin
    if rising_edge(rx_clk) then
        -- On demand, update the latched value.
        if (stats_req_rx = '1') then
            lat_bcst_bytes  <= wrk_bcst_bytes;
            lat_bcst_frames <= wrk_bcst_frames;
            lat_rcvd_bytes  <= wrk_rcvd_bytes;
            lat_rcvd_frames <= wrk_rcvd_frames;
        end if;

        -- Pipeline stage 3:
        -- Working counters are updated on each byte and each frame.
        wrk_rcvd_bytes  <= accumulator(
            wrk_rcvd_bytes, frm_bytes, rx_reset_p, stats_req_rx, rx_eof);
        wrk_rcvd_frames  <= accumulator(
            wrk_rcvd_frames, COUNT_ONE, rx_reset_p, stats_req_rx, rx_eof);
        wrk_bcst_bytes  <= accumulator(
            wrk_bcst_bytes, frm_bytes, rx_reset_p, stats_req_rx, rx_eof and is_bcast);
        wrk_bcst_frames  <= accumulator(
            wrk_bcst_frames, COUNT_ONE, rx_reset_p, stats_req_rx, rx_eof and is_bcast);

        -- Pipeline stage 2:
        -- Detect broadcast frames (Destination-MAC = FF-FF-FF-FF-FF-FF).
        if (frm_wcount = 0) then
            is_bcast := '1';
        end if;
        for b in rx_isff'range loop
            if (rx_incr > 0 and b + frm_wcount * IO_BYTES < ETH_HDR_SRCMAC) then
                is_bcast := is_bcast and rx_isff(b);
            end if;
        end loop;
        
        -- Count bytes within each frame, so the increment is atomic.
        if (rx_reset_p = '1' or rx_eof = '1') then
            frm_bytes := rx_incr;
        else
            frm_bytes := rx_incr + frm_bytes;
        end if;

        -- Matched delay for control signals.
        rx_eof <= rx_last and not rx_reset_p;
        if (rx_reset_p = '1' or rx_last = '1') then
            frm_wcount := 0;
        elsif (rx_incr > 0 and frm_wcount < WCOUNT_MAX) then
            frm_wcount := frm_wcount + 1;
        end if;

        -- Pipeline stage 1:
        -- Buffer write-strobes for improved routing/timing.
        for b in rx_isff'range loop
            rx_isff(b) <= is_byte_ff(rx_data, b);
        end loop;
        if (rx_write = '0') then
            rx_incr <= COUNT_ZERO;
        elsif (rx_nlast > 0) then
            rx_incr <= to_unsigned(rx_nlast, COUNT_WIDTH);
        else
            rx_incr <= to_unsigned(IO_BYTES, COUNT_WIDTH);
        end if;
        rx_last <= rx_write and bool2bit(rx_nlast > 0);
    end if;
end process;

-- Transmit clock domain.
p_stats_tx : process(tx_clk)
    variable frm_bytes : counter_t := COUNT_ZERO;
begin
    if rising_edge(tx_clk) then
        -- On demand, update the latched value.
        if (stats_req_tx = '1') then
            lat_sent_bytes  <= wrk_sent_bytes;
            lat_sent_frames <= wrk_sent_frames;
        end if;

        -- Pipeline stage 3:
        -- Working counters are updated on each byte and each frame.
        wrk_sent_bytes  <= accumulator(
            wrk_sent_bytes, frm_bytes, tx_reset_p, stats_req_tx, tx_eof);
        wrk_sent_frames  <= accumulator(
            wrk_sent_frames, COUNT_ONE, tx_reset_p, stats_req_tx, tx_eof);

        -- Pipeline stage 2:
        -- Count bytes within each frame, so the increment is atomic.
        if (tx_reset_p = '1' or tx_eof = '1') then
            frm_bytes := tx_incr;
        else
            frm_bytes := tx_incr + frm_bytes;
        end if;

        -- Matched delay for control signals.
        tx_eof <= tx_last and not tx_reset_p;

        -- Pipeline stage 1:
        -- Buffer write-strobes for improved routing/timing.
        if (tx_write = '0') then
            tx_incr <= COUNT_ZERO;
        elsif (tx_nlast > 0) then
            tx_incr <= to_unsigned(tx_nlast, COUNT_WIDTH);
        else
            tx_incr <= to_unsigned(IO_BYTES, COUNT_WIDTH);
        end if;
        tx_last <= tx_write and bool2bit(tx_nlast > 0);
    end if;
end process;

-- Clock-crossing for the request event.
u_req_rx : sync_toggle2pulse
    port map(
    in_toggle   => stats_req_t,
    out_strobe  => stats_req_rx,
    out_clk     => rx_clk);
u_req_tx : sync_toggle2pulse
    port map(
    in_toggle   => stats_req_t,
    out_strobe  => stats_req_tx,
    out_clk     => tx_clk);
u_req_st : sync_toggle2pulse
    port map(
    in_toggle   => stats_req_t,
    out_strobe  => stats_req_st,
    out_clk     => status_clk);

-- Synchronize the status word.
status_async <= port_rate & x"00" & port_status;

u_sync : sync_buffer_slv
    generic map(IO_WIDTH => CFGBUS_WORD_SIZE)
    port map(
    in_flag  => status_async,
    out_flag => status_word,
    out_clk  => status_clk);

-- Clock-crossing for the various error toggles.
u_mii_err : sync_toggle2pulse
    port map(
    in_toggle   => err_port.mii_err,
    out_strobe  => evt_mii_err,
    out_clk     => status_clk);
u_ovr_tx : sync_toggle2pulse
    port map(
    in_toggle   => err_port.ovr_tx,
    out_strobe  => evt_ovr_tx,
    out_clk     => status_clk);
u_ovr_rx : sync_toggle2pulse
    port map(
    in_toggle   => err_port.ovr_rx,
    out_strobe  => evt_ovr_rx,
    out_clk     => status_clk);
u_pkt_err : sync_toggle2pulse
    port map(
    in_toggle   => err_port.mii_err,
    out_strobe  => evt_pkt_err,
    out_clk     => status_clk);

u_ptp_tx_err: sync_toggle2pulse
    port map(
    in_toggle   => err_port.tx_ptp_err,
    out_strobe  => evt_ptp_tx_err,
    out_clk     => status_clk);

u_ptp_rx_err: sync_toggle2pulse
    port map(
    in_toggle   => err_port.rx_ptp_err,
    out_strobe  => evt_ptp_rx_err,
    out_clk     => status_clk);

-- Error counting is asynchronous; use the status clock domain.
p_errct : process(status_clk)
begin
    if rising_edge(status_clk) then
        -- On demand, update the latched value.
        if (stats_req_st = '1') then
            lat_err_mii     <= wrk_err_mii;
            lat_err_ovr_tx  <= wrk_err_ovr_tx;
            lat_err_ovr_rx  <= wrk_err_ovr_rx;
            lat_err_pkt     <= wrk_err_pkt;
        end if;

        -- Working counters are updated after each event.
        wrk_err_mii      <= accum_err(
            wrk_err_mii,    evt_mii_err,    stats_req_tx);
        wrk_err_ovr_tx   <= accum_err(
            wrk_err_ovr_tx, evt_ovr_tx,     stats_req_tx);
        wrk_err_ovr_rx   <= accum_err(
            wrk_err_ovr_rx, evt_ovr_rx,     stats_req_tx);
        wrk_err_pkt      <= accum_err(
            wrk_err_pkt,    evt_pkt_err,    stats_req_tx);
        wrk_err_ptp_tx   <= accum_err(
            wrk_err_ptp_tx, evt_ptp_tx_err, stats_req_tx);
        wrk_err_ptp_rx   <= accum_err(
            wrk_err_ptp_rx, evt_ptp_rx_err, stats_req_tx);
    end if;
end process;

end eth_statistics;
