--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Switch event statistics (read through ConfigBus)
--
-- This module is a wrapper for "switch_statistics", adding a ConfigBus
-- interface for readout of Ethernet switch event counters.  It is an
-- analogue to the "port_statistics" and "cfgbus_port_stats" blocks.
-- One block services up to 64 switch cores.
--
-- A write to any of the mapped registers refreshes the statistics
-- counters.  (The write address and write value are ignored.)
--
-- Once refreshed, each register reports the count of events since the
-- previous refresh.  There are 16 registers for each switch_core:
--   [0] Packet errors (Bad checksum, length, etc.)
--   [1] Errors reported by any port's MAC/PHY Tx
--   [2] Errors reported by any port's MAC/PHY Rx
--   [3] Internal MAC table errors (i.e., data corruption)
--   [4] Duplicate MAC address or port change events
--   [5] Other internal switch errors
--   [6] Overflow in any port's Tx FIFO (common)
--   [7] Overflow in any port's Rx FIFO (rare)
--   [8-15] Reserved
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.switch_types.array_switch_error;

entity cfgbus_switch_stats is
    generic (
    DEV_ADDR    : integer;              -- ConfigBus device address
    CORE_COUNT  : integer := 1;         -- Number of switch_core blocks
    COUNT_WIDTH : positive := 8;        -- Width of each counter
    SAFE_COUNT  : boolean := false);    -- Safe counters (no overflow)
    port (
    -- Switch status reporting.
    err_switch  : in  array_switch_error(CORE_COUNT-1 downto 0);

    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end cfgbus_switch_stats;

architecture cfgbus_switch_stats of cfgbus_switch_stats is

constant REG_PER_CORE   : natural := 16;
constant REG_TOTAL      : natural := REG_PER_CORE * CORE_COUNT;
subtype count_t is unsigned(COUNT_WIDTH-1 downto 0);
type reg_array_t is array(REG_TOTAL-1 downto 0) of cfgbus_word;

-- Convert counter to ConfigBus word.
function count2word(x : count_t) return cfgbus_word is
begin
    return std_logic_vector(resize(x, CFGBUS_WORD_SIZE));
end function;

-- Statistics module for each port.
signal stats_array  : reg_array_t := (others => (others => '0'));

-- ConfigBus interface.
signal cfg_ack_i    : cfgbus_ack := cfgbus_idle;
signal latch_req    : std_logic;

begin

-- Drive top-level outputs.
cfg_ack <= cfg_ack_i;

-- Statistics module for each standard port.
gen_stats : for n in 0 to CORE_COUNT-1 generate
    blk_stats : block
        constant BASEADDR : natural := REG_PER_CORE * n;
        signal ct_pkt_err   : count_t;
        signal ct_mii_tx    : count_t;
        signal ct_mii_rx    : count_t;
        signal ct_mac_tbl   : count_t;
        signal ct_mac_dup   : count_t;
        signal ct_mac_int   : count_t;
        signal ct_ovr_tx    : count_t;
        signal ct_ovr_rx    : count_t;
    begin
        -- Instantiate the statistics module.
        u_stats : entity work.switch_statistics
            generic map(
            COUNT_WIDTH => COUNT_WIDTH,
            LATCH_MODE  => true,
            SAFE_COUNT  => SAFE_COUNT)
            port map(
            latch_req   => latch_req,
            ct_pkt_err  => ct_pkt_err,
            ct_mii_tx   => ct_mii_tx,
            ct_mii_rx   => ct_mii_rx,
            ct_mac_tbl  => ct_mac_tbl,
            ct_mac_dup  => ct_mac_dup,
            ct_mac_int  => ct_mac_int,
            ct_ovr_tx   => ct_ovr_tx,
            ct_ovr_rx   => ct_ovr_rx,
            err_switch  => err_switch(n),
            clk         => cfg_cmd.clk,
            reset_p     => cfg_cmd.reset_p);

        -- Map each counter into the memory-mapped array.
        stats_array(BASEADDR+0) <= count2word(ct_pkt_err);
        stats_array(BASEADDR+1) <= count2word(ct_mii_tx);
        stats_array(BASEADDR+2) <= count2word(ct_mii_rx);
        stats_array(BASEADDR+3) <= count2word(ct_mac_tbl);
        stats_array(BASEADDR+4) <= count2word(ct_mac_dup);
        stats_array(BASEADDR+5) <= count2word(ct_mac_int);
        stats_array(BASEADDR+6) <= count2word(ct_ovr_tx);
        stats_array(BASEADDR+7) <= count2word(ct_ovr_rx);
    end block;
end generate;

-- ConfigBus interface.
p_cfgbus : process(cfg_cmd.clk)
    variable rd_temp : cfgbus_word := (others => '0');
begin
    if rising_edge(cfg_cmd.clk) then
        -- A write to any register strobes the "request".
        latch_req <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEV_ADDR));

        -- Respond to read requests.
        if (cfg_cmd.regaddr < REG_TOTAL) then
            rd_temp := stats_array(cfg_cmd.regaddr);
        else
            rd_temp := (others => '0');
        end if;

        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR)) then
            cfg_ack_i <= cfgbus_reply(rd_temp);
        else
            cfg_ack_i <= cfgbus_idle;
        end if;
    end if;
end process;

end cfgbus_switch_stats;
