--------------------------------------------------------------------------
-- Copyright 2023-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock-domain transitions for a PTP real-time clock
--
-- Every SatCat5 real-time clock (RTC) operates in a specific clock domain.
-- (See "ptp_realtime.vhd" for more information.)  This block allows
-- extrapolation of an RTC sequence into a different clock domain.
--
-- Both reference and output clocks must also provide colinear timestamps
-- (see "ptp_counter_sync.vhd").  Unlike the RTC, the raw timestamps are
-- typically free-running and do not need to be locked to any particular
-- reference. They are used to calculate the inter-clock timing.
--
-- The underlying process is as follows:
--  * Reference RTC and corresponding timestamp are sampled periodically.
--  * Each RTC/timestamp pair is forwarded to the output clock domain.
--  * Elapsed time is found by comparing the reference and output timestamps.
--  * The difference is added to the RTC value, with wraparound handling.
--
-- Users must specify the estimated output clock frequency to allow
-- compensation of internal pipeline delays.  An optional user-offset
-- parameter can be used to pre-compensate for fixed external delays.
-- Offsets larger than 500 msec may lead to undefined behavior.
--
-- The default REF_UPDATE is acceptable for most frequency combinations.
-- Choosing larger values increases the worst-case extrapolation interval.
-- If REF_CLK_HZ >> OUT_CLK_HZ, choose REF_UPDATE such that:
--  REF_UPDATE * OUT_CLK_HZ > 4 * REF_CLK_HZ
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.ptp_types.all;

entity ptp_realsync is
    generic (
    OUT_CLK_HZ  : positive;             -- Frequency of "out_clk"
    REF_UPDATE  : positive := 64;       -- Refresh every N ref_clk cycles
    USER_OFFSET : tstamp_t := (others => '0');
    WAIT_LOCKED : boolean := true);     -- Suppress output until locked?
    port (
    -- Reference clock domain.
    ref_clk     : in  std_logic;
    ref_tstamp  : in  tstamp_t;
    ref_rtc     : in  ptp_time_t;

    -- Output clock domain.
    out_clk     : in  std_logic;
    out_tstamp  : in  tstamp_t;
    out_rtc     : out ptp_time_t);
end ptp_realsync;

architecture ptp_realsync of ptp_realsync is

subtype seconds_t is signed(47 downto 0);

-- Clock-crossing for the reference timestamps.
signal xref_tvalid  : std_logic := '0';
signal xref_tdiff   : tstamp_t := (others => '0');
signal xref_sec     : seconds_t := (others => '0');
signal xref_toggle  : std_logic := '0';     -- Toggle in ref_clk domain
signal xout_strobe  : std_logic;            -- Strobe in out_clk domain
signal xout_tvalid  : std_logic := '0';
signal xout_tdiff   : tstamp_t := (others => '0');
signal xout_sec     : seconds_t := (others => '0');

-- Extrapolation of the output sequence.
signal sum_tvalid   : std_logic := '0';
signal sum_tdiff    : tstamp_t := (others => '0');
signal sum_sec      : seconds_t := (others => '0');
signal roll_subns   : tstamp_t := (others => '0');
signal roll_sec     : seconds_t := (others => '0');

begin

-- Latch timestamp / RTC pairs every REF_UPDATE clock cycles.
p_ref : process(ref_clk)
    variable count : integer range 0 to REF_UPDATE-1 := REF_UPDATE-1;
begin
    if rising_edge(ref_clk) then
        if (count = 0) then
            -- Latch reference and precalculate "subns" difference term.
            -- Note: Wraparound / underflow is OK here as long as the final
            --   unwrapped "sum_tdiff" falls in range of [-1, +2) seconds.
            xref_tvalid <= bool2bit(ref_rtc /= PTP_TIME_ZERO)
                       and bool2bit(ref_tstamp /= TSTAMP_DISABLED);
            xref_tdiff  <= (ref_rtc.nsec & ref_rtc.subns) - ref_tstamp;
            xref_sec    <= ref_rtc.sec;
            xref_toggle <= not xref_toggle;
            count       := REF_UPDATE - 1;
        else
            -- Countdown until next update...
            count       := count - 1;
        end if;
    end if;
end process;

-- Cross-clock crossing for each update event.
u_strobe : sync_toggle2pulse
    port map(
    in_toggle   => xref_toggle,
    out_strobe  => xout_strobe,
    out_clk     => out_clk);

-- Extrapolate into the output clock domain.
p_out : process(out_clk)
    constant TOTAL_OFFSET : tstamp_t :=
        get_tstamp_incr(OUT_CLK_HZ / 2) + USER_OFFSET;
begin
    if rising_edge(out_clk) then
        -- Sanity check on the rollover calculation.
        assert (roll_subns < TSTAMP_ONE_SEC)
            report "Rollover violation." severity warning;

        -- Pipeline stage 2: One-second rollover detection.
        if (WAIT_LOCKED and sum_tvalid = '0') then
            roll_subns <= (others => '0');
            roll_sec   <= (others => '0');
        elsif (signed(sum_tdiff) < 0) then
            roll_subns <= sum_tdiff + TSTAMP_ONE_SEC;
            roll_sec   <= sum_sec - 1;
        elsif (sum_tdiff < TSTAMP_ONE_SEC) then
            roll_subns <= sum_tdiff;
            roll_sec   <= sum_sec;
        else
            roll_subns <= sum_tdiff - TSTAMP_ONE_SEC;
            roll_sec   <= sum_sec + 1;
        end if;

        -- Pipeline stage 1: Summation of subnanosecond terms.
        -- (As before, wraparound at 2^48 is expected and routine.)
        sum_tvalid  <= xref_tvalid and bool2bit(out_tstamp /= TSTAMP_DISABLED);
        sum_tdiff   <= xout_tdiff + out_tstamp + TOTAL_OFFSET;
        sum_sec     <= xout_sec;

        -- Pipeline stage 0: Latch each reference timestamp.
        if (xout_strobe = '1') then
            xout_tvalid <= xref_tvalid;
            xout_tdiff  <= xref_tdiff;
            xout_sec    <= xref_sec;
        end if;
    end if;
end process;

-- Final output conversion.
out_rtc.sec     <= roll_sec;
out_rtc.nsec    <= roll_subns(47 downto 16);
out_rtc.subns   <= roll_subns(15 downto 0);

end ptp_realsync;
