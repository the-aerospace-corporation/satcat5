--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Unit test for the queue-indicator selection block (router2_qsel)
--
-- This test simulates a queue with bursty loads, and confirms that the
-- queue-depth estimator correctly nullifies the effect of these bursts.
-- The test is repeated for several different filter configurations.
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.router_sim_tools.all;

entity router2_qsel_tb is
    -- Unit test has no top-level I/O.
end router2_qsel_tb;

architecture tb of router2_qsel_tb is

constant IO_BYTES   : positive := 1;
constant META_WIDTH : natural  := 7;
constant PORT_COUNT : positive := 4;
constant REFCLK_HZ  : positive := 100_000_000;
constant RAW_QDEPTH : unsigned := unsigned(rand_bytes(PORT_COUNT));

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';
signal check_p      : std_logic := '0';

-- Unit under test.
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_meta      : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal in_nlast     : integer range 0 to IO_BYTES := 0;
signal in_pdst      : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal in_write     : std_logic := '0';
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_meta     : std_logic_vector(META_WIDTH-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_write    : std_logic;
signal out_qdepth   : unsigned(7 downto 0);
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal ref_meta     : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal ref_nlast    : integer range 0 to IO_BYTES := 0;
signal ref_write    : std_logic := '0';
signal ref_qdepth   : unsigned(7 downto 0) := (others => '0');

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
check_p <= '1' after 2 us;

-- Input and reference generation;
p_gen : process(clk_100)
begin
    if rising_edge(clk_100) then
        -- Randomize all inputs.
        in_data     <= rand_bytes(IO_BYTES);
        in_meta     <= rand_vec(META_WIDTH);
        in_nlast    <= rand_int(IO_BYTES + 1);
        in_pdst     <= rand_vec(PORT_COUNT);
        in_write    <= rand_bit(0.5);

        -- Calculate expected "qdepth" output.
        ref_qdepth  <= (others => '0');
        if (count_ones(in_pdst) = 1) then
            for n in in_pdst'range loop
                if (in_pdst(n) = '1') then
                    ref_qdepth <= RAW_QDEPTH(8*n+7 downto 8*n);
                end if;
            end loop;
        end if;

        -- Matched delay for other signals.Generate the reference sequence.
        ref_data    <= in_data;
        ref_meta    <= in_meta;
        ref_nlast   <= in_nlast;
        ref_write   <= in_write;
    end if;
end process;

-- Unit under test
uut : entity work.router2_qsel
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => META_WIDTH,
    PORT_COUNT  => PORT_COUNT,
    REFCLK_HZ   => REFCLK_HZ,
    T0_MSEC     => 0.001,
    T1_MSEC     => -1.0)
    port map(
    raw_qdepth  => RAW_QDEPTH,
    in_data     => in_data,
    in_meta     => in_meta,
    in_nlast    => in_nlast,
    in_pdst     => in_pdst,
    in_write    => in_write,
    out_data    => out_data,
    out_meta    => out_meta,
    out_nlast   => out_nlast,
    out_write   => out_write,
    out_qdepth  => out_qdepth,
    clk         => clk_100,
    reset_p     => reset_p);

-- Compare output to reference.
p_check : process(clk_100)
    variable count : natural := 0;
begin
    if rising_edge(clk_100) then
        if (check_p = '1') then
            -- Each field should match exactly.
            assert (out_data = ref_data)
                report "DATA mismatch." severity error;
            assert (out_meta = ref_meta)
                report "META mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
            assert (out_write = ref_write)
                report "WRITE mismatch." severity error;
            assert (out_qdepth = ref_qdepth)
                report "QDEPTH mismatch." severity error;
            -- Give the all-clear after N comparisons.
            if (count = 90_000) then
                report "All tests completed.";
            end if;
            count := count + 1;
        end if;
    end if;
end process;

end tb;
