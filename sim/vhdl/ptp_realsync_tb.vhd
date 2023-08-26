--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation
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
-- Testbench for resynchronized PTP real-time clocks
--
-- This is a unit test for the ptp_realsync block, which transitions an RTC
-- timestamp to a different clock domain.  To adequate test overflow in a
-- reasonable amount of time, all counters are accelerated 100x.
--
-- The complete test takes 7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_realsync_tb is
    -- Unit testbench top level, no I/O ports
end ptp_realsync_tb;

architecture tb of ptp_realsync_tb is

-- Convert timestamp + offset to an RTC value.
function rtc_init(tstamp, offset: tstamp_t) return ptp_time_t is
    variable total : unsigned(TSTAMP_WIDTH downto 0) := extend_add(tstamp, offset);
    variable sec   : integer := to_integer(total / TSTAMP_ONE_SEC);
    variable subns : tstamp_t := resize(total mod TSTAMP_ONE_SEC, TSTAMP_WIDTH);
    variable rtc   : ptp_time_t := (
        sec   => to_signed(sec, 48),
        nsec  => subns(47 downto 16),
        subns => subns(15 downto 0));
begin
    return rtc;
end function;

function rtc_incr(rtc: ptp_time_t; incr: tstamp_t) return ptp_time_t is
    variable subns : tstamp_t := (rtc.nsec & rtc.subns) + incr;
    variable sum   : ptp_time_t := (
        sec   => rtc.sec,
        nsec  => subns(47 downto 16),
        subns => subns(15 downto 0));
begin
    if (subns >= TSTAMP_ONE_SEC) then
        sum.sec   := sum.sec + 1;
        sum.nsec  := sum.nsec - 1_000_000_000;
    end if;
    return sum;
end function;

-- Define ideal rates for the input and output clocks.
constant ACCELERATE : positive := 10_000;
constant REF_CLK_HZ : positive := 100_000_000;
constant OUT_CLK_HZ : positive := 125_000_000;
constant REF_INCR   : tstamp_t := get_tstamp_incr(REF_CLK_HZ / ACCELERATE);
constant OUT_INCR   : tstamp_t := get_tstamp_incr(OUT_CLK_HZ / ACCELERATE);

-- Reference clock domain.
signal ref_clk      : std_logic := '1';
signal ref_tstamp   : tstamp_t := (others => '0');
signal ref_rtc      : ptp_time_t := PTP_TIME_ZERO;

-- Output clock domain.
signal out_clk      : std_logic := '1';
signal out_tstamp   : tstamp_t := (others => '0');
signal out_rtc_ref  : ptp_time_t := PTP_TIME_ZERO;
signal out_rtc_uut  : ptp_time_t;

-- High-level test control.
signal test_offset  : tstamp_t := (others => '0');
signal test_reset   : std_logic := '1';

begin

-- Clock generation.
ref_clk <= not ref_clk after 5.0 ns;    -- 1 / (2*5ns) = 100 MHz
out_clk <= not out_clk after 4.0 ns;    -- 1 / (2*4ns) = 125 MHz

-- Generate each of the time reference signals.
--  * Timestamp is a simple counter.
--  * Real-time clock is initialized to timestamp + test offset,
--    then increments directly after that point.
p_ref : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        ref_tstamp <= ref_tstamp + REF_INCR;
        if (test_reset = '1') then
            ref_rtc <= rtc_init(ref_tstamp + REF_INCR, test_offset);
        else
            ref_rtc <= rtc_incr(ref_rtc, REF_INCR);
        end if;
    end if;
end process;

p_out : process(out_clk)
begin
    if rising_edge(out_clk) then
        out_tstamp  <= out_tstamp + OUT_INCR;
        if (test_reset = '1') then
            out_rtc_ref <= rtc_init(out_tstamp + OUT_INCR, test_offset);
        else
            out_rtc_ref <= rtc_incr(out_rtc_ref, OUT_INCR);
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.ptp_realsync
    generic map(
    OUT_CLK_HZ  => OUT_CLK_HZ / ACCELERATE)
    port map(
    ref_clk     => ref_clk,
    ref_tstamp  => ref_tstamp,
    ref_rtc     => ref_rtc,
    out_clk     => out_clk,
    out_tstamp  => out_tstamp,
    out_rtc     => out_rtc_uut);

-- Compare output to reference.
p_check : process(out_clk)
begin
    if rising_edge(out_clk) then
        if (test_reset = '0') then
            assert (out_rtc_ref = out_rtc_uut)
                report "RTC mismatch." severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure run_one(offset_sec: real) is
    begin
        -- Reset initial state with the new offset.
        test_offset <= get_tstamp_sec(offset_sec);
        test_reset  <= '1';

        -- Wait for pipeline to flush, then resume checking.
        -- With acceleration, trial length ensures a one-second rollover.
        wait for 1 us;
        test_reset  <= '0';
        wait for 122 us;
    end procedure;
begin
    for n in 1 to 10 loop
        run_one(0.0000000000000000000);
        run_one(0.1234567890123456789);
        run_one(0.4321098765432109876);
        run_one(0.7654321098765432109);
        run_one(0.9876543210987654321);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
