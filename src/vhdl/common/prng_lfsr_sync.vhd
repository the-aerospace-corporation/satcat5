--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Auto-synchronizing linear feedback shift register (LFSR)
--
-- This block synchronizes to a predetermined pseudorandom bit sequence
-- (PRBS) generated by a linear feedback shift register (LFSR).  Once
-- synchronized, the output can be compared against the received sequence
-- to measure bit-error-rate (BER).
--
-- After reset, the block consumes the first few input words to attempt
-- synchronization. Subsequent outputs are generated in lockstep with the
-- input. If the generated reference diverges from the input stream, then
-- higher-level control should reset this block to reattempt synchronziation.
-- LFSR parameters must match those provided to "prng_lfsr_gen" or an
-- equivalent source.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.prng_lfsr_common.all;

entity prng_lfsr_sync is
    generic (
    IO_WIDTH    : positive;             -- Output bits per clock cycle
    LFSR_SPEC   : lfsr_spec_t;          -- LFSR specification
    MSB_FIRST   : boolean := true);     -- Bit order if IO_WIDTH > 1
    port (
    -- Input is the received signal.
    in_rcvd     : in  std_logic_vector(IO_WIDTH-1 downto 0);
    in_write    : in  std_logic;

    -- Output is the local reference and a matched-delay copy of the input.
    out_local   : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_rcvd    : out std_logic_vector(IO_WIDTH-1 downto 0);
    out_write   : out std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end prng_lfsr_sync;

architecture prng_lfsr_sync of prng_lfsr_sync is

-- Generate a leap-forward LFSR for the given polynomial.
constant LEAP_LFSR : lfsr_leap_t := create_leap(LFSR_SPEC, IO_WIDTH, MSB_FIRST);

-- Other constants and convenience types.
subtype io_word is std_logic_vector(IO_WIDTH-1 downto 0);
subtype lfsr_word is std_logic_vector(LFSR_SPEC.order-1 downto 0);
constant SYNC_WORDS : positive := div_ceil(LFSR_SPEC.order, IO_WIDTH);

-- LFSR state.
signal in_convert   : io_word;
signal lfsr_count   : integer range 0 to SYNC_WORDS := 0;
signal lfsr_outreg  : io_word := (others => '0');
signal lfsr_state   : lfsr_word := (others => '1');

-- Matched delay.
signal dly1_rcvd    : io_word := (others => '0');
signal dly1_write   : std_logic := '0';

begin

-- Convert input to match internal format.
in_convert <= leap_format(LEAP_LFSR, in_rcvd);

-- Update the LFSR state...
p_lfsr : process(clk)
begin
    if rising_edge(clk) then
        -- Predict the *next* LFSR output.
        -- (Note one-cycle look-ahead using the "skip" parameter.)
        if (in_write = '1') then
            lfsr_outreg <= leap_out(LEAP_LFSR, lfsr_state, LFSR_SPEC.order);
        end if;

        -- Load shift-register, then update in lockstep.
        if (reset_p = '1') then
            -- Global reset.
            lfsr_count  <= 0;
            lfsr_state  <= (others => '1');
        elsif (in_write = '1' and lfsr_count = SYNC_WORDS) then
            -- Once locked, operate LFSR in lockstep.
            lfsr_state  <= leap_next(LEAP_LFSR, lfsr_state);
        elsif (in_write = '1' and IO_WIDTH >= lfsr_state'length) then
            -- Special case when the input is wider than the LFSR.
            lfsr_count  <= lfsr_count + 1;
            lfsr_state  <= in_convert(lfsr_state'range);
        elsif (in_write = '1') then
            -- Normal case for loading shift register.
            lfsr_count  <= lfsr_count + 1;
            lfsr_state  <= lfsr_state(lfsr_state'left-IO_WIDTH downto 0) & in_convert;
        end if;

        -- Matched delay for the input stream.
        dly1_rcvd   <= in_rcvd;
        dly1_write  <= in_write and bool2bit(lfsr_count = SYNC_WORDS) and not reset_p;
    end if;
end process;

-- Drive top-level outputs.
out_local   <= lfsr_outreg;
out_rcvd    <= dly1_rcvd;
out_write   <= dly1_write;

end prng_lfsr_sync;
