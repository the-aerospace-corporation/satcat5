--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Port traffic statistics
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
use     work.eth_frame_common.byte_u;
use     work.switch_types.all;

entity port_statistics is
    generic (
    COUNT_WIDTH : positive := 32;       -- Width of each statistics counter
    SAFE_COUNT  : boolean := true);     -- Safe counters (no overflow)
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
    status_clk  : in  std_logic;
    status_word : out cfgbus_word;

    -- Error counters.
    err_port    : in  port_error_t;
    err_mii     : out byte_u;
    err_ovr_tx  : out byte_u;
    err_ovr_rx  : out byte_u;
    err_pkt     : out byte_u;

    -- Generic internal port interface (monitor only)
    rx_data     : in  port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : in  port_tx_m2s);
end port_statistics;

architecture port_statistics of port_statistics is

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
signal rx_isff          : std_logic;
signal rx_clk,  tx_clk  : std_logic;
signal rx_byte, tx_byte : std_logic;
signal rx_last, tx_last : std_logic;

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

-- Clock reassignment, as a workaround for simulator bugs.
rx_clk  <= rx_data.clk;
tx_clk  <= tx_ctrl.clk;

-- Receive clock domain.
p_stats_rx : process(rx_clk)
    variable frm_bytes : counter_t := COUNT_ONE;
    variable is_bcast  : std_logic := '1';
begin
    if rising_edge(rx_clk) then
        -- On demand, update the latched value.
        if (stats_req_rx = '1') then
            lat_bcst_bytes  <= wrk_bcst_bytes;
            lat_bcst_frames <= wrk_bcst_frames;
            lat_rcvd_bytes  <= wrk_rcvd_bytes;
            lat_rcvd_frames <= wrk_rcvd_frames;
        end if;

        -- Working counters are updated on each byte and each frame.
        wrk_rcvd_bytes  <= accumulator(
            wrk_rcvd_bytes, frm_bytes, rx_data.reset_p, stats_req_rx, rx_last);
        wrk_rcvd_frames  <= accumulator(
            wrk_rcvd_frames, COUNT_ONE, rx_data.reset_p, stats_req_rx, rx_last);
        wrk_bcst_bytes  <= accumulator(
            wrk_bcst_bytes, frm_bytes, rx_data.reset_p, stats_req_rx, rx_last and is_bcast);
        wrk_bcst_frames  <= accumulator(
            wrk_bcst_frames, COUNT_ONE, rx_data.reset_p, stats_req_rx, rx_last and is_bcast);

        -- Detect broadcast frames (Destination-MAC = FF-FF-FF-FF-FF-FF).
        if (rx_data.reset_p = '1' or rx_last = '1') then
            is_bcast := '1';
        elsif (rx_byte = '1' and frm_bytes <= 6) then
            is_bcast := is_bcast and rx_isff;
        end if;

        -- Count bytes within each frame, so the increment is atomic.
        if (rx_data.reset_p = '1' or rx_last = '1') then
            frm_bytes := COUNT_ONE;
        elsif (rx_byte = '1') then
            frm_bytes := saturate_add(frm_bytes, COUNT_ONE, COUNT_WIDTH);
        end if;

        -- Buffer write-strobes for improved routing/timing.
        rx_isff <= bool2bit(rx_data.data = x"FF");
        rx_byte <= rx_data.write;
        rx_last <= rx_data.write and rx_data.last;
    end if;
end process;

-- Transmit clock domain.
p_stats_tx : process(tx_clk)
    variable frm_bytes : counter_t := COUNT_ONE;
begin
    if rising_edge(tx_clk) then
        -- On demand, update the latched value.
        if (stats_req_tx = '1') then
            lat_sent_bytes  <= wrk_sent_bytes;
            lat_sent_frames <= wrk_sent_frames;
        end if;

        -- Working counters are updated on each byte and each frame.
        wrk_sent_bytes  <= accumulator(
            wrk_sent_bytes, frm_bytes, tx_ctrl.reset_p, stats_req_tx, tx_last);
        wrk_sent_frames  <= accumulator(
            wrk_sent_frames, COUNT_ONE, tx_ctrl.reset_p, stats_req_tx, tx_last);

        -- Count bytes within each frame, so the increment is atomic.
        if (tx_ctrl.reset_p = '1' or tx_last = '1') then
            frm_bytes := COUNT_ONE;
        elsif (tx_byte = '1') then
            frm_bytes := frm_bytes + 1;
        end if;

        -- Buffer write-strobes for improved routing/timing.
        tx_byte <= tx_data.valid and tx_ctrl.ready;
        tx_last <= tx_data.valid and tx_ctrl.ready and tx_data.last;
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
status_async <= rx_data.rate & x"00" & rx_data.status;

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
    end if;
end process;

end port_statistics;
