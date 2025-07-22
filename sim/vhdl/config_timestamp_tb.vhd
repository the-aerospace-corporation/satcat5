--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the fixed-interval timestamp counter
--
-- With several different reference clocks, configure a 1-microsecond
-- timer and confirm the tick rate matches expectations.
--
-- The test sequence takes about 0.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity config_timestamp_tb is
    -- Unit testbench, no I/O ports.
end config_timestamp_tb;

architecture tb of config_timestamp_tb is

signal clk_83   : std_logic := '0';
signal clk_100  : std_logic := '0';
signal clk_125  : std_logic := '0';
signal reset_p  : std_logic := '1';

subtype count_t is unsigned(15 downto 0);
signal ctr_ref  : count_t := (others => '0');
signal ctr_out0 : count_t;
signal ctr_out1 : count_t;
signal ctr_out2 : count_t;

begin

-- Generate the reference counter.
p_ref : process
begin
    ctr_ref <= (others => '0');
    wait until falling_edge(reset_p);
    loop
        wait for 1 us;
        ctr_ref <= ctr_ref + 1;
    end loop;
end process;

-- Generate clocks at 83.3, 100.0, and 125.0 MHz.
clk_83  <= not clk_83 after 6 ns;
clk_100 <= not clk_100 after 5 ns;
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Unit under test for each of the above clocks.
uut0 : entity work.config_timestamp
    generic map(
    REFCLK_HZ   => 83_333_333,
    CTR_HZ      => 1_000_000,
    CTR_WIDTH   => ctr_ref'length)
    port map(
    out_ctr     => ctr_out0,
    refclk      => clk_83,
    reset_p     => reset_p);

uut1 : entity work.config_timestamp
    generic map(
    REFCLK_HZ   => 100_000_000,
    CTR_HZ      => 1_000_000,
    CTR_WIDTH   => ctr_ref'length)
    port map(
    out_ctr     => ctr_out1,
    refclk      => clk_100,
    reset_p     => reset_p);

uut2 : entity work.config_timestamp
    generic map(
    REFCLK_HZ   => 125_000_000,
    CTR_HZ      => 1_000_000,
    CTR_WIDTH   => ctr_ref'length)
    port map(
    out_ctr     => ctr_out2,
    refclk      => clk_125,
    reset_p     => reset_p);

-- Inspect the counter at microsecond intervals.
p_check : process
begin
    wait until falling_edge(reset_p);
    wait for 0.5 us;    -- Middle of first window.
    loop
        assert (ctr_out0 = ctr_ref) report "Ctr0 mismatch" severity error;
        assert (ctr_out1 = ctr_ref) report "Ctr0 mismatch" severity error;
        assert (ctr_out2 = ctr_ref) report "Ctr0 mismatch" severity error;
        if (ctr_ref = 900) then
            report "All tests completed.";
        end if;
        wait for 1 us;  -- Middle of next window.
    end loop;
end process;

end tb;
