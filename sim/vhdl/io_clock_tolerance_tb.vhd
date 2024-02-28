--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the clock frequency-tolerance tester
--
-- This testbench runs several instances of the unit under test, with
-- configurations that are nominal, too fast, and too slow.  The test
-- confirms that pass/fail results match expected tolerances.
--
-- The complete test takes 1.2 msec.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity io_clock_tolerance_tb is
    -- Unit testbench top level, no I/O ports
end io_clock_tolerance_tb;

architecture tb of io_clock_tolerance_tb is

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Pass/fail flags from each unit under test.
signal out_pass     : std_logic_vector(3 downto 0);
signal out_done     : std_logic_vector(3 downto 0);

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Units under test:
uut0: entity work.io_clock_tolerance
    generic map(
    REF_CLK_HZ  => 100_110_000, -- Very fast (+1100 ppm)
    TST_CLK_HZ  => 125_000_000)
    port map(
    reset_p     => reset_p,
    ref_clk     => clk_100,
    tst_clk     => clk_125,
    out_pass    => out_pass(0),
    out_done    => out_done(0));

uut1: entity work.io_clock_tolerance
    generic map(
    REF_CLK_HZ  => 100_090_000, -- Fast (+900 ppm)
    TST_CLK_HZ  => 125_000_000)
    port map(
    reset_p     => reset_p,
    ref_clk     => clk_100,
    tst_clk     => clk_125,
    out_pass    => out_pass(1),
    out_done    => out_done(1));

uut2: entity work.io_clock_tolerance
    generic map(
    REF_CLK_HZ  =>  99_910_000, -- Slow (-900 ppm)
    TST_CLK_HZ  => 125_000_000)
    port map(
    reset_p     => reset_p,
    ref_clk     => clk_100,
    tst_clk     => clk_125,
    out_pass    => out_pass(2),
    out_done    => out_done(2));

uut3: entity work.io_clock_tolerance
    generic map(
    REF_CLK_HZ  =>  99_890_000, -- Very slow (-1100 ppm)
    TST_CLK_HZ  => 125_000_000)
    port map(
    reset_p     => reset_p,
    ref_clk     => clk_100,
    tst_clk     => clk_125,
    out_pass    => out_pass(3),
    out_done    => out_done(3));

-- High-level test control.
p_test : process
begin
    wait until falling_edge(reset_p);
    wait for 900 us;
    assert (out_done = "0000" and out_pass = "0000")
        report "Output mismatch near end of test." severity error;
    wait for 200 us;
    assert (out_done = "1111" and out_pass = "0110")
        report "Output mismatch after end of test." severity error;
    report "All tests completed!";
    wait;
end process;

end tb;
