--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- Packet prefix testbench.
--
-- Test takes 1 ms.
--

library ieee;
use ieee.math_real.all;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;
use work.common_functions.all;
use work.eth_frame_common.all;

entity packet_prefix_tb_helper is
    generic(
    RATE_IN  : real;  -- Upstream flow control
    RATE_OUT : real); -- Downstream flow control
    port(
    test_done : out std_logic);
end packet_prefix_tb_helper;

architecture helper of packet_prefix_tb_helper is

constant DATA_WIDTH     : positive := byte_t'length;
constant REF_DEPTH_LOG2 : positive := 6;

constant PREFIX  : byte_t := X"03";

signal in_data   : byte_t;
signal in_last   : std_logic;
signal in_valid  : std_logic := '0';
signal in_ready  : std_logic;

signal out_data  : byte_t;
signal out_last  : std_logic;
signal out_valid : std_logic;
signal out_ready : std_logic := '0';

signal refclk    : std_logic := '0';
signal reset_p   : std_logic := '1';

signal dly_out_last : std_logic;

signal ref_data  : byte_t;
signal ref_write : std_logic;
signal ref_read  : std_logic;
signal ref_full  : std_logic;

signal i_test_done : std_logic := '0';

begin

-- Clock gen
refclk <= not refclk after 5 ns; -- 100 MHz

p_test : process
begin
    reset_p <= '1';
    wait until rising_edge(refclk);
    wait until rising_edge(refclk);
    reset_p <= '0';
    wait for 990 us;
    i_test_done <= '1';
    wait;
end process;
test_done <= i_test_done;

ref_write <= in_valid and in_ready;

p_dly : process(refclk)
begin
    if rising_edge(refclk) then
        if (reset_p = '1') then
            dly_out_last <= '1';
        elsif (out_valid = '1' and out_ready = '1') then
            dly_out_last <= out_last;
        end if;
    end if;
end process;

ref_read <= out_valid and out_ready and not dly_out_last;

u_ref : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH   => DATA_WIDTH,
    DEPTH_LOG2 => REF_DEPTH_LOG2)
    port map(
    in_data    => in_data,
    in_write   => ref_write,
    out_data   => ref_data,
    out_read   => ref_read,
    fifo_full  => ref_full,
    clk        => refclk,
    reset_p    => reset_p);

uut : entity work.packet_prefix
    generic map (
    PREFIX => PREFIX)
    port map (
    in_data   => in_data,
    in_last   => in_last,
    in_valid  => in_valid,
    in_ready  => in_ready,
    out_data  => out_data,
    out_last  => out_last,
    out_valid => out_valid,
    out_ready => out_ready,
    refclk    => refclk,
    reset_p   => reset_p);

p_check : process(refclk)
begin
    if rising_edge(refclk) then
        if (out_valid = '1') and (out_ready = '1') then
            if (dly_out_last = '1') then
                assert(out_data = PREFIX)
                    report "Expected prefix" severity error;
            else
                assert(out_data = ref_data)
                    report "Data mismatch" severity error;
            end if;
        end if;
    end if;
end process;

-- Randomize flow control
p_stream_flow : process(refclk)
    constant RATE_EOF : real := 0.02;
    variable seed1    : positive := 123456;
    variable seed2    : positive := 987654;
    variable rand     : real := 0.0;
begin
    if rising_edge(refclk) then
        -- Upstream flow control
        if (reset_p = '1') then
            in_valid <= '0';
        elsif (in_valid = '0') or (in_ready = '1') then
            uniform(seed1, seed2, rand);
            in_valid <= bool2bit(rand < RATE_IN);
            in_last  <= bool2bit(rand < RATE_EOF);
            if (rand < RATE_IN) then
                in_data  <= I2S(integer(floor(rand * 256.0)), DATA_WIDTH);
            end if;
        end if;

        -- Downstream flow control
        if (reset_p = '1') then
            out_ready <= '0';
        else
            uniform(seed1, seed2, rand);
            out_ready <= bool2bit(rand < RATE_OUT);
        end if;
    end if;
end process;

end helper;

-----------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.common_functions.all;

entity packet_prefix_tb is
end packet_prefix_tb;

architecture tb of packet_prefix_tb is

signal test_done : std_logic_vector(0 to 3) := (others => '0');

begin

-- Instantiate tests with a couple different flow rates
uut0 : entity work.packet_prefix_tb_helper
    generic map(RATE_IN => 0.5, RATE_OUT => 0.5)
    port map(test_done => test_done(0));

uut1 : entity work.packet_prefix_tb_helper
    generic map(RATE_IN => 1.0, RATE_OUT => 1.0)
    port map(test_done => test_done(1));

uut2 : entity work.packet_prefix_tb_helper
    generic map(RATE_IN => 0.1, RATE_OUT => 1.0)
    port map(test_done => test_done(2));

uut3 : entity work.packet_prefix_tb_helper
    generic map(RATE_IN => 1.0, RATE_OUT => 0.1)
    port map(test_done => test_done(3));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
