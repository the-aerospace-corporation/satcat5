--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Testbench for the SGMII data-slip block
--
-- This testbench generates a feed that contains a 32-bit counter, adding
-- or removing bits on command.  The result is sent to the data-slip block,
-- which should realign the data to restore the original counter sequence.
-- The test is repeated under various flow-control conditions.
--
-- A full test takes just under 16 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;

entity sgmii_data_slip_tb is
    -- Unit testbench top level, no I/O ports
end sgmii_data_slip_tb;

architecture tb of sgmii_data_slip_tb is

constant IO_WIDTH   : integer := 32;
subtype io_vector is std_logic_vector(IO_WIDTH-1 downto 0);
subtype io_unsigned is unsigned(IO_WIDTH-1 downto 0);

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input, output, and reference streams.
signal in_data      : io_vector := (others => '0');
signal in_next      : std_logic := '0';
signal out_data     : io_vector;
signal out_next     : std_logic;
signal ref_data     : io_unsigned := (others => '0');

-- Sample-point commanding.
signal slip_early   : std_logic := '0';
signal slip_late    : std_logic := '0';
signal slip_ready   : std_logic;

-- Test control
signal test_index   : integer := 0;     -- Overall test phase
signal test_offset  : integer := 0;     -- Net early/late offset
signal test_rate    : real := 0.0;      -- Input flow-control rate

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Input stream generation.
p_flow : process(clk_100)
    variable seed1      : positive := 1234;
    variable seed2      : positive := 5678;
    variable rand       : real := 0.0;
    variable bcount     : integer := 0;
    variable next_word  : io_unsigned := (others => '0');
    variable req_early  : std_logic := '0';
    variable req_late   : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Set persistent slip-request flags.
        -- (They may not arrive on an active cycle.)
        if (reset_p = '1') then
            req_early := '0';
        elsif (slip_early = '1') then
            req_early := '1';
        end if;

        if (reset_p = '1') then
            req_late := '0';
        elsif (slip_late = '1') then
            req_late := '1';
        end if;

        -- Flow control randomization:
        uniform(seed1, seed2, rand);
        in_next <= bool2bit(rand < test_rate) and not reset_p;

        -- Generate each N-bit word for the UUT.
        if (reset_p = '1') then
            in_data     <= (others => '0');
            next_word   := (others => '0');
            bcount      := 0;
        elsif (in_next = '1') then
            for n in IO_WIDTH-1 downto 0 loop   -- MSB first
                -- Generate the next counter word if required.
                if (bcount = 0) then
                    next_word   := next_word + 1;
                    bcount      := IO_WIDTH;
                end if;
                -- Copy one or more input bits.
                if (req_late = '1') then
                    -- Shift later by inserting an extra bit.
                    req_late    := '0';         -- Clear flag for next time
                    in_data(n)  <= '0';         -- Insert bit, do not consume
                elsif (req_early = '1' and bcount > 1) then
                    -- Shift earlier by consuming two counter bits.
                    req_early   := '0';         -- Clear flag for next time
                    bcount      := bcount - 2;  -- Consume two bits
                    in_data(n)  <= next_word(bcount);
                else
                    -- Normal copy from counter to input.
                    bcount      := bcount - 1;  -- Consume one bit
                    in_data(n)  <= next_word(bcount);
                end if;
            end loop;
        end if;
    end if;
end process;

-- Unit under test
uut : entity work.sgmii_data_slip
    generic map(
    IN_WIDTH    => IO_WIDTH,
    OUT_WIDTH   => IO_WIDTH)
    port map(
    in_data     => in_data,
    in_next     => in_next,
    out_data    => out_data,
    out_next    => out_next,
    slip_early  => slip_early,
    slip_late   => slip_late,
    slip_ready  => slip_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the output stream.
p_check : process(clk_100)
    variable ignore_ct : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Generate simple counter for the reference stream.
        if (reset_p = '1') then
            ref_data <= (others => '0');
        elsif (out_next = '1') then
            ref_data <= ref_data + 1;
        end if;

        -- Check outputs, ignoring a few after each slip event.
        -- Note: Most commands are applied immediately, but some cannot be
        --       applied until there's a gap in the input stream.  Use the
        --       "slip_ready" flag to estimate when it's been applied.
        if (reset_p = '1') then
            ignore_ct := 0;
        elsif (slip_early = '1' or slip_late = '1') then
          ignore_ct := 3;
        elsif (slip_ready = '1' and out_next = '1') then
            if (ignore_ct > 0) then
                ignore_ct := ignore_ct - 1;
            elsif (out_data /= std_logic_vector(ref_data)) then
                report "Data mismatch" severity error;
            end if;
        end if;
    end if;
end process;

-- Overall test control
p_test : process
    procedure slip_one(d : std_logic) is
    begin
        assert (slip_ready = '1')
            report "Slip before ready" severity error;
        wait until rising_edge(clk_100);
        slip_early <= d;
        slip_late  <= not d;
        wait until rising_edge(clk_100);
        slip_early <= '0';
        slip_late  <= '0';
    end procedure;

    procedure sweep(x : integer) is
        constant dir : std_logic := bool2bit(x > 0);
        constant len : integer := abs(x);
    begin
        for n in 1 to len loop
            -- Note: 10 us = 1000 clocks = 200-800 data words
            wait for 10 us;
            slip_one(dir);
        end loop;
    end procedure;

    procedure start_test(r : real) is
    begin
        report "Starting test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;
        test_rate  <= r;
    end procedure;

    variable seed1      : positive := 2158971;
    variable seed2      : positive := 8976012;
    variable rand       : real := 0.0;
begin
    -- Low-rate sweep over offsets -47 to +47.
    start_test(0.2);
    sweep(-47);
    sweep(+47);
    sweep(+47);
    sweep(-47);

    -- High-rate sweep over offsets -96 to +96.
    start_test(0.8);
    sweep(+96);
    sweep(-96);
    sweep(-96);
    sweep(+96);

    -- Random walk for 1000 iterations.
    start_test(0.8);
    for n in 1 to 1000 loop
        uniform(seed1, seed2, rand);
        wait for 10 us;
        slip_one(bool2bit(rand < 0.5));
    end loop;
    wait for 10 us;

    report "All tests completed!";
    wait;
end process;

end tb;
