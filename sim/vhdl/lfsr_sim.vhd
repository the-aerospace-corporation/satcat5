--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- This file contains type definitions, procedures, and functions that
-- define a simple LFSR.  It can be used to transmit a PRBS sequence, or
-- to synchronize with a received sequence. (To measure BER, etc.)
--
-- The default LFSR configuration is:
--   PRBS ITU-T O.160 Section 5.6: x^23+x^18+1 (inverted signal)
--
-- These structures are intended for a variety of simulations, including
-- those that require multiple bits per clock.
--
-- Typical transmitter:
-- p_tx : process(clk)
--     variable lfsr : lfsr_state := LFSR_RESET;
-- begin
--     if rising_edge(clk) then
--         for n in 31 downto 0 loop   -- MSB first
--             lfsr_incr(lfsr);
--             in_data(n) <= lfsr_out_next(lfsr);
--         end if;
--     end if;
-- end process;
--
-- Typical receiver:
-- p_check : process(clk)
--     variable lfsr : lfsr_state := LFSR_RESET;
-- begin
--     if rising_edge(clk) then
--         -- Synchronize with received signal.
--         if (out_rdy = '1' and not lfsr_sync_done(lfsr)) then
--             for n in 7 downto 0 loop    -- MSB-first.
--                 lfsr_sync_next(lfsr, out_data(n));
--             end loop;
--         end if;
--
--         -- Once we have enough data, run PRNG to generate reference byte.
--         if (not lfsr_sync_done(lfsr)) then
--             ref_locked <= '0';
--         elsif (out_rdy = '1') then
--             ref_locked <= '1';
--             for n in 7 downto 0 loop    -- MSB-first
--                 lfsr_incr(lfsr);
--                 ref_data(n) <= lfsr_out_next(lfsr);
--             end loop;
--         end if;
--     end if;
-- end process;
--

library ieee;
use     ieee.std_logic_1164.all;

package LFSR_SIM_TYPES is
    -- Define various LFSR-related data types.
    subtype lfsr_sreg is std_logic_vector(22 downto 0);

    type lfsr_state is record
        sreg    : lfsr_sreg;                -- Fibonacci register state
        rxct    : integer range 0 to 23;    -- Sync bits received (Rx only)
    end record;

    constant LFSR_RESET : lfsr_state := ((others => '1'), 0);

    -- Increment LFSR state vector to generate the next bit.
    procedure lfsr_incr(state : inout lfsr_state);

    -- Synchronize LFSR state by receiving the next bit.
    procedure lfsr_sync_next(state : inout lfsr_state; b : std_logic);

    -- Given LFSR state, calculate the next output bit.
    function lfsr_out_next(state : lfsr_state) return std_logic;

    -- Given receive LFSR state, determine if synchronization is complete.
    function lfsr_sync_done(state : lfsr_state) return boolean;
end LFSR_SIM_TYPES;


package body LFSR_SIM_TYPES is
    procedure lfsr_incr(state : inout lfsr_state) is
        constant ALL_ZEROS : lfsr_sreg := (others => '0');
        constant LFSR_POLY : lfsr_sreg := "10000100000000000000000";
        variable next_bit  : std_logic := '0';
    begin
        if (state.sreg = ALL_ZEROS) then
            -- Special case to get out of the stuck/error state.
            state.sreg := (others => '1');
        else
            -- Fibonacci-form LFSR update.
            for n in state.sreg'range loop
                next_bit := next_bit xor (state.sreg(n) and LFSR_POLY(n));
            end loop;
            state.sreg := state.sreg(21 downto 0) & next_bit;
        end if;
    end procedure;

    procedure lfsr_sync_next(state : inout lfsr_state; b : std_logic) is
    begin
        -- Note: Output inverted; re-invert on the way in as well.
        state.sreg := state.sreg(21 downto 0) & (not b);
        if (state.rxct < 23) then
            state.rxct := state.rxct + 1;
        end if;
    end procedure;

    function lfsr_out_next(state : lfsr_state) return std_logic is
    begin
        return not state.sreg(0);
    end function;

    function lfsr_sync_done(state : lfsr_state) return boolean is
    begin
        return (state.rxct >= 23);
    end function;
end;
