--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Cross-clock counter synchronization for Precision Time Protocol (PTP)
-- See also: ptp_counter_coarse.vhd, ptp_counter_verdact.vhd
--
-- SatCat5 timestamps are referenced to a global free-running counter.
-- However, the global counter operates in its own time-domain.  This
-- block synthesizes an equivalent free-running counter in the user clock
-- clock domain, which is asymptotically collinear to the original with
-- sub-picosecond precision.  (i.e., It follows exactly the same best-fit
-- line for counter value vs. time.)
--
-- This repo includes two different methods for accomplishing this.
--  * ptp_counter_coarse: A simple but effective method, accurate
--      to +/-0.5 clock cycles in the target clock domain.  This
--      method is sufficient for many applications.
--  * ptp_counter_verdact: A much more complex method that can achieve
--      sub-picosecond precision, but is not as robust. The VERDACT
--      circuit requires stable reference clocks, careful PLL tuning,
--      and some trial-and-error to achieve a consistent lock.
--
-- This block is a wrapper that instantiates the selected implementation,
-- providing the least-common-denominator of the two interfaces.  If full
-- features are required, instantiate "ptp_counter_verdact" directly.
--
-- The mode is selected by setting VCONFIG.vclkb_hz to 0.0 or by setting
-- the COARSE_MODE parameter specifically for this block.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;
use     work.ptp_types.all;

entity ptp_counter_sync is
    generic (
    VCONFIG     : vernier_config;   -- Vernier configuration
    USER_CLK_HZ : positive;         -- User clock frequency (Hz)
    DEBUG_MODE  : boolean := false; -- Enable additional diagnostics?
    WAIT_LOCKED : boolean := true;  -- Suppress output until locked?
    COARSE_MODE : boolean := false; -- Override VCONFIG mode select?
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Global reference clocks and counter.
    ref_time    : in  port_timeref;
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    -- Internal diagnostics, not used in normal designs.
    diagnostics : out std_logic_vector(7 downto 0);
    -- User clock and local counter.
    -- (Deassert clock-enable to freeze output if desired.)
    user_clk    : in  std_logic;
    user_rst_p  : in  std_logic := '0';
    user_lock   : out std_logic;    -- Timestamp locked?
    user_ctr    : out tstamp_t;     -- Timestamp value
    user_rate   : out tstamp_t;     -- Timestamp increment
    user_freq   : out tfreq_t);     -- Normalized frequency
end ptp_counter_sync;

architecture ptp_counter_sync of ptp_counter_sync is

constant ENABLE_PTP     : boolean := (VCONFIG.input_hz > 0);
constant ENABLE_FINE    : boolean := (VCONFIG.vclkb_hz > 1.0) and not COARSE_MODE;

begin

gen_none : if not ENABLE_PTP generate
    cfg_ack     <= cfgbus_idle;
    diagnostics <= (others => '0');
    user_lock   <= '0';
    user_ctr    <= TSTAMP_DISABLED;
    user_rate   <= TSTAMP_DISABLED;
    user_freq   <= TFREQ_DISABLED;
end generate;
    
gen_coarse : if ENABLE_PTP and not ENABLE_FINE generate
    u_sync : entity work.ptp_counter_coarse
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => USER_CLK_HZ,
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR)
        port map(
        ref_time    => ref_time,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_ack,
        user_clk    => user_clk,
        user_lock   => user_lock,
        user_ctr    => user_ctr,
        user_rate   => user_rate,
        user_freq   => user_freq);

    diagnostics <= (others => '0');
end generate;

gen_fine : if ENABLE_PTP and ENABLE_FINE generate
    u_sync : entity work.ptp_counter_verdact
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => USER_CLK_HZ,
        DEBUG_MODE  => DEBUG_MODE,
        WAIT_LOCKED => WAIT_LOCKED,
        DEVADDR     => DEVADDR,
        REGADDR     => REGADDR)
        port map(
        ref_time    => ref_time,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_ack,
        diagnostics => diagnostics,
        user_clk    => user_clk,
        user_cken   => '1',
        user_rst_p  => user_rst_p,
        user_lock   => user_lock,
        user_ctr    => user_ctr,
        user_rate   => user_rate,
        user_freq   => user_freq,
        user_idx    => open,
        sync_ref    => open,
        sync_ctr    => open,
        sync_rate   => open,
        sync_freq   => open,
        sync_idx    => open);
end generate;

end ptp_counter_sync;
