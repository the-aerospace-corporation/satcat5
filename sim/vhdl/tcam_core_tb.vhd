--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Ternary-CAM block
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.tcam_constants.all;

entity tcam_core_tb_helper is
    generic (
    TEST_LABEL  : string;           -- Label for this instance
    INPUT_WIDTH : positive;         -- Width of the search term
    TABLE_SIZE  : positive;         -- Max stored MAC addresses
    REPL_MODE   : repl_policy;      -- Replacement mode (see above)
    TCAM_MODE   : write_policy);    -- Enable wildcard searches?
    port (
    test_done   : out std_logic);
end tcam_core_tb_helper;

architecture helper of tcam_core_tb_helper is

-- Define convenience types.
subtype input_word is std_logic_vector(INPUT_WIDTH-1 downto 0);
subtype table_addr is integer range 0 to TABLE_SIZE-1;
subtype table_plen is integer range 1 to INPUT_WIDTH;

-- Reference table stores keyword, prefix-length, and table index
-- (with special codes for NOT_FOUND and DONT_CARE) for a number
-- of pre-generated random addresses.
type ref_entry is record
    keyword : input_word;   -- Base address for search
    keymask : input_word;   -- Prefix mask (1 = fixed, 0 = wildcard)
    keylen  : table_plen;   -- Prefix length (number of '1' bits)
    index   : integer;      -- Expected search index
end record;

constant INDEX_NOT_FOUND    : integer := -1;
constant INDEX_UNKNOWN      : integer := -2;
constant INDEX_ERROR        : integer := -3;
constant REF_COUNT          : positive := 2*TABLE_SIZE;
type ref_array is array(0 to REF_COUNT-1) of ref_entry;

-- Randomly generate an initial reference table.
function initial_table return ref_array is
    variable seed1  : positive := 57105809;
    variable seed2  : positive := 85710857;
    variable rand   : real := 0.0;
    variable addr   : input_word;
    variable mask   : input_word;
    variable wild   : integer := 0;
    variable ref    : ref_array;
begin
    -- For each entry in the table...
    for n in ref'range loop
        -- If applicable, randomly generate a prefix-mask.
        -- (Keep them fairly narrow to avoid collisions.)
        if (TCAM_MODE = TCAM_MODE_MAXLEN) then
            uniform(seed1, seed2, rand);
            wild := integer(floor(rand * 8.0));
            for b in mask'range loop
                mask(b) := bool2bit(b >= wild);
            end loop;
        else
            mask := (others => '1');    -- No wildcard
        end if;
        -- Randomly generate an address.
        for b in addr'range loop
            uniform(seed1, seed2, rand);
            addr(b) := bool2bit(rand < 0.5);
        end loop;
        ref(n).keyword := addr and mask;
        ref(n).keymask := mask;
        ref(n).keylen  := INPUT_WIDTH - wild;
        ref(n).index   := INDEX_NOT_FOUND;
    end loop;
    return ref;
end function;

-- System clock and reset
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test
signal in_data      : input_word := (others => '0');
signal in_next      : std_logic := '0';
signal out_index    : table_addr;
signal out_found    : std_logic;
signal out_next     : std_logic;
signal out_error    : std_logic;
signal cfg_index    : table_addr;
signal cfg_data     : input_word := (others => '0');
signal cfg_plen     : table_plen := INPUT_WIDTH;
signal cfg_valid    : std_logic := '0';
signal cfg_ready    : std_logic;
signal cfg_reject   : std_logic;
signal scan_index   : integer range 0 to TABLE_SIZE-1 := 0;
signal scan_valid   : std_logic := '0';
signal scan_ready   : std_logic;
signal scan_found   : std_logic;
signal scan_data    : std_logic_vector(INPUT_WIDTH-1 downto 0);
signal scan_mask    : std_logic_vector(INPUT_WIDTH-1 downto 0);

-- Reference FIFO.
signal ref_data     : input_word;
signal ref_valid    : std_logic;

-- High-level test control
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal test_table   : ref_array := initial_table;

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Generate input stream.
p_in : process(clk_100)
    variable seed1  : positive := 57105809;
    variable seed2  : positive := 85710857;
    variable rand   : real := 0.0;
    variable rvec   : input_word := (others => '0');
    variable tidx   : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Randomize flow control...
        uniform(seed1, seed2, rand);
        if (rand < test_rate) then
            -- Randomly select one of the table inputs.
            uniform(seed1, seed2, rand);
            tidx := integer(floor(rand * real(REF_COUNT)));
            -- If wildcard mode is enabled, generate a random offset.
            if (TCAM_MODE = TCAM_MODE_MAXLEN) then
                for n in rvec'range loop
                    uniform(seed1, seed2, rand);
                    rvec(n) := bool2bit(rand < 0.5);
                end loop;
                rvec := rvec and not test_table(tidx).keymask;
            else
                rvec := (others => '0');
            end if;
            -- Combine fixed and wildcard portions of address.
            in_data <= test_table(tidx).keyword or rvec;
            in_next <= '1';
        else
            in_data <= (others => '0');
            in_next <= '0';
        end if;
    end if;
end process;

-- Reference FIFO.
p_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => INPUT_WIDTH)
    port map(
    in_data     => in_data,
    in_write    => in_next,
    out_data    => ref_data,
    out_valid   => ref_valid,
    out_read    => out_next,
    clk         => clk_100,
    reset_p     => reset_p);

-- Unit under test.
uut : entity work.tcam_core
    generic map(
    INPUT_WIDTH => INPUT_WIDTH,
    TABLE_SIZE  => TABLE_SIZE,
    REPL_MODE   => REPL_MODE,
    TCAM_MODE   => TCAM_MODE)
    port map(
    in_data     => in_data,
    in_next     => in_next,
    out_index   => out_index,
    out_found   => out_found,
    out_next    => out_next,
    out_error   => out_error,
    cfg_suggest => cfg_index,
    cfg_index   => cfg_index,
    cfg_data    => cfg_data,
    cfg_plen    => cfg_plen,
    cfg_valid   => cfg_valid,
    cfg_ready   => cfg_ready,
    cfg_reject  => cfg_reject,
    scan_index  => scan_index,
    scan_valid  => scan_valid,
    scan_ready  => scan_ready,
    scan_found  => scan_found,
    scan_data   => scan_data,
    scan_mask   => scan_mask,
    clk         => clk_100,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk_100)
    variable tidx : integer := -1;
begin
    if rising_edge(clk_100) then
        -- None of our tests should raise errors.
        assert (out_error = '0')
            report TEST_LABEL & "Unexpected TCAM error." severity error;

        -- Cross-check each output index.
        if (out_next = '1' and ref_valid = '0') then
            report TEST_LABEL & "Reference FIFO desync." severity error;
        elsif (out_next = '1') then
            -- Attempt to find latest entry in reference table.
            tidx := INDEX_ERROR;
            for n in test_table'range loop
                if (test_table(n).keyword = (ref_data and test_table(n).keymask)) then
                    tidx := test_table(n).index;
                end if;
            end loop;
            -- Do we expect a match to this table entry?
            if (tidx = INDEX_ERROR) then
                -- Testbench error (every test address should be in the table).
                report TEST_LABEL & "Reference lookup error." severity error;
            elsif (tidx = INDEX_NOT_FOUND) then
                -- Address should not be in the TCAM's table.
                assert (out_found = '0')
                    report TEST_LABEL & "TCAM output: Unexpected match." severity error;
            elsif (tidx = INDEX_UNKNOWN) then
                -- Unknown state (e.g., address is in the middle of an update)
                null;
            else
                -- Address should be in the TCAM's table.
                assert (out_found = '1' and out_index = tidx)
                    report TEST_LABEL & "TCAM output: Index mismatch." severity error;
            end if;
        end if;
    end if;
end process;


-- High-level test control
p_test : process
    -- Load a single reference address into the UUT.
    procedure load_addr(
        ref_new : natural;                  -- REF index to write
        dupe_wr : std_logic := '0')         -- Is this a duplicate write?
    is
        variable ref_old : integer := -1;   -- REF index being overwritten
        variable idx_ovr : integer := -1;   -- UUT index being overwritten
        variable idx_wr  : integer := -1;   -- UUT index being written
        variable nowrite : std_logic := '0';
    begin
        -- Issue write command.
        wait until rising_edge(clk_100);
        cfg_valid   <= '1';
        cfg_data    <= test_table(ref_new).keyword;
        cfg_plen    <= test_table(ref_new).keylen;
        wait until rising_edge(clk_100);
        -- Note where we're writing the new entry.
        -- This should remain constant until we release VALID (write done)
        -- or UUT asserts REJECT strobe (write cancelled due to preexisting
        -- match at the new specified index).
        idx_ovr     := test_table(ref_new).index;
        idx_wr      := cfg_index;
        -- Are we overwriting something else?
        for n in test_table'range loop
            if (test_table(n).index = idx_wr) then
                ref_old := n;
            end if;
        end loop;
        -- Mark both old and new entries as indeterminate.
        test_table(ref_new).index <= INDEX_UNKNOWN;
        if (ref_old >= 0) then
            test_table(ref_old).index <= INDEX_UNKNOWN;
        end if;
        -- Wait for write to complete.
        while (cfg_ready = '0') loop
            wait until rising_edge(clk_100);
            assert (idx_wr = cfg_index or cfg_reject = '1')
                report TEST_LABEL & "Invalid change to cfg_index." severity error;
        end loop;
        cfg_valid <= '0';
        -- Should we have gotten a REJECT strobe?
        nowrite := cfg_reject;
        if (dupe_wr = '1') then 
            assert (cfg_reject = '1')
                report TEST_LABEL & "Missing REJECT strobe." severity error;
        else
            assert (cfg_reject = '0')
                report TEST_LABEL & "Unexpected REJECT strobe." severity error;
        end if;
        -- Wait a little longer...
        for n in 1 to 16 loop
            wait until rising_edge(clk_100);
        end loop;
        -- Finish updating reference table.
        if (ref_old < 0 and nowrite = '1') then
            test_table(ref_new).index <= idx_ovr;           -- Revert
        elsif (ref_old < 0) then
            test_table(ref_new).index <= idx_wr;            -- Written
        elsif (ref_old >= 0 and nowrite = '1') then
            test_table(ref_old).index <= idx_wr;            -- Restore
            test_table(ref_new).index <= idx_ovr;           -- Revert
        elsif (ref_old >= 0) then
            test_table(ref_old).index <= INDEX_NOT_FOUND;   -- Erased
            test_table(ref_new).index <= idx_wr;            -- Written
        end if;
    end procedure;

    -- Read a single address through the SCAN port.
    procedure read_addr(tbl_idx : natural) is
        variable ref_idx : integer := INDEX_NOT_FOUND;
    begin
        -- Is there a reference entry written in this slot?
        for n in test_table'range loop
            if (test_table(n).index = tbl_idx) then
                ref_idx := n;
            end if;
        end loop;
        -- Issue the scan command.
        wait until rising_edge(clk_100);
        scan_index  <= tbl_idx;
        scan_valid  <= '1';
        -- Wait for command to complete...
        wait until rising_edge(clk_100);
        while (scan_ready = '0') loop
            wait until rising_edge(clk_100);
        end loop;
        -- Confirm results match the corresponding reference, if any.
        if (ref_idx = INDEX_NOT_FOUND) then
            assert (scan_found = '0')
                report "Read: Expected empty table entry." severity error;
        elsif (scan_found = '0') then
            report "Read: Missing table entry." severity error;
        else
            assert (scan_data = test_table(ref_idx).keyword and
                    scan_mask = test_table(ref_idx).keymask)
                report "Read: Mismatched table entry #" & integer'image(ref_idx) severity error;
        end if;
        -- End of scan command.
        scan_valid  <= '0';
        wait until rising_edge(clk_100);
    end procedure;

    -- Read the entire table through the SCAN port.
    procedure read_table is
    begin
        for n in 0 to TABLE_SIZE-1 loop
            read_addr(n);
        end loop;
    end procedure;

    -- Start-of-test setup.
    procedure test_start(rr: real; lbl: string) is
    begin
        report TEST_LABEL & "Test #" & integer'image(test_index + 1) & ": " & lbl;
        test_index  <= test_index + 1;
        test_rate   <= rr;
    end procedure;
begin
    test_done <= '0';
    wait until (reset_p = '0');
    wait for 1 us;

    -- Run for a while with an empty table.
    test_start(0.5, "Empty table");
    read_table;
    wait for 20 us;

    -- Load TCAM table, one address at a time.
    test_start(0.5, "Loading");
    for n in 0 to TABLE_SIZE-1 loop
        load_addr(n);
        wait for 10 us;
    end loop;
    read_table;
    wait for 100 us;

    -- If CONFIRM mode is enabled, attempt to reload an entry.
    if (TCAM_MODE = TCAM_MODE_CONFIRM) then
        test_start(0.5, "Duplicate");
        load_addr(0, '1');
        wait for 50 us;
        load_addr(1, '1');
        wait for 50 us;
    end if;
    read_table;

    -- If overwrite is enabled, overwrite a few entries.
    if (REPL_MODE /= TCAM_REPL_NONE) then
        test_start(0.5, "Overwrite");
        for n in TABLE_SIZE to 2*TABLE_SIZE-1 loop
            load_addr(n);
            wait for 10 us;
        end loop;
        wait for 100 us;
    end if;
    read_table;

    -- Keep running the test at different rates.
    test_start(0.1, "Rate-0.1");
    wait for 200 us;

    test_start(0.9, "Rate-0.9");
    wait for 200 us;

    report TEST_LABEL & "Sub-test finished.";
    test_done <= '1';
    wait;
end process;

end helper;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.tcam_constants.all;

entity tcam_core_tb is
    -- Testbench, no I/O ports
end tcam_core_tb;

architecture tb of tcam_core_tb is

signal test_done : std_logic_vector(3 downto 0) := (others => '1');

begin

-- Simple-write test case.
uut0 : entity work.tcam_core_tb_helper
    generic map(
    TEST_LABEL  => "SIMPLE: ",
    INPUT_WIDTH => 12,
    TABLE_SIZE  => 4,
    REPL_MODE   => TCAM_REPL_NONE,
    TCAM_MODE   => TCAM_MODE_SIMPLE)
    port map(
    test_done   => test_done(0));

-- Typical configuration for MAC-address lookup.
uut1 : entity work.tcam_core_tb_helper
    generic map(
    TEST_LABEL  => "CONFIRM: ",
    INPUT_WIDTH => 48,
    TABLE_SIZE  => 8,
    REPL_MODE   => TCAM_REPL_NRU2,
    TCAM_MODE   => TCAM_MODE_CONFIRM)
    port map(
    test_done   => test_done(1));

-- Typical configuration for ARP-cacheing.
uut2 : entity work.tcam_core_tb_helper
    generic map(
    TEST_LABEL  => "ARPCACHE: ",
    INPUT_WIDTH => 32,
    TABLE_SIZE  => 8,
    REPL_MODE   => TCAM_REPL_PLRU,
    TCAM_MODE   => TCAM_MODE_CONFIRM)
    port map(
    test_done   => test_done(2));

-- Typical configuration for IP-routing tables.
uut3 : entity work.tcam_core_tb_helper
    generic map(
    TEST_LABEL  => "IPROUTER: ",
    INPUT_WIDTH => 32,
    TABLE_SIZE  => 7,
    REPL_MODE   => TCAM_REPL_WRAP,
    TCAM_MODE   => TCAM_MODE_MAXLEN)
    port map(
    test_done   => test_done(3));

-- Print the overall "done" message.
p_done : process
begin
    wait until (and_reduce(test_done) = '1');
    report "All tests completed!";
    wait;
end process;

end tb;
