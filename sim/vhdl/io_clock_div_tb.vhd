--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the programmable clock-divider block
--
-- This testbench configures the clock-divider for different output
-- configurations, with a mixture of fixed and random divide ratios.
--
-- The complete test takes 0.97 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.router_sim_tools.rand_int;

entity io_clock_div_tb is
    -- Unit test has no top-level I/O.
end io_clock_div_tb;

architecture tb of io_clock_div_tb is

constant RATE_WIDTH : positive := 8;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test.
signal cfg_divide   : unsigned(7 downto 0) := (others => '0');
signal out_clk      : std_logic;
signal out_next     : std_logic;

-- High-level test control.
signal test_divide  : unsigned(7 downto 0) := (others => '0');

-- Circular-buffer FIFO for reference clock-divider ratios.
constant FIFO_SIZE : natural := 15;
type fifo_t is array(0 to FIFO_SIZE-1) of natural;
shared variable fifo : fifo_t := (others => 0);
signal wr_idx           : natural := 0;
signal rd_rise, rd_fall : natural := 0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Synchronize configuration changes and note expected duration.
p_ref : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_next = '1') then
            cfg_divide <= test_divide;
            if (test_divide > 0) then
                fifo(wr_idx) := to_integer(test_divide);
                wr_idx <= (wr_idx + 1) mod FIFO_SIZE;
            end if;
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.io_clock_div
    port map(
    ref_clk     => clk_100,
    cfg_divide  => cfg_divide,
    out_clk     => out_clk,
    out_next    => out_next,
    reset_p     => reset_p);

-- Check duration of each output cycle.
p_check : process(out_clk)
    -- First rising edge simply records the reference time.
    -- After that, check duration since previous transition and increment read-index.
    variable tprev : time := 0 ns;
    impure function check_duration(rd_idx: natural) return natural is
        variable ref : natural := fifo(rd_idx);
        variable dt  : natural := (now - tprev) / 5 ns;
    begin
        tprev := now;
        if dt < 500 then
            assert (dt = ref) report "Duration mismatch.";
            return (rd_idx + 1) mod FIFO_SIZE;
        else
            return rd_idx;
        end if;
    end function;
begin
    if rising_edge(out_clk) then
        rd_rise <= check_duration(rd_rise);
    elsif falling_edge(out_clk) then
        rd_fall <= check_duration(rd_fall);
    end if;
end process;

-- High-level test control.
p_test : process
begin
    test_divide <= (others => '0');
    wait for 10 us;
    test_divide <= x"01"; wait for 10 us;
    test_divide <= x"02"; wait for 10 us;
    test_divide <= x"03"; wait for 10 us;
    test_divide <= x"04"; wait for 10 us;
    test_divide <= x"FF"; wait for 10 us;
    test_divide <= x"42"; wait for 10 us;
    for n in 1 to 90 loop
        test_divide <= to_unsigned(1 + rand_int(255), test_divide'length);
        wait for 10 us;
    end loop;
    report "All tests completed.";
    wait;
end process;

end tb;
