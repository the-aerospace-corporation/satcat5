--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- BRAM FIFO Testbench
--
-- This unit test covers both nominal and off-nominal conditions
-- for the BRAM FIFO.  In both cases, the input and output flow
-- control is randomized.  Tests are run in parallel for various
-- generic configurations.
--
-- The complete test takes just under 10.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity fifo_large_sync_tb_helper is
    generic (
    IO_WIDTH    : integer;          -- Word size
    DEPTH_LOG2  : integer);         -- FIFO depth = 2^N
    port (
    clk         : in  std_logic;    -- Common clock
    reset_p     : in  std_logic;    -- Reset between trials
    flow_nom    : in  std_logic;    -- Flow-control mode
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real;         -- Output rate (0-100%)
    test_ok     : out std_logic);
end fifo_large_sync_tb_helper;

architecture helper of fifo_large_sync_tb_helper is

constant FIFO_DEPTH : integer := 2**DEPTH_LOG2;

-- Input stream generation and flow randomization.
signal in_data      : unsigned(IO_WIDTH-1 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal out_read_tmp : std_logic := '0';
signal out_ready    : std_logic := '0';

-- Reference status signals.
signal ref_data     : unsigned(IO_WIDTH-1 downto 0) := (others => '0');
signal ref_last     : std_logic := '0';
signal ref_full     : std_logic := '0';

-- Outputs from unit under test.
signal in_error     : std_logic;
signal out_data     : std_logic_vector(IO_WIDTH-1 downto 0);
signal out_last     : std_logic;
signal out_valid    : std_logic;

begin

-- Input stream generation and flow randomization.
p_gen : process(clk)
    variable seed1   : positive := 1234;
    variable seed2   : positive := 5678;
    variable rand    : real;
    variable word_ct : integer range 0 to FIFO_DEPTH := 0;
begin
    if rising_edge(clk) then
        -- Input stream is a simple counter; update after each write.
        if (reset_p = '1') then
            in_data <= (others => '0');
            in_last <= '0';
        elsif (in_write = '1') then
            in_data <= in_data + 1;
            in_last <= bool2bit(to_integer(in_data+1) mod 7 = 0);
        end if;

        -- Count the number of words currently residing in FIFO.
        if (reset_p = '1') then
            word_ct := 0;
        elsif (in_write = '1' and (out_valid = '0' or out_ready = '0')) then
            word_ct := word_ct + 1;
        elsif (in_write = '0' and out_valid = '1' and out_ready = '1') then
            word_ct := word_ct - 1;
        end if;
        ref_full <= bool2bit(word_ct = FIFO_DEPTH);

        -- Input flow randomization.
        uniform(seed1, seed2, rand);
        in_write <= bool2bit(rand < rate_in and word_ct < FIFO_DEPTH);

        -- Output flow randomization.
        uniform(seed1, seed2, rand);
        out_read_tmp <= bool2bit(rand < rate_out);
    end if;
end process;

out_ready <= out_read_tmp and (out_valid or not flow_nom);

-- Reference status signals.
p_ref : process(clk)
begin
    if rising_edge(clk) then
        -- Update the reference counter after each valid read.
        if (reset_p = '1') then
            ref_data <= (others => '0');
            ref_last <= '0';
        elsif (out_valid = '1' and out_ready = '1') then
            ref_data <= ref_data + 1;
            ref_last <= bool2bit(to_integer(ref_data+1) mod 7 = 0);
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => IO_WIDTH,
    FIFO_DEPTH  => FIFO_DEPTH,
    SIMTEST     => true)
    port map(
    in_data     => std_logic_vector(in_data),
    in_last     => in_last,
    in_write    => in_write,
    in_error    => in_error,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '0' and out_valid = '1' and out_ready = '1') then
            assert (out_data = std_logic_vector(ref_data))
                report "out_data mismatch" severity error;
            assert (out_last = ref_last)
                report "out_last mismatch" severity error;
        end if;

        if (reset_p = '1') then
            test_ok <= '1';
        elsif (out_valid = '1' and out_data /= std_logic_vector(ref_data)) then
            test_ok <= '0';
        elsif (in_error = '1') then
            test_ok <= '0';
        end if;
    end if;
end process;

end helper;


--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_large_sync_tb is
    -- Testbench --> No I/O ports
end fifo_large_sync_tb;

architecture tb of fifo_large_sync_tb is

component fifo_large_sync_tb_helper is
    generic (
    IO_WIDTH    : integer;          -- Word size
    DEPTH_LOG2  : integer);         -- FIFO depth = 2^N
    port (
    clk         : in  std_logic;    -- Common clock
    reset_p     : in  std_logic;    -- Reset between trials
    flow_nom    : in  std_logic;    -- Nominal flow control mode?
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real;         -- Output rate (0-100%)
    test_ok     : out std_logic);
end component;

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal flow_nom     : std_logic := '0';
signal rate_in      : real := 0.0;
signal rate_out     : real := 0.0;
signal test_ok      : std_logic_vector(0 to 3);

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Overall test control
p_test : process
    procedure run_seq(mode : std_logic) is
    begin
        -- Reset strobe before we start.
        reset_p     <= '1';
        flow_nom    <= mode;
        rate_in     <= 0.0;
        rate_out    <= 0.0;
        wait for 1 us;
        reset_p     <= '0';

        -- Run in various flow-control conditions.
        report "Starting sequence (0.1/0.9)" severity note;
        for n in 1 to 99 loop
            rate_in <= 0.9; rate_out <= 0.1; wait for 10 us;
            rate_in <= 0.1; rate_out <= 0.9; wait for 10 us;
        end loop;

        report "Starting sequence (0.4/0.6)" severity note;
        for n in 1 to 10 loop
            rate_in <= 0.6; rate_out <= 0.4; wait for 100 us;
            rate_in <= 0.5; rate_out <= 0.5; wait for 100 us;
            rate_in <= 0.4; rate_out <= 0.6; wait for 100 us;
        end loop;
    end procedure;
begin
    run_seq('0');
    run_seq('1');
    report "All tests completed.";
    wait;
end process;

-- Instantiate test units in various configurations.
test0 : fifo_large_sync_tb_helper
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => 3)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flow_nom    => flow_nom,
    rate_in     => rate_in,
    rate_out    => rate_out,
    test_ok     => test_ok(0));

test1 : fifo_large_sync_tb_helper
    generic map(
    IO_WIDTH    => 12,
    DEPTH_LOG2  => 4)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flow_nom    => flow_nom,
    rate_in     => rate_in,
    rate_out    => rate_out,
    test_ok     => test_ok(1));

test2 : fifo_large_sync_tb_helper
    generic map(
    IO_WIDTH    => 11,
    DEPTH_LOG2  => 5)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flow_nom    => flow_nom,
    rate_in     => rate_in,
    rate_out    => rate_out,
    test_ok     => test_ok(2));

test3 : fifo_large_sync_tb_helper
    generic map(
    IO_WIDTH    => 9,
    DEPTH_LOG2  => 6)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flow_nom    => flow_nom,
    rate_in     => rate_in,
    rate_out    => rate_out,
    test_ok     => test_ok(3));

end tb;
