--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Clock detector block
--
-- This module accepts two input clocks: a known-good reference and a
-- clock that may start or stop unexpectedly.  It generates a flag
-- in each clock domain, indicating whether the test clock is running.
-- The flag can be used as a reset signal, etc.
--
-- A build-time parameter sets the maximum expected ratio between the
-- two clocks.  Either clock can be faster or slower than the other;
-- the parameter sets the maximum tolerable ratio in either direction.
-- The default ratio is 15x; higher ratios lead to a slower response.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.common_primitives.sync_toggle2pulse;

entity io_clock_detect is
    generic (
    -- Maximum expected ratio between clocks
    CLK_RATIO   : positive := 15);
    port (
    -- Reference clock domain
    ref_reset_p : in  std_logic;
    ref_clk     : in  std_logic;
    ref_halted  : out std_logic;
    ref_running : out std_logic;
    -- Test clock domain
    tst_clk     : in  std_logic;
    tst_halted  : out std_logic;
    tst_running : out std_logic);
end io_clock_detect;

architecture io_clock_detect of io_clock_detect is

-- Set counter widths to support specified maximum ratio:
constant CTR_WIDTH : positive := log2_ceil(CLK_RATIO + 1);

signal tog_fast : std_logic := '0'; -- Toggle in clk_test
signal tog_slow : std_logic := '0'; -- Toggle in clk_test
signal det_fast : std_logic;        -- Strobe in clk_ref
signal det_slow : std_logic;        -- Strobe in clk_ref
signal halt_ref : std_logic := '1'; -- Flag in clk_ref
signal halt_tst : std_logic;        -- Flag in clk_test

begin

-- Generate a toggle signal using the test clock.
p_tog : process(tst_clk)
    variable tog_count : unsigned(CTR_WIDTH downto 0) := (others => '0');
begin
    if rising_edge(tst_clk) then
        -- Always toggle the FAST signal.
        tog_fast <= not tog_fast;
        -- Toggle SLOW signal every 2^CTR_WIDTH clocks.
        -- (MSB of an N+1 bit counter toggles every 2^N clocks.)
        tog_count := tog_count + 1;
        tog_slow <= tog_count(tog_count'left);
    end if;
end process;

-- Detect those events in the reference domain.
u_detect_fast : sync_toggle2pulse
    port map(
    in_toggle   => tog_fast,
    out_strobe  => det_fast,
    out_clk     => ref_clk);
u_detect_slow : sync_toggle2pulse
    port map(
    in_toggle   => tog_slow,
    out_strobe  => det_slow,
    out_clk     => ref_clk);

p_detect : process(ref_clk)
    variable wdog_ctr : unsigned(CTR_WIDTH-1 downto 0) := (others => '0');
begin
    if rising_edge(ref_clk) then
        halt_ref <= bool2bit(wdog_ctr = 0);
        if (ref_reset_p = '1') then
            wdog_ctr := (others => '0');    -- Global reset
        elsif (det_fast = '1' or det_slow = '1') then
            wdog_ctr := (others => '1');    -- Event detect
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;       -- Idle countdown
        end if;
    end if;
end process;

-- Bring the HALT flag back into the test-clock domain.
u_reset : sync_reset
    port map(
    in_reset_p  => halt_ref,
    out_reset_p => halt_tst,
    out_clk     => tst_clk);

-- Drive top-level output signals.
ref_halted  <= halt_ref;
ref_running <= not halt_ref;
tst_halted  <= halt_tst;
tst_running <= not halt_tst;

end io_clock_detect;
