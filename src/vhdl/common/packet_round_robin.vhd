--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Round-robin priority scheduler
--
-- This block implements a scheduler for sharing access from multiple
-- sources to a single output port.  When the output port is contested,
-- priority is assigned using the round-robin rule. In short: to assign
-- the next source, count up (with wraparound) from the previous source,
-- stopping at the first one that has data ready.  That source is held
-- until the end-of-frame, and then another is selected.
--
-- For simplicity, the block handles flow-control signals only; data and
-- metadata must be MUXed separately.
--
-- This block supports 100% throughput, but to support reasonable timing
-- it does have a single-cycle decision latency under certain conditions.
--
-- Note: For any given input, once in_valid is asserted it MUST be held
--       high for the full duration of the packet.  If this constraint
--       is not followed then the scheduler may switch inputs prematurely.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity packet_round_robin is
    generic (
    INPUT_COUNT : positive);    -- Number of input ports
    port (
    -- Flow control signals for each input port.
    in_last     : in  std_logic_vector(INPUT_COUNT-1 downto 0);
    in_valid    : in  std_logic_vector(INPUT_COUNT-1 downto 0);
    in_ready    : out std_logic_vector(INPUT_COUNT-1 downto 0);
    in_select   : out integer range 0 to INPUT_COUNT-1;
    in_error    : out std_logic;

    -- Flow control signals for the shared output port.
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System clock (no reset needed).
    clk         : in  std_logic);
end packet_round_robin;

architecture packet_round_robin of packet_round_robin is

-- Convenience types.
subtype port_slv is std_logic_vector(INPUT_COUNT-1 downto 0);
subtype port_idx is integer range 0 to INPUT_COUNT-1;

-- Choose the next selection index using two priority encoders:
-- The first only considers ports counting up from the previous selection.
-- The second considers all ports, to handle the wraparound case.
function round_robin(
    in_valid    : port_slv;
    prev_mask   : port_slv;
    prev_idx    : port_idx)
    return port_idx
is
    constant in_vmask : port_slv := in_valid and prev_mask;
begin
    -- Combinational logic only.
    if (or_reduce(in_vmask) = '1') then
        return priority_encoder(in_vmask);
    elsif (or_reduce(in_valid) = '1') then
        return priority_encoder(in_valid);
    else
        return prev_idx;
    end if;
end function;

-- Internal copies of output signals.
signal in_error_i   : std_logic := '0';
signal out_last_i   : std_logic := '0';
signal out_valid_i  : std_logic := '0';

-- Selection state.
signal select_curr  : port_idx := 0;
signal select_next  : port_idx := 0;
signal select_mask  : port_slv := (others => '0');

begin

-- Drive output signals.
out_last    <= out_last_i;
out_valid   <= out_valid_i;
in_select   <= select_curr;
in_error    <= in_error_i;

-- Combinational logic for each flow-control signal.
out_last_i  <= in_last(select_curr);
out_valid_i <= in_valid(select_curr);
gen_ready : for n in in_ready'range generate
    in_ready(n) <= out_ready and bool2bit(select_curr = n);
end generate;

-- State machine for updating the selection index.
select_next <= round_robin(in_valid, select_mask, select_curr);

p_select : process(clk)
begin
    if rising_edge(clk) then
        if (out_valid_i = '0' or out_last_i = '1') then
            -- Update selection between packets or just after end of packet.
            select_curr <= select_next;
            -- Do the same for the priority-encoder mask (see above).
            for n in select_mask'range loop
                select_mask(n) <= bool2bit(n > select_next);
            end loop;
        end if;
    end if;
end process;

-- Input sanity check:
-- Verify that each input is following the "valid held high" rule.
p_check : process(clk)
    variable expect_valid : port_slv := (others => '0');
begin
    if rising_edge(clk) then
        assert (in_error_i = '0')
            report "Input flow control violation" severity error;
        in_error_i <= or_reduce(expect_valid and not in_valid);
        expect_valid := in_valid and not in_last;
    end if;
end process;

end packet_round_robin;
