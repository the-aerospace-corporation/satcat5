--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Fixed-interval timestamp counter
--
-- This block implements a coarse "timestamp" that increments at a fixed
-- cadence (e.g., once every microsecond). The counter starts from zero
-- after system reset, then counts upward forever with wraparound. There
-- is no provision to discipline or synchronize the counter. For more
-- accurate timestamps, see "ptp_counter_gen" and "ptp_counter_sync".
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity config_timestamp is
    generic (
    REFCLK_HZ   : positive;     -- Reference clock, in Hz.
    CTR_HZ      : positive;     -- Counter rate, in Hz.
    CTR_WIDTH   : positive);    -- Bits in output counter.
    port (
    out_ctr     : out unsigned(CTR_WIDTH-1 downto 0);
    refclk      : in  std_logic;
    reset_p     : in  std_logic);
end config_timestamp;

architecture config_timestamp of config_timestamp is

-- Simplify counters to reduce required bit-width.
constant COUNT_GCD  : positive := int_gcd(REFCLK_HZ, CTR_HZ);
constant COUNT_DN   : positive := REFCLK_HZ / COUNT_GCD;
constant COUNT_UP   : positive := CTR_HZ    / COUNT_GCD;
constant COUNT_DIFF : natural  := COUNT_DN - COUNT_UP;

-- Counter and divider state.
signal count_div    : integer range 0 to COUNT_DN - 1;
signal count_en     : std_logic := '0';
signal count_reg    : unsigned(CTR_WIDTH-1 downto 0) := (others => '0');

begin

-- Sanity check: No more than one output tick per input clock.
assert (REFCLK_HZ >= CTR_HZ) report "Invalid clock configuration.";

-- Wraparound detection for the pre-divider.
count_en <= bool2bit(count_div >= COUNT_DIFF);

-- Counter state machine:
p_count : process(refclk)
begin
    if rising_edge(refclk) then
        -- Count on demand based on pre-divider.
        if (reset_p = '1') then
            count_reg <= (others => '0');
        elsif (count_en = '1') then
            count_reg <= count_reg + 1;
        end if;

        -- Fractional pre-divider with accurate non-integer ratios.
        if (reset_p = '1') then
            count_div <= 0;
        elsif (count_en = '1') then
            count_div <= count_div - COUNT_DIFF;
        else
            count_div <= count_div + COUNT_UP;
        end if;
    end if;
end process;

-- Drive the top-level output.
out_ctr <= count_reg;

end config_timestamp;
