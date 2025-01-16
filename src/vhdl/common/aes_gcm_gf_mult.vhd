--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------

-- iteratively computes the GF(2^128) product of 'a' and 'b'
-- using a serial/parallel algorithm, where 'b' is broken up into 'digit_size' blocks,
-- using the distributive property of Galois Fields, and one digit per clock cycle is processed.
-- https://ieeexplore.ieee.org/document/542803
-- as recommended in NIST's AES-GCM spec:
-- https://csrc.nist.rip/groups/ST/toolkit/BCM/documents/proposedmodes/gcm/gcm-spec.pdf

-- The product will be available 128/digit_size clock cycles after the input is loaded.
-- Uses AXI-style handshakes for inputs and output.
-- inputs are loaded synchronously, all 128 bits at once.

-- Internally uses MSbit-first ordering for GF(2^128), but
-- the AES standard uses LSbit-first ordering for GF(2^128),
-- so we allow ins and out to be bit reversed before calculating

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use work.common_functions.bool2bit;

entity aes_gcm_gf_mult is
    generic(
    digit_size      : natural := 8;     -- any divisor of 128, inclusive
    bit_reverse_a   : boolean := true;  -- set if in_a is MSbit-first
    bit_reverse_b   : boolean := true;  -- set if in_b is MSbit-first
    bit_reverse_ab  : boolean := true); -- set if out_ab is expected as MSbit-first
    port(
    -- in data (AXI-stream)
    in_data_a   : in  std_logic_vector(127 downto 0);
    in_data_b   : in  std_logic_vector(127 downto 0);
    in_valid    : in  std_logic;
    in_ready    : out std_logic := '1';
    -- out data (AXI-stream)
    out_data_ab : out std_logic_vector(127 downto 0);
    out_valid   : out std_logic := '0';
    out_ready   : in  std_logic;
    -- sys
    reset_p     : in std_logic;
    clk         : in std_logic);
end aes_gcm_gf_mult;

architecture gf128_mult of aes_gcm_gf_mult is

-- number of digits in a 128-bit element of GF(2^128)
constant NUM_DIGITS : integer := 128 / digit_size;
-- GF(2^128) generator polynomial is x^128 + x^7 + x^2 + x + 1
constant POLY       : std_logic_vector(7 downto 0) := x"87";

-- signals for the digit multiplier process
signal ab_partial : std_logic_vector(127 downto 0) := (others => '0');
-- tracks the current iteration of the digit multiplier
signal round      : integer range 0 to NUM_DIGITS := 0;

function reverse_bits(in_word : std_logic_vector(127 downto 0))
      return std_logic_vector is
      variable out_word : std_logic_vector(127 downto 0);
  begin
    for i in 0 to 127 loop
        out_word(i) := in_word(127-i);
    end loop;
  return out_word;
end;

-- function that calculates a single digit round
-- of the serial GF multiplication algorithm.
-- the inputs are controlled by the 'update_state' process
function calc_round_digit(
    a_rnd  : std_logic_vector(127 downto 0);
    b_rnd  : std_logic_vector(127 downto 0);
    p_rnd  : std_logic_vector(127 downto 0);
    rnd    : integer range 1 to NUM_DIGITS)
return std_logic_vector is
    variable tmp_product : std_logic_vector(127+digit_size downto 0);
    variable tmp_shift   : std_logic_vector(127+digit_size downto 0);
    variable zeros       : std_logic_vector(digit_size-1 downto 0) := (others => '0');
begin
    -- C' = C * x^D + \sum b_i * x^i * A
    tmp_product := p_rnd & zeros;
    tmp_shift   := zeros & a_rnd;
    for i in 0 to digit_size-1 loop
        if b_rnd(128 - rnd * digit_size + i) = '1' then
            tmp_product := tmp_product xor tmp_shift;
        end if;
        tmp_shift := tmp_shift(126+digit_size downto 0) & '0';
    end loop;
    -- modulo reduction
    -- for i >= 128, if c_i = 0, then add x^(128-i) * (x^7+x^2+x+1) to C'
    for i in digit_size-1 downto 0 loop
        if tmp_product(128 + i) = '1' then
            tmp_product(7+i downto i) := tmp_product(7+i downto i) xor POLY;
        end if;
    end loop;
    if rnd = NUM_DIGITS and bit_reverse_ab then
        return reverse_bits(tmp_product(127 downto 0));
    else
        return tmp_product(127 downto 0);
    end if;
end;

begin

in_ready    <= bool2bit(round = 0 or (round = NUM_DIGITS and out_ready = '1'));
out_valid   <= bool2bit(round = NUM_DIGITS);
out_data_ab <= ab_partial;

-- loads input, offloads output, updates combinatoric inputs,
-- and tracks the state (round/iteration) of the multiplication
update_state : process(clk)
    variable a_tmp, b_tmp : std_logic_vector(127 downto 0);
begin
    if rising_edge(clk) then
        -- load the inputs in the 0-th round (or the final round)
        -- equivalent to rdy = val = '1'
        if (reset_p = '1') then
            round <= 0;
        elsif (round = 0 or (round = NUM_DIGITS and out_ready = '1')) and in_valid = '1' then
            if bit_reverse_a  then
                a_tmp := reverse_bits(in_data_a);
            else
                a_tmp := in_data_a;
            end if;
            if bit_reverse_b then
                b_tmp := reverse_bits(in_data_b);
            else
                b_tmp := in_data_b;
            end if;
            ab_partial <= calc_round_digit(a_tmp, b_tmp, (127 downto 0 => '0'), 1);
            round      <= 1;
        elsif round = NUM_DIGITS and out_ready = '1' and in_valid = '0' then
            -- if the output is read but no new input is loaded, return to round 0
            round      <= 0;
        -- in a standard round, update the partial productwith the next digit of b
        elsif round > 0 and round < NUM_DIGITS then
            ab_partial <= calc_round_digit(a_tmp, b_tmp, ab_partial, round+1);
            round      <= round + 1;
        end if;
    end if;
end process;

end gf128_mult;
