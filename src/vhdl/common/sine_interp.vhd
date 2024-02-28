--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Interpolated sine/cosine function-generator
--
-- This block uses interpolation to calculate sine and cosine with higher
-- precision than is practical for direct lookup-table designs.  It uses
-- a pair of sine and cosine lookup tables for coarse value and slope
-- estimation, then a multiply-accumulate stage for the final output.
--
-- Sine and cosine are complementary (i.e., one is the derivative of the
-- other), so a single pair of tables can be used for both nominal value
-- and derivative.  For an angle "t" in radians:
--      qt = q * round(t / q)   (q = Lookup table quantization step)
--      dt = t - qt             (i.e., Difference from center point)
--      x = A * cos(t)  -->  x' = A * cos(qt) - A*dt * sin(qt)
--      y = A * sin(t)  -->  y' = A * sin(qt) + A*dt * cos(qt)
--
-- Since we need both tables to calculate the derivatives regardless, the
-- marginal cost of generating both outputs simultaneously is small.
--
-- The minimum table size depends on the required accuracy.  A 1024-element
-- table (TBL_SIZE=10) provides adequate precision for outputs up to 16-bits
-- wide.  The coefficient width (TBL_WIDTH=18 default) should be adjusted to
-- match the preferred multiplier size or OUT_WIDTH, whichever is larger.
-- If in doubt, simulate using "sine_interp.py" and "sine_interp_tb.vhd".
--
-- Latency is fixed at exactly six clock cycles.  Output scale defaults to
-- the maximum safe value, but can be reduced if desired.
--
-- Since this module has no persistent state and its output is flushed
-- within a few clock cycles, no reset is required.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;

entity sine_interp is
    generic (
    IN_WIDTH    : positive;         -- Bits in angle input (>= 2)
    OUT_WIDTH   : positive;         -- Bits in output word
    OUT_SCALE   : natural := 0;     -- Override output scale?
    TBL_SIZE    : positive := 10;   -- Lookup table size = 2^N words
    TBL_WIDTH   : positive := 18);  -- Lookup table coefficient width
    port (
    in_theta    : in  unsigned(IN_WIDTH-1 downto 0);
    out_cos     : out signed(OUT_WIDTH-1 downto 0);
    out_sin     : out signed(OUT_WIDTH-1 downto 0);
    clk         : in  std_logic);
end sine_interp;

architecture sine_interp of sine_interp is

-- Define local types.
subtype input_t is unsigned(IN_WIDTH-1 downto 0);
subtype index_t is unsigned(TBL_SIZE-1 downto 0);
subtype value_t is signed(TBL_WIDTH-1 downto 0);
subtype product_t is signed(2*TBL_WIDTH-1 downto 0);

-- Calculate scaling factor for derivative term.
-- (Steal N bits from table lookup to ensure accurate scaling.)
constant DIFF_EXTRA : natural := 6;
constant DIFF_N2RAD : real := MATH_2_PI / real(2**IN_WIDTH);
constant DIFF_SCL_R : real := DIFF_N2RAD * real(2**TBL_WIDTH) * real(2**DIFF_EXTRA);
constant DIFF_SCL_I : value_t := r2s(floor(DIFF_SCL_R), TBL_WIDTH);

-- Number of fractional bits after rounding to nearest table entry.
constant TBL_FRAC   : positive := IN_WIDTH - TBL_SIZE;

-- Calculate scaling factors for the sin/cos lookup table.
-- (Smaller than nominal max to prevent interpolation overflow.)
function TBL_SCALE return natural is
    constant OUT_MAX : positive := 2**(OUT_WIDTH-1) - 1;
    constant TBL_MUL : positive := 2**(TBL_WIDTH - OUT_WIDTH);
begin
    if (OUT_SCALE = 0) then
        return TBL_MUL * OUT_MAX;   -- Default
    elsif (OUT_SCALE <= OUT_MAX) then
        return TBL_MUL * OUT_SCALE; -- User-specified
    else
        return TBL_MUL * OUT_MAX;   -- Overflow
        report "Adjusted scale to avoid interpolation overflow." severity warning;
    end if;
end function;

-- Scale lookup-table value by 2**TBL_WIDTH.
function upscale(x: signed; lsb: natural) return product_t is
    -- Adding 1/2 LSB and then truncating is equivalent to rounding.
    constant HALF_LSB : integer := (2**lsb) / 2;
    variable x2 : product_t := resize(x, 2*TBL_WIDTH);
begin
    return shift_left(x2, TBL_WIDTH) + HALF_LSB;
end function;

-- Truncate product term to match final output scale.
function dnscale(x: signed; W: positive) return signed is
    variable x2 : signed(W-1 downto 0) := x(x'left downto x'length-W);
begin
    return x2;
end function;

-- Input quantization.
signal in_round : input_t := (others => '0');
signal in_delay : input_t := (others => '0');

-- Lookup pipeline.
signal tbl_idx  : index_t;
signal tbl_cos  : value_t;
signal tbl_sin  : value_t;

-- Interpolation pipeline.
signal diff_d1  : value_t := (others => '0');
signal diff_d2  : product_t := (others => '0');
signal diff_d3  : value_t := (others => '0');
signal adj_cos  : product_t := (others => '0');
signal adj_sin  : product_t := (others => '0');
signal mul_cos  : product_t := (others => '0');
signal mul_sin  : product_t := (others => '0');
signal sum_cos  : product_t := (others => '0');
signal sum_sin  : product_t := (others => '0');

begin

-- Design sanity checks.
assert (IN_WIDTH > TBL_SIZE)
    report "Table is larger than input, consider using sine_table.";
assert (TBL_WIDTH >= OUT_WIDTH)
    report "Table width is too small for output.";
assert (TBL_SIZE + TBL_WIDTH >= IN_WIDTH)
    report "Interpolation term exceeds table size.";

-- Pipeline stage 1: Input quantization.
p_input : process(clk)
    -- Adding 1/2 LSB and then truncating is equivalent to rounding.
    constant HALF_LSB_I : input_t := to_unsigned(2**(TBL_FRAC-1), IN_WIDTH);
    constant ROUND_MASK : input_t := not to_unsigned(2**TBL_FRAC-1, IN_WIDTH);
begin
    if rising_edge(clk) then
        in_delay <= in_theta;
        in_round <= (in_theta + HALF_LSB_I) and ROUND_MASK;
    end if;
end process;

-- Pipeline stage 2-4: Sine and cosine lookup tables.
-- (Fixed delay of exactly three clock cycles.)
tbl_idx <= in_round(in_round'left downto TBL_FRAC);

u_cos : entity work.sine_table
    generic map(
    IN_WIDTH    => TBL_SIZE,
    OUT_WIDTH   => TBL_WIDTH,
    OUT_SCALE   => TBL_SCALE,
    OUT_MODE    => "cos")
    port map(
    in_theta    => tbl_idx,
    out_data    => tbl_cos,
    clk         => clk);

u_sin : entity work.sine_table
    generic map(
    IN_WIDTH    => TBL_SIZE,
    OUT_WIDTH   => TBL_WIDTH,
    OUT_SCALE   => TBL_SCALE,
    OUT_MODE    => "sin")
    port map(
    in_theta    => tbl_idx,
    out_data    => tbl_sin,
    clk         => clk);

-- Interpolator pipeline.
p_interp : process(clk)
begin
    if rising_edge(clk) then
        -- Pipeline stage 6: Sum of interpolation terms.
        sum_cos <= adj_cos - mul_sin;
        sum_sin <= adj_sin + mul_cos;
    
        -- Pipeline stage 5: Intermediate products.
        adj_cos <= upscale(tbl_cos, 2*TBL_WIDTH-OUT_WIDTH);
        adj_sin <= upscale(tbl_sin, 2*TBL_WIDTH-OUT_WIDTH);
        mul_cos <= diff_d3 * shift_right(tbl_cos, DIFF_EXTRA);
        mul_sin <= diff_d3 * shift_right(tbl_sin, DIFF_EXTRA);

        -- Pipeline stage 2-4: Calculate and scale the difference term.
        -- (Matched delay with lookup table, above.)
        diff_d3 <= diff_d2(TBL_WIDTH-1 downto 0);
        diff_d2 <= diff_d1 * DIFF_SCL_I;
        diff_d1 <= resize(signed(in_delay - in_round), TBL_WIDTH);
    end if;
end process;

-- Truncate the final output.
out_cos <= dnscale(sum_cos, OUT_WIDTH);
out_sin <= dnscale(sum_sin, OUT_WIDTH);

end sine_interp;
