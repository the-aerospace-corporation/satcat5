--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Not-recently-used (NRU) cache controller with 2 bits per block
--
-- This block implements an algorithm that monitors cache access and
-- decides which block is the best candidate for eviction.  The algorithm
-- uses four states per block:
--  3 = Very frequently used
--  2 = Frequently used
--  1 = Recent use (new blocks start here)
--  0 = Good candidate for eviction
--
-- Empty blocks are in the "0" state.  New blocks start at state "1" and
-- are further promoted on each access.  However, if no blocks are in the
-- "0" state, then ALL blocks are demoted by one step.
--
-- The recommended replacement index is selected in round-robin order
-- from the set of blocks in the "0" state.
--
-- Update latency is two to four clock cycles.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity tcam_cache_nru2 is
    generic (
    TABLE_SIZE  : positive);
    port (
    -- Update queue state for each successful search.
    in_index    : in  integer range 0 to TABLE_SIZE-1;
    in_read     : in  std_logic;
    in_write    : in  std_logic;

    -- Best candidate for eviction.
    out_index   : out integer range 0 to TABLE_SIZE-1;
    out_hold    : in  std_logic := '0';

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end tcam_cache_nru2;

architecture tcam_cache_nru2 of tcam_cache_nru2 is

subtype mask_t is std_logic_vector(TABLE_SIZE-1 downto 0);
signal mask_any     : std_logic := '0';
signal mask_valid   : mask_t := (others => '0');
signal mask_robin   : mask_t := (others => '0');
signal sel_cke      : std_logic := '0';
signal sel_curr     : integer range 0 to TABLE_SIZE-1 := 0;
signal sel_next     : integer range 0 to TABLE_SIZE-1 := 0;

begin

-- Generate the state-machine for each table entry.
mask_any <= or_reduce(mask_valid);

gen_table : for n in mask_valid'range generate
    p_count : process(clk)
        variable count : integer range 0 to 3 := 0;
    begin
        if rising_edge(clk) then
            if (reset_p = '1') then
                count := 0;             -- Reset
            elsif (in_write = '1' and in_index = n) then
                count := 1;             -- New entry
            elsif (in_read = '1' and in_index = n) then
                if (count < 3) then
                    count := count + 1; -- Increment on match
                end if;
            elsif (mask_any = '0') then
                count := count - 1;     -- Decrement all
            end if;
            mask_valid(n) <= bool2bit(count = 0);
        end if;
    end process;
end generate;

-- Combinational logic for the round-robin priority-encoder.

p_robin : process(mask_valid, mask_robin) is
    variable mask_later : mask_t;
begin
    mask_later := mask_valid and mask_robin;
    if (or_reduce(mask_later) = '1') then
        sel_next <= priority_encoder(mask_later);   -- Next item (direct)
    else
        sel_next <= priority_encoder(mask_valid);   -- Next item (wrapped)
    end if;
end process;

-- Output register.
p_out : process(clk)
begin
    if rising_edge(clk) then
        -- Update selection and round-robin mask.
        if (reset_p = '1') then
            sel_curr    <= 0;
            mask_robin  <= (others => '0');
        elsif (out_hold = '0' and mask_any = '1' and sel_cke = '1') then
            sel_curr    <= sel_next;
            for n in mask_robin'range loop
                mask_robin(n) <= bool2bit(n > sel_next);
            end loop;
        end if;

        -- Clock-enable for the output register.
        if (reset_p = '1') then
            sel_cke <= '0';                     -- Global reset
        elsif (mask_any = '0') then
            sel_cke <= '1';                     -- Retry after decrement
        else
            sel_cke <= in_read or in_write;     -- Normal update
        end if;
    end if;
end process;

out_index <= sel_curr;

end tcam_cache_nru2;
