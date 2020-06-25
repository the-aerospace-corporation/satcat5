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
-- Parallel shift-register variant of MAC-address lookup
--
-- This module implements a hybrid serial/parallel MAC lookup table.
-- A small number of matching units (typ. 2-4) operate in parallel,
-- each fed from a small shift register.  This hybrid approach allows
-- adequate throughput and acceptable latency, without the massive
-- resource cost of the brute-force approach.  For simplicity, this
-- block does not implement scrubbing.
--
-- Latency is fixed at exactly 3 + MATCH_SIZE.  This parameter is
-- determined automatically from INPUT_WIDTH, but can be overridden.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_parshift is
    generic (
    INPUT_WIDTH     : integer;          -- Width of main data port
    PORT_COUNT      : integer;          -- Number of Ethernet ports
    TABLE_SIZE      : integer := 32;    -- Max stored MAC addresses
    LATCH_MACADDR   : boolean := true;  -- Latch SRC & DST addresses?
    MATCH_SIZE_OVR  : integer := -1);   -- Override for automatic size.
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
end mac_lookup_parshift;

architecture mac_lookup_parshift of mac_lookup_parshift is

-- Define optimal match-size based on INPUT_WIDTH and LATCH_MACADDR.
-- Minimum Ethernet packet size is 64 bytes = 512 bits.
-- * If LATCH_MACADDR = true, then we C = 512 / N clock cycles to search.
-- * Otherwise, we save a register but have only C = 416 / N clock cycles,
--   because the unbuffered shift register output is changing.
-- Choose MATCH_SIZE = 2^M such that MATCH_SIZE <= C.
function match_size_fn return integer is
begin
    -- Override flag is set, use user value.
    if (MATCH_SIZE_OVR > 0) then
        return MATCH_SIZE_OVR;
    end if;

    -- Auto-detect logic:
    if (LATCH_MACADDR) then
        case INPUT_WIDTH is
            when  8 => return 64;   -- C = 64
            when 16 => return 32;   -- C = 32
            when 24 => return 16;   -- C = 21
            when 32 => return 16;   -- C = 16
            when others => return 8;
                report "Unsupported INPUT_WIDTH" severity error;
        end case;
    else
        case INPUT_WIDTH is
            when  8 => return 32;   -- C = 52
            when 16 => return 16;   -- C = 26
            when 24 => return 16;   -- C = 17
            when 32 => return 8;    -- C = 13
            when others => return 8;
                report "Unsupported INPUT_WIDTH" severity error;
        end case;
    end if;
end function;

constant MATCH_SIZE : integer := match_size_fn;

-- Define various convenience types.
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype mac_addr_t is unsigned(47 downto 0);
constant BROADCAST_MAC : mac_addr_t := (others => '1');

type table_row_t is record
    mac     : mac_addr_t;
    mask    : port_mask_t;
end record;
constant ROW_EMPTY : table_row_t := (
    mac => (others => '0'), mask => (others => '0'));
type table_t is array(0 to MATCH_SIZE-1) of table_row_t;

constant MATCH_UNITS : integer := (TABLE_SIZE + MATCH_SIZE-1) / MATCH_SIZE;
type mask_array_t is array(0 to MATCH_UNITS-1) of port_mask_t;
subtype flag_array_t is std_logic_vector(0 to MATCH_UNITS-1);

subtype match_idx_t is integer range 0 to MATCH_UNITS-1;
subtype table_idx_t is integer range 0 to MATCH_SIZE-1;
subtype table_cnt_t is integer range 0 to MATCH_SIZE;

-- Word-by-word variant of or_reduce.
function or_reduce(x : mask_array_t) return port_mask_t is
    variable result : port_mask_t := (others => '0');
begin
    for n in x'range loop
        result := result or x(n);
    end loop;
    return result;
end function;

-- Shift register extracts destination and source MAC address.
constant in_ready_i : std_logic := '1';
signal mac_dst      : mac_addr_t := (others => '0');
signal mac_src      : mac_addr_t := (others => '0');
signal mac_rdy      : std_logic := '0';
signal reg_psrc     : port_mask_t := (others => '0');
signal src_bcast    : std_logic := '0';
signal dst_bcast    : std_logic := '0';

-- Common logic for address matching.
signal scan_addr    : table_idx_t := 0;
signal scan_final   : std_logic := '0';
signal scan_done    : std_logic := '0';
signal table_wren   : std_logic := '0';
signal table_wridx  : match_idx_t := 0;

-- Output from each matching unit.
signal table_gotsrc : flag_array_t := (others => '0');
signal table_gotdst : flag_array_t := (others => '0');
signal table_msksrc : mask_array_t := (others => (others => '0'));
signal table_mskdst : mask_array_t := (others => (others => '0'));
signal table_full   : flag_array_t := (others => '0');

-- Final output reduction
signal match_gotsrc : std_logic := '0';
signal match_gotdst : std_logic := '0';
signal match_msksrc : port_mask_t := (others => '0');
signal match_mskdst : port_mask_t := (others => '0');

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
    variable final, final_d : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Update shift register if applicable.
        -- Note: Ethernet is always MSW-first.
        if (in_valid = '1' and in_ready_i = '1' and count > 0) then
            sreg := sreg(sreg'left-INPUT_WIDTH downto 0) & in_data;
        end if;

        -- Detect final header word (combinational logic)
        final := in_valid and in_ready_i and bool2bit(count = 1);

        -- Optionally latch MAC addresses, or use unbuffered SREG.
        if (final = '1' or not LATCH_MACADDR) then
            mac_dst <= unsigned(sreg(sreg'left downto sreg'left-47));
            mac_src <= unsigned(sreg(sreg'left-48 downto sreg'left-95));
        end if;

        -- Always latch PSRC and drive the RDY strobe.
        mac_rdy <= final;
        if (final_d = '1') then
            reg_psrc <= in_psrc;
        end if;

        -- Detect the broadcast address.  (One-cycle lag OK.)
        dst_bcast <= bool2bit(mac_dst = BROADCAST_MAC);
        src_bcast <= bool2bit(mac_src = BROADCAST_MAC);

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

        -- One-cycle delay for the final_d strobe.
        final_d := final;
    end if;
end process;

-- Common logic for address matching.
p_scan : process(clk)
begin
    if rising_edge(clk) then
        -- Forward overflow strobe from any match unit.
        error_full <= or_reduce(table_full);

        -- Assert "done" strobe just after final address.
        scan_done  <= scan_final;   -- One extra delay
        scan_final <= bool2bit(scan_addr = MATCH_SIZE-1);

        -- Idle at zero, start counting up after mac_rdy strobe.
        if (reset_p = '1' or scan_addr = MATCH_SIZE-1) then
            scan_addr <= 0;
        elsif (mac_rdy = '1' or scan_addr /= 0) then
            scan_addr <= scan_addr + 1;
        end if;

        -- Store any new source addresses (no match found).
        table_wren <= scan_done and not (src_bcast or match_gotsrc);

        -- Round-robin for storing new addresses.
        if (reset_p = '1') then
            table_wridx <= 0;
        elsif (table_wren = '1') then
            if (table_wridx < MATCH_UNITS-1) then
                table_wridx <= table_wridx + 1;
            else
                table_wridx <= 0;
            end if;
        end if;
    end if;
end process;

-- Instantiate each address-matching unit.
gen_match : for idx in 0 to MATCH_UNITS-1 generate
    p_match : process(clk)
        variable table_count : table_cnt_t := 0;
        variable table_sreg  : table_t := (others => ROW_EMPTY);
        variable table_rdval : table_row_t := ROW_EMPTY;
        variable table_rdok  : std_logic := '0';
    begin
        if rising_edge(clk) then
            -- Compare table contents to source and destination MAC.
            if (mac_rdy = '1') then
                -- Start of new scan, reset status flags.
                table_gotsrc(idx) <= '0';
                table_gotdst(idx) <= '0';
                table_msksrc(idx) <= (others => '0');
                table_mskdst(idx) <= (others => '0');
            elsif (table_rdok = '1') then
                -- Check for match after each valid read.
                if (table_rdval.mac = mac_src) then
                    table_gotsrc(idx) <= '1';
                    table_msksrc(idx) <= table_rdval.mask;
                end if;
                if (table_rdval.mac = mac_dst) then
                    table_gotdst(idx) <= '1';
                    table_mskdst(idx) <= table_rdval.mask;
                end if;
            end if;

            -- Read from addressable shift-register.
            -- Note: This is designed to map well to Xilinx SRL16E.
            table_rdval := table_sreg(scan_addr);
            table_rdok  := bool2bit(scan_addr < table_count);

            -- Update shift-register contents.
            if (table_wren = '1' and table_wridx = idx) then
                table_sreg(1 to MATCH_SIZE-1) := table_sreg(0 to MATCH_SIZE-2);
                table_sreg(0) := (mac => mac_src, mask => reg_psrc);
                table_full(idx) <= bool2bit(table_count = MATCH_SIZE);
            else
                table_full(idx) <= '0';
            end if;

            -- Update row-count.
            if (reset_p = '1') then
                table_count := 0;
            elsif (table_wren = '1' and table_wridx = idx and table_count /= MATCH_SIZE) then
                table_count := table_count + 1;
            end if;
        end if;
    end process;
end generate;

-- Output reduction is all by OR_REDUCE().
match_gotsrc <= or_reduce(table_gotsrc);
match_gotdst <= or_reduce(table_gotdst);
match_msksrc <= or_reduce(table_msksrc);
match_mskdst <= or_reduce(table_mskdst);

-- Table integrity: Check for source-mask mismatch.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (scan_done = '1' and match_gotsrc = '1' and reg_psrc /= match_msksrc) then
            -- Entry is in table, but mismatched port-mask.
            report "Port-mask mismatch" severity error;
            error_table <= '1';
        else
            error_table <= '0';
        end if;
    end if;
end process;

-- Latch output mask and check for broadcast addresses.
p_out : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            out_pdst    <= (others => '0');
            out_valid   <= '0';
        elsif (scan_done = '1') then
            if (dst_bcast = '1' or match_gotdst = '0') then
                out_pdst <= not reg_psrc;
            else
                out_pdst <= match_mskdst;
            end if;
            out_valid <= '1';
        elsif (out_ready = '1') then
            out_valid <= '0';
        end if;
    end if;
end process;

end mac_lookup_parshift;
