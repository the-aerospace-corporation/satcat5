--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the function-generator lookup table
--
-- This unit instantiates "sine_table" in various configurations, drives
-- the input with a simple counter, and confirms that the output matches
-- expectations.
--
-- The complete test takes ~205 microseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;

entity sine_table_tb_single is
    generic (
    IN_WIDTH    : positive := 10;   -- Bits in angle input
    OUT_WIDTH   : positive := 15);  -- Bits in output word
    port (
    clk_100     : in  std_logic;
    done        : out std_logic);
end sine_table_tb_single;

architecture sine_table_tb_single of sine_table_tb_single is

subtype input_t is unsigned(IN_WIDTH-1 downto 0);
subtype output_t is signed(OUT_WIDTH-1 downto 0);

-- Input and reference generation.
signal in_data  : input_t := (others => '0');
signal ref_cos  : integer := 0;
signal ref_sin  : integer := 0;
signal ref_saw  : integer := 0;

-- Outputs under test.
signal out_cos  : output_t;
signal out_sin  : output_t;
signal out_saw  : output_t;
signal done_i   : std_logic := '0';

begin

-- Input and reference generation.
p_input : process(clk_100)
    -- Convert integer input to radians.
    function n2rad(x: input_t) return real is
    begin
        return real(to_integer(x)) * MATH_2_PI / real(2**IN_WIDTH);
    end function;

    -- Scaling for each mode.
    constant SCALE_COS  : real := real(2**(OUT_WIDTH-1) - 1);
    constant SCALE_SAW  : real := real(2**OUT_WIDTH) / MATH_2_PI;
begin
    if rising_edge(clk_100) then
        -- Input is a simple counter.
        -- (This will automatically wrap around at 2^IN_WIDTH.)
        in_data <= in_data + 1;

        -- Generate each reference output.
        -- (Subtract N from in_data to set expected latency.)
        ref_cos <= integer(round(SCALE_COS * cos(n2rad(in_data - 2))));
        ref_sin <= integer(round(SCALE_COS * sin(n2rad(in_data - 2))));
        ref_saw <= integer(round(SCALE_SAW * (n2rad(in_data) - MATH_PI)));
    end if;
end process;

-- Units under test.
uut_cos : entity work.sine_table
    generic map(
    IN_WIDTH    => IN_WIDTH,
    OUT_WIDTH   => OUT_WIDTH,
    OUT_MODE    => "cos")
    port map(
    in_theta    => in_data,
    out_data    => out_cos,
    clk         => clk_100);

uut_sin : entity work.sine_table
    generic map(
    IN_WIDTH    => IN_WIDTH,
    OUT_WIDTH   => OUT_WIDTH,
    OUT_MODE    => "sin")
    port map(
    in_theta    => in_data,
    out_data    => out_sin,
    clk         => clk_100);

uut_saw : entity work.sine_table
    generic map(
    IN_WIDTH    => IN_WIDTH,
    OUT_WIDTH   => OUT_WIDTH,
    OUT_MODE    => "saw")
    port map(
    in_theta    => in_data,
    out_data    => out_saw,
    clk         => clk_100);

-- Check each output.
p_check : process(clk_100)
    constant TOL   : natural := 1;
    variable delay : natural := 5;
    variable loops : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Check outputs, ignoring startup transient.
        if (delay > 0) then
            delay := delay - 1;
        else
            assert (out_cos >= ref_cos-TOL and out_cos <= ref_cos+TOL)
                report "COS mismatch @" & integer'image(to_integer(in_data))
                & ", delta = " & integer'image(to_integer(out_cos) - ref_cos);
            assert (out_sin >= ref_sin-TOL and out_sin <= ref_sin+TOL)
                report "SIN mismatch @" & integer'image(to_integer(in_data))
                & ", delta = " & integer'image(to_integer(out_sin) - ref_sin);
            assert (out_saw >= ref_saw-TOL and out_saw <= ref_saw+TOL)
                report "SAW mismatch @" & integer'image(to_integer(in_data))
                & ", delta = " & integer'image(to_integer(out_saw) - ref_saw);
        end if;

        -- Count the number of complete loops.
        if (in_data = 0 and delay = 0) then
            loops := loops + 1;
            if (loops = 5) then
                report "Lane completed.";
                done_i <= '1';
            end if;
        end if;
    end if;
end process;

done <= done_i;

end sine_table_tb_single;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity sine_table_tb is
    -- Top-level test has no I/O ports.
end sine_table_tb;

architecture sine_table_tb of sine_table_tb is

signal clk_100  : std_logic := '0';
signal done     : std_logic_vector(2 downto 0) := (others => '0');

begin

-- Clock generation
clk_100 <= not clk_100 after 5 ns;

-- Instantiate each test configuration.
uut0 : entity work.sine_table_tb_single
    generic map(IN_WIDTH => 11, OUT_WIDTH => 11)
    port map(clk_100 => clk_100, done => done(0));

uut1 : entity work.sine_table_tb_single
    generic map(IN_WIDTH => 12, OUT_WIDTH => 10)
    port map(clk_100 => clk_100, done => done(1));

uut2 : entity work.sine_table_tb_single
    generic map(IN_WIDTH => 10, OUT_WIDTH => 12)
    port map(clk_100 => clk_100, done => done(2));

-- Report
p_done : process
begin
    wait until and_reduce(done) = '1';
    report "All tests completed!";
    wait;
end process;

end sine_table_tb;
