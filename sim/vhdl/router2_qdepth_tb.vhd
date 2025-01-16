--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Unit test for the queue-depth estimation block (router2_qdepth)
--
-- This test simulates a queue with bursty loads, and confirms that the
-- queue-depth estimator correctly nullifies the effect of these bursts.
-- The test is repeated for several different filter configurations.
--
-- The complete test takes 10.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.router_sim_tools.rand_int;

entity router2_qdepth_tb_single is
    generic (
    TEST_ITER   : positive; -- Number of tests to run
    T0_MSEC     : real;     -- Time window for minimum
    T1_MSEC     : real);    -- Time constant for averaging
end router2_qdepth_tb_single;

architecture single of router2_qdepth_tb_single is

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test.
signal in_qdepth    : unsigned(7 downto 0) := (others => '0');
signal out_qdepth   : unsigned(7 downto 0);

-- Test control.
signal test_index   : natural := 0;
signal test_qdepth  : unsigned(7 downto 0) := (others => '0');

begin

-- Clock generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Input sequence is random in the range [qdepth, 255].
p_qdepth : process(clk)
    variable rand : natural := 0;
begin
    if rising_edge(clk) then
        in_qdepth <= test_qdepth + rand_int(256 - to_integer(test_qdepth));
    end if;
end process;

-- Unit under test.
uut : entity work.router2_qdepth
    generic map(
    REFCLK_HZ   => 100_000_000,
    T0_MSEC     => T0_MSEC,
    T1_MSEC     => T1_MSEC)
    port map(
    in_qdepth   => in_qdepth,
    out_qdepth  => out_qdepth,
    clk         => clk,
    reset_p     => reset_p);

-- High-level test control.
p_test : process
    -- Estimated settling time is the larger of the two time constants.
    constant tau_wait : time := 1 ms * real_max(2.0 * T0_MSEC, 8.0 * T1_MSEC);

    procedure run_one(qdepth: natural) is
        variable diff : integer := 0;
    begin
        -- Set test conditions.
        wait until rising_edge(clk);
        test_index  <= test_index + 1;
        test_qdepth <= to_unsigned(qdepth, test_qdepth'length);
        -- Wait for settling time and check convergence.
        wait for tau_wait;
        diff := to_integer(out_qdepth) - to_integer(test_qdepth);
        assert (abs(diff) < 3)
            report "Output mismatch: " & integer'image(diff);
    end procedure;
begin
    reset_p <= '1';
    test_index <= 0;
    test_qdepth <= (others => '0');
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    run_one(0);
    run_one(255);
    run_one(0);
    run_one(255);
    for n in 1 to TEST_ITER loop
        run_one(rand_int(256));
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity router2_qdepth_tb is
    -- Testbench --> No I/O ports
end router2_qdepth_tb;

architecture tb of router2_qdepth_tb is

begin

-- Demonstrate operation at different pipeline widths.
uut0 : entity work.router2_qdepth_tb_single
    generic map(TEST_ITER => 400, T0_MSEC => 0.01, T1_MSEC => 0.00);
uut1 : entity work.router2_qdepth_tb_single
    generic map(TEST_ITER => 25, T0_MSEC => 0.01, T1_MSEC => 0.04);
uut2 : entity work.router2_qdepth_tb_single
    generic map(TEST_ITER => 8, T0_MSEC => 0.01, T1_MSEC => 0.10);

end tb;
