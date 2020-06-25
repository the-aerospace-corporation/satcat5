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
-- MAC-address lookup using a LUTRAM-based scalable CAM
--
-- This module implements a variant of the scalable CAM described by:
--      Jiang, Weirong. "Scalable ternary content addressable memory
--      implementation using FPGAs." Architectures for Networking and
--      Communications Systems. IEEE, 2013.
--
-- Since we do not need the TCAM functionality, we use the simplest
-- possible architecture (Fig. 3, Fig. 4) and updates are trivial.
-- The search engine is implemented using an array of smaller segments
-- (e.g., eight 64xN LUTRAM elements for Xilinx 7-series devices),
-- where the width is equal to the maximum table size.  This feeds
-- a one-hot decoder to find the lookup index for an ordinary table.
--
-- Latency is fixed at exactly six cycles above the theoretical minimum.
-- (Five if the FIFO is bypassed.)  Throughput is one search per clock,
-- which makes the CAM suitable for datapath widths up to 48 bits,
-- even for runt frames.
--
-- With a datapath from 32 to 48 bits wide, the pipeline is as follows:
--      Stage   *Dest lookup*      *Source lookup*
--      0       MAC address rdy
--      1       1st-stage CAM      MAC address in, latch PSRC
--      2       AND all masks      1st-stage CAM
--      3       Mask decoding      AND all masks
--      4       Table lookup       Mask decoding
--      5       Output mask ready  Table write (if new)
-- In narrower configurations, the source lookup will start later
-- simply because the full MAC address is available later.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity mac_lookup_lutram is
    generic (
    INPUT_WIDTH : integer;          -- Width of main data port
    PORT_COUNT  : integer;          -- Number of Ethernet ports
    OUT_FIFO_SZ : integer := 4;     -- Output FIFO size (0 = disable, 4+ = 2^N)
    TABLE_SIZE  : integer := 64);   -- Max stored MAC addresses
    port (
    -- Main input (Ethernet frame) uses AXI-stream flow control.
    -- PSRC is the input port-mask and must be held for the full frame.
    in_psrc     : in  std_logic_vector(PORT_COUNT-1 downto 0);
    in_data     : in  std_logic_vector(INPUT_WIDTH-1 downto 0);
    in_last     : in  std_logic;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    -- Search result is the port mask for the destination port(s).
    out_pdst    : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Error strobes
    error_full  : out std_logic;    -- No room for new address
    error_table : out std_logic;    -- Table integrity check failed

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end mac_lookup_lutram;

architecture mac_lookup_lutram of mac_lookup_lutram is

-- Divide 48-bit MAC lookup into N smaller segments.
-- TODO: 64x1 is best for Xilinx 7-series, adjust for other platforms.
constant LUTRAM_WIDTH : integer := 6;
constant LUTRAM_COUNT : integer := (47 + LUTRAM_WIDTH) / LUTRAM_WIDTH;

-- Define various convenience types.
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype sub_addr_t is unsigned(LUTRAM_WIDTH-1 downto 0);
subtype mac_addr_t is unsigned(47 downto 0);
constant BROADCAST_MAC : mac_addr_t := (others => '1');

subtype cam_mask_t is std_logic_vector(TABLE_SIZE-1 downto 0);
type cam_mask_array is array(0 to LUTRAM_COUNT-1) of cam_mask_t;

constant PIDX_WIDTH : integer := log2_ceil(PORT_COUNT);
subtype port_idx_t is unsigned(PIDX_WIDTH-1 downto 0);

constant TIDX_WIDTH : integer := log2_ceil(TABLE_SIZE);
constant TIDX_MAX   : integer := 2**TIDX_WIDTH - 1;
subtype tbl_addr_t is unsigned(TIDX_WIDTH-1 downto 0);

-- Get the Nth address segment for a given LUTRAM.
function get_subaddr(addr:mac_addr_t; n:integer) return sub_addr_t is
    constant EXT_WIDTH : integer := LUTRAM_COUNT*LUTRAM_WIDTH;
    variable ext : unsigned(EXT_WIDTH-1 downto 0) := resize(addr, EXT_WIDTH);
    variable sub : sub_addr_t := ext((n+1)*LUTRAM_WIDTH-1 downto n*LUTRAM_WIDTH);
begin
    return sub;
end function;

-- One-hot decoder functions with various in/out sizes.
function one_hot_decode_port(x : port_mask_t) return port_idx_t is
    variable tmp : port_idx_t := (others => '0');
begin
    for n in x'range loop
        if (x(n) = '1') then
            tmp := tmp or to_unsigned(n, PIDX_WIDTH);
        end if;
    end loop;
    return tmp;
end function;

function one_hot_decode_tidx(x : cam_mask_t) return tbl_addr_t is
    variable tmp : tbl_addr_t := (others => '0');
begin
    for n in x'range loop
        if (x(n) = '1') then
            tmp := tmp or to_unsigned(n, TIDX_WIDTH);
        end if;
    end loop;
    return tmp;
end function;

-- Error function returns true if more than one bit is set.
function one_hot_error(x : std_logic_vector) return std_logic is
    variable tmp : std_logic := '0';
begin
    for n in x'range loop
        if (x(n) = '1' and tmp = '1') then
            report "Invalid one-hot input!" severity error;
            return '1';
        end if;
        tmp := tmp or x(n);
    end loop;
    return '0';
end function;

-- Shift register extracts destination and source MAC address.
signal in_wren      : std_logic;
signal mac_addr     : mac_addr_t := (others => '0');
signal mac_psrc     : port_idx_t := (others => '0');
signal mac_rdy_dst  : std_logic := '0';
signal mac_rdy_src  : std_logic := '0';

-- First stage matching units.
signal camrd_masks  : cam_mask_array := (others => (others => '0'));
signal cam_match    : std_logic := '0';
signal cam_rdy_dst  : std_logic := '0';
signal cam_rdy_src  : std_logic := '0';
signal cam_macaddr  : mac_addr_t := (others => '0');
signal cam_psrc     : port_idx_t := (others => '0');
signal cam_tidx     : tbl_addr_t := (others => '0');

-- Final output mask generation.
signal tbl_pidx     : port_idx_t := (others => '0');
signal pdst_mask    : port_mask_t := (others => '0');
signal pdst_valid   : std_logic := '0';
signal pdst_rdy     : std_logic := '0';
signal fifo_ready   : std_logic;

-- Write control for both tables.
signal init_count   : unsigned(5 downto 0) := (others => '0');
signal init_done    : std_logic := '0';
signal camwr_mask   : cam_mask_t := (others => '1');
signal camwr_mac    : mac_addr_t := (others => '0');
signal camwr_tidx   : tbl_addr_t := (others => '0');
signal camwr_psrc   : port_idx_t := (others => '0');
signal camwr_twr    : std_logic := '0';
signal camwr_full   : std_logic := '0';

-- Error reporting
signal psrc_error   : std_logic := '0';
signal pdst_error   : std_logic := '0';
signal fifo_error   : std_logic := '0';
signal cam_error    : std_logic := '0';
signal camwr_ovr    : std_logic := '0';

begin

-- Once startup is done, accept new data unless the output FIFO is nearly full.
in_wren     <= init_done and fifo_ready and in_valid;
in_ready    <= init_done and fifo_ready;

-- Drive each of the error strobes.
error_full  <= camwr_ovr;
error_table <= psrc_error or pdst_error or cam_error;

-- Shift register extracts destination and source MAC address.
p_mac_sreg : process(clk)
    -- Input arrives N bits at a time, how many clocks until we have
    -- destination and source (96 bits total, may not divide evenly)
    constant DST_COUNT  : integer := (47+INPUT_WIDTH) / INPUT_WIDTH;
    constant SRC_COUNT  : integer := (95+INPUT_WIDTH) / INPUT_WIDTH;
    constant DST_SHIFT  : integer := 48 mod INPUT_WIDTH;
    variable sreg       : std_logic_vector(DST_COUNT*INPUT_WIDTH-1 downto 0) := (others => '0');
    variable count      : integer range 0 to SRC_COUNT := 0;
begin
    if rising_edge(clk) then
        -- Update shift register if applicable.
        -- Note: Ethernet is always MSW-first.
        if (in_wren = '1') then
            sreg := sreg(sreg'left-INPUT_WIDTH downto 0) & in_data;
        end if;

        -- Latch the source or destination MAC address (may be partial).
        -- (Need to handle the case where INPUT_WIDTH isn't a multiple of 48.)
        if (count < DST_COUNT) then
            mac_addr <= unsigned(sreg(sreg'left downto sreg'left-47));
        else
            mac_addr <= unsigned(sreg(sreg'left-DST_SHIFT downto sreg'left-DST_SHIFT-47));
        end if;
        mac_rdy_dst <= in_wren and bool2bit(count = DST_COUNT-1);
        mac_rdy_src <= in_wren and bool2bit(count = SRC_COUNT-1);

        -- Latch the source mask (and convert to index).
        if (in_wren = '1' and count = DST_COUNT-1) then
            mac_psrc   <= one_hot_decode_port(in_psrc);
            psrc_error <= one_hot_error(in_psrc);
        else
            psrc_error <= '0';
        end if;

        -- Update word-counting state machine.
        if (init_done = '0') then
            count := 0;
        elsif (in_wren = '1') then
            if (in_last = '1') then
                count := 0;         -- Get ready for next frame.
            elsif (count < SRC_COUNT) then
                count := count + 1; -- Still reading MAC header.
            end if;
        end if;
    end if;
end process;

-- Instantiate each of the first-stage matching units.
-- This process should implement as an array of dual-port Nx1 LUTRAM.
gen_cam_word : for n in 0 to LUTRAM_COUNT-1 generate
    local : block
        signal wr_addr, rd_addr : sub_addr_t;
    begin
        -- Each LUTRAM bank (64xN typ.) shares a common address.
        wr_addr <= get_subaddr(camwr_mac, n);
        rd_addr <= get_subaddr(mac_addr, n);

        -- Instantiate each LUTRAM bit in the bank...
        gen_cam_bit : for b in 0 to TABLE_SIZE-1 generate
            u_lutram : entity work.lutram
                generic map(AWIDTH => LUTRAM_WIDTH)
                port map(
                clk     => clk,
                wraddr  => wr_addr,
                wren    => camwr_mask(b),
                wrval   => camwr_twr,
                rdaddr  => rd_addr,
                rdval   => camrd_masks(n)(b));
        end generate;
    end block;
end generate;

-- Control logic for first-stage matching.
p_cam : process(clk)
    function and_reduce(x : cam_mask_array) return cam_mask_t is
        variable tmp : cam_mask_t := (others => '1');
    begin
        for n in x'range loop
            tmp := tmp and x(n);
        end loop;
        return tmp;
    end function;

    variable tmp1_mask      : cam_mask_t := (others => '0');
    variable tmp1_psrc      : port_idx_t := (others => '0');
    variable tmp1_macaddr   : mac_addr_t := (others => '0');
    variable tmp1_rdy_dst   : std_logic := '0';
    variable tmp1_rdy_src   : std_logic := '0';
    variable tmp0_psrc      : port_idx_t := (others => '0');
    variable tmp0_macaddr   : mac_addr_t := (others => '0');
    variable tmp0_rdy_dst   : std_logic := '0';
    variable tmp0_rdy_src   : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Pipeline stage 2: One-hot decoder (or no-match)
        cam_tidx     <= one_hot_decode_tidx(tmp1_mask);
        cam_error    <= one_hot_error(tmp1_mask);
        cam_match    <= or_reduce(tmp1_mask);
        cam_macaddr  <= tmp1_macaddr;
        cam_psrc     <= tmp1_psrc;
        cam_rdy_dst  <= tmp1_rdy_dst;
        cam_rdy_src  <= tmp1_rdy_src;

        -- Pipeline stage 1: AND-reduce the partial-match masks.
        tmp1_mask    := and_reduce(camrd_masks);
        tmp1_psrc    := tmp0_psrc;  -- Matched delay
        tmp1_macaddr := tmp0_macaddr;
        tmp1_rdy_dst := tmp0_rdy_dst;
        tmp1_rdy_src := tmp0_rdy_src;

        -- Pipeline stage 0: Matched delay for camrd_masks
        tmp0_psrc    := mac_psrc;
        tmp0_macaddr := mac_addr;
        tmp0_rdy_dst := mac_rdy_dst;
        tmp0_rdy_src := mac_rdy_src;
    end if;
end process;

-- Secondary lookup table.
-- (This process should infer as LUTRAM or BRAM.)
p_table : process(clk)
    type tbl_array_t is array(0 to TIDX_MAX) of port_idx_t;
    variable table : tbl_array_t := (others => (others => '0'));
begin
    if rising_edge(clk) then
        -- Note: We don't particularly care about read/write order.
        tbl_pidx <= table(to_integer(cam_tidx));
        if (camwr_twr = '1') then
            table(to_integer(camwr_tidx)) := camwr_psrc;
        end if;
    end if;
end process;

-- Final output mask generation.
p_result : process(clk)
    function make_mask(x : port_idx_t) return port_mask_t is
        variable tmp : port_mask_t := (others => '0');
    begin
        if (x < PORT_COUNT) then
            tmp(to_integer(x)) := '1';
        end if;
        return tmp;
    end function;

    variable tbl_psrc       : port_idx_t := (others => '0');
    variable tbl_bcast      : std_logic := '0';
    variable tbl_rdy_dst    : std_logic := '0';
    variable tbl_match      : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Pipeline stage 1: Generate the destination port mask.
        if (tbl_rdy_dst = '1') then
            if (tbl_bcast = '1' or tbl_match = '0') then
                -- Broadcast or no-match: Send to all EXCEPT source.
                pdst_mask <= not make_mask(tbl_psrc);
            else
                -- Normal case: Destination from table lookup.
                pdst_mask <= make_mask(tbl_pidx);
            end if;
        end if;

        -- Two options for output flow control (see below).
        pdst_rdy <= tbl_rdy_dst;                -- FIFO mode

        if (reset_p = '1' or OUT_FIFO_SZ > 0) then  -- Direct mode
            pdst_valid <= '0';      -- Reset
        elsif (tbl_rdy_dst = '1') then
            pdst_valid <= '1';      -- New data
        elsif (out_ready = '1') then
            pdst_valid <= '0';      -- Consumed
        end if;

        -- Detect lost-data errors in either mode.
        -- If this ever occurs, increase switch_core delay or output FIFO size.
        if (OUT_FIFO_SZ > 0) then
            pdst_error <= fifo_error;
        else
            pdst_error <= tbl_rdy_dst and pdst_valid and not out_ready;
        end if;
        assert (pdst_error = '0')
            report "PDST output lost data." severity error;

        -- Pipeline stage 0: Matched delay for table lookup.
        -- (And detection for the "broadcast" special-case.)
        tbl_bcast   := bool2bit(cam_macaddr = BROADCAST_MAC);
        tbl_psrc    := cam_psrc;
        tbl_match   := cam_match;
        tbl_rdy_dst := cam_rdy_dst;
    end if;
end process;

-- Optionally instantiate a small FIFO for output flow control.
-- This may be required 
gen_fifo : if OUT_FIFO_SZ > 0 generate
    u_fifo : entity work.smol_fifo
        generic map(
        DEPTH_LOG2  => OUT_FIFO_SZ,
        IO_WIDTH    => PORT_COUNT)
        port map(
        in_data     => pdst_mask,
        in_write    => pdst_rdy,
        out_data    => out_pdst,
        out_valid   => out_valid,
        out_read    => out_ready,
        fifo_hempty => fifo_ready,
        fifo_error  => fifo_error,
        reset_p     => reset_p,
        clk         => clk);
end generate;

gen_nofifo : if OUT_FIFO_SZ <= 0 generate
    out_pdst    <= pdst_mask;
    out_valid   <= pdst_valid;
    fifo_ready  <= '1'; -- Unused
    fifo_error  <= '0';
end generate;

-- Write control for both tables (including initial startup).
p_wrctrl : process(clk)
    function make_mask(x : tbl_addr_t) return cam_mask_t is
        variable tmp : cam_mask_t := (others => '0');
    begin
        if (x < TABLE_SIZE) then
            tmp(to_integer(x)) := '1';
        end if;
        return tmp;
    end function;
begin
    if rising_edge(clk) then
        -- Track the number of table entries.
        if (init_done = '0') then
            camwr_full  <= '0';
            camwr_tidx  <= (others => '0');
        elsif (camwr_twr = '1') then
            camwr_full  <= bool2bit(camwr_tidx = TABLE_SIZE-1);
            camwr_tidx  <= camwr_tidx + 1;
        end if;

        -- Startup and update state machine.
        camwr_twr   <= '0';
        camwr_ovr   <= '0';
        camwr_psrc  <= cam_psrc;
        if (reset_p = '1') then
            -- Idle during reset.
            init_count  <= (others => '0');
            init_done   <= '0';
            camwr_mac   <= (others => '0');
            camwr_mask  <= (others => '1');
        elsif (init_done = '0') then
            -- On startup, clear 1st-stage CAM one row at a time.
            init_count  <= init_count + 1;
            init_done   <= bool2bit(init_count = 63);
            camwr_mask  <= (others => '1'); -- Clear all bits
            camwr_mac   <= init_count & init_count & init_count & init_count
                         & init_count & init_count & init_count & init_count;
        elsif (cam_rdy_src = '1' and cam_match = '0') then
            -- Attempt to write a new entry to the table.
            camwr_twr   <= not camwr_full;  -- Table write
            camwr_ovr   <= camwr_full;      -- Table overflow
            camwr_mac   <= cam_macaddr;
            -- Set the new "present" flag for the appropriate bit.
            -- (The same mask is written to each CAM table.)
            camwr_mask  <= make_mask(camwr_tidx);
        else
            -- Idle.
            camwr_mask  <= (others => '0');
        end if;
    end if;
end process;

end mac_lookup_lutram;
