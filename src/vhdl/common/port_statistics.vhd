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

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;
use     work.synchronization.all;

entity port_statistics is
    generic (
    COUNT_WIDTH : integer := 32);       -- Width of each statistics counter
    port (
    -- Statistics interface (bytes received/sent, frames received/sent
    stats_req_t : in  std_logic;        -- Toggle to request next block
    bcst_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    bcst_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    rcvd_frames : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_bytes  : out unsigned(COUNT_WIDTH-1 downto 0);
    sent_frames : out unsigned(COUNT_WIDTH-1 downto 0);

    -- Generic internal port interface (monitor only)
    rx_data     : in  port_rx_m2s;
    tx_data     : in  port_tx_m2s;
    tx_ctrl     : in  port_tx_s2m);
end port_statistics;

architecture port_statistics of port_statistics is

subtype counter_t is unsigned(COUNT_WIDTH-1 downto 0);
constant COUNT_ONE      : counter_t := to_unsigned(1, COUNT_WIDTH);

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

-- Latched values for clock-domain crossing.
signal lat_bcst_bytes   : counter_t := (others => '0');
signal lat_bcst_frames  : counter_t := (others => '0');
signal lat_rcvd_bytes   : counter_t := (others => '0');
signal lat_rcvd_frames  : counter_t := (others => '0');
signal lat_sent_bytes   : counter_t := (others => '0');
signal lat_sent_frames  : counter_t := (others => '0');

-- Clock crossing.
signal stats_req_rx     : std_logic;
signal stats_req_tx     : std_logic;

begin

-- Drive top-level outputs.
bcst_bytes  <= lat_bcst_bytes;
bcst_frames <= lat_bcst_frames;
rcvd_bytes  <= lat_rcvd_bytes;
rcvd_frames <= lat_rcvd_frames;
sent_bytes  <= lat_sent_bytes;
sent_frames <= lat_sent_frames;

-- Combinational logic for next-byte and last-byte strobes.
-- (And clock reassignment, as a workaround for simulator bugs.)
rx_clk  <= rx_data.clk;
rx_isff <= bool2bit(rx_data.data = x"FF");
rx_byte <= rx_data.write;
rx_last <= rx_data.write and rx_data.last;
tx_clk  <= tx_ctrl.clk;
tx_byte <= tx_data.valid and tx_ctrl.ready;
tx_last <= tx_data.valid and tx_ctrl.ready and tx_data.last;

-- Receive clock domain.
p_stats_rx : process(rx_clk)
    variable frm_bytes : counter_t := COUNT_ONE;
    variable is_bcast  : std_logic := '1';
begin
    if rising_edge(rx_clk) then
        -- On demand, update the latched value.
        if (rx_data.reset_p = '1') then
            lat_bcst_bytes  <= (others => '0');
            lat_bcst_frames <= (others => '0');
            lat_rcvd_bytes  <= (others => '0');
            lat_rcvd_frames <= (others => '0');
        elsif (stats_req_rx = '1') then
            lat_bcst_bytes  <= wrk_bcst_bytes;
            lat_bcst_frames <= wrk_bcst_frames;
            lat_rcvd_bytes  <= wrk_rcvd_bytes;
            lat_rcvd_frames <= wrk_rcvd_frames;
        end if;

        -- Working counters are updated on each byte and each frame.
        if (rx_data.reset_p = '1') then
            wrk_rcvd_bytes  <= (others => '0');
            wrk_rcvd_frames <= (others => '0');
        elsif (stats_req_rx = '1' and rx_last = '1') then
            wrk_rcvd_bytes  <= frm_bytes;
            wrk_rcvd_frames <= COUNT_ONE;
        elsif (stats_req_rx = '1') then
            wrk_rcvd_bytes  <= (others => '0');
            wrk_rcvd_frames <= (others => '0');
        elsif (stats_req_rx = '0' and rx_last = '1') then
            wrk_rcvd_bytes  <= saturate_add(wrk_rcvd_bytes, frm_bytes, COUNT_WIDTH);
            wrk_rcvd_frames <= saturate_add(wrk_rcvd_frames, COUNT_ONE, COUNT_WIDTH);
        end if;

        if (rx_data.reset_p = '1') then
            wrk_bcst_bytes  <= (others => '0');
            wrk_bcst_frames <= (others => '0');
        elsif (stats_req_rx = '1' and rx_last = '1' and is_bcast = '1') then
            wrk_bcst_bytes  <= frm_bytes;
            wrk_bcst_frames <= COUNT_ONE;
        elsif (stats_req_rx = '1') then
            wrk_bcst_bytes  <= (others => '0');
            wrk_bcst_frames <= (others => '0');
        elsif (stats_req_rx = '0' and rx_last = '1' and is_bcast = '1') then
            wrk_bcst_bytes  <= saturate_add(wrk_bcst_bytes, frm_bytes, COUNT_WIDTH);
            wrk_bcst_frames <= saturate_add(wrk_bcst_frames, COUNT_ONE, COUNT_WIDTH);
        end if;

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
    end if;
end process;

-- Transmit clock domain.
p_stats_tx : process(tx_clk)
    variable frm_bytes : counter_t := COUNT_ONE;
begin
    if rising_edge(tx_clk) then
        -- On demand, update the latched value.
        if (tx_ctrl.reset_p = '1') then
            lat_sent_bytes  <= (others => '0');
            lat_sent_frames <= (others => '0');
        elsif (stats_req_tx = '1') then
            lat_sent_bytes  <= wrk_sent_bytes;
            lat_sent_frames <= wrk_sent_frames;
        end if;

        -- Working counters are updated on each byte and each frame.
        if (tx_ctrl.reset_p = '1') then
            wrk_sent_bytes  <= (others => '0');
            wrk_sent_frames <= (others => '0');
        elsif (stats_req_tx = '1' and tx_last = '0') then
            wrk_sent_bytes  <= (others => '0');
            wrk_sent_frames <= (others => '0');
        elsif (stats_req_tx = '1' and tx_last = '1') then
            wrk_sent_bytes  <= frm_bytes;
            wrk_sent_frames <= COUNT_ONE;
        elsif (stats_req_tx = '0' and tx_last = '1') then
            wrk_sent_bytes  <= wrk_sent_bytes + frm_bytes;
            wrk_sent_frames <= wrk_sent_frames + 1;
        end if;

        -- Count bytes within each frame, so the increment is atomic.
        if (tx_ctrl.reset_p = '1' or tx_last = '1') then
            frm_bytes := COUNT_ONE;
        elsif (tx_byte = '1') then
            frm_bytes := frm_bytes + 1;
        end if;
    end if;
end process;

-- Clock-crossing for the request event.
u_req_rx : sync_toggle2pulse
    port map(
    in_toggle   => stats_req_t,
    out_strobe  => stats_req_rx,
    out_clk     => rx_clk,
    reset_p     => rx_data.reset_p);

u_req_tx : sync_toggle2pulse
    port map(
    in_toggle   => stats_req_t,
    out_strobe  => stats_req_tx,
    out_clk     => tx_clk,
    reset_p     => tx_ctrl.reset_p);

end port_statistics;
