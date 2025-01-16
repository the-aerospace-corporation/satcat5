--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Packet-header augmentation testbench
--
-- The packet-header augmentation block is used to allow out-of-order parsing
-- of packet-header fields. This unit test instantiates several configurations
-- of the block, then checks output under various flow-control conditions.
--
-- The complete test takes just under 5.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity packet_augment_tb_helper is
    generic (
    IN_BYTES    : positive;
    OUT_BYTES   : positive);
    port (
    clk         : in  std_logic;    -- Common clock
    reset_p     : in  std_logic;    -- Common reset
    flush_req   : in  std_logic;    -- Flush request
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real);        -- Output rate (0-100%)
end packet_augment_tb_helper;

architecture helper of packet_augment_tb_helper is

-- Input, reference, and output streams.
signal in_data      : std_logic_vector(8*IN_BYTES-1 downto 0) := (others => 'X');
signal in_nlast     : integer range 0 to IN_BYTES := 0;
signal in_valid     : std_logic := '0';
signal in_ready     : std_logic;
signal in_generate  : std_logic := '0';
signal in_wcount    : natural := 0;
signal ref_data     : std_logic_vector(8*OUT_BYTES-1 downto 0) := (others => '0');
signal ref_mask     : std_logic_vector(8*OUT_BYTES-1 downto 0) := (others => '0');
signal ref_nlast    : integer range 0 to IN_BYTES := 0;
signal out_data     : std_logic_vector(8*OUT_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IN_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_wcount   : natural := 0;

begin

-- Generate pseudorandom input and reference streams.
p_gen : process(clk)
    variable rem_in, rem_out : natural := 0;
    variable tmp_wcount : natural := 0;
    variable seed1i, seed1o, seed1f : positive := 1234;
    variable seed2i, seed2o, seed2f : positive := 5678;
    variable rand : real;
    variable btmp : unsigned(7 downto 0);
begin
    if rising_edge(clk) then
        -- Packet-length randomization.
        if (reset_p = '1') then
            seed1i  := 1234;
            seed1o  := 1234;
            seed2i  := 5678;
            seed2o  := 5678;
            rem_in  := 42;
            rem_out := 42;
        end if;

        if (in_valid = '1' and in_ready = '1') then
            if (rem_in > IN_BYTES) then
                rem_in := rem_in - IN_BYTES;
            elsif (flush_req = '1') then
                rem_in := 0;    -- Halt input at EOF
            else
                uniform(seed1i, seed2i, rand);
                rem_in := 1 + integer(42.0 * rand);
            end if;
        end if;

        if (out_valid = '1' and out_ready = '1') then
            if (rem_out > IN_BYTES) then
                rem_out := rem_out - IN_BYTES;
            else
                uniform(seed1o, seed2o, rand);
                rem_out := 1 + integer(42.0 * rand);
            end if;
        end if;

        -- On-demand generation of the input data stream.
        if (reset_p = '1') then
            tmp_wcount := 0;
        else
            tmp_wcount := in_wcount + u2i(in_valid and in_ready);
        end if;

        if (reset_p = '1') then
            in_data  <= (others => 'X');
            in_nlast <= 0;
            in_valid <= '0';
        elsif (in_generate = '1' and rem_in > 0) then
            for n in 0 to IN_BYTES-1 loop
                if (n < rem_in) then
                    btmp := to_unsigned((tmp_wcount * IN_BYTES + n) mod 256, 8);
                else
                    btmp := (others => '0');
                end if;
                in_data(in_data'left-8*n downto in_data'left-8*n-7)
                    <= std_logic_vector(btmp);
            end loop;
            if (rem_in > IN_BYTES) then
                in_nlast <= 0;      -- Continue
            else
                in_nlast <= rem_in; -- End-of-frame
            end if;
            in_valid <= '1';
        elsif (in_ready = '1') then
            in_data  <= (others => 'X');
            in_nlast <= 0;
            in_valid <= '0';
        end if;

        in_wcount <= tmp_wcount;

        -- Always generate the reference data stream.
        if (reset_p = '1') then
            tmp_wcount := 0;
        else
            tmp_wcount := out_wcount + u2i(out_valid and out_ready);
        end if;

        for n in 0 to OUT_BYTES-1 loop
            if (n < rem_out) then
                btmp := to_unsigned((tmp_wcount * IN_BYTES + n) mod 256, 8);
            else
                btmp := (others => '0');
            end if;
            ref_data(ref_data'left-8*n downto ref_data'left-8*n-7)
                <= std_logic_vector(btmp);
            if (n < rem_out) then
                btmp := (others => '1');
            else
                btmp := (others => '0');
            end if;
            ref_mask(ref_data'left-8*n downto ref_data'left-8*n-7)
                <= std_logic_vector(btmp);
        end loop;

        if (rem_out > IN_BYTES) then
            ref_nlast <= 0;         -- Continue
        else
            ref_nlast <= rem_out;   -- End-of-frame
        end if;

        out_wcount <= tmp_wcount;

        -- Input and output flow randomization.
        uniform(seed1f, seed2f, rand);
        in_generate <= bool2bit(rand < rate_in);
        uniform(seed1f, seed2f, rand);
        out_ready <= bool2bit(rand < rate_out);
    end if;
end process;

-- Unit under test.
uut : entity work.packet_augment
    generic map(
    IN_BYTES    => IN_BYTES,
    OUT_BYTES   => OUT_BYTES)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Check the output stream against the reference.
p_check : process(clk)
    variable reset_d : std_logic := '1';
begin
    if rising_edge(clk) then
        -- Compare against the reference stream.
        if (out_valid = '1' and reset_p = '0') then
            assert ((out_data and ref_mask) = ref_data)
                report "DATA mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
        end if;
        -- On rising edge of reset, confirm output is flushed.
        if (reset_p = '1' and reset_d = '0') then
            assert (in_wcount = out_wcount)
                report "Missing data." severity error;
        end if;
        reset_d := reset_p;
    end if;
end process;

end helper;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity packet_augment_tb is
    -- Testbench --> No I/O ports
end packet_augment_tb;

architecture tb of packet_augment_tb is

component packet_augment_tb_helper is
    generic (
    IN_BYTES    : positive;
    OUT_BYTES   : positive);
    port (
    clk         : in  std_logic;    -- Common clock
    reset_p     : in  std_logic;    -- Common reset
    flush_req   : in  std_logic;    -- Flush request
    rate_in     : in  real;         -- Input rate (0-100%)
    rate_out    : in  real);        -- Output rate (0-100%)
end component;

signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';
signal flush_req    : std_logic := '0';
signal rate_in      : real := 0.0;
signal rate_out     : real := 0.0;

begin

-- Clock generation
clk <= not clk after 5 ns; -- 1 / (2*5 ns) = 100 MHz

-- Overall test control
p_test : process
    procedure fifo_flush is begin
        flush_req   <= '1';
        wait for 1 us;
        rate_in     <= 0.0;
        rate_out    <= 1.0;
        wait for 1 us;
        reset_p     <= '1';
        wait for 1 us;
        flush_req   <= '0';
        reset_p     <= '0';
    end procedure;
begin
    -- Reset strobe before we start.
    reset_p     <= '1';
    flush_req   <= '0';
    rate_in     <= 0.0;
    rate_out    <= 0.0;
    wait for 1 us;
    reset_p     <= '0';

    -- Run in various flow-control conditions.
    -- After each sub-test, flush the FIFO contents.
    report "Starting sequence (0.1/0.9)" severity note;
    for n in 1 to 99 loop
        rate_in <= 0.9; rate_out <= 0.1; wait for 10 us;
        rate_in <= 0.1; rate_out <= 0.9; wait for 10 us;
    end loop;

    fifo_flush;

    report "Starting sequence (0.4/0.6)" severity note;
    for n in 1 to 10 loop
        rate_in <= 0.6; rate_out <= 0.4; wait for 100 us;
        rate_in <= 0.5; rate_out <= 0.5; wait for 100 us;
        rate_in <= 0.4; rate_out <= 0.6; wait for 100 us;
    end loop;

    fifo_flush;

    report "All tests completed.";
    wait;
end process;

-- Instantiate test units in various configurations.
test0 : packet_augment_tb_helper
    generic map(
    IN_BYTES    => 1,
    OUT_BYTES   => 2)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flush_req   => flush_req,
    rate_in     => rate_in,
    rate_out    => rate_out);

test1 : packet_augment_tb_helper
    generic map(
    IN_BYTES    => 1,
    OUT_BYTES   => 8)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flush_req   => flush_req,
    rate_in     => rate_in,
    rate_out    => rate_out);

test2 : packet_augment_tb_helper
    generic map(
    IN_BYTES    => 8,
    OUT_BYTES   => 9)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flush_req   => flush_req,
    rate_in     => rate_in,
    rate_out    => rate_out);

test3 : packet_augment_tb_helper
    generic map(
    IN_BYTES    => 8,
    OUT_BYTES   => 16)
    port map(
    clk         => clk,
    reset_p     => reset_p,
    flush_req   => flush_req,
    rate_in     => rate_in,
    rate_out    => rate_out);

end tb;
