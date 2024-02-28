--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PTP clock-synthesizer unit
--
-- This unit test connects the clock-synthesizer to a free-running counter.
-- It confirms that it reaches the expected output phase and frequency
-- under a variety of frequency initial conditions.
--
-- The complete test takes just under 2.3 milliseconds.
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
    DITHER_EN   : boolean;
    MSB_FIRST   : boolean);
end ptp_clksynth_tb_helper;

architecture ptp_clksynth_tb_helper of ptp_clksynth_tb_helper is

constant CLK_DLY_NS : real := 0.5e9 / real(PAR_CLK_HZ);
constant SYNTH_NS   : real := 1.0e9 / real(SYNTH_HZ);
constant REF_MODULO : tstamp_t := get_tstamp_incr(REF_MOD_HZ);

signal par_clk      : std_logic := '0';
signal ref_tstamp   : tstamp_t := (others => '0');
signal par_tstamp   : tstamp_t := (others => '0');
signal par_out      : std_logic_vector(PAR_COUNT-1 downto 0);
signal par_ref      : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');
signal par_match    : std_logic_vector(PAR_COUNT-1 downto 0) := (others => '0');
signal reset_p      : std_logic := '1';
signal check_en     : std_logic := '0';
signal ref_lock     : std_logic := '0';
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
            ref_tstamp <= ref_offset;
        elsif REF_MODULO > 0 then
            ref_tstamp <= (ref_tstamp + ref_incr) mod REF_MODULO;
        else
            ref_tstamp <= ref_tstamp + ref_incr;
        end if;
    end if;
end process;

-- Suppress the reference signal on startup?
-- (Many references emit zero until they are locked.)
par_tstamp <= ref_tstamp when (ref_lock = '1') else TSTAMP_DISABLED;

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
            tref := (get_time_nsec(ref_tstamp) + par_ns + real(n) * out_ns) mod SYNTH_NS;
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
    DITHER_EN   => DITHER_EN,
    MSB_FIRST   => MSB_FIRST)
    port map(
    par_clk     => par_clk,
    par_tstamp  => par_tstamp,
    par_out     => par_out,
    reset_p     => reset_p);

-- Compare output to reference.
p_check : process(par_clk)
    variable diff : integer := 0;
    variable ok : std_logic := '0';
begin
    if rising_edge(par_clk) then
        if (reset_p = '0' and check_en = '1') then
            diff := count_zeros(par_match);
            assert ((diff = 0) or (DITHER_EN and diff = 1))
                report "Output clock mismatch: " & integer'image(diff) severity error;
        end if;

        for b in par_ref'range loop
            par_match(b) <= bool2bit((par_ref(b) = 'Z') or (par_ref(b) = par_out(b)));
        end loop;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure test_single(
        offset_ns   : real;             -- Iniital value of timestamp counter
        freq_ppm    : real;             -- Reference frequency offset (ppm)
        lock_time   : time := 5 us;     -- Max allowed time for UUT to lock
        pre_time    : time := 0 us) is  -- Suppress reference on startup?
        constant period_ns : real := 1.0e3 * (1.0e6 + freq_ppm) / real(PAR_CLK_HZ);
    begin
        -- Reset and set test configuration.
        test_index  <= test_index + 1;
        reset_p     <= '1';
        ref_lock    <= bool2bit(pre_time = 0 us);
        check_en    <= '0';
        if (REF_MODULO > 0 and offset_ns < 0.0) then
            ref_offset  <= get_tstamp_nsec(offset_ns) + REF_MODULO;
        else
            ref_offset  <= get_tstamp_nsec(offset_ns);
        end if;
        ref_incr    <= get_tstamp_nsec(period_ns);

        -- Run the test sequence.
        wait for 1 us;          -- Reset unit under test
        report "Starting test #" & integer'image(test_index);
        reset_p <= '0';         -- Release reset
        if (pre_time > 0 us) then
            wait for pre_time;  -- Wait designated period
            ref_lock <= '1';    -- Begin normal operation
        end if;
        wait for lock_time;     -- Wait for lock (varies)
        check_en <= '1';        -- Start checking output
        wait for 190 us;        -- Run for a while
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
    -- Repeat above, but zero input for a while.
    test_single(      0.0, 0.0,  5 us, 10 us);
    test_single(850_000.0, 0.0, 75 us, 10 us);
    test_single(950_000.0, 0.0, 75 us, 10 us);
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
    DITHER_EN   => false,
    MSB_FIRST   => false);

uut1 : entity work.ptp_clksynth_tb_helper
    generic map(
    SYNTH_HZ    => 4_321_000,
    PAR_CLK_HZ  => 100_000_000,
    PAR_COUNT   => 16,
    REF_MOD_HZ  => 1000,
    DITHER_EN   => true,
    MSB_FIRST   => true);

uut2 : entity work.ptp_clksynth_tb_helper
    generic map(
    SYNTH_HZ    => 20_000,
    PAR_CLK_HZ  => 100_000_000,
    PAR_COUNT   => 16,
    REF_MOD_HZ  => 1000,
    DITHER_EN   => false,
    MSB_FIRST   => true);

end tb;
