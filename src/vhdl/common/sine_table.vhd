--------------------------------------------------------------------------
-- Copyright 2022-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Function-generator lookup table
--
-- This block implements a ROM lookup table for various common functions.
-- Functions such as sine or cosine take advantage of quadrant symmetry
-- to reduce the table size.  Each option has a fixed latency.
--
--  Mode  | Full name | Latency   | Notes
--  ------+-----------+-----------+-------
--  cos   | Cosine    | 3         |
--  saw   | Sawtooth  | 1         | Ignores OUT_SCALE
--  sin   | Sine      | 3         | Default function
--
-- Input units are scaled such that 2^IN_WIDTH = 360 degrees.
-- Required memory grows exponentially, recommend IN_WIDTH <= 14.
--
-- The default output scale (OUT_SCALE = 0) sets the maximum magnitude
-- that does not saturate.  For sine and cosine, this means "1.0" maps to
-- Y = (2^OUT_WIDTH-1)-1.  To override this setting, specify OUT_SCALE > 0.
--
-- Since this module has no persistent state and its output is flushed
-- within a few clock cycles, no reset is required.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;

entity sine_table is
    generic (
    IN_WIDTH    : positive;         -- Bits in angle input (>= 2)
    OUT_WIDTH   : positive;         -- Bits in output word
    OUT_SCALE   : natural := 0;     -- Override output scale?
    OUT_MODE    : string := "sin"); -- Output function (see table)
    port (
    in_theta    : in  unsigned(IN_WIDTH-1 downto 0);
    out_data    : out signed(OUT_WIDTH-1 downto 0);
    clk         : in  std_logic);
end sine_table;

architecture sine_table of sine_table is

-- Define table size.
function get_idx_width(mode: string) return natural is
begin
    if (mode = "cos" or mode = "sin") then
        return IN_WIDTH-2;  -- Quadrant symmetry
    else
        return 0;           -- No table needed
    end if;
end function;

constant IDX_WIDTH : natural := get_idx_width(OUT_MODE);

-- Define local types.
subtype quad_t is unsigned(1 downto 0);
subtype index_t is unsigned(IDX_WIDTH-1 downto 0);
subtype input_t is unsigned(IN_WIDTH-1 downto 0);
subtype output_t is signed(OUT_WIDTH-1 downto 0);
type table_t is array(0 to 2**IDX_WIDTH-1) of output_t;

constant IN_HALF    : integer := 2**(IN_WIDTH-1);
constant OUT_MIN    : integer := -2**(OUT_WIDTH-1);
constant OUT_MAX    : integer := 2**(OUT_WIDTH-1)-1;

-- Special cases for specific functions.
function sawtooth(x: input_t) return output_t is
    constant ZDIFF : natural := abs(IN_WIDTH - OUT_WIDTH);
    variable y : input_t := x - IN_HALF;
    variable z : output_t := (others => '0');
begin
    if (IN_WIDTH >= OUT_WIDTH) then
        z := signed(y(y'left downto ZDIFF));
    else
        z(z'left downto ZDIFF) := signed(y);
    end if;
    return z;
end function;

-- Convert real value to table entry, with saturation.
function real2table(x: real) return output_t is
    variable xi : integer := integer(round(x));
begin
    if (xi < OUT_MIN) then
        return to_signed(OUT_MIN, OUT_WIDTH);
    elsif (xi < OUT_MAX) then
        return to_signed(xi, OUT_WIDTH);
    else
        return to_signed(OUT_MAX, OUT_WIDTH);
    end if;
end function;

-- Lookup table creation.
function create_table(mode: string) return table_t is
    constant N2RAD : real := MATH_2_PI / real(2**IN_WIDTH);
    variable scale : real := 0.0;
    variable tbl : table_t := (others => (others => '0'));
begin
    -- Default output scale?
    if OUT_SCALE > 0 then
        scale := real(OUT_SCALE);
    else
        scale := real(OUT_MAX);
    end if;
    -- Set each lookup table entry...
    if (mode = "cos") then
        -- Cosine requires no special-cases.
        for n in tbl'range loop         -- X = cos(theta)
            tbl(n) := real2table(scale * cos(real(n) * N2RAD));
        end loop;
    elsif (mode = "sin") then
        -- Sine overrides first entry (i.e., quadrant boundary).
        tbl(0) := real2table(scale);    -- X = +1.0
        for n in 1 to tbl'right loop    -- X = sin(theta)
            tbl(n) := real2table(scale * sin(real(n) * N2RAD));
        end loop;
    end if;
    return tbl;
end function;

constant TABLE_ROM : table_t := create_table(OUT_MODE);

-- State variables.
-- Note: Some registers have no initial value for better BRAM/URAM packing.
signal in_quad  : quad_t := (others => '0');
signal in_idx   : index_t := (others => '0');
signal ri_quad  : quad_t := (others => '0');
signal ri_idx   : index_t;
signal ro_quad  : quad_t := (others => '0');
signal ro_data  : output_t;
signal ro_flip  : std_logic := '0';
signal ro_zero  : std_logic := '0';
signal mod_data : output_t := (others => '0');

begin

-- Drive final output.
out_data <= mod_data;

-- Separate input into quadrants.
in_quad <= in_theta(IN_WIDTH-1 downto IN_WIDTH-2);
in_idx  <= in_theta(IDX_WIDTH-1 downto 0);

-- Main pipeline.
p_table : process(clk)
begin
    if rising_edge(clk) then
        -- Pipeline stage 3: Final output.
        if (OUT_MODE = "saw") then
            -- Special override for sawtooth mode.
            mod_data <= sawtooth(in_theta);
        elsif (ro_zero = '1') then
            -- Zero override, ignore lookup.
            mod_data <= (others => '0');
        elsif (ro_flip = '1') then
            -- Negative lookup.
            mod_data <= -ro_data;
        else
            -- Positive lookup.
            mod_data <= ro_data;
        end if;

        -- Pipeline stage 2: Lookup table and special-case flags.
        ro_quad <= ri_quad;

        if (IDX_WIDTH > 0) then
            ro_data <= TABLE_ROM(to_integer(ri_idx));
        end if;

        if (OUT_MODE = "cos") then
            ro_flip <= bool2bit(ri_quad = 1 or ri_quad = 2);
            ro_zero <= bool2bit((ri_idx = 0) and (ri_quad = 1 or ri_quad = 3));
        elsif (OUT_MODE = "sin") then
            ro_flip <= bool2bit(ri_quad = 2 or ri_quad = 3);
            ro_zero <= bool2bit((ri_idx = 0) and (ri_quad = 0 or ri_quad = 2));
        else
            ro_flip <= '0';
            ro_zero <= '0';
        end if;

        -- Pipeline stage 1: Per-quadrant table indexing.
        ri_quad <= in_quad;
        if (in_quad = 0 or in_quad = 2) then
            ri_idx <= in_idx;
        else
            ri_idx <= not (in_idx - 1);
        end if;
    end if;
end process;

end sine_table;
