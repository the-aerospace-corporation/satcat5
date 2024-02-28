--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for LFSR generator and synchronizer blocks
--
-- This testbench instantiates a Leap-LFSR generator (prng_lfsr_gen),
-- confirms that its output matches the expected LFSR sequence, and
-- connects its output to another block (prng_lfsr_sync) that syncs
-- to the pseudorandom stream and operates in lockstep.
--
-- The complete test takes 0.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.prng_lfsr_common.all;
use     work.router_sim_tools.all;

entity prng_lfsr_tb_helper is
    -- Helper block instantiates a specific test configuration.
    generic (
    IO_WIDTH    : positive;
    LFSR_SPEC   : lfsr_spec_t;
    MSB_FIRST   : boolean);
end prng_lfsr_tb_helper;

architecture tb of prng_lfsr_tb_helper is

subtype io_word is std_logic_vector(IO_WIDTH-1 downto 0);
subtype lfsr_word is std_logic_vector(LFSR_SPEC.order-1 downto 0);

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- PRBS generator.
signal gen_data     : io_word;
signal gen_valid    : std_logic;
signal gen_ready    : std_logic := '0';
signal gen_write    : std_logic;

-- PRBS synchronizer.
signal sync_local   : io_word;
signal sync_rcvd    : io_word;
signal sync_write   : std_logic;
signal sync_reset   : std_logic;

-- High-level test control.
signal test_count   : integer := 0;
signal test_cycle   : integer := 0;
signal test_rate    : real := 0.0;
signal test_reset   : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- PRBS generator.
uut_gen : entity work.prng_lfsr_gen
    generic map(
    IO_WIDTH    => IO_WIDTH,
    LFSR_SPEC   => LFSR_SPEC,
    MSB_FIRST   => MSB_FIRST)
    port map(
    out_data    => gen_data,
    out_valid   => gen_valid,
    out_ready   => gen_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Flow-control randomization.
gen_write <= gen_valid and gen_ready;

p_flow : process(clk_100)
begin
    if rising_edge(clk_100) then
        gen_ready <= rand_bit(test_rate);
    end if;
end process;

-- PRBS synchronizer.
sync_reset <= reset_p or test_reset;

uut_sync : entity work.prng_lfsr_sync
    generic map(
    IO_WIDTH    => IO_WIDTH,
    LFSR_SPEC   => LFSR_SPEC,
    MSB_FIRST   => MSB_FIRST)
    port map(
    in_rcvd     => gen_data,
    in_write    => gen_write,
    out_local   => sync_local,
    out_rcvd    => sync_rcvd,
    out_write   => sync_write,
    clk         => clk_100,
    reset_p     => sync_reset);

-- High-level test control.
p_check : process(clk_100)
    variable state : lfsr_word := (others => '1');
    variable dref  : io_word := (others => '0');
    variable bidx  : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Rate-control is randomized after each test segment.
        if (reset_p = '1') then
            test_rate <= 1.0;
        elsif (sync_reset = '1') then
            test_rate <= 0.1 + rand_float(0.9);
        end if;

        -- Inspect outputs of the PRBS generator.
        if (reset_p = '1') then
            state := (others => '1');
        elsif (gen_write = '1') then
            -- Generate output and update LFSR state, one bit at a time.
            for tidx in 0 to IO_WIDTH-1 loop
                if MSB_FIRST then
                    bidx := IO_WIDTH - 1 - tidx;
                else
                    bidx := tidx;
                end if;
                dref(bidx) := state(state'left) xor LFSR_SPEC.inv;
                state := lfsr_next(LFSR_SPEC, state);
            end loop;
            -- Compare to the unit under test.
            assert (gen_data = dref)
                report "Generator mismatch." severity error;
        end if;

        -- Inspect outputs of the PRBS synchronizer.
        if (sync_reset = '1') then
            test_cycle <= 0;
            test_reset <= '0';
        elsif (sync_write = '1') then
            test_cycle <= test_cycle + 1;
            assert (sync_local = sync_rcvd)
                report "Synchronizer mismatch." severity error;
            test_reset <= bool2bit(test_cycle >= 99);
        end if;

        -- Count total outputs and print the "done" message.
        if (reset_p = '1') then
            test_count <= 0;
        elsif (sync_write = '1') then
            test_count <= test_count + 1;
            if (test_count = 30000) then
                report "Test completed." severity note;
            end if;
        end if;
    end if;
end process;

end tb;

-------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.prng_lfsr_common.all;

entity prng_lfsr_tb is
    -- Top-level testbench has no I/O.
end prng_lfsr_tb;

architecture tb of prng_lfsr_tb is

component prng_lfsr_tb_helper is
    generic (
    IO_WIDTH    : positive;
    LFSR_SPEC   : lfsr_spec_t;
    MSB_FIRST   : boolean);
end component;

begin

-- Instantiate each test configuration:
uut0 : prng_lfsr_tb_helper
    generic map(
    IO_WIDTH    => 32,
    LFSR_SPEC   => create_prbs(9),
    MSB_FIRST   => true);

uut1 : prng_lfsr_tb_helper
    generic map(
    IO_WIDTH    => 1,
    LFSR_SPEC   => create_prbs(11),
    MSB_FIRST   => true);

uut2 : prng_lfsr_tb_helper
    generic map(
    IO_WIDTH    => 8,
    LFSR_SPEC   => create_prbs(23),
    MSB_FIRST   => false);

end tb;
