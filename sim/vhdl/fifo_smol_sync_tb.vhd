--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Smol FIFO Testbench
--
-- This unit test covers both nominal and off-nominal conditions
-- for the Smol FIFO.  In both cases, the input and output flow
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

entity fifo_smol_sync_tb_helper is
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
end fifo_smol_sync_tb_helper;

architecture helper of fifo_smol_sync_tb_helper is

-- Input stream generation and flow randomization.
signal in_data      : unsigned(IO_WIDTH-1 downto 0) := (others => '0');
signal in_write_tmp : std_logic := '0';
signal in_write     : std_logic := '0';
signal out_read_tmp : std_logic := '0';
signal out_read     : std_logic := '0';

-- Reference status signals.
signal ref_data     : unsigned(IO_WIDTH-1 downto 0) := (others => '0');
signal ref_full     : std_logic := '0';
signal ref_empty    : std_logic := '1';
signal ref_hfull    : std_logic := '0';
signal ref_hempty   : std_logic := '1';
signal ref_error    : std_logic := '0';

-- Outputs from unit under test.
signal out_data     : std_logic_vector(IO_WIDTH-1 downto 0);
signal out_valid    : std_logic;
signal fifo_full    : std_logic;
signal fifo_empty   : std_logic;
signal fifo_hfull   : std_logic;
signal fifo_hempty  : std_logic;
signal fifo_error   : std_logic;

begin

-- Input stream generation and flow randomization.
p_gen : process(clk)
    variable seed1   : positive := 1234;
    variable seed2   : positive := 5678;
    variable rand    : real;
begin
    if rising_edge(clk) then
        -- Update the input counter after each valid write.
        if (reset_p = '1') then
            in_data <= (others => '0');
        elsif (in_write = '1' and (out_read = '1' or fifo_full = '0')) then
            in_data <= in_data + 1;
        end if;

        -- Input flow randomization.
        uniform(seed1, seed2, rand);
        in_write_tmp <= bool2bit(rand < rate_in);

        -- Output flow randomization.
        uniform(seed1, seed2, rand);
        out_read_tmp <= bool2bit(rand < rate_out);
    end if;
end process;

in_write <= in_write_tmp when (flow_nom = '0') else
            in_write_tmp and not fifo_full;
out_read <= out_read_tmp when (flow_nom = '0') else
            out_read_tmp and not fifo_empty;

-- Reference status signals.
p_ref : process(clk)
    constant WORD_MAX   : integer := 2**DEPTH_LOG2;
    constant WORD_HALF  : integer := WORD_MAX / 2;
    variable word_ct    : integer range 0 to WORD_MAX := 0;
begin
    if rising_edge(clk) then
        -- Update the reference counter after each valid read.
        if (reset_p = '1') then
            ref_data <= (others => '0');
        elsif (out_valid = '1' and out_read = '1') then
            ref_data <= ref_data + 1;
        end if;

        -- Detect overflow/underflow conditions.
        if (flow_nom = '1') then
            ref_error <= '0';   -- No errors in nominal mode
        elsif (in_write = '1' and out_read = '0' and fifo_full = '1') then
            ref_error <= '1';   -- Expect overflow
        elsif (out_read = '1' and out_valid = '0') then
            ref_error <= '1';   -- Expect underflow
        else
            ref_error <= '0';   -- No error expected
        end if;

        -- Update the stored word count.
        if (reset_p = '1') then
            word_ct := 0;
        else
            if (out_read = '1' and word_ct > 0) then
                word_ct := word_ct - 1;
            end if;
            if (in_write = '1' and word_ct < WORD_MAX) then
                word_ct := word_ct + 1;
            end if;
        end if;

        -- Use updated word count to drive reference status signals.
        ref_full    <= bool2bit(word_ct >= WORD_MAX);
        ref_hempty  <= bool2bit(word_ct <= WORD_HALF);
        ref_hfull   <= bool2bit(word_ct > WORD_HALF);
        ref_empty   <= bool2bit(word_ct = 0);
    end if;
end process;

-- Unit under test.
uut : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => IO_WIDTH,
    DEPTH_LOG2  => DEPTH_LOG2,
    ERROR_UNDER => true,    -- Treat underflow as error
    ERROR_OVER  => true,    -- Treat overflow as error
    ERROR_PRINT => false)   -- Suppress warning messages
    port map(
    in_data     => std_logic_vector(in_data),
    in_write    => in_write,
    out_data    => out_data,
    out_valid   => out_valid,
    out_read    => out_read,
    fifo_full   => fifo_full,
    fifo_empty  => fifo_empty,
    fifo_hfull  => fifo_hfull,
    fifo_hempty => fifo_hempty,
    fifo_error  => fifo_error,
    clk         => clk,
    reset_p     => reset_p);

-- Output checking.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '0' and out_valid = '1' and out_read = '1') then
            assert (out_data = std_logic_vector(ref_data))
                report "out_data mismatch" severity error;
        end if;

        assert (fifo_full = ref_full)
            report "fifo_full mismatch" severity error;
        assert (fifo_empty = ref_empty)
            report "fifo_empty mismatch" severity error;
        assert (fifo_hfull = ref_hfull)
            report "fifo_hfull mismatch" severity error;
        assert (fifo_hempty = ref_hempty)
            report "fifo_hempty mismatch" severity error;
        assert (fifo_error = ref_error)
            report "fifo_error mismatch" severity error;

        if (reset_p = '1') then
            test_ok <= '1';
        elsif (out_valid = '1' and out_read = '1' and
               out_data /= std_logic_vector(ref_data)) then
            test_ok <= '0';
        elsif (fifo_full /= ref_full or
               fifo_empty /= ref_empty or
               fifo_hfull /= ref_hfull or
               fifo_hempty /= ref_hempty or
               fifo_error /= ref_error) then
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

entity fifo_smol_sync_tb is
    -- Testbench --> No I/O ports
end fifo_smol_sync_tb;

architecture tb of fifo_smol_sync_tb is

component fifo_smol_sync_tb_helper is
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
test0 : fifo_smol_sync_tb_helper
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

test1 : fifo_smol_sync_tb_helper
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

test2 : fifo_smol_sync_tb_helper
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

test3 : fifo_smol_sync_tb_helper
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
