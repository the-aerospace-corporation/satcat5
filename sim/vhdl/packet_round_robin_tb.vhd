--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the round-robin priority scheduler
--
-- This testbench evaluates the round-robin priority scheduler.
-- Under a variety of input loading conditions, it verifies that:
--    * All inputs are serviced equally.
--    * All inputs are serviced promptly.
--    * Input selection is never switched mid-packet.
--    * Flow control signals are asserted correctly.
--
-- The test will run indefinitely, with adequate coverage after ~20 msec.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity packet_round_robin_tb is
    -- Unit testbench top level, no I/O ports
end packet_round_robin_tb;

architecture tb of packet_round_robin_tb is

constant INPUT_COUNT : integer := 12;

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test.
signal in_last      : std_logic_vector(INPUT_COUNT-1 downto 0) := (others => '0');
signal in_valid     : std_logic_vector(INPUT_COUNT-1 downto 0) := (others => '0');
signal in_ready     : std_logic_vector(INPUT_COUNT-1 downto 0);
signal in_select    : integer range 0 to INPUT_COUNT-1;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';

-- Test control.
type count_array is array(INPUT_COUNT-1 downto 0) of integer;
signal test_index   : integer := 0;
signal test_start   : std_logic := '0';
signal pkt_count    : count_array := (others => 0);
signal pkt_total    : integer := 0;
signal in_rate      : real := 0.0;
signal out_rate     : real := 0.0;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Instantiate several independent randomize test sources.
gen_src : for n in in_valid'range generate
    p_src : process(clk_100)
        variable seed1   : positive := 1000*n + 1;
        variable seed2   : positive := 99999 - seed1;
        variable rand    : real := 0.0;
        variable rem_len : integer := 0;
        variable delay   : integer := 0;
    begin
        if rising_edge(clk_100) then
            -- Update the pending-word counter.
            if (reset_p = '1') then
                rem_len := 0;
            elsif (rem_len > 0 and in_valid(n) = '1' and in_ready(n) = '1') then
                rem_len := rem_len - 1;
            end if;

            -- If we are between packets, random chance of starting a new one.
            uniform(seed1, seed2, rand);
            if (reset_p = '0' and rem_len = 0 and rand > in_rate) then
                uniform(seed1, seed2, rand);
                rem_len := 1 + integer(floor(rand * 10.0));
            end if;

            -- Drive the valid and last strobes appropriately.
            in_valid(n) <= bool2bit(rem_len > 0);
            in_last(n)  <= bool2bit(rem_len = 1);

            -- Sanity-check on flow control rules.
            if (in_select = n) then
                assert (out_valid = in_valid(n))
                    report "Mismatch in out_valid" severity error;
                assert (in_ready(n) = out_ready)
                    report "Mismatch in in_ready" severity error;
            else
                assert (in_ready(n) = '0')
                    report "Unexpected in_ready" severity error;
            end if;

            -- Verify no more than N other inputs are serviced before this one.
            if (rem_len = 0) then
                -- Nothing on this input, reset counter
                delay := 0;
            elsif (out_valid = '1' and out_ready = '1' and out_last = '1') then
                -- End of packet detected.  Was it us or another input?
                if (in_select = n) then
                    delay := 0;
                elsif (delay >= INPUT_COUNT) then
                    assert (delay <= INPUT_COUNT)
                        report "Excessive delay on input " & integer'image(n)
                        severity error;
                else
                    delay := delay + 1;
                end if;
            end if;
        end if;
    end process;
end generate;

-- Unit under test.
uut : entity work.packet_round_robin
    generic map(
    INPUT_COUNT     => INPUT_COUNT)
    port map(
    in_last         => in_last,
    in_valid        => in_valid,
    in_ready        => in_ready,
    in_select       => in_select,
    in_error        => open,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    clk             => clk_100);

-- Output flow-control randomization and packet counting.
p_flow : process(clk_100)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
begin
    if rising_edge(clk_100) then
        -- Output flow control.
        uniform(seed1, seed2, rand);
        out_ready <= bool2bit(rand < out_rate) and not reset_p;

        -- Count packets from each input.
        if (test_start = '1') then
            pkt_count <= (others => 0);
            pkt_total <= 0;
        elsif (out_valid = '1' and out_ready = '1' and out_last = '1') then
            pkt_count(in_select) <= pkt_count(in_select) + 1;
            pkt_total <= pkt_total + 1;
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
    variable seed1  : positive := 328010;
    variable seed2  : positive := 784905;
    variable rand1, rand2 : real := 0.0;

    procedure run_test(ri, ro : real) is
        variable pkt_min, pkt_max : integer;
    begin
        -- Announce start of test and set rates.
        report "Starting test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;
        in_rate     <= ri;
        out_rate    <= ro;

        -- Strobe test-start and wait for results.
        test_start <= '1';
        wait for 1 us;
        test_start <= '0';
        wait for 999 us;

        -- Check packet counts are asserted fairly.
        -- TODO: How to check promptness?
        assert(pkt_total > 1000)
            report "Low packet count" severity warning;
        pkt_min := (pkt_total * 8) / (INPUT_COUNT * 10);
        pkt_max := (pkt_total * 12) / (INPUT_COUNT * 10);
        for n in pkt_count'range loop
            assert (pkt_min < pkt_count(n) and pkt_count(n) < pkt_max)
                report "Unfair servicing on port " & integer'image(n)
                severity error;
        end loop;
    end procedure;
begin
    -- Test various corner cases.
    run_test(0.01, 0.8);
    run_test(0.05, 0.8);
    run_test(0.10, 0.8);
    run_test(0.20, 0.2);

    -- Continue testing with random scenarios.
    loop
        uniform(seed1, seed2, rand1);
        rand1 := 0.01 + 0.09 * rand1;
        uniform(seed1, seed2, rand2);
        rand2 := 0.2 + 0.8 * rand2;
        run_test(rand1, rand2);
    end loop;
end process;

end tb;
