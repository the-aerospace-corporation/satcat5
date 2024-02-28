--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Pseudo-LRU cache controller
--
-- This testbench runs two separate tests:
--  * A series of fixed queries with known answers.
--  * A randomly generated sequence to verify statistical fairness.
--
-- The complete test takes less than 1.7 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity tcam_cache_tb_helper is
    generic (
    ALGORITHM   : string;       -- "NRU2", "PLRU"
    TABLE_SIZE  : positive;     -- Typically 7 or 8
    VERBOSE     : boolean := false);
    port (
    test_done   : out std_logic);
end tcam_cache_tb_helper;

architecture helper of tcam_cache_tb_helper is

-- Return label for this test unit.
function get_label return string is
begin
    return ALGORITHM & "_" & integer'image(TABLE_SIZE) & ": ";
end function;

-- Convert string to table-index.
function char2idx(x : character) return natural is
begin
    return character'pos(x) - character'pos('A');
end function;

-- System clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input sequence generator
signal in_index     : integer range 0 to TABLE_SIZE-1 := 0;
signal in_read      : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_done      : std_logic := '0';

-- Output statistics.
type count_array_t is array(0 to TABLE_SIZE-1) of natural;
signal out_index    : integer range 0 to TABLE_SIZE-1;
signal out_hold     : std_logic := '0';
signal count_run    : std_logic := '0';
signal count_in     : count_array_t := (others => 0);
signal count_out    : count_array_t := (others => 0);
signal count_total  : natural := 0;

-- Test control
type string_ptr is access string;
signal test_index   : integer := 0;
signal test_rate    : real := -1.0;
shared variable test_fixed : string_ptr := null;

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Input sequence generator
p_in : process(clk_100)
    variable seed1  : positive := 87501875;
    variable seed2  : positive := 68115321;
    variable rand   : real := 0.0;
    variable rd_idx : integer := 0;
    variable wr_idx : integer := 0;
    variable hld_ct : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Randomize the input stream.
        in_write <= '0';
        in_read  <= '0';
        uniform(seed1, seed2, rand);
        if (test_rate < 0.0 or reset_p = '1') then
            -- Pause stream between tests.
            in_index    <= 0;
            in_done     <= '0';
            rd_idx      := 0;
            wr_idx      := 0;
        elsif (rand >= test_rate) then
            -- No new data this clock.
            in_index    <= 0;
        elsif (wr_idx < TABLE_SIZE) then
            -- Always start by writing [0..N)
            in_index    <= wr_idx;
            in_write    <= '1';
            wr_idx      := wr_idx + 1;
        elsif (test_fixed = null) then
            -- Random read
            uniform(seed1, seed2, rand);
            in_index    <= integer(floor(rand * real(TABLE_SIZE)));
            in_read     <= '1';
        elsif (rd_idx < test_fixed.all'length) then
            -- Fixed read (note strings are 1-indexed)
            rd_idx      := rd_idx + 1;
            in_index    <= char2idx(test_fixed.all(rd_idx));
            in_read     <= '1';
        else
            -- End of fixed sequence
            in_index    <= 0;
            in_done     <= '1';
        end if;

        -- Randomly assert the out_hold flag for a few clock cycles.
        uniform(seed1, seed2, rand);
        if (hld_ct > 0) then
            hld_ct := hld_ct - 1;
        elsif (rand < 0.01) then
            hld_ct := 5;
        end if;
        out_hold <= bool2bit(hld_ct > 0);
    end if;
end process;

-- Unit under test
gen_nru2 : if (ALGORITHM = "NRU2") generate
    uut : entity work.tcam_cache_nru2
        generic map(
        TABLE_SIZE  => TABLE_SIZE)
        port map(
        in_index    => in_index,
        in_read     => in_read,
        in_write    => in_write,
        out_index   => out_index,
        out_hold    => out_hold,
        clk         => clk_100,
        reset_p     => reset_p);
end generate;

gen_plru : if (ALGORITHM = "PLRU") generate
    uut : entity work.tcam_cache_plru
        generic map(
        TABLE_SIZE  => TABLE_SIZE)
        port map(
        in_index    => in_index,
        in_read     => in_read,
        in_write    => in_write,
        out_index   => out_index,
        out_hold    => out_hold,
        clk         => clk_100,
        reset_p     => reset_p);
end generate;

-- Output statistics.
p_count : process(clk_100)
    variable in_prev1   : integer := 0;
    variable in_prev2   : integer := 0;
    variable out_prev   : integer := 0;
    variable hold_chk   : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Sample output after each new input.
        -- (Not perfect, but shouldn't introduce any bias...)
        if (reset_p = '1' or count_run = '0') then
            count_in    <= (others => 0);
            count_out   <= (others => 0);
            count_total <= 0;
        elsif (in_read = '1') then
            count_in(in_index) <= count_in(in_index) + 1;
            count_out(out_index) <= count_out(out_index) + 1;
            count_total <= count_total + 1;
        end if;

        -- Confirm the "out_hold" flag is respected.
        if (hold_chk = '1') then
            assert (out_index = out_prev)
                report get_label & "Unexpected change in out_index" severity error;
        end if;
        out_prev    := out_index;
        hold_chk    := out_hold and not reset_p;
    end if;
end process;

-- High-level test control
-- Test control
p_test : process
    -- Start test sequence.
    procedure start(rr:real; x:string) is
    begin
        -- Cleanup from previous test.
        wait until rising_edge(clk_100);
        reset_p     <= '1';
        if (test_fixed /= null) then
            deallocate(test_fixed);
        end if;

        -- Start of new test.
        if (VERBOSE) then
            report get_label & "Starting test #" & integer'image(test_index + 1);
        end if;
        test_index  <= test_index  +1;
        test_rate   <= rr;
        count_run   <= '0';
        if (x'length > 0) then
            test_fixed := new string'(x);
        else
            test_fixed := null;
        end if;
        wait until rising_edge(clk_100);
        reset_p     <= '0';
    end procedure;

    -- Wait for N input words.
    procedure in_wait(iter:natural) is
        variable remct : natural := iter;
    begin
        while (remct > 0) loop
            wait until rising_edge(clk_100);
            if (in_read = '1') then
                remct := remct - 1;
            end if;
        end loop;
    end procedure;

    -- Quick test of the priority-encoder function.
    procedure test_priority is
        subtype mask_t is std_logic_vector(6 downto 0);
        constant ERRMSG : string := "Bad priority_encoder.";
        constant TEST0 : mask_t := "1010101";   -- Priority = LSB
        constant TEST1 : mask_t := "1000010";
        constant TEST2 : mask_t := "1111100";
        constant TEST3 : mask_t := "0001000";
        constant TEST4 : mask_t := "1010000";
        constant TEST5 : mask_t := "0100000";
        constant TEST6 : mask_t := "1000000";
    begin
        assert (priority_encoder(TEST0) = 0) report ERRMSG;
        assert (priority_encoder(TEST1) = 1) report ERRMSG;
        assert (priority_encoder(TEST2) = 2) report ERRMSG;
        assert (priority_encoder(TEST3) = 3) report ERRMSG;
        assert (priority_encoder(TEST4) = 4) report ERRMSG;
        assert (priority_encoder(TEST5) = 5) report ERRMSG;
        assert (priority_encoder(TEST6) = 6) report ERRMSG;
    end procedure;

    -- Run a single fixed-sequence test with a known final answer(s).
    -- (Note: Output is non-deterministic due to recycler timing.)
    procedure run_fixed(rr:real; x,y:string) is
        variable ok : std_logic := '0';
    begin
        -- Start test sequence.
        start(rr, x);

        -- Wait a while, then confirm output.
        -- (Match any on the list of acceptable outputs.)
        wait until rising_edge(in_done);
        wait for 0.1 us;
        for n in y'range loop
            ok := ok or bool2bit(out_index = char2idx(y(n)));
        end loop;
        assert (ok = '1')
            report get_label & "Test " & integer'image(test_index)
                & " output mismatch: " & integer'image(out_index)
            severity error;

        -- Cleanup.
        test_rate <= 0.0;
        wait for 0.1 us;
    end procedure;

    -- Run a random sequence to confirm fairness.
    procedure run_random(rr:real; iter,tol:positive) is
        variable count_min, count_max : natural;
    begin
        -- Start test sequence.
        start(rr, "");

        -- Let the system reach a fair initial state.
        in_wait(iter / 2);
        count_run <= '1';

        -- Run at least N more input words.
        in_wait(iter);
        test_rate <= 0.0;
        wait for 0.1 us;

        -- Confirm approximate fairness.
        count_min := ((100-tol) * count_total) / (100 * TABLE_SIZE);
        count_max := ((100+tol) * count_total) / (100 * TABLE_SIZE);
        for n in count_in'range loop
            assert (count_min < count_in(n) and count_in(n) < count_max)
                report get_label & "Count_in "
                    & integer'image(test_index) & "." & integer'image(n)
                    & " is out of range: " & integer'image(count_in(n))
                severity error;
            assert (count_min < count_out(n) and count_out(n) < count_max)
                report get_label & "Count_out "
                    & integer'image(test_index) & "." & integer'image(n)
                    & " is out of range: " & integer'image(count_out(n))
                severity error;
        end loop;
    end procedure;

    -- Run a full test sequence at designated rate.
    -- (Test sequence depends on block type and table size.)
    procedure run_sequence(rr:real) is
    begin
        if (ALGORITHM = "NRU2" and TABLE_SIZE = 7) then
            -- NRU2 Size 7 (A-G)
            run_fixed(rr, "ABCDEF", "G");
            run_fixed(rr, "ABCDEFG", "ABCDE");
            run_fixed(rr, "ABCDEFGGGGGGGGG", "ABCDE");
            run_fixed(rr, "ABCDEFGDGDGDGDG", "ABCEF");
            run_fixed(rr, "ABCDEFGFBFDGCFE", "AG");
            run_fixed(rr, "BBBBBBBCDEFGAAE", "DF");
            run_fixed(rr, "BBBBBBBCDEFGABE", "CDFG");
            run_random(rr, 15000, 30);
        elsif (ALGORITHM = "PLRU" and TABLE_SIZE = 7) then
            -- PLRU Size 7 (A-G) tests the recycler function.
            -- TODO: Tighter tolerances if we improve the recycler.
            run_fixed(rr, "ABCDEFG", "A");
            run_fixed(rr, "ABCDEFGGGGGGGGG", "A");
            run_fixed(rr, "ABCDEFGDGDGDGDG", "A");
            run_fixed(rr, "ABCDEFGFGFGFGFG", "A");
            run_fixed(rr, "BBBBBBBCDEFGAAE", "C");
            run_fixed(rr, "BBBBBBBCDEFGABE", "C");
            run_random(rr, 15000, 60);
        elsif (ALGORITHM = "PLRU" and TABLE_SIZE = 8) then
            -- PLRU Size 8 (A-H)
            run_fixed(rr, "ABCDEFGH", "A");
            run_fixed(rr, "ABCDEFGHGGGGGGGG", "A");
            run_fixed(rr, "ABCDEFGHDGDGDGDG", "A");
            run_fixed(rr, "ABCDEFGHFGFGFGFG", "A");
            run_fixed(rr, "BBBBBBBCDHEFGAAE", "C");
            run_fixed(rr, "BBBBBBBCDHEFGABE", "C");
            run_random(rr, 15000, 20);
        else
            report get_label & "Unsupported test configuration." severity failure;
        end if;
    end procedure;
begin
    -- Initial reset.
    reset_p     <= '1';
    test_done   <= '0';
    wait for 1 us;

    -- Quick test of selected items from common_functions.
    test_priority;

    -- Run test sequences under different flow-control conditions.
    run_sequence(0.2);
    run_sequence(0.8);
    run_sequence(0.9);

    test_done   <= '1';
    report get_label & "Done.";
    wait;
end process;

end helper;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity tcam_cache_tb is
    -- Testbench, no I/O ports
end tcam_cache_tb;

architecture tb of tcam_cache_tb is

signal test_done : std_logic_vector(2 downto 0) := (others => '1');

begin

-- Instantiate each test configuration.
uut0 : entity work.tcam_cache_tb_helper
    generic map(
    ALGORITHM   => "NRU2",
    TABLE_SIZE  => 7)
    port map(
    test_done   => test_done(0));

uut1 : entity work.tcam_cache_tb_helper
    generic map(
    ALGORITHM   => "PLRU",
    TABLE_SIZE  => 7)
    port map(
    test_done   => test_done(1));

uut2 : entity work.tcam_cache_tb_helper
    generic map(
    ALGORITHM   => "PLRU",
    TABLE_SIZE  => 8)
    port map(
    test_done   => test_done(2));

-- Print the overall "done" message.
p_done : process
begin
    wait until (and_reduce(test_done) = '1');
    report "All tests completed!";
    wait;
end process;

end tb;
