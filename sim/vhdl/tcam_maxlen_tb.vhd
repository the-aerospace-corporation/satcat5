--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- Testbench for TCAM Max-length prefix (MLP) helper module
--
-- This is a unit test for the MLP block, which confirms that the
-- correct input is selected under a variety of search conditions,
-- and that error-detection works as expected.
--
-- The complete test takes less than 6.1 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity tcam_maxlen_tb is
    generic (TABLE_SIZE : positive := 7);
    -- Testbench, no I/O ports
end tcam_maxlen_tb;

architecture tb of tcam_maxlen_tb is

-- Ensure we can always have unique table entries.
constant INPUT_WIDTH : positive := TABLE_SIZE + 1;

-- System clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream and delayed copy
signal in_mask      : std_logic_vector(TABLE_SIZE-1 downto 0) := (others => '0');
signal in_type      : std_logic := '0';
signal in_rdy       : std_logic := '0';
signal in_write     : std_logic;
signal dly_mask     : std_logic_vector(TABLE_SIZE-1 downto 0);
signal dly_type     : std_logic;
signal dly_rdy      : std_logic;
signal dly_read     : std_logic;

-- Reference stream (combinational logic)
signal ref_index    : integer range 0 to TABLE_SIZE-1;
signal ref_found    : std_logic;
signal ref_error    : std_logic;
signal ref_type     : std_logic;
signal ref_rdy      : std_logic;

-- Output stream from unit under test
signal out_index    : integer range 0 to TABLE_SIZE-1;
signal out_found    : std_logic;
signal out_type     : std_logic;
signal out_rdy      : std_logic;
signal out_error    : std_logic;

-- Configuration interface
type cfg_table_t is array(TABLE_SIZE-1 downto 0) of positive;
signal cfg_index    : integer range 0 to TABLE_SIZE-1 := 0;
signal cfg_plen     : integer range 1 to INPUT_WIDTH := INPUT_WIDTH;
signal cfg_write    : std_logic := '0';
signal cfg_table    : cfg_table_t := (others => INPUT_WIDTH);

-- High-level test control
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;

begin

-- System clock and reset.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Input stream and delayed copy
p_in : process(clk_100)
    constant PMASK : real := 1.0 / real(TABLE_SIZE);
    variable seed1 : positive := 58710587;
    variable seed2 : positive := 87510471;
    variable rand  : real := 0.0;
begin
    if rising_edge(clk_100) then
        uniform(seed1, seed2, rand);
        if (rand < test_rate) then
            -- Randomize test vector.
            for n in in_mask'range loop
                uniform(seed1, seed2, rand);
                in_mask(n) <= bool2bit(rand < PMASK);
            end loop;
            uniform(seed1, seed2, rand);
            in_type <= bool2bit(rand < 0.5);
            uniform(seed1, seed2, rand);
            in_rdy  <= bool2bit(rand < 0.5);
        else
            in_mask <= (others => '0');
            in_type <= '0';
            in_rdy  <= '0';
        end if;
    end if;
end process;

in_write <= in_rdy or in_type;
dly_read <= out_rdy or out_type;

u_dly : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => TABLE_SIZE,
    META_WIDTH  => 2)
    port map(
    in_data     => in_mask,
    in_meta(0)  => in_type,
    in_meta(1)  => in_rdy,
    in_write    => in_write,
    out_data    => dly_mask,
    out_meta(0) => dly_type,
    out_meta(1) => dly_rdy,
    out_valid   => open,
    out_read    => dly_read,
    clk         => clk_100,
    reset_p     => reset_p);

-- Reference stream (combinational logic)
ref_found   <= or_reduce(dly_mask);
ref_type    <= dly_type;
ref_rdy     <= dly_rdy;

p_ref : process(dly_mask)
    variable max_idx, max_len : integer := 0;
    variable max_dup : std_logic := '0';
begin
    -- Scan over matching entries...
    max_idx := 0;
    max_len := 0;
    max_dup := '0';
    for n in dly_mask'range loop
        if (dly_mask(n) = '0') then
            null;           -- Input disabled
        elsif (cfg_table(n) > max_len) then
            max_idx := n;   -- New running max
            max_len := cfg_table(n);
        elsif (cfg_table(n) = max_len) then
            max_dup := '1'; -- Duplicate found
        end if;
    end loop;

    -- Drive output based on maximum.
    ref_index   <= max_idx;
    ref_error   <= max_dup;
end process;

-- Unit under test
uut : entity work.tcam_maxlen
    generic map(
    INPUT_WIDTH => INPUT_WIDTH,
    META_WIDTH  => 8,           -- Don't-care
    TABLE_SIZE  => TABLE_SIZE)
    port map(
    in_data     => (others => '0'),
    in_meta     => (others => '0'),
    in_mask     => in_mask,
    in_type     => in_type,
    in_rdy      => in_rdy,
    out_data    => open,        -- Not tested
    out_meta    => open,        -- Not tested
    out_index   => out_index,
    out_found   => out_found,
    out_type    => out_type,
    out_rdy     => out_rdy,
    out_error   => out_error,
    cfg_index   => cfg_index,
    cfg_plen    => cfg_plen,
    cfg_write   => cfg_write,
    clk         => clk_100,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_rdy = '0' and out_type = '0') then
            -- No output this cycle.
            null;
        elsif (ref_error = '1') then
            -- In error case, all other outputs are don't-care.
            assert (out_error = '1')
                report "Missing out_error" severity error;
        else
            -- Nominal case checks all output signals.
            assert (out_index = ref_index)
                report "Output mismatch (index)" severity error;
            assert (out_found = ref_found)
                report "Output mismatch (found)" severity error;
            assert (out_type = ref_type)
                report "Output mismatch (type)" severity error;
            assert (out_rdy = ref_rdy)
                report "Output mismatch (rdy)" severity error;
            assert (out_index = ref_index)
                report "Output mismatch (index)" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Generate a randomly shuffled configuration table.
    variable seed1 : positive := 18715890;
    variable seed2 : positive := 51075809;
    impure function shuffle return cfg_table_t is
        variable rand : real := 0.0;
        variable idx1, idx2, tmp : integer := 0;
        variable tbl : cfg_table_t := (others => INPUT_WIDTH);
    begin
        -- Initialize table with unique numbers.
        for n in tbl'range loop
            tbl(n) := n+1;
        end loop;
        -- Randomly swap a large number of times.
        for n in 0 to 2*TABLE_SIZE loop
            -- Select two random indices.
            uniform(seed1, seed2, rand);
            idx1 := integer(floor(rand * real(TABLE_SIZE)));
            uniform(seed1, seed2, rand);
            idx2 := integer(floor(rand * real(TABLE_SIZE)));
            -- Swap those two values.
            tmp       := tbl(idx1);
            tbl(idx1) := tbl(idx2);
            tbl(idx2) := tmp;
        end loop;
        -- Return the shuffled result.
        return tbl;
    end function;

    -- Run a test sequence.
    procedure run_one(rr : real) is
    begin
        -- Announce test start.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        test_rate   <= 0.0; -- Pause for now

        -- Load configuration table.
        for n in cfg_table'range loop
            wait until rising_edge(clk_100);
            cfg_write   <= '1';
            cfg_index   <= n;
            cfg_plen    <= cfg_table(n);
            wait until rising_edge(clk_100);
            cfg_write   <= '0';
        end loop;

        -- Let data flow through for a while.
        test_rate   <= rr;
        wait for 1 ms;
        test_rate   <= 0.0;
        wait for 1 us;
    end procedure;
begin
    wait until (reset_p = '0');

    -- Load a basic configuration.
    cfg_table <= shuffle;
    run_one(0.1);

    -- Load a configuration with table collisions.
    cfg_table <= (others => 1);
    run_one(0.1);

    -- Run a few more at different flow-control rates.
    cfg_table <= shuffle;
    run_one(0.3);
    cfg_table <= shuffle;
    run_one(0.6);
    cfg_table <= shuffle;
    run_one(0.9);
    cfg_table <= shuffle;
    run_one(1.0);

    report "All tests completed!";
    wait;
end process;

end tb;
