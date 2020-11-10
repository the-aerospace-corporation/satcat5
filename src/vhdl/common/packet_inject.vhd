--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Auxiliary packet injector
--
-- This is a general-purpose infrastructure function that allows packets
-- from various secondary streams to be "injected" during idle time on a
-- primary data stream.  (e.g., For insertion of keep-alive messages,
-- ARP requests, and other low-volume traffic.)
--
-- All ports use AXI-style valid/ready flow control.  The lowest-numbered
-- input port gets the highest priority, followed by port #1, #2, and so on.
-- All inputs except the primary should provide contiguous data (i.e., once
-- asserted, VALID cannot be deasserted until end-of-frame), but this error
-- check can be disabled if desired.
--
-- If the primary input stream CANNOT use flow control, use a FIFO such as
-- "bram_fifo".  The FIFO depth must be large enough to accommodate the worst-
-- case time spent servicing another output.  If out_ready is held constant-
-- high, then the minimum FIFO size is equal to MAX_OUT_BYTES+1.
--
-- The "out_aux" flag indicates if the current output was taken from the
-- primary input or one of the auxiliary input(s).
--
-- As a failsafe, malformed packets from auxiliary sources may be fragmented
-- in order to preserve data flow on the primary stream.  This contingency
-- is triggered only if they exceed the specified maximum length.  Error
-- strobes are provided to facilitate any further required action.
--
-- Example usage:
--  * Primary data port has no flow control.  Data is always written to a
--    bram_fifo large enough for one max-length packet (typically 2 kiB).
--  * Secondary port(s) each have AXI valid/ready flow control, with the
--    added caveat that packet data must be contiguous once started.
--  * When idle, or at the end of each output packet, or if an auxiliary
--    frame exceeds the specified maximum length, switch inputs:
--     a) If there's any data in the FIFO, always prioritize that input.
--     b) Otherwise select any of the waiting secondary ports.
--  * Once selected, that port selection is locked until end-of-frame.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity packet_inject is
    generic (
    -- Number of input data ports.
    INPUT_COUNT     : integer;
    -- Options for each output frame.
    APPEND_FCS      : boolean;
    MIN_OUT_BYTES   : integer := 0;
    MAX_OUT_BYTES   : integer := 65535;
    -- Enforce rules on primary and secondary inputs?
    RULE_PRI_MAXLEN : boolean := true;
    RULE_PRI_CONTIG : boolean := true;
    RULE_AUX_MAXLEN : boolean := true;
    RULE_AUX_CONTIG : boolean := true);
    port (
    -- Vector of input ports
    -- Priority goes to the lowest-numbered input channel with valid data.
    in_data         : in  byte_array_t(INPUT_COUNT-1 downto 0);
    in_last         : in  std_logic_vector(INPUT_COUNT-1 downto 0);
    in_valid        : in  std_logic_vector(INPUT_COUNT-1 downto 0);
    in_ready        : out std_logic_vector(INPUT_COUNT-1 downto 0);
    in_error        : out std_logic;

    -- Combined output port
    out_data        : out byte_t;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_aux         : out std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end packet_inject;

architecture packet_inject of packet_inject is

-- State encoding: 0 = Idle, 1+ = Input N-1
constant STATE_IDLE     : integer := 0;
signal sel_state        : integer range 0 to INPUT_COUNT := STATE_IDLE;
signal sel_change       : std_logic := '0';
signal sel_mask         : std_logic_vector(0 to INPUT_COUNT-1);

-- Select the designated output.
signal mux_data         : byte_t := (others => '0');
signal mux_aux          : std_logic := '0';
signal mux_last         : std_logic := '0';
signal mux_valid        : std_logic := '0';
signal mux_ready        : std_logic;
signal mux_clken        : std_logic;

-- Max-length watchdog.
signal len_watchdog     : integer range 0 to MAX_OUT_BYTES-1 := 0;
signal error_contig     : std_logic := '0';
signal error_maxlen     : std_logic := '0';

begin

-- Upstream flow-control.
gen_flow : for n in in_ready'range generate
    sel_mask(n) <= bool2bit(sel_state = n + 1)
                or bool2bit(n = 0 and sel_state = STATE_IDLE);
    in_ready(n) <= sel_mask(n) and mux_clken;
end generate;

-- Combined error strobe.
in_error <= error_contig or error_maxlen;

-- Input-selection state machine.
mux_clken  <= mux_ready or not mux_valid;
sel_change <= mux_clken when (sel_state = STATE_IDLE)
         else mux_clken when (len_watchdog = MAX_OUT_BYTES-1)
         else (in_valid(sel_state-1) and in_last(sel_state-1));

p_sel : process(clk)
begin
    if rising_edge(clk) then
        -- Update the selected input channel between packets.
        if (reset_p = '1') then
            sel_state <= STATE_IDLE;
        elsif (mux_clken = '1' and sel_change = '1') then
            -- Revert to idle state in most cases.
            sel_state <= STATE_IDLE;
            -- If we're already idle, pick the highest priority active input.
            if (sel_state = STATE_IDLE) then
                for n in INPUT_COUNT-1 downto 0 loop
                    if (in_valid(n) = '1') then
                        sel_state <= n+1;
                    end if;
                end loop;
            end if;
        end if;

        -- Watchdog timer for designated inputs.
        if (reset_p = '1' or sel_change = '1') then
            len_watchdog <= 0;
        elsif (mux_clken = '1' and RULE_PRI_MAXLEN and sel_state = 1) then
            len_watchdog <= len_watchdog + 1;
        elsif (mux_clken = '1' and RULE_AUX_MAXLEN and sel_state > 1) then
            len_watchdog <= len_watchdog + 1;
        end if;

        -- One-word buffer for the selected input.
        if (mux_clken = '0') then
            -- Hold current data while we wait.
            null;
        elsif (sel_state = STATE_IDLE) then
            -- Default to the primary input.
            mux_data  <= in_data(0);
            mux_aux   <= '0';
            mux_last  <= in_last(0);
            mux_valid <= in_valid(0);
        else
            -- Choose the active input.
            mux_data  <= in_data(sel_state-1);
            mux_aux   <= bool2bit(sel_state > 1);
            mux_last  <= sel_change;
            mux_valid <= in_valid(sel_state-1);
        end if;

        -- Check for various error conditions.
        if (sel_state = STATE_IDLE) then
            error_maxlen <= '0';
            error_contig <= '0';
        elsif (mux_clken = '1') then
            error_maxlen <= bool2bit(len_watchdog = MAX_OUT_BYTES-1) and not in_last(sel_state-1);
            error_contig <= bool2bit((sel_state = 1 and RULE_PRI_CONTIG)
                                  or (sel_state > 1 and RULE_AUX_CONTIG))
                        and not in_valid(sel_state-1);
        end if;
    end if;
end process;

-- (Optional) Add zero-padding and append FCS/CRC32 to each frame.
gen_crc : if (MIN_OUT_BYTES > 0 or APPEND_FCS) generate
    u_crc : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => MIN_OUT_BYTES,   -- Zero-padding as needed
        APPEND_FCS  => APPEND_FCS,      -- Append FCS to final output?
        META_WIDTH  => 1,               -- One bit of metadata
        STRIP_FCS   => false)           -- No FCS to be stripped
        port map(
        in_data     => mux_data,
        in_meta(0)  => mux_aux,
        in_last     => mux_last,
        in_valid    => mux_valid,
        in_ready    => mux_ready,
        out_data    => out_data,
        out_meta(0) => out_aux,
        out_last    => out_last,
        out_valid   => out_valid,
        out_ready   => out_ready,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_nocrc : if (MIN_OUT_BYTES = 0 and not APPEND_FCS) generate
    out_data  <= mux_data;
    out_aux   <= mux_aux;
    out_last  <= mux_last;
    out_valid <= mux_valid;
    mux_ready <= out_ready;
end generate;

end packet_inject;
