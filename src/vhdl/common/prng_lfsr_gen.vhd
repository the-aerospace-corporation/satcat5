--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Linear feedback shift register (LFSR)
--
-- This block is a pseudorandom number generator (PRNG) using a linear
-- feedback shift register (LFSR).  The "leap-forward" technique allows
-- generation of several bits in each clock cycle if desired.  LFSR
-- parameters are specified using the functions in "prng_lfsr_common".
--
-- The block can be used as a source of industry standard pseudorandom
-- bit sequences (PRBS) used for bit-error-rate testing.  The corresponding
-- receiver with automatic synchronization is defined in "prng_lfsr_sync".
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.prng_lfsr_common.all;

entity prng_lfsr_gen is
    generic (
    IO_WIDTH    : positive;             -- Output bits per clock cycle
    LFSR_SPEC   : lfsr_spec_t;          -- LFSR specification
    MSB_FIRST   : boolean := true);     -- Bit order if IO_WIDTH > 1
    port (
    -- Output stream.
    out_data    : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_valid   : out std_logic;
    out_ready   : in  std_logic := '1';

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end prng_lfsr_gen;

architecture prng_lfsr_gen of prng_lfsr_gen is

-- Generate a leap-forward LFSR for the given polynomial.
constant LEAP_LFSR : lfsr_leap_t := create_leap(LFSR_SPEC, IO_WIDTH, MSB_FIRST);

-- LFSR state.
subtype lfsr_word is std_logic_vector(LFSR_SPEC.order-1 downto 0);
signal lfsr_state   : lfsr_word := (others => '1');
signal lfsr_valid   : std_logic := '0';

begin

-- Drive top-level outputs.
out_data    <= leap_out(LEAP_LFSR, lfsr_state);
out_valid   <= lfsr_valid;

-- Update the LFSR state using the leap-forward matrix.
p_lfsr : process(clk)
begin
    if rising_edge(clk) then
        lfsr_valid <= not reset_p;
        if (reset_p = '1') then
            lfsr_state <= (others => '1');
        elsif (lfsr_valid = '1' and out_ready = '1') then
            lfsr_state <= leap_next(LEAP_LFSR, lfsr_state);
        end if;
    end if;
end process;

end prng_lfsr_gen;
