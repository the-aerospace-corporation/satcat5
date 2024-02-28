--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Byte-repacking FIFO Testbench
--
-- This unit drives a sparsely-packed random bytes into the unit under test,
-- and confirms that the output is a densely packed byte-counter.  It covers
-- a variety of randomized flow-control conditions and build-time configurations.
--
-- The complete test takes less than one millisecond.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity fifo_repack_tb_helper is
    generic (
    IO_BYTES    : positive);        -- Word size
    port (
    clk         : in  std_logic;    -- Common clock
    reset_p     : in  std_logic;    -- Reset between trials
    rate_in     : in  real);        -- Input rate (0-100%)
end fifo_repack_tb_helper;

architecture helper of fifo_repack_tb_helper is

-- Input and reference stream generation.
signal in_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_last     : std_logic := '0';
signal in_write    : std_logic_vector(IO_BYTES-1 downto 0) := (others => '0');
signal ref_data    : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal ref_nlast   : integer range 0 to IO_BYTES := 0;
signal ref_last    : std_logic := '0';

-- Output from UUT
signal out_data    : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast   : integer range 0 to IO_BYTES;
signal out_last    : std_logic;
signal out_write   : std_logic;

begin

-- Input and reference stream generation.
p_in : process(clk)
    constant SEED1  : positive := 123456;
    constant SEED2  : positive := 987654;
    variable iseed1 : positive := SEED1;    -- Input data
    variable iseed2 : positive := SEED2;
    variable rseed1 : positive := SEED1;    -- Reference data
    variable rseed2 : positive := SEED2;
    variable rand   : real := 0.0;
    variable enable : std_logic := '0';
    variable final  : std_logic := '0';
    variable btemp  : byte_t := (others => '0');
    variable bcount : natural := 0;

    -- Update "btemp", "enable", and "final" using designated PRNG state.
    procedure rand_next(variable s1, s2 : inout positive) is
    begin
        btemp := (others => '0');
        enable := '0';
        if (final = '0') then
            -- Should we generate a byte for this lane?
            uniform(s1, s2, rand);
            enable := bool2bit(rand < rate_in);
            if (enable = '1') then
                -- Randomize each bit in the byte.
                for b in btemp'range loop
                    uniform(s1, s2, rand);
                    btemp(b) := bool2bit(rand < 0.5);
                end loop;
                -- Should this be the final byte in the frame?
                uniform(s1, s2, rand);
                final := bool2bit(rand < 0.01);
            end if;
        end if;
    end procedure;
begin
    if rising_edge(clk) then
        -- Reset PRNG state to keep input and reference in sync.
        if (reset_p = '1') then
            iseed1  := SEED1;
            iseed2  := SEED2;
            rseed1  := SEED1;
            rseed2  := SEED2;
        end if;

        -- Generate input stream.
        if (reset_p = '1') then
            in_data  <= (others => '0');
            in_last  <= '0';
            in_write <= (others => '0');
        else
            final := '0';
            for n in 0 to IO_BYTES-1 loop
                -- Generate next byte, if applicable.
                rand_next(iseed1, iseed2);
                -- Drive output for this lane.
                in_data(8*IO_BYTES-1-8*n downto 8*IO_BYTES-8-8*n) <= btemp;
                in_write(IO_BYTES-1-n) <= enable;
            end loop;
            in_last <= final;
        end if;

        -- Generate output stream.
        if (reset_p = '1' or out_write = '1') then
            ref_data <= (others => '0');
            bcount := 0;
            final := '0';
            -- Retry until we get a full word of data or end-of-frame.
            while final = '0' and bcount < IO_BYTES loop
                -- Generate next byte, if applicable.
                rand_next(rseed1, rseed2);
                -- Drive output for the next open lane.
                if (enable = '1') then
                    ref_data(8*IO_BYTES-1-8*bcount downto 8*IO_BYTES-8-8*bcount) <= btemp;
                    bcount := bcount + 1;
                end if;
            end loop;
            if (final = '1') then
                ref_nlast <= bcount;
                ref_last  <= '1';
            else
                ref_nlast <= 0;
                ref_last  <= '0';
            end if;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.fifo_repack
    generic map(
    LANE_COUNT  => IO_BYTES)
    port map(
    in_data     => in_data,
    in_last     => in_last,
    in_write    => in_write,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_last    => out_last,
    out_write   => out_write,
    clk         => clk,
    reset_p     => reset_p);

-- Check outputs.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (out_write = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch" severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch" severity error;
            assert (out_last = ref_last)
                report "LAST mismatch" severity error;
        end if;
    end if;
end process;

end helper;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity fifo_repack_tb is
    -- Testbench --> No I/O ports
end fifo_repack_tb;

architecture tb of fifo_repack_tb is

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal rate_in      : real := 0.0;

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Overall test control
p_test : process
    procedure run_single(rate : real) is
    begin
        -- Reset strobe before we start.
        reset_p <= '1';
        rate_in <= rate;
        wait for 1 us;

        -- Run for a while.
        reset_p <= '0';
        wait for 99 us;
    end procedure;
begin
    run_single(1.0);
    run_single(0.5);
    run_single(0.2);
    run_single(0.1);
    report "All tests completed.";
    wait;
end process;

-- Instantiate test units in various configurations.
test1 : entity work.fifo_repack_tb_helper
    generic map(IO_BYTES => 1)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    rate_in     => rate_in);

test2 : entity work.fifo_repack_tb_helper
    generic map(IO_BYTES => 2)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    rate_in     => rate_in);

test3 : entity work.fifo_repack_tb_helper
    generic map(IO_BYTES => 3)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    rate_in     => rate_in);

test5 : entity work.fifo_repack_tb_helper
    generic map(IO_BYTES => 5)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    rate_in     => rate_in);

test8 : entity work.fifo_repack_tb_helper
    generic map(IO_BYTES => 8)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    rate_in     => rate_in);

end tb;
