--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Shared types and functions used for working with linear feedback shift
-- registers (LFSRs).  See also: "prng_lfsr_gen" and "prng_lfsr_sync".
--
-- An LFSR is defined by a polynomial and the output polarity.  For these
-- functions, the preferred format is the standard mathematical form, listing
-- all terms including the implied "1".  As a result, an Nth-order polynomial
-- is specified by a std_logic_vector with N+1 bits.  Terms are listed
-- MSB-first, e.g., x^7 + x^6 + 1 is "11000001".
--
-- For compatibility with VHDL99, the records must be fully constrained.
-- The maximum width is predefined and variable-width fields are padded.
--
-- Provided definitions include configurations used for industry-standard
-- pseudorandom bit sequences (PRBS) used for bit-error-rate testing.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

package prng_lfsr_common is
    -- Define the maximum supported LFSR width.
    constant LFSR_MAX_ORDER : positive := 32;
    subtype lfsr_poly_t is std_logic_vector(LFSR_MAX_ORDER downto 0);
    subtype lfsr_matrix_t is std_logic_vector(LFSR_MAX_ORDER*LFSR_MAX_ORDER-1 downto 0);

    -- Basic LFSR specification is polynomial and polarity only.
    type lfsr_spec_t is record
        order:  positive;           -- Order for this polymial
        poly:   lfsr_poly_t;        -- Polynomial in padded form
        inv:    std_logic;          -- Invert output?
    end record;

    constant LFSR_INVALID : lfsr_spec_t := (1, (others => 'X'), 'X');

    -- Generate an LFSR specification from a polynomial.
    function create_lfsr(
        poly:   std_logic_vector;   -- Polynomial in standard form
        inv:    boolean := false)   -- Invert output?
        return lfsr_spec_t;

    -- Industry-standard PRBS sequences (e.g., PRBS-9, PRBS-23, etc.)
    -- as defined by ITU-T O.150 Section 5 or widely used de-facto standards.
    function create_prbs(order: positive) return lfsr_spec_t;

    -- Advance an LFSR state-vector by one timestep.
    -- The state vector should be of type std_logic_vector(order-1 downto 0).
    -- The data is stored MSB-first (current output in MSB, feedback into LSB).
    function lfsr_next(
        lfsr: lfsr_spec_t;          -- LFSR specification
        state: std_logic_vector)    -- Current state vector (width = order)
        return std_logic_vector;    -- New state vector (width = order)

    -- Given an LFSR state-vector, return the next output bit.
    function lfsr_out(
        lfsr: lfsr_spec_t;          -- LFSR specification
        state: std_logic_vector)    -- Current state vector (width = order)
        return std_logic;           -- Next output bit

    -- A leap-forward LFSR allows generation of multiple bits each clock cycle.
    -- See also: P.P. Chu and R.E. Jones, "Design Techniques of FPGA Based
    --  Random Number Generator." Mil & Aero Applications 1999, Section V.
    --  https://citeseerx.ist.psu.edu/document?repid=rep1&type=pdf&doi=9c3d5c5c541a527013f676a60a4b08235c2885fd
    type lfsr_leap_t is record
        lfsr:   lfsr_spec_t;        -- LFSR specification
        steps:  positive;           -- Output bits per "leap"
        msb:    boolean;            -- Output order MSB-first?
        mat_o:  lfsr_matrix_t;      -- Leap-ahead matrix ("order")
        mat_s:  lfsr_matrix_t;      -- Leap-ahead matrix ("steps")
    end record;

    -- Create a leap-forward LFSR from a basic specification.
    function create_leap(
        lfsr:   lfsr_spec_t;        -- LFSR specification
        steps:  positive;           -- Requested bits per clock cycle
        msb:    boolean := false)   -- Output order MSB-first?
        return lfsr_leap_t;

    -- Leap-forward matrix generation (internal use only).
    function create_matrix(
        lfsr:   lfsr_spec_t;        -- LFSR specification
        steps:  positive)           -- Requested leap-ahead distance
        return lfsr_matrix_t;       -- Leap-ahead matrix (A^n)

    -- Apply a leap-forward matrix to a state vector (internal use only).
    function apply_matrix(
        matrix: lfsr_matrix_t;      -- Leap-ahead matrix (see "create_matrix")
        state:  std_logic_vector)   -- Current state vector (width = order)
        return std_logic_vector;    -- New state vector (width = order)

    -- Apply the "inv" and "msb" flags (note: this function is its own inverse).
    function leap_format(
        leap:   lfsr_leap_t;        -- Leap-LFSR specification
        data:   std_logic_vector)   -- Original data
        return std_logic_vector;    -- Modified data

    -- Advance a leap-LFSR state-vector by a N steps.
    function leap_next(
        leap:   lfsr_leap_t;        -- Leap-LFSR specification
        state:  std_logic_vector)   -- Current state vector (width = order)
        return std_logic_vector;    -- New state vector (width = order)

    -- The state vector should be of type std_logic_vector(order-1 downto 0).
    -- (This is trivial if skip + width <= length(state), hard otherwise.)
    function leap_out(
        leap:   lfsr_leap_t;        -- Leap-LFSR specification
        state:  std_logic_vector;   -- Current state vector (width = order)
        skip:   natural := 0)       -- Skip-ahead N bits before first output
        return std_logic_vector;    -- Next N output bits

    -- As "leap_out", but ignores formatting flags (internal use only).
    function leap_raw(
        matrix: lfsr_matrix_t;      -- Leap-ahead matrix (steps = order)
        state:  std_logic_vector;   -- Current state vector (width = order)
        width:  positive;           -- Output bits to generate
        skip:   natural)            -- Skip-ahead N bits before first output
        return std_logic_vector;    -- Next N state bits (unformatted output)

end package;

package body prng_lfsr_common is
    function create_lfsr(poly: std_logic_vector; inv: boolean := false)
        return lfsr_spec_t is
        variable tmp : lfsr_poly_t := (others => 'X');
    begin
        -- Sanity checks on the input polynomial.
        assert (poly'left <= LFSR_MAX_ORDER)
            report "Polynomial size exceeds LFSR_MAX_ORDER." severity error;
        assert (poly(poly'left) = '1')
            report "Polynomial is not in standard form." severity error;
        assert ((poly'right = 1) or (poly'right = 0 and poly(0) = '1'))
            report "Polynomial is not in standard form." severity error;
        -- Copy one bit at a time for explicit to/downto conversion.
        for b in poly'range loop
            tmp(b) := poly(b);
        end loop;
        -- Return the complete LFSR specification.
        return (poly'length-1, tmp, bool2bit(inv));
    end function;

    function create_prbs(order: positive) return lfsr_spec_t is
        -- Polynomials of various lengths defined by ITU-T O.150, Section 5.
        -- Standard form: a bit in the Nth position indicates the x^n term.
        constant POLY_PRBS9 : std_logic_vector(9 downto 0)
            := "1000100001";  -- x^9 + x^5 + 1 (positive)
        constant POLY_PRBS11 : std_logic_vector(11 downto 0)
            := "101000000001";  -- x^11 + x^9 + 1 (positive)
        constant POLY_PRBS15 : std_logic_vector(15 downto 0)
            := "1100000000000001";  -- x^15 + x^14 + 1 (inverted)
        constant POLY_PRBS20 : std_logic_vector(20 downto 0)
            := "100000000000000001001";  -- x^20 + x^3 + 1 (positive)
        constant POLY_PRBS23 : std_logic_vector(23 downto 0)
            := "100001000000000000000001";  -- x^23 + x^18 + 1 (inverted)
        constant POLY_PRBS29 : std_logic_vector(29 downto 0)
            := "101000000000000000000000000001";  -- x^29 + x^27 + 1 (inverted)
        constant POLY_PRBS31 : std_logic_vector(31 downto 0)
            := "10010000000000000000000000000001";  -- x^31 + x^28 + 1 (inverted)
        -- Additional polynomials by industry convention:
        constant POLY_PRBS7 : std_logic_vector(7 downto 0)
            := "11000001";  -- x^7 + x^6 + 1 (inverted)
        constant POLY_PRBS17 : std_logic_vector(17 downto 0)
            := "100100000000000001";  -- x^17 + x^14 + 1 (positive)
    begin
        case order is
            when 7 =>   return create_lfsr(POLY_PRBS7, true);
            when 9 =>   return create_lfsr(POLY_PRBS9, false);
            when 11 =>  return create_lfsr(POLY_PRBS11, false);
            when 15 =>  return create_lfsr(POLY_PRBS15, true);
            when 17 =>  return create_lfsr(POLY_PRBS17, false);
            when 20 =>  return create_lfsr(POLY_PRBS20, false);
            when 23 =>  return create_lfsr(POLY_PRBS23, true);
            when 29 =>  return create_lfsr(POLY_PRBS29, true);
            when 31 =>  return create_lfsr(POLY_PRBS31, true);
            when others => return LFSR_INVALID;
        end case;
    end function;

    function lfsr_next(lfsr: lfsr_spec_t; state: std_logic_vector)
        return std_logic_vector is
        variable x : std_logic := '0';
        variable y : std_logic_vector(state'range);
    begin
        assert (state'length = lfsr.order)
            report "State vector does not match LFSR." severity error;
        -- Calculate the tapped-XOR feedback term:
        for b in state'range loop
            x := x xor (state(b) and lfsr.poly(b+1));
        end loop;
        -- Shift everything left by one, feedback into LSB.
        y := state(state'left-1 downto 0) & x;
        return y;
    end function;

    function lfsr_out(lfsr: lfsr_spec_t; state: std_logic_vector)
        return std_logic is
    begin
        -- Output is the MSB of the state vector, optionally inverted.
        return state(lfsr.order-1) xor lfsr.inv;
    end function;

    function create_leap(lfsr: lfsr_spec_t; steps: positive; msb: boolean := false)
        return lfsr_leap_t is
        variable mat_o : lfsr_matrix_t := create_matrix(lfsr, lfsr.order);
        variable mat_s : lfsr_matrix_t := create_matrix(lfsr, steps);
    begin
        return (lfsr, steps, msb, mat_o, mat_s);
    end function;

    function create_matrix(
        lfsr:   lfsr_spec_t;        -- LFSR specification
        steps:  positive)           -- Requested leap-ahead distance
        return lfsr_matrix_t is
        subtype row is std_logic_vector(lfsr.order-1 downto 0);
        type mat is array(lfsr.order-1 downto 0) of row;
        variable row_temp : row := (others => '0');
        variable mat_incr : mat := (others => (others => '0'));
        variable mat_prev : mat := (others => (others => '0'));
        variable mat_next : mat := (others => (others => '0'));
        variable mat_flat : lfsr_matrix_t := (others => '0');
    begin
        -- Define the increment-by-one matrix, A.
        -- First row is the feedback term, all others simply right-shift.
        mat_incr(0) := lfsr.poly(lfsr.order downto 1);
        for r in 1 to lfsr.order-1 loop
            mat_incr(r)(r-1) := '1';
        end loop;
        -- Iterative modulo-2 matrix multiply, i.e., A^(n+1) = A * A^n.
        mat_next := mat_incr;
        for n in 2 to steps loop
            mat_prev := mat_next;
            for r in 0 to lfsr.order-1 loop
                for c in 0 to lfsr.order-1 loop
                    for i in 0 to lfsr.order-1 loop
                        row_temp(i) := mat_prev(r)(i) and mat_incr(i)(c);
                    end loop;
                    mat_next(r)(c) := xor_reduce(row_temp);
                end loop;
            end loop;
        end loop;
        -- Flatten and pad the leap-forward matrix A^N.
        -- (VHDL-93 doesn't allow indefinite array-of-arrays.)
        for r in 0 to lfsr.order-1 loop
            mat_flat((r+1)*lfsr.order-1 downto r*lfsr.order) := mat_next(r);
        end loop;
        return mat_flat;
    end function;

    function apply_matrix(matrix: lfsr_matrix_t; state: std_logic_vector)
        return std_logic_vector is
        constant order : positive := state'length;
        variable x : std_logic_vector(state'range) := (others => 'U');
        variable y : std_logic_vector(state'range) := (others => 'U');
    begin
        assert (matrix'length >= order * order)
            report "State vector does not match leap matrix." severity error;
        for n in state'range loop
            x := matrix((n+1)*order-1 downto n*order);  -- Nth row of matrix
            y(n) := xor_reduce(state and x);            -- Nth output bit
        end loop;
        return y;
    end function;

    function leap_format(leap: lfsr_leap_t; data: std_logic_vector)
        return std_logic_vector is
        variable mask : std_logic_vector(data'range) := (others => leap.lfsr.inv);
    begin
        if leap.msb then
            return data xor mask;
        else
            return flip_vector(data xor mask);
        end if;
    end function;

    function leap_next(leap: lfsr_leap_t; state: std_logic_vector)
        return std_logic_vector is
    begin
        assert (state'length = leap.lfsr.order)
            report "State vector does not match LFSR." severity error;
        return apply_matrix(leap.mat_s, state);
    end function;

    function leap_out(leap: lfsr_leap_t; state: std_logic_vector; skip: natural := 0)
        return std_logic_vector is
    begin
        assert (state'length = leap.lfsr.order)
            report "State vector does not match LFSR." severity error;
        return leap_format(leap, leap_raw(leap.mat_o, state, leap.steps, skip));
    end function;

    function leap_raw(
        matrix: lfsr_matrix_t;      -- Leap-ahead matrix (steps = order)
        state:  std_logic_vector;   -- Current state vector (width = order)
        width:  positive;           -- Output bits to generate
        skip:   natural)            -- Skip-ahead N bits before first output
        return std_logic_vector is
        constant order : positive := state'length;
        constant start : integer := order - skip;
        variable result : std_logic_vector(width-1 downto 0);
        variable state2 : std_logic_vector(order-1 downto 0);
    begin
        if skip + width <= order then
            -- Trival case draws bits directly from the shift register.
            result := state(start-1 downto start-width);
        elsif skip < order then
            -- Partial result is concatenated recursively.
            state2 := apply_matrix(matrix, state);
            result := state(start-1 downto 0)
                    & leap_raw(matrix, state2, width-start, 0);
        else
            -- Advance state recursively until we reach requested offset.
            state2 := apply_matrix(matrix, state);
            result := leap_raw(matrix, state2, width, skip-order);
        end if;
        return result;
    end function;
end package body;
