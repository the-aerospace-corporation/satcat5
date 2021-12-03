--------------------------------------------------------------------------
-- Copyright 2020, 2021 The Aerospace Corporation
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
-- Port traffic statistics (with ConfigBus)
--
-- This module instantiates a port_statistics block for each attached
-- Ethernet port, and makes the results available on a memory-mapped
-- ConfigBus interface.
--
-- A write to any of the mapped registers refreshes the statistics
-- counters.  (The write address and write value are ignored.)
--
-- Once refreshed, each register reports total observed traffic since
-- the previous refresh.  There are eight registers for each port:
--   * Broadcast bytes received (from device to switch)
--   * Broadcast frames received
--   * Total bytes received (from device to switch)
--   * Total frames received
--   * Total bytes sent (from switch to device)
--   * Total frames sent
--   * Error reporting:
--      Bits 31..24: Count MAC/PHY errors
--      Bits 23..16: Count Tx-FIFO overflow (common)
--      Bits 15..08: Count Rx-FIFO overflow (rare)
--      Bits 07..00: Count packet errors (bad checksum, length, etc.)
--   * Link-status reporting:
--      Bits 31..16: Link speed (Mbps)
--      Bits 15..08: Reserved
--      Bits 07..00: Port status word
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_u;
use     work.switch_types.all;

entity cfgbus_port_stats is
    generic (
    PORT_COUNT  : natural := 0;         -- Number of standard ports
    PORTX_COUNT : natural := 0;         -- Number of 10-gigabit ports
    CFG_DEVADDR : integer;              -- ConfigBus peripheral address (-1 = any)
    COUNT_WIDTH : positive := 32;       -- Internal counter width (16-32 bits)
    SAFE_COUNT  : boolean := true);     -- Safe counters (no overflow)
    port (
    -- Generic internal port interface (monitor only)
    rx_data     : in  array_rx_m2s(PORT_COUNT-1 downto 0) := (others => RX_M2S_IDLE);
    tx_data     : in  array_tx_s2m(PORT_COUNT-1 downto 0) := (others => TX_S2M_IDLE);
    tx_ctrl     : in  array_tx_m2s(PORT_COUNT-1 downto 0) := (others => TX_M2S_IDLE);
    xrx_data    : in  array_rx_m2sx(PORTX_COUNT-1 downto 0) := (others => RX_M2SX_IDLE);
    xtx_data    : in  array_tx_s2mx(PORTX_COUNT-1 downto 0) := (others => TX_S2MX_IDLE);
    xtx_ctrl    : in  array_tx_m2sx(PORTX_COUNT-1 downto 0) := (others => TX_M2SX_IDLE);
    err_ports   : in  array_port_error(PORT_COUNT+PORTX_COUNT-1 downto 0) := (others => PORT_ERROR_NONE);

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_port_stats;

architecture cfgbus_port_stats of cfgbus_port_stats is

constant PORT_TOTAL : natural := PORT_COUNT + PORTX_COUNT;
constant WORD_MULT  : natural := 8;
constant WORD_COUNT : natural := WORD_MULT * PORT_TOTAL;
subtype stat_word is unsigned(COUNT_WIDTH-1 downto 0);
type stats_array_t is array(WORD_COUNT-1 downto 0) of cfgbus_word;

-- Convert counter to ConfigBus word.
function count2word(x : stat_word) return cfgbus_word is
begin
    return std_logic_vector(resize(x, CFGBUS_WORD_SIZE));
end function;

-- Statistics module for each port.
signal stats_req_t  : std_logic := '0';
signal stats_array  : stats_array_t := (others => (others => '0'));
signal cfg_ack_i    : cfgbus_ack := cfgbus_idle;

begin

-- Drive top-level outputs.
cfg_ack <= cfg_ack_i;

-- Statistics module for each standard port.
gen_stats : for n in 0 to PORT_COUNT-1 generate
    blk_stats : block
        constant BASEADDR : natural := WORD_MULT * n;
        signal bcst_bytes   : stat_word;
        signal bcst_frames  : stat_word;
        signal rcvd_bytes   : stat_word;
        signal rcvd_frames  : stat_word;
        signal sent_bytes   : stat_word;
        signal sent_frames  : stat_word;
        signal errct_mii    : byte_u;
        signal errct_ovr_tx : byte_u;
        signal errct_ovr_rx : byte_u;
        signal errct_pkt    : byte_u;
        signal status       : cfgbus_word;
    begin
        -- Instantiate the statistics module.
        u_stats : entity work.port_statistics
            generic map(
            COUNT_WIDTH => COUNT_WIDTH,
            SAFE_COUNT  => SAFE_COUNT)
            port map(
            stats_req_t => stats_req_t,
            bcst_bytes  => bcst_bytes,
            bcst_frames => bcst_frames,
            rcvd_bytes  => rcvd_bytes,
            rcvd_frames => rcvd_frames,
            sent_bytes  => sent_bytes,
            sent_frames => sent_frames,
            status_clk  => cfg_cmd.clk,
            status_word => status,
            err_port    => err_ports(n),
            err_mii     => errct_mii,
            err_ovr_tx  => errct_ovr_tx,
            err_ovr_rx  => errct_ovr_rx,
            err_pkt     => errct_pkt,
            rx_data     => rx_data(n),
            tx_data     => tx_data(n),
            tx_ctrl     => tx_ctrl(n));

        -- Map each counter into the memory-mapped array.
        stats_array(BASEADDR+0) <= count2word(bcst_bytes);
        stats_array(BASEADDR+1) <= count2word(bcst_frames);
        stats_array(BASEADDR+2) <= count2word(rcvd_bytes);
        stats_array(BASEADDR+3) <= count2word(rcvd_frames);
        stats_array(BASEADDR+4) <= count2word(sent_bytes);
        stats_array(BASEADDR+5) <= count2word(sent_frames);
        stats_array(BASEADDR+6) <= std_logic_vector(
            errct_mii & errct_ovr_tx & errct_ovr_rx & errct_pkt);
        stats_array(BASEADDR+7) <= status;
    end block;
end generate;

-- Statistics module for each 10-GbE port.
gen_xstats : for n in 0 to PORTX_COUNT-1 generate
    blk_stats : block
        constant BASEADDR : natural := WORD_MULT * (PORT_COUNT + n);
        signal bcst_bytes   : stat_word;
        signal bcst_frames  : stat_word;
        signal rcvd_bytes   : stat_word;
        signal rcvd_frames  : stat_word;
        signal sent_bytes   : stat_word;
        signal sent_frames  : stat_word;
        signal errct_mii    : byte_u;
        signal errct_ovr_tx : byte_u;
        signal errct_ovr_rx : byte_u;
        signal errct_pkt    : byte_u;
        signal status       : cfgbus_word;
    begin
        -- Instantiate the statistics module.
        u_stats : entity work.portx_statistics
            generic map(
            COUNT_WIDTH => COUNT_WIDTH,
            SAFE_COUNT  => SAFE_COUNT)
            port map(
            stats_req_t => stats_req_t,
            bcst_bytes  => bcst_bytes,
            bcst_frames => bcst_frames,
            rcvd_bytes  => rcvd_bytes,
            rcvd_frames => rcvd_frames,
            sent_bytes  => sent_bytes,
            sent_frames => sent_frames,
            status_clk  => cfg_cmd.clk,
            status_word => status,
            err_port    => err_ports(PORT_COUNT+n),
            err_mii     => errct_mii,
            err_ovr_tx  => errct_ovr_tx,
            err_ovr_rx  => errct_ovr_rx,
            err_pkt     => errct_pkt,
            rx_data     => xrx_data(n),
            tx_data     => xtx_data(n),
            tx_ctrl     => xtx_ctrl(n));

        -- Map each counter into the memory-mapped array.
        stats_array(BASEADDR+0) <= count2word(bcst_bytes);
        stats_array(BASEADDR+1) <= count2word(bcst_frames);
        stats_array(BASEADDR+2) <= count2word(rcvd_bytes);
        stats_array(BASEADDR+3) <= count2word(rcvd_frames);
        stats_array(BASEADDR+4) <= count2word(sent_bytes);
        stats_array(BASEADDR+5) <= count2word(sent_frames);
        stats_array(BASEADDR+6) <= std_logic_vector(
            errct_mii & errct_ovr_tx & errct_ovr_rx & errct_pkt);
        stats_array(BASEADDR+7) <= status;
    end block;
end generate;

-- ConfigBus interface.
p_cfgbus : process(cfg_cmd.clk)
    variable rd_temp : cfgbus_word := (others => '0');
begin
    if rising_edge(cfg_cmd.clk) then
        -- A write to any register toggles the "request" signal.
        if (cfgbus_wrcmd(cfg_cmd, CFG_DEVADDR)) then
            stats_req_t <= not stats_req_t;
        end if;

        -- Respond to read requests.
        if (cfg_cmd.regaddr < WORD_COUNT) then
            rd_temp := stats_array(cfg_cmd.regaddr);
        else
            rd_temp := (others => '0');
        end if;

        if (cfgbus_rdcmd(cfg_cmd, CFG_DEVADDR)) then
            cfg_ack_i <= cfgbus_reply(rd_temp);
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

end cfgbus_port_stats;
