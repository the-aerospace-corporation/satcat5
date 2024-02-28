--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- MAC-pipeline processing for the Precision Time Protocol (PTP)
--
-- A PTP-enabled SatCat5 switch acts as an "End-to-end Transparent Clock"
-- as described in IEEE 1588-2019 Section 10.2.  This block is part of the
-- shared-medium switch pipeline, responsible for on-the-fly adjustment of
-- frame data and timestamp metadata.  It works in conjunction with final
-- per-port egress processing performed by "ptp_egress.vhd".
--
-- These tasks are:
--  * Identify PTP frames in both L2 (Ethernet) and L3 (UDP) format.
--    (The detected format is stored to simplify egress processing.)
--  * Extract the correctionField and subtract the ingress timestamp.
--    (Since egress timestamp is different for each port, the final
--     residence-time must be calculated and applied at that stage.)
--  * For PTP-over-UDP frames, overwrite and disable the UDP checksum.
--    (The Ethernet checksum must be recalculated during egress, but
--     the IEEE 1588 spec specifically allows bypass of UDP checksums.)
--  * If MIXED_STEP is asserted, duplicate and modify certain one-step
--    packets to aide in two-step conversion on a per-port basis:
--      * A ConfigBus register marks ports that require two-step conversion.
--      * Duplicate selected PTP packets, changing the second messageType
--        field to its complement (e.g., Sync -> Follow_up)
--      * Drive the "keep" mask to selectively retain each packet:
--          * Ports that are one-step capable (cfg_2step = '0'):
--            Retain original packet and drop the unneeded second packet.
--          * Ports that are two-step only (cfg_2step = '1'):
--            Retain both packets; egress port must set "twoStepFlag".
--  * Store per-frame outputs in a FIFO for cross-functional synchronization.
--
-- This block can auto-detect PTP frames in both L2 (Ethernet) and L3 (UDP)
-- format. Both modes are enabled by default, but can be bypassed to save
-- FPGA resources if only one mode is needed.
--
-- The update process follows rules from Section 10.2 using the "singleton"
-- option (Section 10.2.1 Note 1).  As such, this block always makes changes
-- to the active frame on-the-fly and does not require a cache for pairing with
-- past messages (e.g., Sync + Follow-up pairs).  This shortcut ignores certain
-- recommendations from the 2019 version of the standard, but remains compatible
-- with any endpoint following the delay calculation semantics from Annex J.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer_slv;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity ptp_adjust is
    generic (
    IO_BYTES    : positive;         -- Width of datapath
    PORT_COUNT  : positive;         -- Number of Ethernet ports
    MIXED_STEP  : boolean := true;  -- Step-type conversion?
    PTP_STRICT  : boolean := true;  -- Drop frames with missing timestamps?
    SUPPORT_L2  : boolean := true;  -- L2 supported? (Ethernet)
    SUPPORT_L3  : boolean := true); -- L3 supported? (UDP)
    port (
    -- Input data stream
    in_meta     : in  switch_meta_t;
    in_psrc     : in  integer range 0 to PORT_COUNT-1;
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;    -- AXI flow-control
    in_ready    : out std_logic;    -- AXI flow-control
    -- Modified data stream
    out_meta    : out switch_meta_t;
    out_psrc    : out integer range 0 to PORT_COUNT-1;
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;    -- AXI flow-control
    out_ready   : in  std_logic;    -- AXI flow-control
    -- Frame metadata: timestamp and "keep-frame" mask.
    cfg_2step   : in  std_logic_vector(PORT_COUNT-1 downto 0);
    frm_pmask   : out std_logic_vector(PORT_COUNT-1 downto 0);
    frm_pmode   : out ptp_mode_t;   -- PTP mode (Eth/UDP/None)
    frm_tstamp  : out tstamp_t;     -- Modified timestamp
    frm_valid   : out std_logic;    -- AXI flow-control
    frm_ready   : in  std_logic;    -- AXI flow-control
    -- ptp error
    ptp_err     : out std_logic;
    ptp_err_psrc: out integer range 0 to PORT_COUNT-1;
    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_adjust;

architecture ptp_adjust of ptp_adjust is

constant PIDX_WIDTH : positive := log2_ceil(PORT_COUNT);
constant META_WIDTH : positive := PIDX_WIDTH + SWITCH_META_WIDTH;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;
subtype mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype pidx_t is integer range 0 to PORT_COUNT-1;

-- Convert PSRC / Switch-meta to vector form and back.
function meta2vec(meta: switch_meta_t; psrc: pidx_t) return meta_t is
    constant temp : meta_t := i2s(psrc, PIDX_WIDTH) & switch_m2v(meta);
begin
    return temp;
end function;

function vec2meta(x: meta_t) return switch_meta_t is
    constant temp : switch_meta_v := x(SWITCH_META_WIDTH-1 downto 0);
begin
    return switch_v2m(temp);
end function;

function vec2psrc(x: meta_t) return pidx_t is
    constant temp : pidx_t := u2i(x(x'left downto SWITCH_META_WIDTH));
begin
    return temp;
end function;

-- Parser counts to the word just after the last possible header byte.
constant PTP_BYTE_MAX : positive := UDP_HDR_MAX + PTP_HDR_MSGDAT;
constant PTP_WORD_MAX : positive := 1 + (PTP_BYTE_MAX / IO_BYTES);

-- Input stream and associated metadata.
signal in_meta_vec  : meta_t;
signal in_ready_i   : std_logic;
signal port_2step   : mask_t;

-- Packet-cloning buffer (if MIXED_STEP is enabled).
signal mix_data     : data_t;
signal mix_nlast    : last_t;
signal mix_meta     : meta_t;
signal mix_valid    : std_logic;
signal mix_ready    : std_logic;
signal mix_original : std_logic;
signal mix_wcount   : integer range 0 to PTP_WORD_MAX := 0;

-- PTP message parser.
signal ptp_data     : data_t := (others => '0');
signal ptp_nlast    : last_t := 0;
signal ptp_meta     : meta_t := (others => '0');
signal ptp_valid    : std_logic := '0';
signal ptp_ready    : std_logic;
signal ptp_eof      : std_logic;
signal ptp_clone    : std_logic := '0';
signal ptp_follow   : std_logic := '0';
signal ptp_is_udp   : std_logic := '0';
signal ptp_is_adj   : std_logic := '0';
signal ptp_ip_ihl   : nybb_u := (others => '0');
signal ptp_msg_sdo  : nybb_t := (others => '0');
signal ptp_msg_typ  : nybb_t := (others => '0');
signal ptp_tcorr    : tstamp_t := TSTAMP_DISABLED;
signal ptp_tstamp   : tstamp_t;
signal ptp_wcount   : integer range 0 to PTP_WORD_MAX := 0;

-- Packet modification.
signal mod_data     : data_t := (others => '0');
signal mod_nlast    : last_t := 0;
signal mod_meta     : meta_t := (others => '0');
signal mod_valid    : std_logic := '0';
signal mod_ready    : std_logic;

-- Frame metadata (sync'd to "mod_*")
constant FRM_META_WIDTH : integer := PORT_COUNT + PTP_MODE_WIDTH + TSTAMP_WIDTH;
signal meta_write   : std_logic := '0';
signal meta_pmask   : mask_t := (others => '1');
signal meta_pmode   : ptp_mode_t := PTP_MODE_NONE;
signal meta_tstamp  : tstamp_t := TSTAMP_DISABLED;
signal meta_vec_in  : std_logic_vector(FRM_META_WIDTH-1 downto 0);
signal meta_vec_out : std_logic_vector(FRM_META_WIDTH-1 downto 0);

begin

-- Upstream flow-control and metadata format conversion.
in_ready    <= in_ready_i;
in_meta_vec <= meta2vec(in_meta, in_psrc);

-- Optional buffer for MIXED_STEP conversion.
gen_mixed0 : if not MIXED_STEP generate
    -- Simple bypass if MIXED_STEP is disabled.
    port_2step      <= (others => '0');
    mix_original    <= '1';
    mix_data        <= in_data;
    mix_nlast       <= in_nlast;
    mix_meta        <= in_meta_vec;
    mix_valid       <= in_valid;
    in_ready_i      <= mix_ready;
end generate;

gen_mixed1 : if MIXED_STEP generate blk_mixed : block is
    signal ptp_write    : std_logic;
    signal ptp_commit   : std_logic;
    signal ptp_revert   : std_logic;
    signal fifo_data    : data_t;
    signal fifo_nlast   : last_t;
    signal fifo_meta    : meta_t;
    signal fifo_valid   : std_logic;
    signal fifo_ready   : std_logic;
begin
    -- Cross-clock buffer for each port's "two-step" flag.
    u_buffer : sync_buffer_slv
        generic map(IO_WIDTH => PORT_COUNT)
        port map(
        in_flag     => cfg_2step,
        out_flag    => port_2step,
        out_clk     => clk);

    -- Save a copy of any frames marked for duplication.
    -- (And preserve associated metadata, including source port.)
    ptp_write   <= ptp_valid and ptp_ready;
    ptp_commit  <= bool2bit(ptp_nlast > 0) and ptp_clone;
    ptp_revert  <= bool2bit(ptp_nlast > 0) and not ptp_clone;

    u_fifo_dupe : entity work.fifo_packet
        generic map(
        INPUT_BYTES     => IO_BYTES,
        OUTPUT_BYTES    => IO_BYTES,
        META_WIDTH      => META_WIDTH,
        BUFFER_KBYTES   => 2,
        MAX_PACKETS     => 16)
        port map(
        in_clk          => clk,
        in_data         => ptp_data,
        in_nlast        => ptp_nlast,
        in_pkt_meta     => ptp_meta,
        in_last_commit  => ptp_commit,
        in_last_revert  => ptp_revert,
        in_write        => ptp_write,
        in_reset        => open,
        in_overflow     => open,
        out_clk         => clk,
        out_data        => fifo_data,
        out_nlast       => fifo_nlast,
        out_pkt_meta    => fifo_meta,
        out_valid       => fifo_valid,
        out_ready       => fifo_ready,
        out_reset       => open,
        out_overflow    => open,
        reset_p         => reset_p);

    -- Inject duplicated frames into the output stream.
    -- Note: Cloned stream gets priority to ensure it is sent promptly.
    u_inject : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        IO_BYTES        => IO_BYTES,
        META_WIDTH      => META_WIDTH,
        APPEND_FCS      => false)
        port map(
        in0_data        => fifo_data,
        in1_data        => in_data,
        in0_nlast       => fifo_nlast,
        in1_nlast       => in_nlast,
        in0_meta        => fifo_meta,
        in1_meta        => in_meta_vec,
        in_valid(0)     => fifo_valid,
        in_valid(1)     => in_valid,
        in_ready(0)     => fifo_ready,
        in_ready(1)     => in_ready_i,
        in_error        => open,
        out_data        => mix_data,
        out_nlast       => mix_nlast,
        out_meta        => mix_meta,
        out_valid       => mix_valid,
        out_ready       => mix_ready,
        out_aux         => mix_original,
        clk             => clk,
        reset_p         => reset_p);
end block; end generate;

-- PTP message parser.
mix_ready <= ptp_ready or not ptp_valid;

p_parse : process(clk)
    -- The "correctionField" is 64 bits but we only retain TSTAMP_WIDTH.
    -- Discard excess, if any, and assume the MSBs are zero.
    constant TBYTES_KEEP : positive := TSTAMP_WIDTH / 8;

    -- Parser state:
    variable is_ptp_eth, is_ptp_udp, is_ptp_adj, is_ptp_cpy : std_logic := '0';
    variable ver, ihl : nybb_u := (others => '0');

    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, mix_data);
        return strm_byte_present(IO_BYTES, bidx, mix_wcount);
    end function;

    -- As above, but automatically adds the appropriate header offset.
    impure function get_ptp_byte(pidx : natural) return boolean is
    begin
        if (is_ptp_udp = '1') then
            return get_eth_byte(UDP_HDR_DAT(ihl) + pidx);
        elsif (is_ptp_eth = '1') then
            return get_eth_byte(ETH_HDR_DATA + pidx);
        else
            return false;
        end if;
    end function;

    -- Given PTP message type, should the correctionField be adjusted?
    function need_correction(x : byte_t) return std_logic is
        variable typ : nybb_t := x(3 downto 0);     -- messageType in LSBs
    begin
        return bool2bit(typ = PTP_MSG_SYNC          -- Section 10.2.2.1
                     or typ = PTP_MSG_DLYREQ        -- Section 10.2.2.2
                     or typ = PTP_MSG_PDLYREQ       -- Section 10.2.2.3
                     or typ = PTP_MSG_PDLYRSP);     -- Section 10.2.2.3
    end function;

    -- Given PTP message type, does it need MIXED_STEP conversion?
    function need_follow_up(x : byte_t) return std_logic is
        variable typ : nybb_t := x(3 downto 0);     -- messageType in LSBs
    begin
        return bool2bit(MIXED_STEP) and             -- Feature enabled?
               bool2bit(typ = PTP_MSG_SYNC          -- Section 10.2.2.1
                     or typ = PTP_MSG_PDLYRSP);     -- Section 10.2.2.3
    end function;
begin
    if rising_edge(clk) then
        -- VALID signal needs a true reset.
        if (reset_p = '1') then
            ptp_valid <= '0';                   -- Global reset
        elsif (mix_ready = '1') then
            ptp_valid <= mix_valid;             -- Storing new data?
        end if;

        -- WCOUNT signal needs a true reset.
        if (reset_p = '1') then
            mix_wcount  <= 0;                   -- Global reset
        elsif (mix_valid = '1' and mix_ready = '1') then
            if (mix_nlast > 0) then             -- Word-count for parser:
                mix_wcount <= 0;                -- Start of new frame
            elsif (mix_wcount < PTP_WORD_MAX) then
                mix_wcount <= mix_wcount + 1;   -- Count up to max
            end if;
        end if;

        -- Everything else can skip reset to minimize excess fanout.
        if (mix_ready = '1') then
            -- Matched-delay buffer for packet contents.
            ptp_data    <= mix_data;
            ptp_meta    <= mix_meta;
            ptp_nlast   <= mix_nlast;
            ptp_follow  <= not mix_original;
            ptp_wcount  <= mix_wcount;
        end if;

        -- Note: Data may arrive gradually or as an entire frame in one clock
        --  cycle.  Use of variables here helps with datapath configurability.
        if (mix_valid = '1' and mix_ready = '1') then
            -- Determine the type of each incoming frame:
            --  * PTP-Eth: EtherType = 0x88F7
            --  * PTP-UDP: EtherType = 0x0800, Proto = UDP, Port = 319 or 320
            -- Check 1st and 2nd byte of EtherType
            if (get_eth_byte(ETH_HDR_ETYPE+0)) then
                is_ptp_eth := bool2bit(SUPPORT_L2 and btmp = ETYPE_PTP(15 downto 8));
                is_ptp_udp := bool2bit(SUPPORT_L3 and btmp = ETYPE_IPV4(15 downto 8));
            end if;
            if (get_eth_byte(ETH_HDR_ETYPE+1)) then
                is_ptp_eth := is_ptp_eth and bool2bit(btmp = ETYPE_PTP(7 downto 0));
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = ETYPE_IPV4(7 downto 0));
            end if;
            -- IP header: Valid IP+UDP header? (Check Version/IHL and Protocol)
            if (get_eth_byte(IP_HDR_VERSION)) then
                ver := unsigned(btmp(7 downto 4));      -- IP-header version (0x04)
                ihl := unsigned(btmp(3 downto 0));      -- IP-header length (IHL)
                is_ptp_udp := is_ptp_udp and bool2bit(ver = 4 and ihl >= 5);
            end if;
            if (get_eth_byte(IP_HDR_PROTOCOL)) then 
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = IPPROTO_UDP);
            end if;
            -- UDP header: Check UDP destination port = 0x013F or 0x0140
            if (get_eth_byte(UDP_HDR_DST(ihl)+0)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = x"01");
            end if;
            if (get_eth_byte(UDP_HDR_DST(ihl)+1)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = x"3F" or btmp = x"40");
            end if;

            -- Set or clear flags based on messageType.
            if (get_ptp_byte(PTP_HDR_TYPE)) then
                is_ptp_adj := need_correction(btmp);    -- Adjust correctionField?
                is_ptp_cpy := need_follow_up(btmp);     -- MIXED_STEP conversion?
                ptp_msg_sdo <= btmp(7 downto 4);        -- majorSdoId
                ptp_msg_typ <= btmp(3 downto 0);        -- messageType
            elsif (get_eth_byte(0)) then
                is_ptp_adj := '0';                      -- Clear for new frames
                is_ptp_cpy := '0';
            end if;

            -- Set or clear the "clone" flag based on messageType and twoStepFlag.
            -- (Bit index 1 of the first byte in flagField, see Table 37.)
            if (not MIXED_STEP) then
                ptp_clone <= '0';                       -- Feature disabled
            elsif (is_ptp_cpy = '0' or mix_original = '0') then
                ptp_clone <= '0';                       -- Non-clonable frame
            elsif (get_ptp_byte(PTP_HDR_FLAG)) then
                ptp_clone <= bool2bit(btmp(1) = '0')    -- Clone if twoStepFlag = 0 and
                         and or_reduce(port_2step);     -- at least one port needs it.
            end if;

            -- Store each byte of correctionField as it is received.
            for n in TBYTES_KEEP-1 downto 0 loop
                if (get_ptp_byte(PTP_HDR_CORR + 7 - n)) then
                    ptp_tcorr(8*n+7 downto 8*n) <= unsigned(btmp);
                end if;
            end loop;
        end if;

        -- Copy parser flags for downstream use.
        ptp_is_udp  <= is_ptp_udp;  -- Is this a PTP-over-UDP frame?
        ptp_is_adj  <= is_ptp_adj;  -- Does this frame need adjustments?
        ptp_ip_ihl  <= ihl;         -- Internet header length (if UDP)
    end if;
end process;

-- Packet modification.
ptp_eof     <= ptp_valid and ptp_ready and bool2bit(ptp_nlast > 0);
ptp_ready   <= mod_ready or not mod_valid;
ptp_tstamp  <= vec2meta(ptp_meta).tstamp;

p_modify : process(clk)
    -- Replace the byte at the specified offset from start of frame.
    procedure replace_eth_byte(bidx: natural; bval: byte_t) is
        variable bmod : natural := bidx mod IO_BYTES;
    begin
        if (strm_byte_present(IO_BYTES, bidx, ptp_wcount)) then
            mod_data(8*(IO_BYTES-bmod)-1 downto 8*(IO_BYTES-bmod-1)) <= bval;
        end if;
    end procedure;

    -- Replace the byte at the specified offset from start of PTP message.
    procedure replace_ptp_byte(pidx: natural; bval: byte_t) is
    begin
        if (ptp_is_udp = '1') then
            replace_eth_byte(UDP_HDR_DAT(ptp_ip_ihl) + pidx, bval);
        else
            replace_eth_byte(ETH_HDR_DATA + pidx, bval);
        end if;
    end procedure;
begin
    if rising_edge(clk) then
        -- VALID signal needs a true reset.
        if (reset_p = '1') then
            mod_valid <= '0';               -- Global reset
        elsif (ptp_ready = '1') then
            mod_valid <= ptp_valid;         -- Storing new data?
        end if;
        ptp_err <= '0';

        -- Store metadata at the end of each frame.
        meta_write <= ptp_eof and not reset_p;
        if (ptp_eof = '1') then
            if (MIXED_STEP and ptp_follow = '1') then
                -- Follow-up frames are saved only for 2-step ports,
                -- and they never require egress adjustments.
                meta_pmask  <= port_2step;
                meta_pmode  <= PTP_MODE_NONE;
                meta_tstamp <= TSTAMP_DISABLED;
            elsif (ptp_is_adj = '0') then
                -- No egress adjustments required for this frame.
                meta_pmask  <= (others => '1');
                meta_pmode  <= PTP_MODE_NONE;
                meta_tstamp <= TSTAMP_DISABLED;
            elsif (PTP_STRICT and ptp_tstamp = TSTAMP_DISABLED) then
                -- Strict mode drops frames with missing ingress timestamps.
                meta_pmask  <= (others => '0');
                meta_pmode  <= PTP_MODE_NONE;
                meta_tstamp <= TSTAMP_DISABLED;
                ptp_err <= '1';
                ptp_err_psrc <= vec2psrc(ptp_meta);
            elsif (ptp_is_udp = '1') then
                -- Adjustments required, UDP mode
                meta_pmask  <= (others => '1');
                meta_pmode  <= PTP_MODE_UDP;
                meta_tstamp <= ptp_tcorr - ptp_tstamp;
            else
                -- Adjustments required, Ethernet mode.
                meta_pmask  <= (others => '1');
                meta_pmode  <= PTP_MODE_ETH;
                meta_tstamp <= ptp_tcorr - ptp_tstamp;
            end if;
        end if;

        -- Store the modified data stream.
        if (ptp_ready = '1') then
            -- We never change frame length, only contents.
            mod_meta    <= ptp_meta;
            mod_nlast   <= ptp_nlast;
            -- Default to unmodified data, then selectively replace...
            mod_data    <= ptp_data;
            -- PTP-UDP disables UDP checksum so we can modify contents safely.
            if (ptp_is_udp = '1') then
                replace_eth_byte(UDP_HDR_CHK(ptp_ip_ihl) + 0, x"00");
                replace_eth_byte(UDP_HDR_CHK(ptp_ip_ihl) + 1, x"00");
            end if;
            -- Replace the messageType field in cloned follow-up messages.
            if (ptp_follow = '1' and ptp_msg_typ = PTP_MSG_SYNC) then
                replace_ptp_byte(PTP_HDR_TYPE, ptp_msg_sdo & PTP_MSG_FOLLOW);
            elsif (ptp_follow = '1' and ptp_msg_typ = PTP_MSG_PDLYRSP) THEN
                replace_ptp_byte(PTP_HDR_TYPE, ptp_msg_sdo & PTP_MSG_PDLYRFU);
            end if;
        end if;
    end if;
end process;

-- Connect modified data stream to the output.
out_meta    <= vec2meta(mod_meta);
out_psrc    <= vec2psrc(mod_meta);
out_data    <= mod_data;
out_nlast   <= mod_nlast;
out_valid   <= mod_valid;
mod_ready   <= out_ready;

-- FIFO for packet metadata.
meta_vec_in <= meta_pmask & meta_pmode & std_logic_vector(meta_tstamp);

u_fifo_frm : entity work.fifo_smol_sync
    generic map(IO_WIDTH => FRM_META_WIDTH)
    port map(
    in_data     => meta_vec_in,
    in_write    => meta_write,
    out_data    => meta_vec_out,
    out_valid   => frm_valid,
    out_read    => frm_ready,
    clk         => clk,
    reset_p     => reset_p);

frm_pmask   <= meta_vec_out(meta_vec_out'left downto PTP_MODE_WIDTH+TSTAMP_WIDTH);
frm_pmode   <= meta_vec_out(PTP_MODE_WIDTH+TSTAMP_WIDTH-1 downto TSTAMP_WIDTH);
frm_tstamp  <= unsigned(meta_vec_out(TSTAMP_WIDTH-1 downto 0));

end ptp_adjust;
