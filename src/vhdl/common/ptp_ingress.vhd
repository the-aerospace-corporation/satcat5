--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ingress processing for the Precision Time Protocol (PTP)
--
-- This block provides initial parsing of PTP frames, identifying incoming
-- frames by transport protocol (i.e., Layer-2 / Layer-3 / Non-PTP).
--
-- Optionally, it can also parse TLVs appended to each incoming message,
-- identifying up to eight requested tlvType values.  The final output
-- is the byte-offset (see "tlvpos_t" in "ptp_types.vhd") for the start
-- of the PTP message and for each requested tag, if present.
--
-- By moving this logic to the individual ports, it greatly reduces the
-- worst-case parsing recursion. This improves timing in the switch core.
-- (i.e., Since a TLV can be just four bytes long, a 64-byte data pipeline
--  would need to handle up to 16 chained TLVs each clock cycle, which is
--  impractical at reasonable clock rates.)
--
-- Outputs are ready exactly just after the input end-of-frame strobe.
-- (One cycle if FIFO_ENABLE = false, otherwise two cycles.)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;

entity ptp_ingress is
    generic (
    -- General-purpose setup.
    IO_BYTES    : positive;         -- Width of datapath
    FIFO_ENABLE : boolean := true;  -- Enable output FIFO?
    SUPPORT_L2  : boolean := true;  -- L2 supported? (Ethernet)
    SUPPORT_L3  : boolean := true;  -- L3 supported? (UDP)
    -- Specify up to eight TLVs of interest.
    TLV_ID0     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID1     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID2     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID3     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID4     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID5     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID6     : tlvtype_t := TLVTYPE_NONE;
    TLV_ID7     : tlvtype_t := TLVTYPE_NONE);
    port (
    -- Input data stream.
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_write    : in  std_logic;
    -- Frame metadata, one strobe per frame.
    -- Flow control mode depends on FIFO_ENABLE setting.
    out_pmsg    : out tlvpos_t;     -- Offset to PTP start-of-message (0 = N/A)
    out_tlv0    : out tlvpos_t;     -- Offset to each requested TLV (ID0 - ID7)
    out_tlv1    : out tlvpos_t;
    out_tlv2    : out tlvpos_t;
    out_tlv3    : out tlvpos_t;
    out_tlv4    : out tlvpos_t;
    out_tlv5    : out tlvpos_t;
    out_tlv6    : out tlvpos_t;
    out_tlv7    : out tlvpos_t;
    out_write   : out std_logic;    -- Write strobe (FIFO_ENABLE false)
    out_valid   : out std_logic;    -- AXI flow control (FIFO_ENABLE true)
    out_ready   : in  std_logic;    -- AXI flow control (FIFO_ENABLE true)
    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_ingress;

architecture ptp_ingress of ptp_ingress is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Disable TLV parsing if none are enabled.
constant SUPPORT_TLV : boolean :=
    (TLV_ID0 /= TLVTYPE_NONE) or
    (TLV_ID1 /= TLVTYPE_NONE) or
    (TLV_ID2 /= TLVTYPE_NONE) or
    (TLV_ID3 /= TLVTYPE_NONE) or
    (TLV_ID4 /= TLVTYPE_NONE) or
    (TLV_ID5 /= TLVTYPE_NONE) or
    (TLV_ID6 /= TLVTYPE_NONE) or
    (TLV_ID7 /= TLVTYPE_NONE);

-- Counter maximum is just beyond the maximum byte of interest.
constant BCOUNT_MAX : positive := ptp_parse_bytes(SUPPORT_TLV, SUPPORT_L3);
constant WCOUNT_MAX : positive := 1 + (BCOUNT_MAX / IO_BYTES);

-- Packet-parsing state machine.
subtype counter_t is integer range 0 to 2047;
signal in_wcount    : integer range 0 to WCOUNT_MAX := 0;
signal parse_run    : std_logic := '0';
signal parse_tnext  : counter_t := 0;
signal parse_len    : tlvlen_t := (others => '0');
signal parse_rem    : counter_t := 0;
signal parse_typ    : nybb_t := (others => '0');
signal parse_pmsg   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv0   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv1   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv2   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv3   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv4   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv5   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv6   : tlvpos_t := TLVPOS_NONE;
signal parse_tlv7   : tlvpos_t := TLVPOS_NONE;

-- Output FIFO for packet metadata.
subtype meta_t is std_logic_vector(8*TLVPOS_WIDTH-1 downto 0);
signal fifo_write   : std_logic := '0';
signal fifo_valid   : std_logic := '0';
signal fifo_meta    : meta_t := (others => '0');
signal out_meta     : meta_t := (others => '0');

begin

p_parse : process(clk)
    -- Minimum length TLV is four bytes, so wide pipeline may have
    -- more than one TLV per input word, which parsed recursively.
    -- Note: Both L2 and L3 tags always start on an even-numbered byte.
    --  * IO_BYTES = 1/2        -> 1 tag per clock.
    --  * IO_BYTES = 3/4/5/6    -> 2 tags per clock.
    --  * IO_BYTES = 7/8/9/10   -> 3 tags per clock.
    constant MAX_TLV_RECURSION : positive := (IO_BYTES + 5) / 4;

    -- Parser state:
    variable is_ptp_eth, is_ptp_udp : std_logic := '0';
    variable tlv_base, tlv_next : counter_t := 0;
    variable tlv_type           : tlvtype_t := (others => '0');
    variable tlv_len            : tlvlen_t := (others => '0');
    variable tlv_pos            : tlvpos_t := TLVPOS_NONE;

    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, in_data);
        return strm_byte_present(IO_BYTES, bidx, in_wcount);
    end function;

    -- Add PTP message offset to the length of Ethernet and UDP headers.
    impure function ptp_msg_start return natural is
    begin
        if (is_ptp_udp = '1') then
            return UDP_HDR_DAT(IP_IHL_MIN);
        elsif (is_ptp_eth = '1') then
            return ETH_HDR_DATA;
        else
            return 0;
        end if;
    end function;

    -- As "get_eth_byte", counting from the start of the PTP message.
    impure function get_ptp_byte(pidx : natural) return boolean is
        variable bidx : natural := ptp_msg_start + pidx;
    begin
        return get_eth_byte(bidx) and (ptp_msg_start > 0);
    end function;

    -- Calculate the number of bytes remaining to end-of-message.
    impure function get_tlv_rem(len: tlvlen_t) return counter_t is
    begin
        if (32 <= len and len < 2048) then
            return ptp_msg_start + to_integer(len) - IO_BYTES * (in_wcount+1);
        else
            return 0;
        end if;
    end function;

    -- Get the initial value of "tnext" for TLV parsing.
    impure function get_tlv_start(typ: nybb_t) return natural is
    begin
        return ptp_msg_start + ptp_msg_len(typ) + 4 - IO_BYTES * (in_wcount+1);
    end function;

    -- Simplified stream parsing for reading TLV headers.
    impure function get_tlv_byte(bidx : integer) return boolean is
    begin
        if (0 <= bidx and bidx < IO_BYTES) then
            btmp := strm_byte_value(bidx, in_data);
            return true;
        else
            return false;
        end if;
    end function;

    -- Does the current tlvType match the specified ID?
    impure function tlv_match(id : tlvtype_t) return boolean is
    begin
        return (tlv_type = id) and (id /= TLVTYPE_NONE);
    end function;
begin
    if rising_edge(clk) then
        -- WCOUNT signal needs a true reset.
        if (reset_p = '1') then
            in_wcount <= 0;                     -- Global reset
        elsif (in_write = '1') then
            if (in_nlast > 0) then
                in_wcount <= 0;                 -- Start of new frame
            elsif (in_wcount < WCOUNT_MAX) then
                in_wcount <= in_wcount + 1;     -- Count up to max
            end if;
        end if;

        -- Write packet metadata to FIFO just after the end-of-frame.
        fifo_write <= in_write and bool2bit(in_nlast > 0) and not reset_p;

        -- Note: Data may arrive gradually or as an entire frame in one clock
        --  cycle.  Use of variables here helps with datapath configurability.
        if (in_write = '1') then
            -------- Pipeline stage 2: Recursive TLV parsing. ----------------
            -- Set initial conditions for this clock cycle.
            tlv_base := in_wcount * IO_BYTES;   -- Byte offset of current word.
            tlv_next := parse_tnext;            -- Relative offset to next TLV.

            -- Execute parser logic up to the maximum recursion depth.
            -- (i.e., Once for GbE ports, three times for 10 GbE ports.)
            for n in 1 to MAX_TLV_RECURSION loop
                -- TLV header within the current data word?
                if (in_wcount = 0 or not SUPPORT_TLV) then
                    -- Reset matched tags for each new frame.
                    -- (Or if TLV parsing is completely disabled.)
                    parse_tlv0 <= TLVPOS_NONE;
                    parse_tlv1 <= TLVPOS_NONE;
                    parse_tlv2 <= TLVPOS_NONE;
                    parse_tlv3 <= TLVPOS_NONE;
                    parse_tlv4 <= TLVPOS_NONE;
                    parse_tlv5 <= TLVPOS_NONE;
                    parse_tlv6 <= TLVPOS_NONE;
                    parse_tlv7 <= TLVPOS_NONE;
                elsif (0 < tlv_next and tlv_next <= parse_rem) then
                    -- First two bytes of each TLV are the type.
                    -- On receiving the second byte, match tag(s) of interest.
                    if (get_tlv_byte(tlv_next - 4)) then
                        tlv_type(15 downto 8) := btmp;
                    end if;
                    if (get_tlv_byte(tlv_next - 3)) then
                        tlv_type(7 downto 0) := btmp;
                        tlv_pos := bidx_to_tlvpos(tlv_base + tlv_next);
                        if tlv_match(TLV_ID0) then parse_tlv0 <= tlv_pos; end if;
                        if tlv_match(TLV_ID1) then parse_tlv1 <= tlv_pos; end if;
                        if tlv_match(TLV_ID2) then parse_tlv2 <= tlv_pos; end if;
                        if tlv_match(TLV_ID3) then parse_tlv3 <= tlv_pos; end if;
                        if tlv_match(TLV_ID4) then parse_tlv4 <= tlv_pos; end if;
                        if tlv_match(TLV_ID5) then parse_tlv5 <= tlv_pos; end if;
                        if tlv_match(TLV_ID6) then parse_tlv6 <= tlv_pos; end if;
                        if tlv_match(TLV_ID7) then parse_tlv7 <= tlv_pos; end if;
                    end if;
                    -- Next two bytes of each TLV are the length.
                    -- On receiving the second byte, increment scan position.
                    -- If length is invalid, abort further parsing.
                    if (get_tlv_byte(tlv_next - 2)) then
                        tlv_len(15 downto 8) := unsigned(btmp);
                    end if;
                    if (get_tlv_byte(tlv_next - 1)) then
                        tlv_len(7 downto 0) := unsigned(btmp);
                        if (tlv_len(0) = '0' and tlv_len < 1536) then
                            tlv_next := tlv_next + to_integer(tlv_len) + 4;
                        else
                            tlv_next := 0;
                        end if;
                    end if;
                end if;
            end loop;

            -- Update the persistent "run" and "tnext" state.
            if (SUPPORT_TLV and get_ptp_byte(PTP_HDR_MSGDAT)
                and ptp_msg_len(parse_typ) > 0) then
                -- Able to start parsing TLV?
                parse_run   <= '1';
                parse_tnext <= get_tlv_start(parse_typ);
            elsif (get_eth_byte(0)) then
                -- Reset at the start of each new frame.
                parse_run   <= '0';
                parse_tnext <= 0;
            elsif (in_nlast = 0 and tlv_next >= IO_BYTES) then
                -- Continue TNEXT countdown, incrementing as we reach each TLV.
                parse_run   <= '1';
                parse_tnext <= tlv_next - IO_BYTES;
            elsE
                -- Return to the idle state.
                parse_run   <= '0';
                parse_tnext <= 0;
            end if;

            -- Countdown to end-of-packet based on PTP messageLength.
            -- (This helps prevent spurious tlvType matches against the FCS.)
            if (SUPPORT_TLV and get_ptp_byte(PTP_HDR_MSGDAT)) then
                parse_rem <= get_tlv_rem(parse_len);
            elsif (parse_rem > IO_BYTES) then
                parse_rem <= parse_rem - IO_BYTES;
            else
                parse_rem <= 0;
            end if;

            -------- Pipeline stage 1: Ethernet and UDP parsing. -------------
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
            -- Note: No IPv4 options allowed per IEEE-1588-2019 Appendix C.5.
            if (get_eth_byte(IP_HDR_VERSION)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = x"45");
            end if;
            if (get_eth_byte(IP_HDR_PROTOCOL)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = IPPROTO_UDP);
            end if;
            -- UDP header: Check UDP destination port = 0x013F or 0x0140
            if (get_eth_byte(UDP_HDR_DST(IP_IHL_MIN)+0)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = x"01");
            end if;
            if (get_eth_byte(UDP_HDR_DST(IP_IHL_MIN)+1)) then
                is_ptp_udp := is_ptp_udp and bool2bit(btmp = x"3F" or btmp = x"40");
            end if;

            -- Record certain fields in the PTP header.
            -- Note: Use of a signals here breaks combinational logic chains.
            -- Delay is OK because earliest TLV occurs 40+ bytes after the PTP
            -- msgType, and this block should not exceed 8 bytes per clock.
            if (get_ptp_byte(PTP_HDR_TYPE)) then
                parse_pmsg <= bidx_to_tlvpos(ptp_msg_start);
                parse_typ  <= btmp(3 downto 0);
            elsif (get_eth_byte(0)) then
                parse_pmsg <= TLVPOS_NONE;
            end if;
            if (get_ptp_byte(PTP_HDR_LEN + 0)) then
                parse_len(15 downto 8) <= unsigned(btmp);
            end if;
            if (get_ptp_byte(PTP_HDR_LEN + 1)) then
                parse_len(7 downto 0) <= unsigned(btmp);
            end if;
        end if;
    end if;
end process;

-- Output FIFO for packet metadata?
gen_fifo1 : if FIFO_ENABLE generate
    fifo_meta <= parse_tlv7 & parse_tlv6 & parse_tlv5 & parse_tlv4
               & parse_tlv3 & parse_tlv2 & parse_tlv1 & parse_tlv0;

    u_fifo : entity work.fifo_smol_sync
        generic map(
        IO_WIDTH    => TLVPOS_WIDTH,
        META_WIDTH  => 8*TLVPOS_WIDTH)
        port map(
        in_data     => parse_pmsg,
        in_meta     => fifo_meta,
        in_write    => fifo_write,
        out_data    => out_pmsg,
        out_meta    => out_meta,
        out_valid   => fifo_valid,
        out_read    => out_ready,
        clk         => clk,
        reset_p     => reset_p);

    out_write <= fifo_valid and out_ready;
    out_valid <= fifo_valid;
    out_tlv0 <= out_meta(1*TLVPOS_WIDTH-1 downto 0*TLVPOS_WIDTH);
    out_tlv1 <= out_meta(2*TLVPOS_WIDTH-1 downto 1*TLVPOS_WIDTH);
    out_tlv2 <= out_meta(3*TLVPOS_WIDTH-1 downto 2*TLVPOS_WIDTH);
    out_tlv3 <= out_meta(4*TLVPOS_WIDTH-1 downto 3*TLVPOS_WIDTH);
    out_tlv4 <= out_meta(5*TLVPOS_WIDTH-1 downto 4*TLVPOS_WIDTH);
    out_tlv5 <= out_meta(6*TLVPOS_WIDTH-1 downto 5*TLVPOS_WIDTH);
    out_tlv6 <= out_meta(7*TLVPOS_WIDTH-1 downto 6*TLVPOS_WIDTH);
    out_tlv7 <= out_meta(8*TLVPOS_WIDTH-1 downto 7*TLVPOS_WIDTH);
end generate;

gen_fifo0 : if not FIFO_ENABLE generate
    out_write <= fifo_write;
    out_valid <= '0';
    out_pmsg <= parse_pmsg;
    out_tlv0 <= parse_tlv0;
    out_tlv1 <= parse_tlv1;
    out_tlv2 <= parse_tlv2;
    out_tlv3 <= parse_tlv3;
    out_tlv4 <= parse_tlv4;
    out_tlv5 <= parse_tlv5;
    out_tlv6 <= parse_tlv6;
    out_tlv7 <= parse_tlv7;
end generate;

end ptp_ingress;
