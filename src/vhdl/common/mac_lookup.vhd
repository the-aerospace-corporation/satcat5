--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
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
-- MAC-address lookup using LUTRAM-based TCAM
--
-- This block includes all of the logic required to automatically learn
-- the MAC address(es) associated with each switch port, then lookup
-- the destination port(s) for each frame.
--
-- In most cases, a single TCAM block is used to search for source and
-- destination addresses in sequence.  However, for very wide datapaths
-- (>= 96 bits), two copies of the TCAM are instantiated and kept in sync
-- to allow concurrent searches.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.tcam_constants.all;

entity mac_lookup is
    generic (
    IO_BYTES        : positive;         -- Width of main data port
    PORT_COUNT      : positive;         -- Number of Ethernet ports
    TABLE_SIZE      : positive;         -- Max stored MAC addresses
    MISS_BCAST      : std_logic;        -- Broadcast or drop unknown MAC?
    CACHE_POLICY    : repl_policy);     -- TCAM cache-replacement strategy
    port (
    -- Main input (Ethernet frame)
    -- PSRC is the input port-index and must be held for the full frame.
    in_psrc         : in  integer range 0 to PORT_COUNT-1;
    in_wcount       : in  mac_bcount_t;
    in_data         : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_last         : in  std_logic;
    in_write        : in  std_logic;

    -- Search result is the port mask for the destination port(s).
    out_psrc        : out integer range 0 to PORT_COUNT-1;
    out_pmask       : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- Promiscuous-port mask.
    cfg_prmask      : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- Error strobes
    error_change    : out std_logic;    -- MAC address changed ports
    error_table     : out std_logic;    -- Table integrity check failed

    -- System interface
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end mac_lookup;

architecture mac_lookup of mac_lookup is

-- Convert integer indices to std_logic_vector.
constant PIDX_WIDTH : natural := log2_ceil(PORT_COUNT);
constant TIDX_WIDTH : natural := log2_ceil(TABLE_SIZE);
subtype port_idx_t is std_logic_vector(PIDX_WIDTH-1 downto 0);
subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype tbl_idx_t is integer range 0 to TABLE_SIZE-1;
subtype tbl_idx_u is std_logic_vector(TIDX_WIDTH-1 downto 0);

-- Special MAC addresses should never be written to the TCAM.
-- As destination, all except "swcontrol" are treated as broadcast.
-- (Multicast distribution is restricted by IGMP-snooping, if enabled.)
function mac_is_special(mac : mac_addr_t) return std_logic is
begin
    return bool2bit(
        mac_is_swcontrol(mac) or
        mac_is_l2multicast(mac) or
        mac_is_l3multicast(mac) or
        mac_is_broadcast(mac));
end function;

-- Filtered MAC addresses are any that should never be relayed.
-- (e.g., The local-link addresses for controlling managed switches.)
function mac_is_filtered(mac : mac_addr_t) return std_logic is
begin
    return bool2bit(mac_is_swcontrol(mac));
end function;

-- Extract destination and source MAC address.
signal pkt_psrc     : port_idx_t := (others => '0');
signal pkt_dst_mac  : mac_addr_t := (others => '0');
signal pkt_dst_rdy  : std_logic := '0';
signal pkt_src_mac  : mac_addr_t := (others => '0');
signal pkt_src_rdy  : std_logic := '0';

-- TCAM search results
signal find_psrc    : port_idx_t := (others => '0');
signal find_dst_idx : port_idx_t := (others => '0');
signal find_dst_all : std_logic := '0';
signal find_dst_drp : std_logic := '0';
signal find_dst_ok  : std_logic := '0';
signal find_dst_rdy : std_logic := '0';
signal find_src_mac : mac_addr_t := (others => '0');
signal find_src_idx : port_idx_t := (others => '0');
signal find_src_drp : std_logic := '0';
signal find_src_ok  : std_logic := '0';
signal find_src_rdy : std_logic := '0';
signal find_error   : std_logic := '0';

-- Final output mask and queueing.
signal dst_pmask    : port_mask_t;
signal out_pvec     : port_idx_t;

-- Address-learning filter.
signal learn_addr   : mac_addr_t := (others => '0');
signal learn_pidx   : port_idx_t := (others => '0');
signal learn_write  : std_logic := '0';
signal learn_error  : std_logic := '0';

-- Queued writes to TCAM.
signal cfg_macaddr  : mac_addr_t := (others => '0');
signal cfg_pidx     : port_idx_t;
signal cfg_valid    : std_logic;
signal cfg_ready    : std_logic;
signal cfg_wren     : std_logic;

begin

-- Top-level error strobes.
error_change <= learn_error;
error_table  <= find_error;

-- Extract destination and source MAC address.
p_pkt : process(clk)
    variable temp : byte_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Confirm each field as it passes through on the main stream.
        -- (Depending on bus width, these might happen in sequence or all at once.)
        for n in 0 to 5 loop
            if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+n, in_wcount)) then
                temp := strm_byte_value(IO_BYTES, ETH_HDR_DSTMAC+n, in_data);
                pkt_dst_mac(47-8*n downto 40-8*n) <= temp;  -- MSB-first
            end if;
            if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_SRCMAC+n, in_wcount)) then
                temp := strm_byte_value(IO_BYTES, ETH_HDR_SRCMAC+n, in_data);
                pkt_src_mac(47-8*n downto 40-8*n) <= temp;  -- MSB-first
            end if;
        end loop;

        -- Ready strobes asserted on the last byte in each field.
        pkt_psrc    <= i2s(in_psrc, PIDX_WIDTH);
        pkt_dst_rdy <= in_write and bool2bit(strm_byte_present(IO_BYTES, ETH_HDR_DSTMAC+5, in_wcount));
        pkt_src_rdy <= in_write and bool2bit(strm_byte_present(IO_BYTES, ETH_HDR_SRCMAC+5, in_wcount));
    end if;
end process;

-- Instantiate either one or two TCAM units.
gen_tcam1 : if (IO_BYTES < 12) generate
    local : block
        signal pkt_addr     : mac_addr_t;
        signal pkt_rdy      : std_logic;
        signal tcam_pre_mac : mac_addr_t;
        signal tcam_pre_rdy : std_logic;
        signal tcam_mac     : mac_addr_t;
        signal tcam_pidx    : port_idx_t;
        signal tcam_psrc    : port_idx_t;
        signal tcam_ok      : std_logic;
        signal cfg_tidx     : tbl_idx_t;
    begin
        -- Search destination, then source.
        pkt_addr <= pkt_dst_mac when (pkt_dst_rdy = '1') else pkt_src_mac;
        pkt_rdy  <= pkt_dst_rdy or pkt_src_rdy;

        u_tcam : entity work.tcam_table
            generic map(
            IN_WIDTH    => MAC_ADDR_WIDTH,  -- Search by MAC address = 48 bits
            META_WIDTH  => PIDX_WIDTH,      -- Matched delay for source index
            OUT_WIDTH   => PIDX_WIDTH,      -- Result is the physical port-index
            TABLE_SIZE  => TABLE_SIZE,      -- User sets cache size
            REPL_MODE   => CACHE_POLICY,    -- User sets cache policy
            TCAM_MODE   => TCAM_MODE_CONFIRM)
            port map(
            in_meta     => pkt_psrc,
            in_search   => pkt_addr,
            in_next     => pkt_rdy,
            pre_search  => tcam_pre_mac,
            pre_next    => tcam_pre_rdy,
            out_meta    => tcam_psrc,
            out_search  => tcam_mac,
            out_result  => tcam_pidx,
            out_found   => tcam_ok,
            out_error   => find_error,
            cfg_suggest => cfg_tidx,
            cfg_index   => cfg_tidx,
            cfg_search  => cfg_macaddr,
            cfg_result  => cfg_pidx,
            cfg_valid   => cfg_valid,
            cfg_ready   => cfg_ready,
            clk         => clk,
            reset_p     => reset_p);

        -- Extract DST results for output, and SRC results for learning.
        -- (Most fields are simply duplicated due to time-multiplexing.)
        find_psrc       <= tcam_psrc;
        find_src_mac    <= tcam_mac;
        find_dst_idx    <= tcam_pidx;
        find_src_idx    <= tcam_pidx;
        find_dst_ok     <= tcam_ok;
        find_src_ok     <= tcam_ok;

        -- Matched delay for associated metadata.
        p_lookup : process(clk)
            variable tcam_tog : std_logic := '0';
        begin
            if rising_edge(clk) then
                -- Filter for various special MAC addresses.
                find_dst_all    <= mac_is_special(tcam_pre_mac);
                find_dst_drp    <= mac_is_filtered(tcam_pre_mac);
                find_src_drp    <= mac_is_special(tcam_pre_mac);

                -- Output-ready strobe toggles between destination and source.
                -- TODO: Is there a good way to resync this after SEU or other error?
                find_dst_rdy    <= (tcam_pre_rdy and not reset_p) and not tcam_tog;
                find_src_rdy    <= (tcam_pre_rdy and not reset_p) and tcam_tog;
                if (reset_p = '1') then
                    tcam_tog := '0';
                elsif (tcam_pre_rdy = '1') then
                    tcam_tog := not tcam_tog;
                end if;
            end if;
        end process;
    end block;
end generate;

gen_tcam2 : if (IO_BYTES >= 12) generate
    local : block
        signal tsrc_err     : std_logic;
        signal tdst_err     : std_logic;
        signal pre_dst_mac  : mac_addr_t;
        signal pre_src_mac  : mac_addr_t;
        signal cfg_tidx     : tbl_idx_t;
    begin
        -- Search destination and source concurrently.
        u_tcam0 : entity work.tcam_table
            generic map(
            IN_WIDTH    => MAC_ADDR_WIDTH,  -- Search by MAC address = 48 bits
            META_WIDTH  => PIDX_WIDTH,      -- Matched delay for source index
            OUT_WIDTH   => PIDX_WIDTH,      -- Result is the physical port index
            TABLE_SIZE  => TABLE_SIZE,      -- User sets cache size
            REPL_MODE   => CACHE_POLICY,    -- User sets cache policy
            TCAM_MODE   => TCAM_MODE_CONFIRM)
            port map(
            in_meta     => pkt_psrc,
            in_search   => pkt_src_mac,
            in_next     => pkt_src_rdy,
            pre_search  => pre_src_mac,
            out_meta    => find_psrc,
            out_search  => find_src_mac,
            out_result  => find_src_idx,
            out_found   => find_src_ok,
            out_next    => find_src_rdy,
            out_error   => tsrc_err,
            cfg_suggest => cfg_tidx,
            cfg_index   => cfg_tidx,
            cfg_search  => cfg_macaddr,
            cfg_result  => cfg_pidx,
            cfg_valid   => cfg_valid,
            cfg_ready   => cfg_ready,
            clk         => clk,
            reset_p     => reset_p);

        u_tcam1 : entity work.tcam_table
            generic map(
            IN_WIDTH    => MAC_ADDR_WIDTH,  -- Search by MAC address = 48 bits
            OUT_WIDTH   => PIDX_WIDTH,      -- Result is the physical port index
            TABLE_SIZE  => TABLE_SIZE,      -- Same table size as TCAM0
            REPL_MODE   => TCAM_REPL_WRAP,  -- Cache controlled by TCAM0
            TCAM_MODE   => TCAM_MODE_CONFIRM)
            port map(
            in_search   => pkt_dst_mac,
            in_next     => pkt_dst_rdy,
            pre_search  => pre_dst_mac,
            out_result  => find_dst_idx,
            out_found   => find_dst_ok,
            out_next    => find_dst_rdy,
            out_error   => tdst_err,
            cfg_suggest => open,            -- Cache controlled by TCAM0
            cfg_index   => cfg_tidx,
            cfg_search  => cfg_macaddr,
            cfg_result  => cfg_pidx,
            cfg_valid   => cfg_valid,
            cfg_ready   => open,            -- Identical to TCAM0
            clk         => clk,
            reset_p     => reset_p);

        -- Matched delay for associated metadata.
        p_lookup : process(clk)
        begin
            if rising_edge(clk) then
                find_dst_all    <= mac_is_special(pre_dst_mac);
                find_dst_drp    <= mac_is_filtered(pre_dst_mac);
                find_src_drp    <= mac_is_special(pre_src_mac);
                find_error      <= tsrc_err or tdst_err;
            end if;
        end process;
    end block;
end generate;

-- Set the destination mask based on search results:
--  * Never loop any packet back to its origin.
--  * Switch control -> Drop
--  * Broadcast, multicast, or promiscuous -> Broadcast
--  * Cache miss -> Broadcast or drop per user setting
--  * Cache hit -> Send to designated port
gen_dst_mask : for n in dst_pmask'range generate
    dst_pmask(n) <= '0' when (n = u2i(find_psrc))           -- Loopback
               else '0' when (find_dst_drp = '1')           -- Switch control
               else '1' when (cfg_prmask(n) = '1')          -- Promiscuous
               else '1' when (find_dst_all = '1')           -- Broadcast
               else MISS_BCAST when (find_dst_ok = '0')     -- Miss
               else bool2bit(n = u2i(find_dst_idx));        -- Hit
end generate;

-- Final output FIFO 
out_psrc <= u2i(to_01_vec(out_pvec));

u_dst_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => PORT_COUNT,
    META_WIDTH  => PIDX_WIDTH)
    port map(
    in_data     => dst_pmask,
    in_meta     => find_psrc,
    in_write    => find_dst_rdy,
    out_data    => out_pmask,
    out_meta    => out_pvec,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Address-learning filter.
p_learn : process(clk)
begin
    if rising_edge(clk) then
        -- Drive the write-enable strobe:
        if (reset_p = '1' or find_src_rdy = '0' or find_src_drp = '1') then
            learn_write <= '0'; -- Idle or ignored
            learn_error <= '0';
        elsif (find_src_ok = '0') then
            learn_write <= '1'; -- Cache miss -> Add to table
            learn_error <= '0';
        elsif (find_src_idx /= find_psrc) then
            learn_write <= '1'; -- Port change -> Update table
            learn_error <= '1';
        else
            learn_write <= '0'; -- Consistency check OK
            learn_error <= '0';
        end if;
        -- Matched delay for port-index and MAC-address fields.
        learn_pidx <= find_psrc;
        learn_addr <= find_src_mac;
    end if;
end process;

-- Queued writes to TCAM.
u_cfg_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => MAC_ADDR_WIDTH,  -- Data channel = MAC address
    META_WIDTH  => PIDX_WIDTH,      -- Meta channel = Port index
    ERROR_OVER  => false)           -- Safe to drop if overwhelmed
    port map(
    in_data     => learn_addr,
    in_meta     => learn_pidx,
    in_write    => learn_write,
    out_data    => cfg_macaddr,
    out_meta    => cfg_pidx,
    out_valid   => cfg_valid,
    out_read    => cfg_ready,
    clk         => clk,
    reset_p     => reset_p);

end mac_lookup;
