--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- LUTRAM-based asynchronous FIFO Testbench
--
-- This unit test covers a variety of random flow-control conditions
-- for the LUTRAM FIFO.  Tests are run in parallel for various
-- sizing parameters and relative clock frequencies.
--
-- The complete test takes just under 5.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity fifo_smol_async_tb_helper is
    generic (
    IO_WIDTH    : integer;          -- Word size
    META_WIDTH  : integer;          -- Word size
    DEPTH_LOG2  : integer);         -- FIFO depth = 2^N
    port (
    in_clk      : in  std_logic;    -- Write clock
    out_clk     : in  std_logic;    -- Read clock
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real;         -- Output rate (0-100%)
    reset_p     : in  std_logic);   -- System reset
end fifo_smol_async_tb_helper;

architecture helper of fifo_smol_async_tb_helper is

subtype data_word is std_logic_vector(IO_WIDTH-1 downto 0);
subtype meta_word is std_logic_vector(META_WIDTH-1 downto 0);

-- Initial state for syncrhonized PRNGs.
constant SYNC_SEED1 : positive := 5871057;
constant SYNC_SEED2 : positive := 9130151;

-- Input stream
signal in_data      : data_word := (others => '0');
signal in_meta      : meta_word := (others => '0');
signal in_last      : std_logic := '0';
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal in_early     : std_logic;
signal in_early_d   : std_logic := '0';

-- Reference stream
signal ref_data     : data_word := (others => '0');
signal ref_meta     : meta_word := (others => '0');
signal ref_last     : std_logic := '0';

-- Output stream
signal out_data     : data_word;
signal out_meta     : meta_word;
signal out_last     : std_logic;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';

begin

-- Input stream generation and flow randomization.
p_in : process(in_clk)
    variable seedi1, seedf1 : positive := 12345;
    variable seedi2, seedf2 : positive := 67890;
    variable rand : real;
begin
    if rising_edge(in_clk) then
        -- Reset state for the synchronized PRNG.
        if (reset_p = '1') then
            seedi1 := SYNC_SEED1;
            seedi2 := SYNC_SEED2;
        end if;

        -- Flow-control randomization for input:
        uniform(seedf1, seedf2, rand);
        if (reset_p = '1') then
            -- Stream reset.
            in_data  <= (others => '0');
            in_meta  <= (others => '0');
            in_last  <= '0';
            in_valid <= '0';
        elsif ((rand < rate_in) and (in_valid = '0' or in_ready = '1')) then
            -- Generate next input (data, meta, last).
            for n in IO_WIDTH-1 downto 0 loop
                uniform(seedi1, seedi2, rand);
                in_data(n) <= bool2bit(rand < 0.5);
            end loop;
            for n in META_WIDTH-1 downto 0 loop
                uniform(seedi1, seedi2, rand);
                in_meta(n) <= bool2bit(rand < 0.5);
            end loop;
            uniform(seedi1, seedi2, rand);
            in_last  <= bool2bit(rand < 0.1);
            in_valid <= '1';
        elsif (in_ready = '1') then
            -- Previous word consumed, no replacement yet.
            in_valid <= '0';
        end if;

        -- Safety check on the "early" indicator.
        assert (in_early_d = '0' or in_ready = '1')
            report "EARLY violation" severity error;
        in_early_d <= in_early;
    end if;
end process;

-- Reference stream generation and output flow randomization.
p_out : process(out_clk)
    variable seedr1, seedf1 : positive := 43210;
    variable seedr2, seedf2 : positive := 98765;
    variable rand : real;
begin
    if rising_edge(out_clk) then
        -- Reset state for each synchronized PRNG.
        if (reset_p = '1') then
            seedr1 := SYNC_SEED1;
            seedr2 := SYNC_SEED2;
        end if;

        -- Generate next refrence on demand.
        if ((reset_p = '1') or (out_valid = '1' and out_ready = '1')) then
            for n in IO_WIDTH-1 downto 0 loop
                uniform(seedr1, seedr2, rand);
                ref_data(n) <= bool2bit(rand < 0.5);
            end loop;
            for n in META_WIDTH-1 downto 0 loop
                uniform(seedr1, seedr2, rand);
                ref_meta(n) <= bool2bit(rand < 0.5);
            end loop;
            uniform(seedr1, seedr2, rand);
            ref_last <= bool2bit(rand < 0.1);
        end if;

        -- Flow-control randomization for output.
        uniform(seedf1, seedf2, rand);
        out_ready <= bool2bit(rand < rate_out);
    end if;
end process;

-- Unit under test.
uut : entity work.fifo_smol_async
    generic map(
    IO_WIDTH    => IO_WIDTH,
    META_WIDTH  => META_WIDTH,
    DEPTH_LOG2  => DEPTH_LOG2)
    port map(
    in_clk      => in_clk,
    in_data     => in_data,
    in_meta     => in_meta,
    in_last     => in_last,
    in_valid    => in_valid,
    in_ready    => in_ready,
    in_early    => in_early,
    out_clk     => out_clk,
    out_data    => out_data,
    out_meta    => out_meta,
    out_last    => out_last,
    out_valid   => out_valid,
    out_ready   => out_ready,
    reset_p     => reset_p);

-- Output checking.
p_check : process(out_clk)
begin
    if rising_edge(out_clk) then
        if (out_valid = '1') then
            assert (out_data = ref_data)
                report "out_data mismatch" severity error;
            assert (out_meta = ref_meta)
                report "out_meta mismatch" severity error;
            assert (out_last = ref_last)
                report "out_last mismatch" severity error;
        end if;
    end if;
end process;

end helper;


--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;

entity fifo_smol_async_tb is
    -- Testbench --> No I/O ports
end fifo_smol_async_tb;

architecture tb of fifo_smol_async_tb is

component fifo_smol_async_tb_helper is
    generic (
    IO_WIDTH    : integer;          -- Word size
    META_WIDTH  : integer;          -- Word size
    DEPTH_LOG2  : integer);         -- FIFO depth = 2^N
    port (
    in_clk      : in  std_logic;    -- Write clock
    out_clk     : in  std_logic;    -- Read clock
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real;         -- Output rate (0-100%)
    reset_p     : in  std_logic);   -- System reset
end component;

signal clk7         : std_logic := '0';
signal clk94        : std_logic := '0';
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';
signal flow_nom     : std_logic := '0';
signal rate_in      : real := 0.0;
signal rate_out     : real := 0.0;

begin

-- Clock generation
clk7    <= not clk7 after 71.4 ns;  -- 1 / (2*71.4 ns) = 7.0 MHz
clk94   <= not clk94 after 5.3 ns;  -- 1 / (2*5.3 ns) = 94.3 MHz
clk100  <= not clk100 after 5.0 ns; -- 1 / (2*5.0 ns) = 100.0 MHz

-- Overall test control
p_test : process
begin
    -- Reset strobe before we start.
    reset_p     <= '1';
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

    report "All tests completed.";
    wait;
end process;

-- Instantiate test units in various configurations.
test0 : fifo_smol_async_tb_helper
    generic map(
    IO_WIDTH    => 8,
    META_WIDTH  => 0,
    DEPTH_LOG2  => 4)
    port map(
    in_clk       => clk100,
    out_clk     => clk100,
    rate_in     => rate_in,
    rate_out    => rate_out,
    reset_p     => reset_p);

test1 : fifo_smol_async_tb_helper
    generic map(
    IO_WIDTH    => 1,
    META_WIDTH  => 7,
    DEPTH_LOG2  => 5)
    port map(
    in_clk      => clk100,
    out_clk     => clk94,
    rate_in     => rate_in,
    rate_out    => rate_out,
    reset_p     => reset_p);

test2 : fifo_smol_async_tb_helper
    generic map(
    IO_WIDTH    => 7,
    META_WIDTH  => 1,
    DEPTH_LOG2  => 5)
    port map(
    in_clk      => clk94,
    out_clk     => clk100,
    rate_in     => rate_in,
    rate_out    => rate_out,
    reset_p     => reset_p);

test3 : fifo_smol_async_tb_helper
    generic map(
    IO_WIDTH    => 8,
    META_WIDTH  => 0,
    DEPTH_LOG2  => 6)
    port map(
    in_clk      => clk100,
    out_clk     => clk7,
    rate_in     => rate_in,
    rate_out    => rate_out,
    reset_p     => reset_p);

test4 : fifo_smol_async_tb_helper
    generic map(
    IO_WIDTH    => 8,
    META_WIDTH  => 0,
    DEPTH_LOG2  => 7)
    port map(
    in_clk      => clk7,
    out_clk     => clk100,
    rate_in     => rate_in,
    rate_out    => rate_out,
    reset_p     => reset_p);

end tb;
