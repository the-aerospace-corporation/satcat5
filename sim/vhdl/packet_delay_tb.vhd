--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the fixed-delay buffer
--
-- This testbench confirms that the fixed-delay buffer applies exactly
-- the specified delay in a variety of configurations.
--
-- A full test only takes ~1 millisecond.
--

---------------------------------------------------------------------
----------------------------- HELPER MODULE -------------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.switch_meta_null;

entity packet_delay_tb_single is
    generic (
    IO_BYTES    : integer;          -- Width of input port
    DELAY_COUNT : integer);         -- Fixed delay, in clocks
    port (
    io_clk      : in  std_logic;
    reset_p     : in  std_logic);
end packet_delay_tb_single;

architecture single of packet_delay_tb_single is

-- Test I/O
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_nlast     : integer range 0 to IO_BYTES := 0;
signal in_write     : std_logic := '0';
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_write    : std_logic;

-- Reference sequence
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal ref_nlast    : integer range 0 to IO_BYTES := 0;
signal ref_write    : std_logic := '0';
signal ref_enable   : std_logic := '0';

begin

-- Input and reference generation.
p_input : process(io_clk)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
begin
    if rising_edge(io_clk) then
        if (reset_p = '1') then
            in_data     <= (others => '0');
            in_nlast    <= IO_BYTES-1;
            in_write    <= '0';
        else
            for n in in_data'range loop
                uniform(seed1, seed2, rand);
                in_data(n) <= bool2bit(rand < 0.5);
            end loop;
            uniform(seed1, seed2, rand);
            in_nlast <= integer(floor(rand * real(IO_BYTES+1)));
            uniform(seed1, seed2, rand);
            in_write <= bool2bit(rand < 0.5);
        end if;
    end if;
end process;

p_ref : process(io_clk)
    variable seed1  : positive := 1234;
    variable seed2  : positive := 5678;
    variable rand   : real := 0.0;
    variable delay  : integer := 0;
begin
    if rising_edge(io_clk) then
        if (reset_p = '1') then
            ref_data     <= (others => '0');
            ref_nlast    <= IO_BYTES-1;
            ref_write    <= '0';
            delay        := DELAY_COUNT;
        elsif (delay > 0) then
            delay := delay - 1;
        else
            for n in in_data'range loop
                uniform(seed1, seed2, rand);
                ref_data(n) <= bool2bit(rand < 0.5);
            end loop;
            uniform(seed1, seed2, rand);
            ref_nlast <= integer(floor(rand * real(IO_BYTES+1)));
            uniform(seed1, seed2, rand);
            ref_write <= bool2bit(rand < 0.5);
        end if;
        ref_enable <= bool2bit(delay = 0);
    end if;
end process;

-- Unit under test
uut : entity work.packet_delay
    generic map(
    IO_BYTES    => IO_BYTES,
    DELAY_COUNT => DELAY_COUNT)
    port map(
    in_data     => in_data,
    in_meta     => SWITCH_META_NULL,    -- Not tested
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_data    => out_data,
    out_meta    => open,                -- Not tested
    out_nlast   => out_nlast,
    out_write   => out_write,
    io_clk      => io_clk,
    reset_p     => reset_p);

-- Output checking.
p_check : process(io_clk)
begin
    if rising_edge(io_clk) then
        if (reset_p = '1' or ref_enable = '0') then
            -- Just after reset, confirm write is deasserted.
            assert (out_write /= '1')
                report "Unexpected out_write strobe." severity error;
        else
            -- At all other times, check for 100% match.
            assert (out_data = ref_data)
                report "Data mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLast mismatch." severity error;
            assert (out_write = ref_write)
                report "Write mismatch." severity error;
        end if;
    end if;
end process;

end single;



---------------------------------------------------------------------
----------------------------- TOP LEVEL TESTBENCH -------------------
---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity packet_delay_tb is
    -- Unit testbench top level, no I/O ports
end packet_delay_tb;

architecture tb of packet_delay_tb is

signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Instantiate each test configuration.
u0 : entity work.packet_delay_tb_single
    generic map(
    IO_BYTES    => 1,
    DELAY_COUNT => 0)
    port map(
    io_clk      => clk_100,
    reset_p     => reset_p);

u1 : entity work.packet_delay_tb_single
    generic map(
    IO_BYTES    => 2,
    DELAY_COUNT => 1)
    port map(
    io_clk      => clk_100,
    reset_p     => reset_p);

u3 : entity work.packet_delay_tb_single
    generic map(
    IO_BYTES    => 1,
    DELAY_COUNT => 3)
    port map(
    io_clk      => clk_100,
    reset_p     => reset_p);

u63 : entity work.packet_delay_tb_single
    generic map(
    IO_BYTES    => 1,
    DELAY_COUNT => 63)
    port map(
    io_clk      => clk_100,
    reset_p     => reset_p);

end tb;
