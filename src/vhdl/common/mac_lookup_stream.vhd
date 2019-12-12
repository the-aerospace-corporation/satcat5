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
-- Streaming serial-port-only variant of MAC-address lookup
--
-- This module implements a simplified MAC-address lookup table,
-- specifically optimized for use with SPI and UART endpoints to
-- support "runt" packets as short as 18 bytes.  Since this allows
-- no time for more complex lookup schemes, we instead match the
-- incoming byte stream, one at a time, against a single address
-- per port.  (Since SPI/UART endpoints are unlikely to share.)
--
-- All other addresses are directed to the special "uplink" port
-- (index zero), which is usually connected to a separate gigabit-
-- Ethernet switch core. Packets routed from the uplink back to the
-- uplink are simply dropped, to avoid internal loops.
--
-- Latency for this variant is never more than two clock cycles.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_types.all;

entity mac_lookup_stream is
    generic (
    PORT_COUNT      : integer);         -- Number of Ethernet ports
    port (
    -- Main input (Ethernet frame) uses AXI-stream flow control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc         : in  std_logic_vector(PORT_COUNT-1 downto 0);
    in_data         : in  std_logic_vector(7 downto 0);
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Search result is the port mask for the destination port(s).
    out_pdst        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_stream;

architecture mac_lookup_stream of mac_lookup_stream is

subtype byte_t is std_logic_vector(7 downto 0);

signal in_bcount    : integer range 0 to 13 := 0;
signal in_wr_src    : std_logic;
signal in_wr_dst    : std_logic;
signal match_bcast  : std_logic := '1';
signal match_found  : std_logic := '0';
signal match_flag   : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '1');
signal match_pdst   : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal match_valid  : std_logic := '0';

begin

-- Already ready for incoming data.
in_ready <= '1';

-- Byte-counting state machine detects SRC-MAC and DST-MAC fields.
in_wr_dst <= in_valid and bool2bit(0 <= in_bcount and in_bcount < 6);
in_wr_src <= in_valid and bool2bit(6 <= in_bcount and in_bcount < 12);

p_count : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            in_bcount <= 0;             -- Global reset
        elsif (in_valid = '1' and in_last = '1') then
            in_bcount <= 0;             -- End of packet, get ready for next.
        elsif (in_valid = '1' and in_bcount < 13) then
            in_bcount <= in_bcount + 1; -- Count off bytes 0-12, stop at 13.
        end if;
    end if;
end process;

-- Instantiate a matching unit for each regular port.
gen_match : for n in 1 to PORT_COUNT-1 generate
    p_match : process(clk)
        type sreg_t is array(0 to 5) of byte_t;
        -- TODO: Vivado optimizes away all bytes of addr_sreg
        --       except addr_sreg(5). This breaks MAC lookup by causing
        --       all non-broadcast packets to be routed to the uplink port.
        --       Workaround is to set KEEP on addr_sreg.
        variable addr_sreg : sreg_t := (others => (others => '1'));
        attribute KEEP : string;
        attribute KEEP of addr_sreg : variable is "true";
    begin
        if rising_edge(clk) then
            -- Check each destination byte against the stored address.
            if (in_valid = '1' and in_last = '1') then
                match_flag(n) <= '1';
            elsif (in_wr_dst = '1' and in_data /= addr_sreg(in_bcount)) then
                match_flag(n) <= '0';
            end if;

            -- Store source address for this port.
            if (in_psrc(n) = '1' and in_wr_src = '1') then
                addr_sreg := addr_sreg(1 to 5) & in_data;
            end if;
        end if;
    end process;
end generate;

-- Uplink port matches if none of the regular ports do, and the
-- source port was not the uplink (loopback is not allowed).
-- Combinational logic ensures it's ready in sync with others.
match_found <= or_reduce(match_flag(PORT_COUNT-1 downto 1));
match_flag(0) <= not (in_psrc(0) or match_found);

-- Matching unit for the broadcast address, plus output logic.
p_bcast : process(clk)
begin
    if rising_edge(clk) then
        -- Broadcast MAC address = FF:FF:FF:FF:FF:FF
        if (in_valid = '1' and in_last = '1') then
            match_bcast <= '1';
        elsif (in_wr_dst = '1' and in_data /= x"FF") then
            match_bcast <= '0';
        end if;

        -- Latch the main output.
        if (reset_p = '1') then
            -- Global reset.
            match_pdst  <= (others => '0');
            match_valid <= '0';
        elsif (in_valid = '1' and in_bcount = 12) then
            -- Latch output one cycle after end of DST-MAC.
            if (match_bcast = '1') then
                match_pdst <= not in_psrc;  -- Broadcast
            else
                match_pdst <= match_flag;   -- Single-port
            end if;
            match_valid <= '1';
        elsif (out_ready = '1') then
            -- Clear outputs once consumed.
            match_pdst  <= (others => '0');
            match_valid <= '0';
        end if;
    end if;
end process;

-- Drive the final output ports.
out_pdst  <= match_pdst;
out_valid <= match_valid;

end mac_lookup_stream;
