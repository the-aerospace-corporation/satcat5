--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation
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
-- Testbench for the PTP clock-synthesizer unit
--
-- This unit test connects the clock-synthesizer to a free-running counter.
-- It confirms that it reaches the expected output phase and frequency
-- under a variety of frequency initial conditions.
--
-- The complete test takes just under 1.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.ptp_types.all;

entity ptp_clksynth_tb_helper is
    generic (
    SYNTH_HZ    : positive;
    PAR_CLK_HZ  : positive;
    PAR_COUNT   : positive;
    REF_MOD_HZ  : natural;
    MSB_FIRST   : boolean);
end ptp_clksynth_tb_helper;

architecture ptp_clksynth_tb_helper of ptp_clksynth_tb_helper is

constant CLK_DLY_NS : real := 0.5e9 / real(PAR_CLK_HZ);
constant SYNTH_NS   : real := 1.0e9 / real(SYNTH_HZ);
constant REF_MODULO : tstamp_t := get_tstamp_incr(REF_MOD_HZ);

signal par_clk      : std_logic := '0';
signal par_tstamp   : tstamp_t := (others => '0');
signal par_out      : std_logic_vector(PAR_COUNT-1 downto 0);
signal par_ref      : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');
signal par_match    : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');
signal reset_p      : std_logic := '1';
signal check_en     : std_logic := '0';
signal ref_incr     : tstamp_t := (others => '0');
signal ref_offset   : tstamp_t := (others => '0');
signal test_index   : natural := 0;

begin

-- Clock generation.
par_clk <= not par_clk after CLK_DLY_NS * 1 ns;

-- Generate the free-running reference counter.
p_tstamp : process(par_clk)
begin
    if rising_edge(par_clk) then
        if (reset_p = '1') then
            par_tstamp <= ref_offset;
        elsif REF_MODULO > 0 then
            par_tstamp <= (par_tstamp + ref_incr) mod REF_MODULO;
        else
            par_tstamp <= par_tstamp + ref_incr;
        end if;
    end if;
end process;

-- Generate reference signal.
p_ref : process(par_clk)
    constant MARGIN : real := 0.5;
    variable par_ns : real := 0.0;
    variable out_ns : real := 0.0;
    variable tref : real := 0.0;
    variable btmp : std_logic := '0';
begin
    if rising_edge(par_clk) then
        -- Recalculate precise increments for each test configuration.
        if (reset_p = '1') then
            par_ns := get_time_nsec(ref_incr);
            out_ns := par_ns / real(PAR_COUNT);
        end if;
        -- Calculate expected phase of each reference bit.
        for n in 0 to PAR_COUNT-1 loop
            -- Modulo current time to get clock phase.
            tref := (get_time_nsec(par_tstamp) + par_ns + real(n) * out_ns) mod SYNTH_NS;
            -- Add some fuzziness at the edges. ('Z' = Don't-care)
            if (tref < MARGIN) then
                btmp := 'Z';    -- Rising edge
            elsif (tref < 0.5*SYNTH_NS - MARGIN) then
                btmp := '1';    -- Asserted
            elsif (tref < 0.5*SYNTH_NS + MARGIN) then
                btmp := 'Z';    -- Falling edge
            elsif (tref < SYNTH_NS - MARGIN) then
                btmp := '0';    -- Deasserted
            else
                btmp := 'Z';    -- Rising edge
            end if;
            -- Assign to the appropriate parallel bit.
            if MSB_FIRST then
                par_ref(par_ref'left-n) <= btmp;
            else
                par_ref(n) <= btmp;
            end if;
        end loop;
    end if;
end process;

-- Unit under test.
uut : entity work.ptp_clksynth
    generic map(
    SYNTH_HZ    => SYNTH_HZ,
    PAR_CLK_HZ  => PAR_CLK_HZ,
    PAR_COUNT   => PAR_COUNT,
    REF_MOD_HZ  => REF_MOD_HZ,
    MSB_FIRST   => MSB_FIRST)
    port map(
    par_clk     => par_clk,
    par_tstamp  => par_tstamp,
    par_out     => par_out,
    reset_p     => reset_p);

-- Compare output to reference.
p_check : process(par_clk)
    variable ok : std_logic := '0';
begin
    if rising_edge(par_clk) then
        if (reset_p = '0' and check_en = '1') then
            assert (and_reduce(par_match) = '1')
                report "Output clock mismatch: " & integer'image(count_zeros(par_match)) severity error;
        end if;

        for b in par_ref'range loop
            par_match(b) <= bool2bit((par_ref(b) = 'Z') or (par_ref(b) = par_out(b)));
        end loop;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure test_single(offset_ns, freq_ppm : real; lock_time : time := 5 us) is
        constant period_ns : real := 1.0e3 * (1.0e6 + freq_ppm) / real(PAR_CLK_HZ);
    begin
        -- Reset and set test configuration.
        test_index  <= test_index + 1;
        reset_p     <= '1';
        check_en    <= '0';
        if (REF_MODULO > 0 and offset_ns < 0.0) then
            ref_offset  <= get_tstamp_nsec(offset_ns) + REF_MODULO;
        else
            ref_offset  <= get_tstamp_nsec(offset_ns);
        end if;
        ref_incr    <= get_tstamp_nsec(period_ns);

        -- Run the test sequence.
        wait for 1 us;      -- Reset unit under test
        report "Starting test #" & integer'image(test_index);
        reset_p <= '0';     -- Release reset
        wait for lock_time; -- Wait for lock (varies)
        check_en <= '1';    -- Start checking output
        wait for 190 us;    -- Run for a while
    end procedure;
begin
    -- Ordinary tests.
    test_single(   0.0,    0.0);
    test_single(  50.0,   50.0);
    test_single( 100.0,  100.0);
    test_single( -50.0, -100.0);
    test_single( -80.0,   25.0);
    -- Rollover tests may take longer to lock.
    test_single(850_000.0, 0.0, 75 us);
    test_single(950_000.0, 0.0, 75 us);
    report "All tests completed!";
    wait;
end process;

end ptp_clksynth_tb_helper;

--------------------------------------------------------------------------

entity ptp_clksynth_tb is
    -- Testbench --> No I/O ports
end ptp_clksynth_tb;

architecture tb of ptp_clksynth_tb is

begin

-- Instantiate each test configuration:
uut0 : entity work.ptp_clksynth_tb_helper
    generic map(
    SYNTH_HZ    => 7_654_321,
    PAR_CLK_HZ  => 125_000_000,
    PAR_COUNT   => 16,
    REF_MOD_HZ  => 0,
    MSB_FIRST   => false);

uut1 : entity work.ptp_clksynth_tb_helper
    generic map(
    SYNTH_HZ    => 4_321_000,
    PAR_CLK_HZ  => 100_000_000,
    PAR_COUNT   => 16,
    REF_MOD_HZ  => 1000,
    MSB_FIRST   => true);

end tb;
