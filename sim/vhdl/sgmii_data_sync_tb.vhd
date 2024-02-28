--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the SGMII data synchronization block
--
-- This testbench generates a pseudorandom bit stream at approximately
-- 4.000 samples per bit, optionally with a small frequency offset and
-- Gaussian random jitter.  The synchronization block under test should
-- lock to this signal and remain locked throughout each test.
--
-- To help validate the resulting data, the input is an LFSR sequence:
--   PRBS ITU-T O.160 Section 5.6: x^23+x^18+1 (inverted signal)
--
-- This type of PRNG allows easy bit-level receiver synchronization,
-- even if the stream starts from an unknown initial position.
--
-- A full test takes just under 110 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM, SIN, COS, etc.
use     work.common_functions.all;
use     work.lfsr_sim_types.all;

entity sgmii_data_sync_tb is
    -- Unit testbench top level, no I/O ports
end sgmii_data_sync_tb;

architecture tb of sgmii_data_sync_tb is

constant LANE_COUNT : integer := 10;
subtype input_word is std_logic_vector(4*LANE_COUNT-1 downto 0);
subtype output_word is std_logic_vector(LANE_COUNT-1 downto 0);

-- Clock and reset generation
signal clk_100      : std_logic := '0';

-- Input and output streams.
signal in_data      : input_word := (others => '0');
signal in_next      : std_logic := '0';
signal in_count     : integer := 0;
signal out_data     : output_word;
signal out_next     : std_logic;
signal out_locked   : std_logic;

-- Auxiliary output stream, for statistics gathering.
type stats_t is array(0 to 15) of integer;
signal aux_data     : input_word;
signal aux_next     : std_logic;
shared variable aux_stats : stats_t := (others => 0);

-- Reference synchronization.
signal out_error    : std_logic := '0';
signal ref_data     : output_word := (others => '0');
signal ref_locked   : std_logic := '0';
signal ref_errors   : integer := 0;
signal ref_checked  : integer := 0;

-- Test control
constant flow_rate  : real := 0.8;      -- Clock-enable rate
signal test_reset   : std_logic := '1'; -- Reset receiver
signal test_nosig   : std_logic := '0'; -- Source = noise
signal test_index   : integer := 0;     -- Overall test phase
signal test_df_ppm  : real := 0.0;      -- Frequency offset (+/- 100 ppm max)
signal test_jitter  : real := 0.0;      -- Jitter over +/- X samples

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;

-- Input stream generation.
p_flow : process(clk_100)
    -- PRNG for flow-control and jitter randomization.
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;
    -- Gaussian AWGN using Box-Muller algorithm.
    variable box1, box2 : real := 0.0;
    variable box_toggle : boolean := false;
    impure function rand_gauss return real is
    begin
        if (not box_toggle) then
            -- Generate a new pair of random numbers.
            uniform(seed1, seed2, rand);
            box1 := sqrt(-2.0 * log(rand + 0.00000001));
            uniform(seed1, seed2, rand);
            box2 := 2.0 * MATH_PI * rand;
            -- Return first half of generated pair.
            box_toggle := true;
            return box1 * cos(box2);
        else
            -- Return second half of generated pair.
            box_toggle := false;
            return box1 * sin(box2);
        end if;
    end function;
    -- Bit-repetition and LFSR state.
    variable phase      : real := 0.0;
    variable jitter     : real := 0.0;
    variable lfsr       : lfsr_state := LFSR_RESET;
    variable curr_bit   : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Flow-control randomization:
        uniform(seed1, seed2, rand);
        if (rand < flow_rate) then
            -- Generate each bit of the input word.
            for n in 4*LANE_COUNT-1 downto 0 loop   -- MSB first
                -- Should we transition to the next bit?
                if (test_nosig = '1') then
                    lfsr_incr(lfsr);
                    curr_bit := lfsr_out_next(lfsr);
                    phase    := 0.0;
                elsif (phase + jitter >= 4.0) then
                    lfsr_incr(lfsr);
                    curr_bit := lfsr_out_next(lfsr);
                    jitter   := test_jitter * rand_gauss;
                    phase    := phase - 4.0;
                end if;
                -- Copy current bit and increment NCO phase.
                in_data(n) <= curr_bit;
                phase      := phase + 1.0 + 0.000001 * test_df_ppm;
            end loop;
            in_next <= '1';
        else
            in_next <= '0';
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.sgmii_data_sync
    generic map(
    DLY_STEP    => (others => '0'),
    LANE_COUNT  => LANE_COUNT)
    port map(
    in_data     => in_data,
    in_next     => in_next,
    in_tsof     => (others => '0'),
    aux_data    => aux_data,
    aux_next    => aux_next,
    out_data    => out_data,
    out_tsof    => open,            -- Not tested
    out_next    => out_next,
    out_locked  => out_locked,
    clk         => clk_100,
    reset_p     => test_reset);

-- Gather statistics on pulse alignment.
p_stats : process(clk_100)
    variable pulse : std_logic_vector(3 downto 0);
    variable incr  : integer := 0;
begin
    if rising_edge(clk_100) then
        if (test_reset = '1') then
            aux_stats := (others => 0);
        elsif (out_locked = '1' and aux_next = '1') then
            -- Count incidence of each possible four-bit pulse shape...
            for p in 0 to 15 loop
                pulse := i2s(p, 4);
                incr  := 0;
                for n in 0 to LANE_COUNT-1 loop
                    if (aux_data(4*n+3 downto 4*n) = pulse) then
                        incr := incr + 1;
                    end if;
                end loop;
                aux_stats(p) := aux_stats(p) + incr;
            end loop;
        end if;
    end if;
end process;

-- Generate and confirm the reference sequence.
p_check : process(clk_100)
    variable lfsr       : lfsr_state := LFSR_RESET;
    variable consec_err : integer := 0;
begin
    if rising_edge(clk_100) then
        -- We should never unlock, except during test restart.
        if (test_reset = '0' and test_nosig = '0' and
            out_locked = '0' and ref_locked = '1') then
            report "Receiver lost lock." severity error;
        end if;

        -- Once locked, compare reference sequence.
        if (test_reset = '1') then
            out_error   <= '0';
            ref_checked <= 0;
            ref_errors  <= 0;
            consec_err  := 0;
        elsif (test_nosig = '0' and ref_locked = '1' and
               out_locked = '1' and out_next = '1') then
            out_error   <= bool2bit(out_data /= ref_data);
            if (out_data = ref_data) then
                -- Data match, reset consecutive error count.
                consec_err := 0;
            elsif (out_data /= ref_data) then
                -- Update error count; don't report each one.
                ref_errors <= ref_errors + 1;
                -- Flush LFSR state after N consecutive errors.
                consec_err := consec_err + 1;
                if (consec_err >= 10) then
                    consec_err := 0;
                    lfsr := LFSR_RESET;
                end if;
            end if;
            ref_checked <= ref_checked + 1;
        end if;

        -- Initial LFSR synchronization.
        if (out_locked = '0') then
            -- No signal lock, reset LFSR state.
            lfsr := LFSR_RESET;
        elsif (out_next = '1' and not lfsr_sync_done(lfsr)) then
            -- Push received data into shift register.
            for n in LANE_COUNT-1 downto 0 loop    -- MSB-first.
                lfsr_sync_next(lfsr, out_data(n));
            end loop;
        end if;

        -- Once we have enough data, run PRNG for the next byte.
        if (not lfsr_sync_done(lfsr)) then
            ref_locked <= '0';
        elsif (out_next = '1') then
            ref_locked <= '1';
            for n in LANE_COUNT-1 downto 0 loop    -- MSB-first
                lfsr_incr(lfsr);
                ref_data(n) <= lfsr_out_next(lfsr);
            end loop;
        end if;

        -- Count input words.
        if (test_reset = '1') then
            in_count <= 0;
        elsif (in_next = '1') then
            in_count <= in_count + 1;
        end if;
    end if;
end process;

-- Overall test control
p_test : process
    procedure run_test(num_words : integer; dfreq_ppm, jitter_ui : real) is
        variable temp_ctr : integer := 0;
    begin
        -- Set test conditions and reset receiver.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        test_df_ppm <= dfreq_ppm;       -- Frequency offset (PPM)
        test_jitter <= jitter_ui * 4.0; -- Convert UI to samples
        test_nosig  <= '0';
        test_reset  <= '1';
        wait for 1 us;
        test_reset  <= '0';
        wait for 1 us;

        -- Wait until we've sent N words...
        wait until (in_count >= num_words);

        -- Confirm received data looks OK.
        assert (ref_locked = '1' and ref_checked > num_words/2)
            report "End of test, receiver not locked." severity error;
        if (ref_errors > num_words/100) then
            report "Bit errors: " & integer'image(ref_errors)
                          & " / " & integer'image(ref_checked)
                severity error;
        elsif (ref_errors > 0) then
            report "Bit errors: " & integer'image(ref_errors)
                          & " / " & integer'image(ref_checked)
                severity warning;
        else
            report "Bit errors: " & integer'image(ref_errors)
                          & " / " & integer'image(ref_checked)
                severity note;
        end if;

        -- Disconnect signal and wait for unlock.
        test_nosig  <= '1';
        temp_ctr    := 10000;
        while (out_locked = '1' and temp_ctr > 0) loop
            wait until rising_edge(clk_100);
            temp_ctr := temp_ctr - 1;
        end loop;
        assert (out_locked = '0')
            report "No signal, receiver still locked." severity error;
    end procedure;

    constant WORDS_SHORT    : integer := 50000;
    constant WORDS_MEDIUM   : integer := 200000;
    constant WORDS_LONG     : integer := 1000000;


    procedure run_sweep(jitter_ui : real) is
    begin
        report "Starting frequency sweep";
        run_test(WORDS_MEDIUM,   20.0, jitter_ui);
        run_test(WORDS_MEDIUM,   40.0, jitter_ui);
        run_test(WORDS_MEDIUM,   80.0, jitter_ui);
        run_test(WORDS_MEDIUM,  120.0, jitter_ui);
        run_test(WORDS_MEDIUM,  -20.0, jitter_ui);
        run_test(WORDS_MEDIUM,  -40.0, jitter_ui);
        run_test(WORDS_MEDIUM,  -80.0, jitter_ui);
        run_test(WORDS_MEDIUM, -120.0, jitter_ui);
    end procedure;
begin
    -- Run a few short tests with no frequency offset:
    run_test(WORDS_SHORT, 0.0, 0.00);
    run_test(WORDS_SHORT, 0.0, 0.02);
    run_test(WORDS_SHORT, 0.0, 0.04);
    run_test(WORDS_SHORT, 0.0, 0.08);
    run_test(WORDS_SHORT, 0.0, 0.12);

    -- Now run a full frequency sweep at varying jitter levels:
    run_sweep(0.02);
    run_sweep(0.04);
    run_sweep(0.08);
    run_sweep(0.12);

    -- Longer tests for specific cases:
    run_test(WORDS_LONG, -80.0, 0.07);
    run_test(WORDS_LONG, 120.0, 0.07);
    report "All tests completed.";
    wait;
end process;

end tb;
