--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Send ICMP Replies
--
-- This block accepts a packet-routing command and a copy of the associated
-- packet.  If the action requires an ICMP reply, this block constructs and
-- sends the ICMP reply, including the first N bytes of the original packet.
-- Formatting follows IETF RFC 792 ("Internet Control Message Protocol").
--
-- As a simple rate-limiting method, only one ICMP reply can be queued at a
-- time. Any additional commands received during this time are ignored.
-- This behavior is allowed under IETF RFC 1812, but the "icmp_drop" strobe
-- is provided in case upstream blocks need to handle this condition.
--
-- Output is a Ethernet frames containing ICMP messages, with no FCS.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_icmp_send is
    generic (
    -- MAC address for the router itself
    ROUTER_MAC  : mac_addr_t;
    -- Parameters for the subnet-mask command, if supported
    MASK_ENABLE : boolean := true;
    -- Parameters for the timestamp command, if supported
    TIME_ENABLE : boolean := true;      -- Command supported?
    -- Default TTL for ICMP errors and responses
    ICMP_TTL    : natural := 64;
    -- Set initial state and per-packet increment for IP-header ID field.
    IP_ID_INIT  : natural := 0;
    IP_ID_INCR  : natural := 1;
    -- Max bytes from original to send in each reply?
    ECHO_BYTES  : natural := 64);
    port (
    -- Input stream (from source)
    in_cmd      : in  action_t;
    in_data     : in  byte_t;
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- ICMP command stream (back to source)
    icmp_data   : out byte_t;
    icmp_last   : out std_logic;
    icmp_valid  : out std_logic;
    icmp_ready  : in  std_logic;
    icmp_drop   : out std_logic;

    -- Router configuration and system time.
    -- Note: Host is responsible for setting MSB in non-UTC mode.
    router_ip   : in  ip_addr_t;
    subnet_mask : in  ip_addr_t;
    time_msec   : in  timestamp_t;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router_icmp_send;

architecture router_icmp_send of router_icmp_send is

-- Is the specified command an ICMP reply?
function cmd_is_icmp(cmd : action_t) return boolean is
begin
    return (cmd = ACT_ICMP_ECHO)
        or (cmd = ACT_ICMP_DNU)
        or (cmd = ACT_ICMP_DHU)
        or (cmd = ACT_ICMP_DRU)
        or (cmd = ACT_ICMP_DPU)
        or (cmd = ACT_ICMP_TTL)
        or (cmd = ACT_ICMP_MASK and MASK_ENABLE)
        or (cmd = ACT_ICMP_TIME and TIME_ENABLE);
end function;

-- Fixed fields in the IP header, by byte offset.
constant IPHDR06    : ip_checksum_t := x"4000"; -- Fragmentation flags
constant IPHDR08    : ip_checksum_t :=          -- TTL + Protocol
    to_unsigned(ICMP_TTL, 8) & to_unsigned(1, 8);

-- Parse certain fields from original message.
signal parse_cmd    : action_t := ACT_DROP;
signal parse_bcount : bcount_t := (others => '0');
signal parse_caplen : bcount_t := (others => '0');
signal parse_capchk : ip_checksum_t := (others => '0');
signal parse_dscp   : byte_t := (others => '0');
signal parse_macsrc : mac_addr_t := (others => '0');
signal parse_ipsrc  : ip_addr_t := (others => '0');
signal parse_active : std_logic := '0';
signal parse_first  : std_logic := '1';
signal parse_wrfifo : std_logic := '0';
signal parse_wrzero : std_logic := '0';
signal parse_commit : std_logic := '0';
signal parse_drop   : std_logic := '0';

-- FIFO buffers selected parts of original message.
signal fifo_wr_data : byte_t;
signal fifo_wr_last : std_logic;
signal fifo_wr_en   : std_logic;
signal fifo_rd_data : byte_t;
signal fifo_rd_last : std_logic;
signal fifo_rd_en   : std_logic;

-- Calculate various output header fields:
constant HDRID_INIT : bcount_t := to_unsigned(IP_ID_INIT, 16);
signal hdr_ip_id    : bcount_t := HDRID_INIT;
signal hdr_ip_len   : bcount_t := (others => '0');
signal hdr_version  : ip_checksum_t := (others => '0');
signal hdr_opcode   : ip_checksum_t := (others => '0');
signal hdr_tstamp   : timestamp_t := (others => '0');

-- CRC calculation for IP and ICMP headers.
signal chksum_ip    : ip_checksum_t := (others => '0');
signal chksum_icmp  : ip_checksum_t := (others => '0');

-- Packet generator state machine.
signal pkt_bcount   : integer range 0 to 63 := 0;
signal pkt_data     : byte_t := (others => '0');
signal pkt_last     : std_logic := '0';
signal pkt_valid    : std_logic := '0';
signal pkt_ready    : std_logic;
signal pkt_done     : std_logic;
signal pkt_rdfifo   : std_logic := '0';

begin

-- Parse certain fields from original message.
p_parse : process(clk)
    -- Pad input byte to 16 bits, shifted left by B.
    function pad16(x : byte_t ; b : integer) return ip_checksum_t is
        variable tmp : ip_checksum_t := resize(unsigned(x), 16);
    begin
        return shift_left(tmp, b);
    end function;
begin
    if rising_edge(clk) then
        -- Accept or reject new command at the start of each frame.
        -- Fire the "commit" strobe when we've finished collecting data.
        parse_commit <= '0';
        parse_drop   <= '0';
        if (reset_p = '1') then
            parse_active <= '0';
            parse_cmd    <= ACT_DROP;
        elsif (in_write = '1' and parse_first = '1') then
            -- New frame.  Is the generator ready for a new command?
            if (pkt_valid = '0' and parse_commit = '0') then
                -- Accept the new command.
                parse_active <= bool2bit(cmd_is_icmp(in_cmd));
                parse_cmd    <= in_cmd;
            else
                -- Clear "active" flag but don't change latched command.
                parse_active <= '0';
                -- Strobe "drop" if this would have been an ICMP reply.
                parse_drop   <= bool2bit(cmd_is_icmp(in_cmd));
            end if;
        elsif (in_write = '1' and parse_active = '1') then
            -- Are we finished collecting data?
            if (in_last = '1' or parse_caplen = ECHO_BYTES-1) then
                -- Clear active flag and assert commit strobe.
                parse_active <= '0';
                parse_commit <= '1';
            end if;
        end if;

        -- Depending on the active command, decide which bytes to capture.
        -- Note we are deciding whether to save the NEXT byte, so +1 offset:
        --  00-13 = MAC header (always present)
        --  14-33 = IP header (always present)
        --  34-37 = ICMP type/code/checksum (if applicable)
        if (reset_p = '1' or parse_active = '0') then
            -- Inactive, no data written to FIFO.
            parse_wrzero <= '0';
            parse_wrfifo <= '0';
        elsif (in_write = '0') then
            -- No change until next byte is written.
            null;
        elsif (parse_cmd = ACT_ICMP_ECHO) then
            -- "Echo Reply" grabs everything after the ICMP checksum.
            parse_wrzero <= '0';
            parse_wrfifo <= bool2bit(37 <= parse_bcount and parse_bcount < 37+ECHO_BYTES);
        elsif (parse_cmd = ACT_ICMP_MASK and MASK_ENABLE) then
            -- "Address mask reply" grabs 4 bytes, starting after ICMP checksum.
            parse_wrzero <= '0';
            parse_wrfifo <= bool2bit(37 <= parse_bcount and parse_bcount < 41);
        elsif (parse_cmd = ACT_ICMP_TIME and TIME_ENABLE) then
            -- "Timestamp reply" grabs 8 bytes, starting after ICMP checksum.
            parse_wrzero <= '0';
            parse_wrfifo <= bool2bit(37 <= parse_bcount and parse_bcount < 45);
        elsif (parse_cmd = ACT_ICMP_DNU
            or parse_cmd = ACT_ICMP_DHU
            or parse_cmd = ACT_ICMP_DRU
            or parse_cmd = ACT_ICMP_DPU
            or parse_cmd = ACT_ICMP_TTL) then
            -- Most ICMP errors capture everything starting from the IP header.
            -- Prepend four zero-bytes to simplify output logic for the "unused" field.
            parse_wrzero <= bool2bit(9 <= parse_bcount and parse_bcount < 13);
            parse_wrfifo <= bool2bit(13 <= parse_bcount and parse_bcount < 13+ECHO_BYTES);
        else
            -- No active capture.
            parse_wrzero <= '0';
            parse_wrfifo <= '0';
        end if;

        -- Latch specific fields from input frame:
        if (in_write = '1' and parse_active = '1') then
            if (6 <= parse_bcount and parse_bcount < 12) then
                -- Source MAC address
                parse_macsrc <= parse_macsrc(39 downto 0) & in_data;
            elsif (15 = parse_bcount) then
                -- DSCP / TTL flags, not including ECN
                parse_dscp <= in_data and x"FC";
            elsif (26 <= parse_bcount and parse_bcount < 30) then
                -- Source IP address
                parse_ipsrc <= parse_ipsrc(23 downto 0) & in_data;
            end if;
        end if;

        -- Increment the capture-length and capture-checksum tallies.
        -- (These must not be cleared until generator is done.)
        if (reset_p = '1' or pkt_done = '1') then
            parse_caplen <= (others => '0');    -- Clear counters
            parse_capchk <= (others => '0');
        elsif (in_write = '0') then
            null;                               -- No update
        elsif (parse_wrzero = '1') then
            parse_caplen <= parse_caplen + 1;   -- Zero padding
        elsif (parse_wrfifo = '1' and parse_bcount(0) = '0') then
            parse_caplen <= parse_caplen + 1;   -- Even bytes (MSBs)
            parse_capchk <= ip_checksum(parse_capchk, pad16(in_data, 8));
        elsif (parse_wrfifo = '1') then
            parse_caplen <= parse_caplen + 1;   -- Odd bytes (LSBs)
            parse_capchk <= ip_checksum(parse_capchk, pad16(in_data, 0));
        end if;

        -- Update the start-of-frame flag and frame-offset counter.
        -- (These track the received frame even if we rejected the command.)
        if (reset_p = '1') then
            parse_first  <= '1';  -- Global reset
            parse_bcount <= (others => '0');
        elsif (in_write = '1' and in_last = '1') then
            parse_first  <= '1';  -- End of frame -> ready for next
            parse_bcount <= (others => '0');
        elsif (in_write = '1') then
            parse_first  <= '0';  -- Middle of frame
            parse_bcount <= parse_bcount + 1;
        end if;
    end if;
end process;

-- FIFO buffers selected parts of original message.
p_fifo : process(clk)
begin
    if rising_edge(clk) then
        -- Select original input data or zero-padding.
        if (parse_wrfifo = '1') then
            fifo_wr_data <= in_data;
            fifo_wr_last <= in_last or bool2bit(parse_caplen = ECHO_BYTES-1);
        else
            fifo_wr_data <= (others => '0');
            fifo_wr_last <= '0';
        end if;
        fifo_wr_en <= in_write and (parse_wrfifo or parse_wrzero);
    end if;
end process;

fifo_rd_en <= pkt_rdfifo and pkt_ready;

u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => log2_ceil(ECHO_BYTES))
    port map(
    in_data     => fifo_wr_data,
    in_last     => fifo_wr_last,
    in_write    => fifo_wr_en,
    out_data    => fifo_rd_data,
    out_last    => fifo_rd_last,
    out_read    => fifo_rd_en,
    clk         => clk,
    reset_p     => reset_p);

-- Calculate various output fields:
p_header : process(clk)
    constant VERSION_IHL : byte_u := x"45";
begin
    if rising_edge(clk) then
        -- IPv4 "Identification" field is just a simple packet counter.
        -- (If we have multiple 
        if (reset_p = '1') then
            hdr_ip_id <= HDRID_INIT;
        elsif (pkt_done = '1') then
            hdr_ip_id <= hdr_ip_id + IP_ID_INCR;
        end if;

        -- Latch other fields at start of command:
        if (parse_commit = '1') then
            -- Combined Version, IHL, DSCP/TOS, and ECN fields.
            hdr_version <= VERSION_IHL & unsigned(parse_dscp);

            -- IPv4 "Total length" field depends on command type.
            if (parse_cmd = ACT_ICMP_TIME and TIME_ENABLE) then
                -- Timestamp Reply = 20 IP + 12 ICMP + Buffer contents
                hdr_ip_len <= to_unsigned(32, 16) + parse_caplen;
            elsif (parse_cmd = ACT_ICMP_MASK and MASK_ENABLE) then
                -- Address Mask Reply = 20 IP + 8 ICMP + Buffer contents
                hdr_ip_len <= to_unsigned(28, 16) + parse_caplen;
            else
                -- All others = 20 IP + 4 ICMP + Buffer contents
                hdr_ip_len <= to_unsigned(24, 16) + parse_caplen;
            end if;

            -- ICMP opcode (Type and Code fields)
            if (parse_cmd = ACT_ICMP_DNU) then
                hdr_opcode <= x"0300";
            elsif (parse_cmd = ACT_ICMP_DHU) then
                hdr_opcode <= x"0301";
            elsif (parse_cmd = ACT_ICMP_DRU) then
                hdr_opcode <= x"0302";
            elsif (parse_cmd = ACT_ICMP_DPU) then
                hdr_opcode <= x"0303";
            elsif (parse_cmd = ACT_ICMP_TTL) then
                hdr_opcode <= x"0B00";
            elsif (parse_cmd = ACT_ICMP_MASK and MASK_ENABLE) then
                hdr_opcode <= x"1200";
            elsif (parse_cmd = ACT_ICMP_TIME and TIME_ENABLE) then
                hdr_opcode <= x"0E00";
            else    -- e.g., ACT_ICMP_ECHO
                hdr_opcode <= x"0000";
            end if;

            -- Message timestamp is copied verbatim.
            -- (Note: MSB should be set if time isn't referenced to UTC.)
            hdr_tstamp <= time_msec;
        end if;
    end if;
end process;

-- CRC calculation for IP and ICMP headers.
-- Since we send the Ethernet header first, we have enough of a headstart
-- to calculate the IP and ICMP checksums before they're needed.
p_checksum : process(clk)
    -- Precalculate checksum for fixed fields of IP and ICMP headers.
    -- Note: No need to worry about order; this calculation is commutative.
    function chk_ip_fixed return ip_checksum_t is
        variable chk : ip_checksum_t := (others => '0');
    begin
        chk := ip_checksum(chk, IPHDR06);
        chk := ip_checksum(chk, IPHDR08);
        return chk;
    end function;

    constant INIT_IP    : ip_checksum_t := chk_ip_fixed;
    constant INIT_ICMP  : ip_checksum_t := chk_ip_fixed;

    variable wct : integer range 0 to 7 := 0;
    variable tmp : ip_checksum_t := (others => '0');
begin
    if rising_edge(clk) then
        -- IP header checksum.
        if (parse_commit = '1') then
            -- Initial state includes all fixed fields.
            chksum_ip <= INIT_IP;
        elsif (wct > 0) then
            -- Increment CRC calculation for each variable field.
            case wct is
            when 7 => tmp := hdr_version;                   -- Version, IHL, etc.
            when 6 => tmp := hdr_ip_len;                    -- Total length
            when 5 => tmp := hdr_ip_id;                     -- Identification
            when 4 => tmp := get_word_s(router_ip, 1);      -- Src IP
            when 3 => tmp := get_word_s(router_ip, 0);
            when 2 => tmp := get_word_s(parse_ipsrc, 1);    -- Dst IP
            when 1 => tmp := get_word_s(parse_ipsrc, 0);
            when others => tmp := (others => '0');          -- Idle
            end case;
            chksum_ip <= ip_checksum(chksum_ip, tmp);
        end if;

        -- ICMP frame checksum.
        if (parse_commit = '1') then
            -- Initial state always reflects buffer contents.
            chksum_icmp <= parse_capchk;
        elsif (wct > 1 and parse_cmd = ACT_ICMP_MASK and MASK_ENABLE) then
            case wct is
            when 3 => tmp := get_word_s(subnet_mask, 1);    -- Address mask
            when 2 => tmp := get_word_s(subnet_mask, 0);
            when others => tmp := (others => '0');          -- Idle
            end case;
            chksum_icmp <= ip_checksum(chksum_icmp, tmp);
        elsif (wct > 1 and parse_cmd = ACT_ICMP_TIME and TIME_ENABLE) then
            -- Fields specific to the Timestamp Reply message.
            case wct is
            when 5 => tmp := get_word_u(hdr_tstamp, 1);     -- Received time
            when 4 => tmp := get_word_u(hdr_tstamp, 0);
            when 3 => tmp := get_word_u(hdr_tstamp, 1);     -- Transmit time
            when 2 => tmp := get_word_u(hdr_tstamp, 0);
            when others => tmp := (others => '0');          -- Idle
            end case;
            chksum_icmp <= ip_checksum(chksum_icmp, tmp);
        elsif (wct = 1) then
            -- All messages include the ICMP Type + Code
            chksum_icmp <= ip_checksum(chksum_icmp, hdr_opcode);
        end if;

        -- Update word-counter.
        if (reset_p = '1') then
            wct := 0;           -- Reset to idle
        elsif (parse_commit = '1') then
            wct := 7;           -- Start new sweep
        elsif (wct > 0) then
            wct := wct - 1;     -- Continue countdown
        end if;
    end if;
end process;

-- Packet generator state machine.
pkt_done <= pkt_valid and pkt_ready and pkt_last;

p_pkt : process(clk)
begin
    if rising_edge(clk) then
        -- Latch the next output byte:
        if (pkt_valid = '0' or pkt_ready = '1') then
            pkt_last <= '0';                -- Set default
            if (pkt_bcount < 6) then        -- Destination MAC
                pkt_data <= get_byte_s(parse_macsrc, 5-pkt_bcount);
            elsif (pkt_bcount < 12) then    -- Source MAC
                pkt_data <= get_byte_s(ROUTER_MAC, 11-pkt_bcount);
            elsif (pkt_bcount = 12) then    -- Ethertype (MSB)
                pkt_data <= x"08";
            elsif (pkt_bcount = 13) then    -- Ethertype (LSB)
                pkt_data <= x"00";
            elsif (pkt_bcount < 16) then    -- IP Version + IHL + DSCP + ECN
                pkt_data <= get_byte_u(hdr_version, 15-pkt_bcount);
            elsif (pkt_bcount < 18) then    -- IP Total Length
                pkt_data <= get_byte_u(hdr_ip_len, 17-pkt_bcount);
            elsif (pkt_bcount < 20) then    -- IP Identification
                pkt_data <= get_byte_u(hdr_ip_id, 19-pkt_bcount);
            elsif (pkt_bcount < 22) then    -- IP Fragmentation flags
                pkt_data <= get_byte_u(IPHDR06, 21-pkt_bcount);
            elsif (pkt_bcount < 24) then    -- IP TTL + Protocol
                pkt_data <= get_byte_u(IPHDR08, 23-pkt_bcount);
            elsif (pkt_bcount < 26) then    -- IP Header Checksum
                pkt_data <= not get_byte_u(chksum_ip, 25-pkt_bcount);
            elsif (pkt_bcount < 30) then    -- IP Source Address
                pkt_data <= get_byte_s(router_ip, 29-pkt_bcount);
            elsif (pkt_bcount < 34) then    -- IP Destination Address
                pkt_data <= get_byte_s(parse_ipsrc, 33-pkt_bcount);
            elsif (pkt_bcount < 36) then    -- ICMP Type + Code
                pkt_data <= get_byte_u(hdr_opcode, 35-pkt_bcount);
            elsif (pkt_bcount < 38) then    -- ICMP Frame Checksum
                pkt_data <= not get_byte_u(chksum_icmp, 37-pkt_bcount);
            elsif (MASK_ENABLE and parse_cmd = ACT_ICMP_MASK and pkt_bcount < 46) then
                -- Special case for the "Address mask request" message:
                if (pkt_bcount < 42) then   -- Buffer contents (4 bytes)
                    pkt_data <= fifo_rd_data;
                else                        -- Address mask (4 bytes)
                    pkt_data <= get_byte_s(subnet_mask, 45-pkt_bcount);
                end if;
                pkt_last <= bool2bit(pkt_bcount = 45);
            elsif (TIME_ENABLE and parse_cmd = ACT_ICMP_TIME and pkt_bcount < 54) then
                -- Special case for the "Timestamp reply" message:
                if (pkt_bcount < 46) then       -- Buffer contents (8 bytes)
                    pkt_data <= fifo_rd_data;   
                elsif (pkt_bcount < 50) then    -- Receive timestamp (4 bytes)
                    pkt_data <= get_byte_u(hdr_tstamp, 49-pkt_bcount);
                else                            -- Transmit timestamp (4 bytes)
                    pkt_data <= get_byte_u(hdr_tstamp, 53-pkt_bcount);
                end if;
                pkt_last <= bool2bit(pkt_bcount = 53);
            else
                -- All other ICMP messages: Concatenate buffer contents
                -- (Echo Reply, Destination Unreachable, Time Exceeded)
                pkt_data <= fifo_rd_data;
                pkt_last <= fifo_rd_last;
            end if;
        end if;

        -- Enable read from FIFO on next pkt_ready strobe.
        -- (Note: This starts one byte earlier than the logic above.)
        if (reset_p = '1' or pkt_done = '1') then
            -- Start each new frame in "normal" mode.
            pkt_rdfifo <= '0';
        elsif (pkt_bcount = 37 and pkt_ready = '1') then
            -- All ICMP messages begin reading FIFO at byte 38.
            pkt_rdfifo <= '1';
        end if;

        -- Assert "valid" on "commit" strobe, deassert at end-of-frame.
        if (reset_p = '1') then
            pkt_valid <= '0';   -- Global reset
        elsif (parse_commit = '1') then
            pkt_valid <= '1';   -- Start new message
        elsif (pkt_done = '1') then
            pkt_valid <= '0';   -- End of ICMP frame
        end if;

        -- Update the output frame's byte-offset counter.
        if (reset_p = '1' or pkt_done = '1') then
            pkt_bcount <= 0;                -- Reset between frames
        elsif (parse_commit = '1') then
            pkt_bcount <= 1;                -- First byte of new frame
        elsif (pkt_valid = '1' and pkt_ready = '1' and pkt_bcount < 63) then
            pkt_bcount <= pkt_bcount + 1;   -- Move to next byte
        end if;
    end if;
end process;

-- Connect top-level I/O ports.
icmp_data   <= pkt_data;
icmp_last   <= pkt_last;
icmp_valid  <= pkt_valid;
icmp_drop   <= parse_drop;
pkt_ready   <= icmp_ready;

end router_icmp_send;
