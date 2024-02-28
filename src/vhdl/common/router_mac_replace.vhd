--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- MAC-address replacement for Proxy-ARP
--
-- This block modifies the destination MAC-address for Ethernet frames as
-- they pass through the router.  The rules are as follows:
--  * Inspect EtherType field to determine packet type
--  * For IPv4 frames (EtherType = 0x0800):
--      * Parse packet up to the IP header.
--      * Query the destination IP against the ARP-cache.
--      * If a match is found, replace destination MAC and send to output.
--      * Otherwise, optionally make a second attempt after a short delay:
--          * If the "retry" option is disabled (buffer size = 0), or the
--            buffer is full, silently drop the packet.
--          * Do not read from the FIFO for at least a few milliseconds.
--            (Packets are timestamped on entry to measure this.)
--          * Once the time has elapsed, replay data into the main pipeline.
--          * If the second ARP query attempt also fails, drop the packet
--            and send an ICMP "Destination host unreachable" message.
--  * For non-IPv4 frames, policy is set at build time.
--      * If enabled, they are forwarded verbatim.
--
-- The input stream should be Ethernet frames with the FCS removed.
-- The output stream follows the same format.
--
-- The "retry" option adds complexity, but eliminates problems where the
-- the first few frames to a given IP address are needlessly dropped.  This
-- method may also result in out-of-order packet delivery.  Buffer sizes
-- are small; it is hoped that cache-miss traffic is a very small fraction
-- of the overall total.
--
-- An alternative mitigation is to ask all hosts to send unsolicited ARP
-- announcements, to pre-fill the cache.  However, this raises the chance
-- of cache overflow/thrashing if there are too many hosts.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_mac_replace is
    generic (
    -- MAC address for the router itself.
    ROUTER_MACADDR  : mac_addr_t;
    -- Retry buffer size, in kilobytes (0 = disable)
    RETRY_KBYTES    : natural := 4;
    -- Retry delay, in clock cycles (goal = 5-10 msec)
    RETRY_DLY_CLKS  : natural := 1_000_000;
    -- Parameters for ICMP replies
    ICMP_ECHO_BYTES : natural := 64;
    ICMP_REPLY_TTL  : natural := 64;
    ICMP_ID_INIT    : natural := 0;
    ICMP_ID_INCR    : natural := 1;
    -- Block all non-IPv4 packets?
    NOIP_BLOCK_ALL  : boolean := true);
    port (
    -- Input stream
    in_data         : in  byte_t;
    in_last         : in  std_logic;
    in_valid        : in  std_logic;
    in_ready        : out std_logic;

    -- Output stream
    out_data        : out byte_t;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;

    -- ICMP error stream (optional)
    icmp_data       : out byte_t;
    icmp_last       : out std_logic;
    icmp_valid      : out std_logic;
    icmp_ready      : in  std_logic;

    -- Query / reply interface to the ARP-Cache.
    query_addr      : out byte_t;
    query_first     : out std_logic;
    query_valid     : out std_logic;
    query_ready     : in  std_logic;
    reply_addr      : in  byte_t;
    reply_first     : in  std_logic;
    reply_match     : in  std_logic;
    reply_write     : in  std_logic;

    -- Router configuration
    router_ipaddr   : in  ip_addr_t;

    -- Dropped-packet and error strobes.
    pkt_drop        : out std_logic;
    pkt_error       : out std_logic;

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end router_mac_replace;

architecture router_mac_replace of router_mac_replace is

-- Define possible commands for each packet:
constant CMD_WIDTH  : natural := 2;
subtype cmd_t is std_logic_vector(CMD_WIDTH-1 downto 0);
constant CMD_DROP   : cmd_t := i2s(0, CMD_WIDTH);   -- Drop this packet
constant CMD_NOIP   : cmd_t := i2s(1, CMD_WIDTH);   -- Forward non-IP packet
constant CMD_IP1ST  : cmd_t := i2s(2, CMD_WIDTH);   -- Forward IP packet (1st try)
constant CMD_IP2ND  : cmd_t := i2s(3, CMD_WIDTH);   -- Forward IP packet (2nd try)

-- Time-counter widths are fixed at 8 bits.
subtype tcount_t is unsigned(7 downto 0);

-- Packet injector MUXes in the feedback path, if enabled.
signal fb_data      : byte_t;
signal fb_last      : std_logic;
signal fb_valid     : std_logic;
signal fb_ready     : std_logic;
signal inj_data     : byte_t;
signal inj_last     : std_logic;
signal inj_write    : std_logic;
signal inj_valid    : std_logic;
signal inj_ready    : std_logic;
signal inj_retry    : std_logic;
signal inj_error    : std_logic;

-- Parse key fields from each incoming packet.
signal parse_bct    : integer range 0 to 63 := 0;
signal parse_cmd    : cmd_t := CMD_DROP;
signal parse_rdy    : std_logic := '0';
signal parse_drop   : std_logic := '0';
signal qry_addr_i   : byte_t := (others => '0');
signal qry_first_i  : std_logic := '0';
signal qry_valid_i  : std_logic := '0';

-- Small FIFOs to buffer data and commands.
signal dfifo_data   : byte_t;
signal dfifo_last   : std_logic;
signal dfifo_valid  : std_logic;
signal dfifo_read   : std_logic;
signal cfifo_dout   : cmd_t;
signal cfifo_valid  : std_logic;
signal cfifo_read   : std_logic;
signal mfifo_addr   : byte_t;
signal mfifo_match  : std_logic;
signal mfifo_first  : std_logic;
signal mfifo_valid  : std_logic;
signal mfifo_read   : std_logic;
signal mfifo_skip   : std_logic;
signal mfifo_desync : std_logic;

-- Forward path: Drop, keep, or modify.
signal fwd_data     : byte_t := (others => '0');
signal fwd_last     : std_logic := '0';
signal fwd_write    : std_logic := '0';
signal fwd_hempty   : std_logic;
signal fwd_bct      : integer range 0 to 15 := 0;

-- Feedback path: Retry with delay
signal alt_data     : byte_t := (others => '0');
signal alt_last     : std_logic := '0';
signal alt_wr_retry : std_logic := '0';
signal alt_wr_icmp  : std_logic := '0';
signal alt_drop     : std_logic := '0';
signal icmp_drop    : std_logic := '0';
signal tcount_now   : tcount_t := (others => '0');
signal tcount_rcvd  : tcount_t;
signal tcount_diff  : tcount_t;
signal tcount_ok    : std_logic := '0';
signal rfifo_data   : byte_t;
signal rfifo_last   : std_logic;
signal rfifo_meta   : byte_t;
signal rfifo_valid  : std_logic;
signal rfifo_ready  : std_logic;

begin

-- Combine the various droppped-packet and error strobes.
pkt_drop    <= parse_drop or alt_drop or icmp_drop;
pkt_error   <= inj_error or mfifo_desync;

-- Packet injector MUXes in the feedback path, if enabled.
gen_inject : if (RETRY_KBYTES > 0) generate
    -- Give priority to the main input (index 0).
    u_inject : entity work.packet_inject
        generic map(
        INPUT_COUNT     => 2,
        APPEND_FCS      => false,
        RULE_PRI_CONTIG => false)
        port map(
        in0_data        => in_data,
        in1_data        => fb_data,
        in_last(0)      => in_last,
        in_last(1)      => fb_last,
        in_valid(0)     => in_valid,
        in_valid(1)     => fb_valid,
        in_ready(0)     => in_ready,
        in_ready(1)     => fb_ready,
        in_error        => inj_error,
        out_data        => inj_data,
        out_last        => inj_last,
        out_valid       => inj_valid,
        out_ready       => inj_ready,
        out_aux         => inj_retry,
        clk             => clk,
        reset_p         => reset_p);
end generate;

gen_direct : if (RETRY_KBYTES <= 0) generate
    -- No injector, just connect directly.
    inj_data    <= in_data;
    inj_last    <= in_last;
    inj_valid   <= in_valid;
    inj_retry   <= '0';
    inj_error   <= '0';
    in_ready    <= inj_ready;

    -- Tie off unused ICMP outputs.
    icmp_data   <= (others => '0');
    icmp_last   <= '0';
    icmp_valid  <= '0';
    icmp_drop   <= '0';

    -- Assert "drop" strobe at the end of any unmatched packet.
    -- (This is normally driven by the feedback fifo_packet.)
    p_drop : process(clk)
    begin
        if rising_edge(clk) then
            alt_drop <= cfifo_read and not (mfifo_match or mfifo_skip);
        end if;
    end process;
end generate;

-- Parse key fields from each incoming packet.
inj_write   <= inj_valid and inj_ready;
inj_ready   <= fwd_hempty and (query_ready or not qry_valid_i);
query_addr  <= qry_addr_i;
query_first <= qry_first_i;
query_valid <= qry_valid_i;

p_parse : process(clk)
    variable inj_data_d : byte_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Decide command based on Ethertype (bytes 12-13).
        if (inj_write = '1' and parse_bct = 13) then
            if (inj_data_d = x"08" and inj_data = x"00") then
                -- Ethertype 0x0800 = IPv4
                if (inj_retry = '1') then
                    parse_cmd <= CMD_IP2ND; -- 2nd attempt
                else
                    parse_cmd <= CMD_IP1ST; -- 1st attempt
                end if;
            elsif (NOIP_BLOCK_ALL) then
                -- Non-IPv4 (blocked)
                parse_cmd <= CMD_DROP;
            else
                -- Non-IPv4 (allowed)
                parse_cmd <= CMD_NOIP;
            end if;
            parse_rdy <= '1';
        else
            parse_rdy <= '0';
        end if;

        -- "Dropped packet" strobe.
        parse_drop <= parse_rdy and bool2bit(parse_cmd = CMD_DROP);

        -- For IPv4 packets, query destination address (bytes 30-33).
        if (inj_write = '1') then
            qry_addr_i  <= inj_data;
            qry_first_i <= bool2bit(parse_bct = 30);
        end if;

        if (reset_p = '1') then
            qry_valid_i <= '0';     -- Global reset
        elsif ((inj_write = '1') and
               (parse_cmd = CMD_IP1ST or parse_cmd = CMD_IP2ND) and
               (30 <= parse_bct and parse_bct < 34)) then
            qry_valid_i <= '1';     -- Latch new data
        elsif (query_ready = '1') then
            qry_valid_i <= '0';     -- Previous data consumed
        end if;

        -- Update the byte offset counter.
        if (reset_p = '1') then
            parse_bct <= 0;             -- Global reset
        elsif (inj_write = '1' and inj_last = '1') then
            parse_bct <= 0;             -- End-of-frame
        elsif (inj_write = '1' and parse_bct < 63) then
            parse_bct <= parse_bct + 1; -- Increment up to max
        end if;

        -- Delay-by-one for input data.
        if (inj_write = '1') then
            inj_data_d := inj_data;
        end if;
    end if;
end process;

-- Small FIFOs to buffer data and commands.
--  * Data buffer (DFIFO) holds data while we decide what to do.
--    (Worst case delay = 34 bytes for Eth+IP headers, plus ARP-lookup time.
--  * Command buffer (CFIFO) holds the command for each packet.
--  * MAC-address buffer (MFIFO) holds the results of the ARP-cache query.
--    (Each result needs 6 bytes, just need enough for 1-2 packets.
--     Don't read the last MFIFO byte until end-of-frame; we need the match flag.)
mfifo_skip  <= bool2bit(cfifo_dout = CMD_DROP or cfifo_dout = CMD_NOIP);
dfifo_read  <= fwd_hempty and dfifo_valid and cfifo_valid and (mfifo_valid or mfifo_skip);
cfifo_read  <= dfifo_read and dfifo_last;
mfifo_read  <= dfifo_read and (not mfifo_skip) and (bool2bit(fwd_bct < 5) or dfifo_last);

u_dfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,           -- Word size = 1 byte
    DEPTH_LOG2  => 6)           -- Depth = 2^6 = 64 bytes
    port map(
    in_data     => inj_data,
    in_last     => inj_last,
    in_write    => inj_write,
    out_data    => dfifo_data,
    out_last    => dfifo_last,
    out_valid   => dfifo_valid,
    out_read    => dfifo_read,
    clk         => clk,
    reset_p     => reset_p);

u_cfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => CMD_WIDTH,   -- Word size = 1 command word
    DEPTH_LOG2  => 3)           -- Depth = 2^3 = 8 commands
    port map(
    in_data     => parse_cmd,
    in_write    => parse_rdy,
    out_data    => cfifo_dout,
    out_valid   => cfifo_valid,
    out_read    => cfifo_read,
    clk         => clk,
    reset_p     => reset_p);

u_mfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,           -- Word size = 1 byte
    META_WIDTH  => 2,           -- Retain "first" and "match" flags
    DEPTH_LOG2  => 4)           -- Depth = 2^4 = 16 bytes = 2.6 addresses
    port map(
    in_data     => reply_addr,
    in_meta(0)  => reply_match,
    in_meta(1)  => reply_first,
    in_write    => reply_write,
    out_data    => mfifo_addr,
    out_meta(0) => mfifo_match,
    out_meta(1) => mfifo_first,
    out_valid   => mfifo_valid,
    out_read    => mfifo_read,
    clk         => clk,
    reset_p     => reset_p);

-- Forward path: Drop packet, keep intact, or replace destination MAC.
p_fwd : process(clk)
begin
    if rising_edge(clk) then
        -- Modify data stream as required:
        if (cfifo_dout = CMD_DROP or cfifo_dout = CMD_NOIP or fwd_bct >= 6) then
            -- No modifications to this byte.
            fwd_data <= dfifo_data;
        else
            -- IP packet, replace the destination MAC address.
            fwd_data <= mfifo_addr;
        end if;

        -- Drive the "last" and "write" strobes for the output.
        if (cfifo_dout = CMD_DROP) then
            -- Always drop this frame.
            fwd_last    <= '0';
            fwd_write   <= '0';
        elsif (cfifo_dout = CMD_NOIP) then
            -- Forward verbatim.
            fwd_last    <= dfifo_last;
            fwd_write   <= dfifo_read;
        else
            -- IP frame, forward only if we found the matching MAC.
            fwd_last    <= dfifo_last and mfifo_match;
            fwd_write   <= dfifo_read and mfifo_match;
        end if;

        -- Sanity check on the "mfifo_first" flag.
        if (mfifo_read = '1' and fwd_bct = 0 and mfifo_first = '0') then
            report "MFIFO desynchronized!" severity error;
            mfifo_desync <= '1';
        else
            mfifo_desync <= '0';
        end if;

        -- Update the byte offset counter.
        if (reset_p = '1' or cfifo_read = '1') then
            fwd_bct <= 0;           -- Reset or end-of-frame.
        elsif (dfifo_valid = '1' and dfifo_read = '1' and fwd_bct < 15) then
            fwd_bct <= fwd_bct + 1; -- Increment up to max
        end if;
    end if;
end process;

-- Output FIFO for downstream flow-control.
u_ofifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 8,
    DEPTH_LOG2  => 4)
    port map(
    in_data     => fwd_data,
    in_last     => fwd_last,
    in_write    => fwd_write,
    fifo_hempty => fwd_hempty,
    out_data    => out_data,
    out_last    => out_last,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Instantiate the ICMP generator and feedback path, if enabled.
gen_feedback : if (RETRY_KBYTES > 0) generate
    -- Drive the alternate path data and last/write strobes:
    p_alt : process(clk)
    begin
        if rising_edge(clk) then
            -- Data is just a delayed copy of dfifo_data.
            alt_data <= dfifo_data;
            alt_last <= dfifo_last;

            -- Write strobes are enabled only for specific commands.
            if (dfifo_read = '1' and mfifo_match = '0') then
                alt_wr_retry <= bool2bit(cfifo_dout = CMD_IP1ST);
                alt_wr_icmp  <= bool2bit(cfifo_dout = CMD_IP2ND);
            else
                alt_wr_retry <= '0';
                alt_wr_icmp  <= '0';
            end if;
        end if;
    end process;

    -- Generate ICMP error messages, derived from the input packet.
    u_icmp : entity work.router_icmp_send
        generic map(
        ROUTER_MAC  => ROUTER_MACADDR,
        MASK_ENABLE => false,
        TIME_ENABLE => false,
        ICMP_TTL    => ICMP_REPLY_TTL,
        IP_ID_INIT  => ICMP_ID_INIT,
        IP_ID_INCR  => ICMP_ID_INCR,
        ECHO_BYTES  => ICMP_ECHO_BYTES)
        port map(
        in_cmd      => ACT_ICMP_DHU,
        in_data     => alt_data,
        in_last     => alt_last,
        in_write    => alt_wr_icmp,
        icmp_data   => icmp_data,
        icmp_last   => icmp_last,
        icmp_valid  => icmp_valid,
        icmp_ready  => icmp_ready,
        icmp_drop   => icmp_drop,
        router_ip   => router_ipaddr,
        subnet_mask => (others => '0'), -- Unused
        time_msec   => (others => '0'), -- Unused
        clk         => clk,
        reset_p     => reset_p);

    -- Buffers packets for retry, or drop if full.
    fb_data         <= rfifo_data;
    fb_last         <= rfifo_last;
    fb_valid        <= tcount_ok and rfifo_valid;
    rfifo_ready     <= tcount_ok and fb_ready;

    u_fifo : entity work.fifo_packet
        generic map(
        INPUT_BYTES     => 1,
        OUTPUT_BYTES    => 1,
        BUFFER_KBYTES   => RETRY_KBYTES,
        META_WIDTH      => 8,
        FLUSH_TIMEOUT   => 2 * RETRY_DLY_CLKS)
        port map(
        in_clk          => clk,
        in_data         => alt_data,
        in_pkt_meta     => std_logic_vector(tcount_now),
        in_last_commit  => alt_last,
        in_last_revert  => std_logic'('0'),
        in_write        => alt_wr_retry,
        in_overflow     => alt_drop,
        out_clk         => clk,
        out_data        => rfifo_data,
        out_pkt_meta    => rfifo_meta,
        out_last        => rfifo_last,
        out_valid       => rfifo_valid,
        out_ready       => rfifo_ready,
        out_overflow    => open,
        reset_p         => reset_p);

    -- Minimum-delay calculation.
    tcount_rcvd <= unsigned(rfifo_meta);
    tcount_diff <= tcount_now - tcount_rcvd;

    p_delay : process(clk)
        -- Each tick of "tcount_now" is about 1/16th of RETRY_DLY_CLKS.
        constant DIV_MAX : natural := RETRY_DLY_CLKS / 16 - 1;
        variable div_ctr : integer range 0 to DIV_MAX := DIV_MAX;
    begin
        if rising_edge(clk) then
            -- Set "ok" flag when tcount_diff is between 16-127 ticks.
            -- (This indicates the required time has elapsed.)
            if (reset_p = '1') then
                tcount_ok <= '0';   -- Global reset
            elsif (rfifo_valid = '1' and rfifo_ready = '1' and fb_last = '1') then
                tcount_ok <= '0';   -- Clear promptly after each packet.
            elsif (rfifo_valid = '1' and 16 <= tcount_diff and tcount_diff <= 127) then
                tcount_ok <= '1';   -- Ready to start reading next packet.
            end if;

            -- Count clock cycles to define "now".
            if (reset_p = '1') then
                tcount_now  <= (others => '0');
                div_ctr     := DIV_MAX;
            elsif (div_ctr > 0) then
                div_ctr     := div_ctr - 1;
            else
                tcount_now  <= tcount_now + 1;
                div_ctr     := DIV_MAX;
            end if;
        end if;
    end process;
end generate;

end router_mac_replace;
