--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Virtual-LAN tag parsing and removal
--
-- When Virtual-LAN is enabled, this block is inserted just after the FCS
-- field is checked and removed.  It looks for VLAN tags in the incoming data,
-- removes them if present, and enforces port-specific tag policy rules.
--
-- Per 802.1Q section 6.9, there are three supported policy modes:
--  * 00 = Admit all frames (default)
--  * 01 = Admit only untagged and priority-tagged frames
--  * 10 = Admit only VLAN-tagged frames
--  * 11 = Reserved
-- Violations of these policies cause the packet to be rejected.
--
-- Tag Control Information (TCI) is made available as output metadata,
-- containing the PCP, DEI, and VID fields for each frame.  Each switch port
-- also sets default values for each TCI field.  The output TCI is as follows:
--  * If no tag is present at the input, all fields use the port default.
--  * If the tag has a reserved VID (000 or FFF), then the output VID is
--    the port default but other fields are copied from the tag.
--  * Otherwise, all fields are copied from the tag.
--
-- Configuration of per-port policy and  TCI settings are loaded through
-- a single write-only ConfigBus register, which must be written atomically:
--  * Bits 31-24: Port index to be configured
--  * Bits 23-22: Reserved (write zeros)
--  * Bits 21-20: Egress policy (see "eth_frame_vtag.vhd")
--  * Bits 19-18: Reserved (write zeros)
--  * Bits 17-16: Ingress policy (see above)
--  * Bits 15-13: Default TCI: Priority Code Point (PCP)
--  * Bits 12-12: Default TCI: Drop eligible indicator (DEI)
--  * Bits 11-00: Default TCI: VLAN identifier (VID)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_vstrip is
    generic (
    DEVADDR     : integer;      -- ConfigBus device address
    REGADDR     : integer;      -- ConfigBus register address
    IO_BYTES    : positive;     -- Width of main data ports
    PORT_INDEX  : natural;      -- Index of the current port
    VID_DEFAULT : vlan_vid_t := x"001");
    port (
    -- Main input stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_write    : in  std_logic;
    in_nlast    : in  integer range 0 to IO_BYTES := IO_BYTES;
    in_commit   : in  std_logic;
    in_revert   : in  std_logic;
    in_error    : in  std_logic;

    -- Modified output stream, with metadata
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_vtag    : out vlan_hdr_t;
    out_write   : out std_logic;
    out_nlast   : out integer range 0 to IO_BYTES;
    out_commit  : out std_logic;
    out_revert  : out std_logic;
    out_error   : out std_logic;

    -- Configuration interface (write-only)
    cfg_cmd     : in  cfgbus_cmd;

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_vstrip;

architecture eth_frame_vstrip of eth_frame_vstrip is

constant META_WIDTH     : positive := VLAN_HDR_WIDTH + 3;
constant WCOUNT_MAX     : positive := 1 + (HEADER_CRC_BYTES / IO_BYTES);
constant VTAG_DEFAULT   : vlan_hdr_t :=
    vlan_get_hdr(PCP_NONE, DEI_NONE, VID_DEFAULT);

-- Data FIFO size estimator.
function get_fifo_size return positive is
begin
    -- Buffer has a total depth of IO_BYTES * 2^N.
    -- Choose N so that this delay is at least 18 bytes.
    if (IO_BYTES = 1) then
        return 5;   -- 2^5 = 32 >= 18 bytes
    else
        return 4;   -- 2^4 * IO_BYTES >= 18 bytes
    end if;
end function;

-- Input buffering
signal in_last      : std_logic;
signal in_bmask     : std_logic_vector(IO_BYTES-1 downto 0);
signal in_wcount    : integer range 0 to WCOUNT_MAX := 0;
signal pre_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal pre_bmask    : std_logic_vector(IO_BYTES-1 downto 0);
signal pre_last     : std_logic;
signal pre_valid    : std_logic;
signal pre_ready    : std_logic;
signal pre_write    : std_logic;
signal pre_wcount   : integer range 0 to WCOUNT_MAX := 0;

-- Input parsing
signal parse_vtag   : std_logic := '0';
signal parse_wtag   : std_logic := '0';
signal parse_vhdr   : vlan_hdr_t := (others => '0');
signal parse_commit : std_logic := '0';
signal parse_revert : std_logic := '0';
signal parse_error  : std_logic := '0';
signal parse_panic  : std_logic := '0';
signal parse_write  : std_logic := '0';

-- Buffered per-packet metdata
signal frm_vtag     : std_logic;
signal frm_vhdr     : vlan_hdr_t := (others => '0');
signal frm_commit   : std_logic := '0';
signal frm_revert   : std_logic := '0';
signal frm_error    : std_logic := '0';
signal frm_panic    : std_logic := '0';
signal frm_valid    : std_logic;
signal frm_next     : std_logic;

-- Re-packing FIFO
signal fifo_data    : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal fifo_meta    : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal fifo_last    : std_logic := '0';
signal fifo_write   : std_logic_vector(IO_BYTES-1 downto 0);
signal out_meta_i   : std_logic_vector(META_WIDTH-1 downto 0);
signal out_last_i   : std_logic;

-- ConfigBus interface
signal cfg_policy   : tag_policy_t := VTAG_ADMIT_ALL;
signal cfg_default  : vlan_hdr_t := VTAG_DEFAULT;

begin

-- Normalize input stream so NLAST field isn't doing double-duty.
in_last     <= in_commit or in_revert or in_error;
gen_bmask : for n in in_bmask'range generate
    in_bmask(n) <= bool2bit(n < in_nlast) or not in_last;
end generate;

-- Parse each field as it passes through the main input stream.
p_parse : process(clk)
    variable has_tag : std_logic := '0';
    variable temp : byte_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Does the outer EtherType field indicate an 802.1Q tag? (TPID = 0x8100)
        -- (Depending on bus width, these might happen in sequence or all at once.)
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+0, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+0, in_data);
            has_tag := bool2bit(temp = x"81");
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+1, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+1, in_data);
            has_tag := has_tag and bool2bit(temp = x"00");
            parse_wtag <= '1';  -- Write flag to FIFO
        else
            parse_wtag <= '0';  -- Idle
        end if;
        parse_vtag <= has_tag;

        -- Latch tag contents (ignored if not present).
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+2, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+2, in_data);
            parse_vhdr(15 downto 8) <= temp;
        end if;
        if (in_write = '1' and strm_byte_present(IO_BYTES, ETH_HDR_ETYPE+3, in_wcount)) then
            temp := strm_byte_value(IO_BYTES, ETH_HDR_ETYPE+3, in_data);
            parse_vhdr(7 downto 0) <= temp;
        end if;

        -- Set the panic flag if EOF arrives mid-tag.
        if (in_write = '1' and in_wcount = 0) then
            parse_panic <= '0';
        end if;
        if (in_write = '1' and in_last = '1' and has_tag = '1'
            and IO_BYTES*in_wcount + in_nlast < ETH_HDR_ETYPE+6) then
            parse_panic <= '1';
        end if;

        -- Push new frame metadata at the end of each frame.
        if (in_write = '1' and in_last = '1') then
            parse_commit    <= in_commit;
            parse_revert    <= in_revert;
            parse_error     <= in_error;
            parse_write     <= '1';
        else
            parse_write     <= '0';
        end if;

        -- Track current position in each frame.
        -- (Separate counters synchronized to "in_data" and "pre_data".)
        if (reset_p = '1' or (in_write = '1' and in_last = '1')) then
            in_wcount <= 0;
        elsif (in_write = '1' and in_wcount < WCOUNT_MAX) then
            in_wcount <= in_wcount + 1;
        end if;

        if (reset_p = '1' or (pre_write = '1' and pre_last = '1')) then
            pre_wcount <= 0;
        elsif (pre_write = '1' and pre_wcount < WCOUNT_MAX) then
            pre_wcount <= pre_wcount + 1;
        end if;
    end if;
end process;

-- Main FIFO buffers raw data until we've read all required headers.
pre_write <= pre_valid and pre_ready and (frm_valid or not pre_last);
frm_next  <= pre_write and pre_last;

u_fifo_data : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8*IO_BYTES,
    META_WIDTH  => IO_BYTES,
    DEPTH_LOG2  => get_fifo_size)
    port map(
    in_data     => in_data,
    in_meta     => in_bmask,
    in_last     => in_last,
    in_write    => in_write,
    out_data    => pre_data,
    out_meta    => pre_bmask,
    out_last    => pre_last,
    out_valid   => pre_valid,
    out_read    => pre_write,
    clk         => clk,
    reset_p     => reset_p);

-- A separate FIFO buffers the "tag-present" flag.
-- (Required much earlier than other per-frame metadata.)
u_fifo_vtag : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 1)
    port map(
    in_data(0)  => parse_vtag,
    in_write    => parse_wtag,
    out_data(0) => frm_vtag,
    out_valid   => pre_ready,
    out_read    => frm_next,
    clk         => clk,
    reset_p     => reset_p);

-- Depending on IO_BYTES, may need another FIFO for per-frame metadata.
-- (Depends on delay between end-of-frame vs. header fields of next frame.)
gen_meta1 : if IO_BYTES > 1 generate
    u_fifo_meta : entity work.fifo_smol_sync
        generic map(
        IO_WIDTH    => VLAN_HDR_WIDTH,
        META_WIDTH  => 4)
        port map(
        in_data     => parse_vhdr,
        in_meta(0)  => parse_commit,
        in_meta(1)  => parse_revert,
        in_meta(2)  => parse_error,
        in_meta(3)  => parse_panic,
        in_write    => parse_write,
        out_data    => frm_vhdr,
        out_meta(0) => frm_commit,
        out_meta(1) => frm_revert,
        out_meta(2) => frm_error,
        out_meta(3) => frm_panic,
        out_valid   => frm_valid,
        out_read    => frm_next,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_meta0 : if IO_BYTES = 1 generate
    frm_vhdr    <= parse_vhdr;
    frm_commit  <= parse_commit;
    frm_revert  <= parse_revert;
    frm_error   <= parse_error;
    frm_panic   <= parse_panic;
    frm_valid   <= '1';
end generate;

-- Once we know whether a tag is present, decide which bytes to keep.
p_keep : process(clk)
    variable bidx : integer range 0 to IO_BYTES*(WCOUNT_MAX+1)-1 := 0;
    variable oidx : integer range 0 to IO_BYTES-1 := 0;
    variable tmp_pcp : vlan_pcp_t;
    variable tmp_dei : vlan_dei_t;
    variable tmp_vid : vlan_vid_t;
    variable tmp_commit, tmp_revert, tmp_error : std_logic;
begin
    if rising_edge(clk) then
        -- Matched delay for the bulk data.
        fifo_data <= pre_data;

        -- Update WRITE and LAST strobes.
        if (reset_p = '1' or pre_write = '0') then
            -- No data this cycle.
            fifo_write  <= (others => '0');
            fifo_last   <= '0';
        else
            -- Drive the LAST strobe.
            fifo_last   <= pre_last;
            -- Decide each WRITE strobe individually.
            for b in IO_BYTES-1 downto 0 loop
                bidx := IO_BYTES * pre_wcount + b;
                oidx := IO_BYTES - 1 - b;
                if (pre_last = '1' and frm_panic = '1') then
                    -- Illegal mid-tag EOF -> We will discard this frame, so
                    -- write anything to ensure LAST/REVERT strobe survives.
                    fifo_write(oidx) <= '1';
                elsif (frm_vtag = '1' and 12 <= bidx and bidx < 16) then
                    fifo_write(oidx) <= '0';            -- Drop tag contents
                else
                    fifo_write(oidx) <= pre_bmask(b);   -- Copy input mask
                end if;
            end loop;
        end if;

        -- Latch frame metadata on the last word only.
        if (pre_write = '1' and pre_last = '1') then
            -- Override specific VLAN tag fields as needed.
            if (frm_vtag = '0') then
                tmp_pcp := vlan_get_pcp(cfg_default);   -- No user tag
                tmp_dei := vlan_get_dei(cfg_default);
                tmp_vid := vlan_get_vid(cfg_default);
            elsif (vlan_get_vid(frm_vhdr) = VID_NONE) then
                tmp_pcp := vlan_get_pcp(frm_vhdr);    -- Priority tag
                tmp_dei := vlan_get_dei(frm_vhdr);
                tmp_vid := vlan_get_vid(cfg_default);
            else
                tmp_pcp := vlan_get_pcp(frm_vhdr);    -- Full tag
                tmp_dei := vlan_get_dei(frm_vhdr);
                tmp_vid := vlan_get_vid(frm_vhdr);
            end if;
            -- Keep or modify the commit/revert/error strobes.
            if (frm_panic = '1') then
                tmp_commit  := '0';             -- Bad frame with incomplete tag.
                tmp_revert  := '1';
                tmp_error   := '1';
            elsif (frm_vtag = '1' and vlan_get_vid(frm_vhdr) = VID_RSVD) then
                tmp_commit  := '0';             -- Reserved VID is always rejected.
                tmp_revert  := '1';
                tmp_error   := '1';
            elsif (cfg_policy = VTAG_PRIORITY and
                (frm_vtag = '1' and vlan_get_vid(frm_vhdr) /= VID_NONE)) then
                tmp_commit  := '0';             -- VID not allowed in this mode.
                tmp_revert  := '1';
                tmp_error   := '1';
            elsif (cfg_policy = VTAG_MANDATORY and
                (frm_vtag = '0' or vlan_get_vid(frm_vhdr) = VID_NONE)) then
                tmp_commit  := '0';             -- Tags are mandatory in this mode
                tmp_revert  := '1';
                tmp_error   := '1';
            else
                tmp_commit  := frm_commit;    -- All other cases -> Copy input
                tmp_revert  := frm_revert;
                tmp_error   := frm_error;
            end if;
            -- Metadata word appends all of the above fields.
            fifo_meta <= tmp_commit & tmp_revert & tmp_error
                & vlan_get_hdr(tmp_pcp, tmp_dei, tmp_vid);
        end if;
    end if;
end process;

-- Repack partial words into dense form for fifo_packet.
u_repack : entity work.fifo_repack
    generic map(
    LANE_COUNT  => IO_BYTES,
    META_WIDTH  => META_WIDTH)
    port map(
    in_data     => fifo_data,
    in_meta     => fifo_meta,
    in_last     => fifo_last,
    in_write    => fifo_write,
    out_data    => out_data,
    out_meta    => out_meta_i,
    out_nlast   => out_nlast,
    out_last    => out_last_i,
    out_write   => out_write,
    clk         => clk,
    reset_p     => reset_p);

-- Unpack final metadata and end-of-frame strobes.
out_commit  <= out_last_i and out_meta_i(VLAN_HDR_WIDTH+2);
out_revert  <= out_last_i and out_meta_i(VLAN_HDR_WIDTH+1);
out_error   <= out_last_i and out_meta_i(VLAN_HDR_WIDTH+0);
out_vtag    <= out_meta_i(VLAN_HDR_WIDTH-1 downto 0);

-- ConfigBus interface handling.
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_cmd.reset_p = '1') then
            -- Global reset reverts to required default under 802.1Q.
            cfg_policy  <= VTAG_ADMIT_ALL;
            cfg_default <= VTAG_DEFAULT;
        elsif (cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR)) then
            -- Ignore writes unless they have a matching port-index.
            if (u2i(cfg_cmd.wdata(31 downto 24)) = PORT_INDEX) then
                cfg_policy  <= cfg_cmd.wdata(17 downto 16);
                cfg_default <= cfg_cmd.wdata(15 downto 0);
            end if;
        end if;
    end if;
end process;

end eth_frame_vstrip;
