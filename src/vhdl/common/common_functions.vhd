--------------------------------------------------------------------------
-- Copyright 2020-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Generic functions that are useful to nearly any VHDL block
--

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

package COMMON_FUNCTIONS is
-- Functions
    -- Convert a standard logic vector to an unsigned integer
    function U2I(a: std_logic_vector) return natural;
    -- Convert unsigned vector to an integer.
    function U2I(a: unsigned) return natural;
    -- Convert a standard logic (bit) to an integer: '0'->0, '1'->1
    function U2I(a: std_logic) return natural;
    -- Convert a boolean value to an integer: false->0, true->1
    function U2I(a: boolean) return natural;
    -- Convert an integer to a L-bit standard logic vector
    function I2S(a: natural; w: natural) return std_logic_vector;
    -- Convert real to a L-bit signed (including W > 32)
    function R2S(a: real; w: natural) return signed;
    -- Convert real to a L-bit unsigned (including W > 32)
    function R2U(a: real; w: natural) return unsigned;
    -- As R2U, but with rounding instead of truncation.
    function R2UR(a: real; w: natural) return unsigned;
    -- Convert signed vector to an integer.
    function S2I(a: signed) return integer;
    -- Convert signed to real, avoiding integer overflow.
    function S2R(a: signed) return real;
    -- Convert unsigned to real, avoiding integer overflow.
    function U2R(a: unsigned) return real;
    -- Convert a boolean to a bit, false->'0', true->'1'
    function bool2bit(a: boolean) return std_logic;

    -- Resize a std_logic_vector using the rules for UNSIGNED
    function resize(a: std_logic_vector; w: natural) return std_logic_vector;

    -- Saturate an unsigned input to N output bits.
    function saturate(a: unsigned; w: natural) return unsigned;

    -- Add the two inputs, with saturation on overflow.
    function saturate_add(a, b: unsigned; w: natural) return unsigned;

    -- Add the two inputs, sizing the result to prevent overflow.
    function extend_add(a, b: unsigned) return unsigned;
    function extend_sub(a, b: unsigned) return signed;

    -- Perform an XOR reduction
    -- (i.e., Return '1' if an odd number of input bits are '1')
    function xor_reduce(a: std_logic_vector) return std_logic;
    -- Return '1' if any of the bits in the input are '1'
    function or_reduce(a: std_logic_vector) return std_logic;
    -- Return '1' if all the bits in the input are '1'
    function and_reduce(a: std_logic_vector) return std_logic;

    -- Are all bits in the input the same? (i.e., all '0' or all '1'.)
    function same_bits(a: std_logic_vector) return std_logic;

    -- X / Y, rounded up, down, or to the nearest integer.
    function div_ceil(a: natural; b: positive) return natural;
    function div_floor(a: natural; b: positive) return natural;
    function div_round(a: natural; b: positive) return natural;

    -- Log2(x), rounded up or down.
    function log2_ceil(a: natural) return integer;
    function log2_floor(a: natural) return integer;

    -- Return the maximum of the two inputs
    function int_max(a,b: integer) return integer;
    function real_max(a,b: real) return real;
    -- Return the minimum of the two inputs
    function int_min(a,b: integer) return integer;
    function real_min(a,b: real) return real;
    -- Return the least common multiple of two inputs
    function int_lcm(a,b: positive) return positive;

    -- Return the input value if "en" is true, zero otherwise.
    function value_else_zero(x: natural; en: boolean) return natural;
    function value_else_zero(x: real; en: boolean) return real;

    -- Reverse the bit-order of a vector.
    function flip_vector(x: std_logic_vector) return std_logic_vector;

    -- Bit-shift functions for std_logic_vector, using rules for unsigned.
    function shift_left(x: std_logic_vector; b: integer) return std_logic_vector;
    function shift_right(x: std_logic_vector; b: integer) return std_logic_vector;

    -- Count the number of '0' or '1' bits in the input.
    function count_zeros(x : std_logic_vector) return natural;
    function count_ones(x : std_logic_vector) return natural;

    -- Given a bit-mask with exactly one set bit, return its index.
    function one_hot_decode(x: std_logic_vector; w: positive) return unsigned;

    -- Given a bit-index, return a bit-mask with exactly one set bit.
    function one_hot_encode(n: natural; w: positive) return std_logic_vector;

    -- Given a bit-mask, return true if more than one bit is set.
    function one_hot_error(x: std_logic_vector) return std_logic;

    -- Given a bit-mask, return the lowest-indexed '1' bit (if any).
    function priority_encoder(x: std_logic_vector) return natural;

    -- Convert integer quantity d = [0..N] to a B-bit fraction [0..2^B-1].
    function scale_fraction(x,n,b: natural) return unsigned;

    -- Map all std_logic values (0/1/H/L/Z/X/U) to either '0' or '1'.
    function to_01_vec(a: std_logic_vector) return std_logic_vector;
    function to_01_vec(a: unsigned)         return unsigned;
    function to_01_vec(a: signed)           return signed;
    function to_01_std(a: std_logic)        return std_logic;

    -- Convert std_logic_vector to a string, for debugging.
    function slv_to_string(a: std_logic_vector) return string;

    -- Check string equality
    function str_equal(str1: string; str2: string) return boolean;

    -- Given clock rate and baud rate, calculate clocks per bit.
    function clocks_per_baud(
        clkref_hz   : positive;
        baud_hz     : positive;
        round_up    : boolean := true)
        return positive;

    -- Wrapper for "clocks_per_baud" that checks for 5% error tolerance.
    function clocks_per_baud_uart(
        clkref_hz   : positive;
        baud_hz     : positive)
        return positive;

    -- AXI address-conversion: Convert raw byte-address to a word-index.
    function convert_address(
        x : std_logic_vector;   -- AXI byte address
        b : natural;            -- Base address (often zero)
        w : positive)           -- Width of output
        return unsigned;
end package;

package body COMMON_FUNCTIONS is
    function U2I(a: std_logic_vector) return natural is
    begin
        return to_integer(unsigned(to_01_vec(a)));
    end;
    function U2I(a: unsigned) return natural is
    begin
        return to_integer(to_01_vec(a));
    end;
    function U2I(a: std_logic) return natural is
    begin
        if a = '0' then return 0; else return 1; end if;
    end;
    function U2I(a: boolean) return natural is
    begin
        if a then return 1; else return 0; end if;
    end function;

    function I2S(a: natural; w: natural) return std_logic_vector is
    begin
        return std_logic_vector(TO_UNSIGNED(a, w));
    end;

    function R2S(a: real; w: natural) return signed is
        constant ONE : unsigned(w-1 downto 0) := to_unsigned(1, w);
        variable tmp : unsigned(w-1 downto 0) := r2u(abs(a), w);
    begin
        if (a < 0.0) then   -- Two's complement negation
            return signed((not tmp) + ONE);
        else
            return signed(tmp);
        end if;
    end function;

    function R2U(a: real; w: natural) return unsigned is
        variable result : unsigned(w-1 downto 0) := (others => '0');
        variable brem   : real := a;            -- Bit-by-bit remainder
        variable bscale : real := 2.0 ** w;     -- Scale of next bit
    begin
        if (w < 32) then
            -- Simple direct conversion for smaller integers.
            result := to_unsigned(integer(a), w);
        else
            -- Manual workaround for VHDL'93 signed integer overflow limit.
            assert (a < bscale) report "R2U overflow" severity warning;
            for b in w-1 downto 0 loop
                bscale := 0.5 * bscale;
                if (brem >= bscale) then
                    result(b) := '1';
                    brem := brem - bscale;
                end if;
            end loop;
        end if;
        return result;
    end function;

    function R2UR(a: real; w: natural) return unsigned is
    begin
        return R2U(a + 0.5, w);
    end function;

    function S2I(a: signed) return integer is
    begin
        return to_integer(to_01_vec(a));
    end function;

    function S2R(a: signed) return real is
        variable x : real := 0.0;
    begin
        -- Workaround for XSIM bug, assign below rather than in function init.
        x := u2r(unsigned(abs(a)));
        if (a < 0) then
            return -x;
        else
            return x;
        end if;
    end function;

    function U2R(a: unsigned) return real is
        variable x : unsigned(a'length-1 downto 0) := a;
        variable accum  : real := 0.0;      -- Bit-by-bit summation
        variable bscale : real := 1.0;      -- Scale of next bit
    begin
        if (a'length < 32) then
            -- Simple direct conversion for smaller inputs.
            return real(to_integer(x));
        else
            -- Manual workaround for VHDL'93 signed integer overflow limit.
            for b in 0 to a'length-1 loop
                if (x(b) = '1') then
                    accum := accum + bscale;
                else
                end if;
                bscale := bscale * 2.0;
            end loop;
            return accum;
        end if;
    end function;

    function bool2bit(a: boolean)   return std_logic is
    begin
        if a then return '1'; else return '0'; end if;
    end;

    function resize(a: std_logic_vector; w: natural) return std_logic_vector is
    begin
        return std_logic_vector(resize(UNSIGNED(a), w));
    end;

    function saturate(a: unsigned; w: natural) return unsigned is
        constant MAX_POS : unsigned(w-1 downto 0) := (others => '1');
    begin
        if (a >= MAX_POS) then
            return MAX_POS;
        else
            return resize(a, w);
        end if;
    end function;

    function saturate_add(a, b: unsigned; w: natural) return unsigned is
    begin
        -- Calculate saturated output from the overflow-free sum.
        return saturate(extend_add(a, b), w);
    end;

    function extend_add(a, b: unsigned) return unsigned is
        -- Calculate sum with enough width to never overflow.
        constant ws  : natural := 1 + int_max(a'length, b'length);
        variable sum : unsigned(ws-1 downto 0) := resize(a, ws) + resize(b, ws);
    begin
        return sum;
    end;

    function extend_sub(a, b: unsigned) return signed is
        -- Calculate sum with enough width to never overflow.
        constant ws  : natural := 1 + int_max(a'length, b'length);
        variable dif : signed(ws-1 downto 0) := signed(resize(a, ws)) - signed(resize(b, ws));
    begin
        return dif;
    end;

    function xor_reduce(a: std_logic_vector) return std_logic is
        variable result : std_logic := '0';
    begin
        for i in a'range loop
            result := result xor a(i);
        end loop;
        return result;
    end;

    function or_reduce(a: std_logic_vector) return std_logic is
        variable z : std_logic := '0';
    begin
        for i in a'range loop
            z := z or a(i);
        end loop;
        return z;
    end;

    function and_reduce(a: std_logic_vector) return std_logic is
        variable z : std_logic := '1';
    begin
        for i in a'range loop
            z := z and a(i);
        end loop;
        return z;
    end;

    function same_bits(a: std_logic_vector) return std_logic is
        variable z : std_logic := '1';
    begin
        for i in a'range loop
            z := z and (a(i) xnor a(a'left));
        end loop;
        return z;
    end;

    function div_ceil(a: natural; b: positive) return natural is
    begin
        return (a + b - 1) / b;
    end function;

    function div_floor(a: natural; b: positive) return natural is
    begin
        return a / b;
    end function;

    function div_round(a: natural; b: positive) return natural is
    begin
        return (a + b / 2) / b;
    end function;

    function log2_ceil(a: natural) return integer is
    begin
        return log2_floor(2*a-1);
    end;

    function log2_floor(a: natural) return integer is
        variable b, l: natural;
    begin
        assert a > 0 report "Outside of log2 range" severity failure;
        b := a; l := 0;
        while b > 1 loop
            l := l + 1; b := b / 2;
        end loop;
        return l;
    end;

    function int_max(a, b: integer) return integer is
    begin
        if a > b then return a;
        else return b;
        end if;
    end;

    function int_min(a, b: integer) return integer is
    begin
        if a < b then return a;
        else return b;
        end if;
    end;

    function real_max(a, b: real) return real is
    begin
        if a > b then return a;
        else return b;
        end if;
    end;

    function real_min(a, b: real) return real is
    begin
        if a < b then return a;
        else return b;
        end if;
    end;

    function int_lcm(a,b: positive) return positive is
        -- Set a reasonable initial guess.
        -- (Immediate solution if A is a multiple of B or vice-versa.)
        variable accum_a : positive := a * int_max(1, b/a);
        variable accum_b : positive := b * int_max(1, a/b);
    begin
        -- Keep incrementing the smaller accumulator until they match.
        -- (This function is not intended to be synthesizable.)
        while accum_a /= accum_b loop
            if (accum_a < accum_b) then
                accum_a := accum_a + a;
            else
                accum_b := accum_b + b;
            end if;
        end loop;
        return accum_a;
    end;

    function value_else_zero(x: natural; en: boolean) return natural is
    begin
        if en then
            return x;
        else
            return 0;
        end if;
    end function;

    function value_else_zero(x: real; en: boolean) return real is
    begin
        if en then
            return x;
        else
            return 0.0;
        end if;
    end function;

    function flip_vector(x: std_logic_vector) return std_logic_vector is
        variable y : std_logic_vector(x'length-1 downto 0) := x;
        variable z : std_logic_vector(x'length-1 downto 0);
    begin
        for b in z'range loop
            z(b) := y(y'left-b);
        end loop;
        return z;
    end function;

    function shift_left(x: std_logic_vector; b: integer) return std_logic_vector is
    begin
        return std_logic_vector(shift_left(unsigned(x), b));
    end function;

    function shift_right(x: std_logic_vector; b: integer) return std_logic_vector is
    begin
        return std_logic_vector(shift_right(unsigned(x), b));
    end function;

    function count_zeros(x : std_logic_vector) return natural is
        variable tmp : integer range 0 to x'length := 0;
    begin
        for n in x'range loop
            if (x(n) = '0') then
                tmp := tmp + 1;
            end if;
        end loop;
        return tmp;
    end function;

    function count_ones(x : std_logic_vector) return natural is
        variable tmp : integer range 0 to x'length := 0;
    begin
        for n in x'range loop
            if (x(n) = '1') then
                tmp := tmp + 1;
            end if;
        end loop;
        return tmp;
    end function;

    function one_hot_decode(x: std_logic_vector; w: positive) return unsigned is
        variable tmp : unsigned(w-1 downto 0) := (others => '0');
    begin
        -- Sanity-check on requested width.
        assert (2**w >= x'length);
        -- OR-tree method uses fewer resources than a true priority encoder.
        for n in x'range loop
            if (x(n) = '1') then
                tmp := tmp or to_unsigned(n, w);
            end if;
        end loop;
        return tmp;
    end function;

    function one_hot_encode(n: natural; w: positive) return std_logic_vector is
        variable tmp : std_logic_vector(w-1 downto 0) := (others => '0');
    begin
        for b in tmp'range loop
            tmp(b) := bool2bit(b = n);
        end loop;
        return tmp;
    end function;

    function one_hot_error(x: std_logic_vector) return std_logic is
        variable tmp : std_logic := '0';
    begin
        for n in x'range loop
            if (x(n) = '1' and tmp = '1') then
                return '1';
            end if;
            tmp := tmp or x(n);
        end loop;
        return '0';
    end function;

    function priority_encoder(x: std_logic_vector) return natural is
        constant NMAX : natural := x'length - 1;
    begin
        for n in 0 to NMAX-1 loop
            if (x(n) = '1') then
                return n;
            end if;
        end loop;
        return NMAX;
    end function;

    function scale_fraction(x,n,b: natural) return unsigned is
        -- Estimate required precision for intermediate calculations.
        constant shift : natural := int_max(b, 8 + log2_ceil(n));
        constant total : natural := b + shift;
        -- Direct method: floor((x * 2^b) / (n+1))
        -- For constant N, simpler to precalculate inverse and multiply.
        constant inv : natural := div_floor(2**total, n+1);
        variable y : unsigned(total-1 downto 0) :=
            shift_right(to_unsigned(x * inv, total), shift);
    begin
        return y(b-1 downto 0);
    end;

    -- This function is useful to avoid having X's in simulation when feedback
    -- loops are present.  Note that it synthesizes to no hardware.
    function to_01_vec(a: std_logic_vector) return std_logic_vector is
        variable result : std_logic_vector(a'range) := a;
    begin
-- translate_off
        for i in a'range loop
            if(a(i) = '1' or a(i) = 'H') then
                result(i) := '1';
            else
                result(i) := '0';
            end if;
        end loop;
-- translate_on
        return result;
    end;

    function to_01_vec(a: unsigned) return unsigned is
    begin
        return unsigned(to_01_vec(std_logic_vector(a)));
    end function;

    function to_01_vec(a: signed) return signed is
    begin
        return signed(to_01_vec(std_logic_vector(a)));
    end function;

    function to_01_std(a: std_logic) return std_logic is
        variable result : std_logic := a;
    begin
-- translate_off
        if(a = '1' or a = 'H') then
            result := '1';
        else
            result := '0';
        end if;
-- translate_on
        return result;
    end;

    function slv_to_string(a: std_logic_vector) return string is
        variable result : string(1 to a'length) := (others => NUL);
        variable wr_idx : positive := 1;
    begin
-- translate_off
        for n in a'range loop
            -- Value of std_logic'image(x) is three characters: '1', '0', etc.
            -- Select the interesting character, i.e., index 2 of [1, 2, 3].
            result(wr_idx) := std_logic'image(a(n))(2);
            wr_idx := wr_idx + 1;   -- Input vector may be "to" or "downto"
        end loop;
-- translate_on
        return result;
    end function;

    function str_equal(str1: string; str2:string ) return boolean is
    begin
        -- String equality operator only works on strings of same length
        if str1'length /= str2'length then
            return false;
        else
            return (str1 = str2);
        end if;
    end function;

    function clocks_per_baud(
        clkref_hz   : positive;
        baud_hz     : positive;
        round_up    : boolean := true)
        return positive is
    begin
        if (round_up) then
            return int_max(1, div_ceil(clkref_hz, baud_hz));
        else
            return int_max(1, div_round(clkref_hz, baud_hz));
        end if;
    end function;

    function clocks_per_baud_uart(
        clkref_hz   : positive;
        baud_hz     : positive)
        return positive
    is
        -- Calculate clocks per bit-period (round nearest), then
        -- back-calculate the baud rate that was actually achieved.
        constant CLKDIV : positive := clocks_per_baud(CLKREF_HZ, BAUD_HZ, false);
        constant ACTUAL : positive := clocks_per_baud(CLKREF_HZ, CLKDIV, false);
    begin
        -- Confirm achieved rate is within spec.
        assert ((100 * baud_hz < 105 * ACTUAL)
            and (100 * baud_hz >  95 * ACTUAL))
            report "Invalid UART rate (max error 5%)" severity error;
        return CLKDIV;
    end function;

    function convert_address(
        x : std_logic_vector;   -- AXI byte address
        b : natural;            -- Base address (often zero)
        w : positive)           -- Width of output
        return unsigned
    is
        -- Subtract offset / base-address.
        variable xb : unsigned(w+1 downto 0)
            := resize(unsigned(x) - to_unsigned(b, x'length), w+2);
        -- Divide-by-four converts byte address to word-address.
        -- Ignore MSBs; not all implementations force them to zero.
        variable xu : unsigned(w-1 downto 0) := xb(w+1 downto 2);
    begin
        return xu;
    end function;
end package body;
