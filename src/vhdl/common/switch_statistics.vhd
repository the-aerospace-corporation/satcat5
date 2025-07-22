--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Switch event statistics
--
-- This module monitors the "err_switch" output from switch_core, and
-- maintains counters for the following event statistics:
--   * Packet errors (Bad checksum, length, etc.)
--   * Errors reported by any port's MAC/PHY Tx
--   * Errors reported by any port's MAC/PHY Rx
--   * Internal MAC table errors (i.e., data corruption)
--   * Duplicate MAC address or port change events
--   * Other internal switch errors
--   * Overflow in any port's Tx FIFO (common)
--   * Overflow in any port's Rx FIFO (rare)
--
-- Counters can be operated in rollover mode or in latched mode.  In
-- rollover mode, output counters increment forever without being reset.
-- The reader must compare against the previously-read value to detect
-- changes, including rollover/wraparound to zero on counter overflow.
--
-- In latched mode, outpus are read by asserting the "latch_req" strobe
-- for a single clock cycle, which simultaneously transfers counter
-- contents to a buffer register and resets the working counter.  This
-- mode is simpler to operate, but increases FPGA resource utilization.
--
-- This block operates asynchronously to the switch_core clock.  They
-- may safely share a clock or use completely different clocks.
--
-- This block pairs with "cfgbus_switch_stats".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.switch_types.switch_error_t;

entity switch_statistics is
    generic (
    COUNT_WIDTH : positive := 8;            -- Width of each counter
    LATCH_MODE  : boolean := true;          -- Latch or rollover mode?
    SAFE_COUNT  : boolean := false);        -- Safe counters (no overflow)
    port (
    -- Event counters.
    latch_req   : in  std_logic := '0';     -- Latch mode only
    ct_pkt_err  : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_mii_tx   : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_mii_rx   : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_mac_tbl  : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_mac_dup  : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_mac_int  : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_ovr_tx   : out unsigned(COUNT_WIDTH-1 downto 0);
    ct_ovr_rx   : out unsigned(COUNT_WIDTH-1 downto 0);

    -- Switch status reporting.
    err_switch  : in  switch_error_t;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end switch_statistics;

architecture switch_statistics of switch_statistics is

subtype count_t is unsigned(COUNT_WIDTH-1 downto 0);
constant COUNT_ZERO : count_t := to_unsigned(0, COUNT_WIDTH);
constant COUNT_ONE  : count_t := to_unsigned(1, COUNT_WIDTH);

-- Event counter with all options.
function accumulator(
    acc: count_t;       -- Accumulator value
    rst: std_logic;     -- Global reset
    rd:  std_logic;     -- Read/consume counter
    en:  std_logic)     -- Increment enable
    return count_t is
begin
    if (rst = '1') then
        return COUNT_ZERO;                          -- Reset
    elsif (rd = '1' and en = '0') then
        return COUNT_ZERO;                          -- Consumed
    elsif (rd = '1' and en = '1') then
        return COUNT_ONE;                           -- Consumed + add
    elsif (en = '1' and SAFE_COUNT) then
        return saturate_add(acc, COUNT_ONE, COUNT_WIDTH); -- Safe add
    elsif (en = '1') then
        return acc + COUNT_ONE;                     -- Unsafe add
    else
        return acc;                                 -- No change
    end if;
end function;

signal strb_pkt_err : std_logic;
signal strb_mii_tx  : std_logic;
signal strb_mii_rx  : std_logic;
signal strb_mac_tbl : std_logic;
signal strb_mac_dup : std_logic;
signal strb_mac_int : std_logic;
signal strb_ovr_tx  : std_logic;
signal strb_ovr_rx  : std_logic;

signal lat_pkt_err  : count_t := (others => '0');
signal lat_mii_tx   : count_t := (others => '0');
signal lat_mii_rx   : count_t := (others => '0');
signal lat_mac_tbl  : count_t := (others => '0');
signal lat_mac_dup  : count_t := (others => '0');
signal lat_mac_int  : count_t := (others => '0');
signal lat_ovr_tx   : count_t := (others => '0');
signal lat_ovr_rx   : count_t := (others => '0');

signal wrk_pkt_err  : count_t := (others => '0');
signal wrk_mii_tx   : count_t := (others => '0');
signal wrk_mii_rx   : count_t := (others => '0');
signal wrk_mac_tbl  : count_t := (others => '0');
signal wrk_mac_dup  : count_t := (others => '0');
signal wrk_mac_int  : count_t := (others => '0');
signal wrk_ovr_tx   : count_t := (others => '0');
signal wrk_ovr_rx   : count_t := (others => '0');

begin

-- Convert toggle signals to strobes.
sync_pkt_err : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.pkt_err,
    out_strobe  => strb_pkt_err,
    out_clk     => clk);
sync_mii_tx : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.mii_tx,
    out_strobe  => strb_mii_tx,
    out_clk     => clk);
sync_mii_rx : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.mii_rx,
    out_strobe  => strb_mii_rx,
    out_clk     => clk);
sync_mac_tbl : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.mac_tbl,
    out_strobe  => strb_mac_tbl,
    out_clk     => clk);
sync_mac_dup : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.mac_dup,
    out_strobe  => strb_mac_dup,
    out_clk     => clk);
sync_mac_int : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.mac_int,
    out_strobe  => strb_mac_int,
    out_clk     => clk);
sync_ovr_tx : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.ovr_tx,
    out_strobe  => strb_ovr_tx,
    out_clk     => clk);
sync_ovr_rx : sync_toggle2pulse
    port map(
    in_toggle   => err_switch.ovr_rx,
    out_strobe  => strb_ovr_rx,
    out_clk     => clk);

-- Counter state machine.
p_count : process(clk)
begin
    if rising_edge(clk) then
        -- Optional latch-mode registers.
        if (reset_p = '1' or latch_req = '1') then
            lat_pkt_err <= wrk_pkt_err;
            lat_mii_tx  <= wrk_mii_tx;
            lat_mii_rx  <= wrk_mii_rx;
            lat_mac_tbl <= wrk_mac_tbl;
            lat_mac_dup <= wrk_mac_dup;
            lat_mac_int <= wrk_mac_int;
            lat_ovr_tx  <= wrk_ovr_tx;
            lat_ovr_rx  <= wrk_ovr_rx;
        end if;

        -- Working counters.
        wrk_pkt_err <= accumulator(wrk_pkt_err, reset_p, latch_req, strb_pkt_err);
        wrk_mii_tx  <= accumulator(wrk_mii_tx,  reset_p, latch_req, strb_mii_tx);
        wrk_mii_rx  <= accumulator(wrk_mii_rx,  reset_p, latch_req, strb_mii_rx);
        wrk_mac_tbl <= accumulator(wrk_mac_tbl, reset_p, latch_req, strb_mac_tbl);
        wrk_mac_dup <= accumulator(wrk_mac_dup, reset_p, latch_req, strb_mac_dup);
        wrk_mac_int <= accumulator(wrk_mac_int, reset_p, latch_req, strb_mac_int);
        wrk_ovr_tx  <= accumulator(wrk_ovr_tx,  reset_p, latch_req, strb_ovr_tx);
        wrk_ovr_rx  <= accumulator(wrk_ovr_rx,  reset_p, latch_req, strb_ovr_rx);
    end if;
end process;

-- Connect the top-level outputs.
ct_pkt_err  <= lat_pkt_err when LATCH_MODE else wrk_pkt_err;
ct_mii_tx   <= lat_mii_tx  when LATCH_MODE else wrk_mii_tx;
ct_mii_rx   <= lat_mii_rx  when LATCH_MODE else wrk_mii_rx;
ct_mac_tbl  <= lat_mac_tbl when LATCH_MODE else wrk_mac_tbl;
ct_mac_dup  <= lat_mac_dup when LATCH_MODE else wrk_mac_dup;
ct_mac_int  <= lat_mac_int when LATCH_MODE else wrk_mac_int;
ct_ovr_tx   <= lat_ovr_tx  when LATCH_MODE else wrk_ovr_tx;
ct_ovr_rx   <= lat_ovr_rx  when LATCH_MODE else wrk_ovr_rx;

end switch_statistics;
