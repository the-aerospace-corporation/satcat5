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
-- Brute-force variant of MAC-address lookup, fast but very large
--
-- This module implements a brute-force MAC lookup table, using a large
-- shift-register of known addresses.  Each table entry checks for an
-- address match in parallel, so the full process is complete in a few
-- clock cycles.  New addresses simply shift into the table without need for
-- scrubbing or other integrity checks.  The result is highly effective but
-- requires a massive amount of FPGA fabric, making it impractical for
-- large address spaces.
--
-- Latency of this design is fixed at exactly three clock cycles.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_types.all;

entity mac_lookup_brute is
    generic (
    INPUT_WIDTH     : integer;          -- Width of main data port
    PORT_COUNT      : integer;          -- Number of Ethernet ports
    TABLE_SIZE      : integer := 31);   -- Max stored MAC addresses
    port (
    -- Main input (Ethernet frame) uses AXI-stream flow control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc         : in  std_logic_vector(PORT_COUNT-1 downto 0);
    in_data         : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Search result is the port mask for the destination port(s).
    out_pdst        : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- Error strobes
    error_full      : out std_logic;    -- No room for new address
    error_table     : out std_logic;    -- Table integrity check failed

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup_brute;

architecture mac_lookup_brute of mac_lookup_brute is

-- Define various convenience types.
subtype mac_addr_t is unsigned(47 downto 0);
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype table_idx_t is integer range 0 to TABLE_SIZE-1;
subtype table_cnt_t is integer range 0 to TABLE_SIZE;
constant BROADCAST_MAC : mac_addr_t := (others => '1');

type table_row_t is record
    mac     : mac_addr_t;
    mask    : port_mask_t;
end record;
constant ROW_EMPTY : table_row_t := (
    mac => (others => '0'), mask => (others => '0'));
type table_t is array(0 to TABLE_SIZE-1) of table_row_t;

-- Shift register extracts destination and source MAC address.
constant in_ready_i : std_logic := '1';
signal mac_dst      : mac_addr_t := (others => '0');
signal mac_src      : mac_addr_t := (others => '0');
signal mac_rdy      : std_logic := '0';

-- Main lookup table and matching logic.
signal table_value  : table_t := (others => ROW_EMPTY);
signal table_count  : table_cnt_t := 0;
signal table_wr     : std_logic := '0';
signal match_pdst   : port_mask_t := (others => '0');
signal match_psrc   : port_mask_t := (others => '0');
signal match_rdy    : std_logic := '0';

begin

-- Drive external copies of various internal signals.
in_ready <= in_ready_i;

-- Shift register extracts destination and source MAC address.
p_mac_sreg : process(clk)
    -- Input arrives N bits at a time, how many clocks until we have
    -- destination and source (96 bits total, may not divide evenly)
    constant MAX_COUNT : integer := (95+INPUT_WIDTH) / INPUT_WIDTH;
    variable sreg   : std_logic_vector(MAX_COUNT*INPUT_WIDTH-1 downto 0) := (others => '0');
    variable count  : integer range 0 to MAX_COUNT;
begin
    if rising_edge(clk) then
        -- Update shift register if applicable.
        -- Note: Ethernet is always MSW-first.
        if (in_valid = '1' and in_ready_i = '1' and count > 0) then
            sreg := sreg(sreg'left-INPUT_WIDTH downto 0) & in_data;
            mac_rdy <= bool2bit(count = 1); -- Last MAC word, start search
        else
            mac_rdy <= '0';
        end if;
        mac_dst <= unsigned(sreg(sreg'left downto sreg'left-47));
        mac_src <= unsigned(sreg(sreg'left-48 downto sreg'left-95));

        -- Update word-count state machine and ready strobe.
        if (reset_p = '1') then
            count := MAX_COUNT;     -- Ready for first frame.
        elsif (in_valid = '1' and in_ready_i = '1') then
            if (in_last = '1') then
                count := MAX_COUNT; -- Get ready for next frame.
            elsif (count > 0) then
                count := count - 1; -- Still reading MAC.
            end if;
        end if;
    end if;
end process;

-- Main lookup table and matching logic.
p_table : process(clk)
    variable tmp_dst, tmp_src : port_mask_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Pipeline stage 3: Shift in each new row and update row count.
        if (table_wr = '1') then
            error_full <= bool2bit(table_count = TABLE_SIZE);
            table_value(0).mac  <= mac_src;
            table_value(0).mask <= in_psrc;
            for n in 1 to TABLE_SIZE-1 loop
                table_value(n).mac  <= table_value(n-1).mac;
                table_value(n).mask <= table_value(n-1).mask;
            end loop;
        else
            error_full <= '0';
        end if;

        if (reset_p = '1') then
            table_count <= 0;
        elsif (table_wr = '1' and table_count < TABLE_SIZE) then
            table_count <= table_count + 1;
        end if;

        -- Pipeline stage 2: Decide whether to write a new row.
        table_wr <= match_rdy
                and bool2bit(mac_src /= BROADCAST_MAC)
                and not or_reduce(match_psrc);

        -- Pipeline stage 1: Check for matching addresses.
        -- TODO: Consider pipelining the implied OR-tree.
        match_rdy   <= mac_rdy;
        tmp_dst     := (others => '0');
        tmp_src     := (others => '0');
        for n in 0 to TABLE_SIZE-1 loop
            if (n < table_count and table_value(n).mac = mac_dst) then
                tmp_dst := tmp_dst or table_value(n).mask;
            end if;
            if (n < table_count and table_value(n).mac = mac_src) then
                tmp_src := tmp_src or table_value(n).mask;
            end if;
        end loop;
        match_pdst <= tmp_dst;
        match_psrc <= tmp_src;
    end if;
end process;

-- Table integrity: Check for source-mask mismatch.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (match_rdy = '1' and or_reduce(match_psrc) = '1') then
            -- Entry is in table, confirm matching port-mask.
            assert (in_psrc = match_psrc)
                report "Port-mask mismatch" severity error;
            error_table <= bool2bit(in_psrc /= match_psrc);
        else
            error_table <= '0';
        end if;
    end if;
end process;

-- Latch output and check for broadcast addresses.
p_out : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            out_pdst    <= (others => '0');
            out_valid   <= '0';
        elsif (match_rdy = '1') then
            if (mac_dst = BROADCAST_MAC or or_reduce(match_pdst) = '0') then
                out_pdst <= not in_psrc;
            else
                out_pdst <= match_pdst;
            end if;
            out_valid <= '1';
        elsif (out_ready = '1') then
            out_valid <= '0';
        end if;
    end if;
end process;

end mac_lookup_brute;
