--------------------------------------------------------------------------
-- Copyright 2020-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the IP-Gateway and ICMP server
--
-- This testbench generates a variety of Raw-Ethernet and IPv4 traffic for
-- the router_ip_gateway block, and confirms that each packet is passed along,
-- dropped, or generates an ICMP reply as expected under a variety of input
-- and output flow-control conditions.  (Also covers router_icmp_send, since
-- that block is used to generate the ICMP replies.)
--
-- The complete test takes about 20-22 milliseconds depending on PRNG.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_ip_gateway_tb is
    generic (
    -- Adjust generics to test different configurations.
    IPV4_BLOCK_MCAST    : boolean := true;
    IPV4_BLOCK_FRAGMENT : boolean := true;
    IPV4_DMAC_FILTER    : boolean := false;
    NOIP_BLOCK_ALL      : boolean := false;
    NOIP_BLOCK_ARP      : boolean := true;
    NOIP_BLOCK_BCAST    : boolean := true;
    ICMP_ECHO_BYTES     : integer := 64);
    -- No I/O ports
end router_ip_gateway_tb;

architecture tb of router_ip_gateway_tb is

-- Arbitrary addresses for the router:
constant ROUTER_MACADDR : mac_addr_t := x"DEADBEEFCAFE";
constant ROUTER_IPADDR  : ip_addr_t := x"C0A80101";
constant ROUTER_SUBNET  : ip_addr_t := x"FFFF0000";

-- Print a message with the disposition of each packet?
constant DEBUG_VERBOSE  : boolean := false;

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Input stream (from source)
signal in_data          : byte_t := (others => '0');
signal in_last          : std_logic := '0';
signal in_valid         : std_logic := '0';
signal in_ready         : std_logic;
signal in_drop          : std_logic;

-- Main output stream (to destination)
signal tst_out_data     : byte_t := (others => '0');
signal tst_out_last     : std_logic := '0';
signal tst_out_write    : std_logic := '0';
signal ref_out_data     : byte_t;
signal ref_out_last     : std_logic;
signal ref_out_valid    : std_logic;
signal ref_out_ready    : std_logic;
signal uut_out_data     : byte_t;
signal uut_out_last     : std_logic;
signal uut_out_valid    : std_logic;
signal uut_out_ready    : std_logic := '0';

-- ICMP command stream (back to source)
signal tst_icmp_data    : byte_t := (others => '0');
signal tst_icmp_last    : std_logic := '0';
signal tst_icmp_write   : std_logic := '0';
signal ref_icmp_data    : byte_t;
signal ref_icmp_last    : std_logic;
signal ref_icmp_valid   : std_logic;
signal ref_icmp_ready   : std_logic;
signal uut_icmp_data    : byte_t;
signal uut_icmp_last    : std_logic;
signal uut_icmp_valid   : std_logic;
signal uut_icmp_ready   : std_logic := '0';

-- Router configuration
signal router_link_ok   : std_logic := '0';
signal time_msec        : timestamp_t := (others => '0');

-- High-level test control
signal test_idx_hi      : natural := 0;
signal test_idx_lo      : natural := 0;
signal test_rate_in     : real := 0.0;
signal test_rate_out    : real := 0.0;
signal test_rate_icmp   : real := 0.0;
signal test_drop_ct     : natural := 0;

begin

-- Clock generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Unit under test
uut : entity work.router_ip_gateway
    generic map(
    ROUTER_MACADDR      => ROUTER_MACADDR,
    IPV4_BLOCK_MCAST    => IPV4_BLOCK_MCAST,
    IPV4_BLOCK_FRAGMENT => IPV4_BLOCK_FRAGMENT,
    IPV4_DMAC_FILTER    => IPV4_DMAC_FILTER,
    IPV4_DMAC_REPLACE   => false,
    IPV4_SMAC_REPLACE   => false,
    NOIP_BLOCK_ALL      => NOIP_BLOCK_ALL,
    NOIP_BLOCK_ARP      => NOIP_BLOCK_ARP,
    NOIP_BLOCK_BCAST    => NOIP_BLOCK_BCAST,
    NOIP_DMAC_REPLACE   => false,
    NOIP_SMAC_REPLACE   => false,
    ICMP_ECHO_BYTES     => ICMP_ECHO_BYTES,
    DEBUG_VERBOSE       => DEBUG_VERBOSE)
    port map(
    in_data         => in_data,
    in_last         => in_last,
    in_valid        => in_valid,
    in_ready        => in_ready,
    in_drop         => in_drop,
    out_data        => uut_out_data,
    out_last        => uut_out_last,
    out_valid       => uut_out_valid,
    out_ready       => uut_out_ready,
    icmp_data       => uut_icmp_data,
    icmp_last       => uut_icmp_last,
    icmp_valid      => uut_icmp_valid,
    icmp_ready      => uut_icmp_ready,
    router_ipaddr   => ROUTER_IPADDR,
    router_submask  => ROUTER_SUBNET,
    router_link_ok  => router_link_ok,
    time_msec       => time_msec,
    clk             => clk_100,
    reset_p         => reset_p);

-- FIFOs for the two test streams.
ref_out_ready <= uut_out_valid and uut_out_ready;
u_fifo_out : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => 8,
    FIFO_DEPTH  => 4096)
    port map(
    in_data     => tst_out_data,
    in_last     => tst_out_last,
    in_write    => tst_out_write,
    out_data    => ref_out_data,
    out_last    => ref_out_last,
    out_valid   => ref_out_valid,
    out_ready   => ref_out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

ref_icmp_ready <= uut_icmp_valid and uut_icmp_ready;
u_fifo_icmp : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => 8,
    FIFO_DEPTH  => 1024)
    port map(
    in_data     => tst_icmp_data,
    in_last     => tst_icmp_last,
    in_write    => tst_icmp_write,
    out_data    => ref_icmp_data,
    out_last    => ref_icmp_last,
    out_valid   => ref_icmp_valid,
    out_ready   => ref_icmp_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check output streams + auxiliary control.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        -- Flow-control randomization.
        uut_out_ready   <= rand_bit(test_rate_out);
        uut_icmp_ready  <= rand_bit(test_rate_icmp);

        -- Increment timestamp after each received ICMP packet.
        if (reset_p = '1') then
            time_msec <= (others => '0');
        elsif (uut_icmp_valid = '1' and uut_icmp_ready = '1' and uut_icmp_last = '1') then
            time_msec <= time_msec + 1;
        end if;

        -- Check the main output stream.
        if (uut_out_valid = '1' and uut_out_ready = '1') then
            if (ref_out_valid = '1') then
                assert (uut_out_data = ref_out_data
                    and uut_out_last = ref_out_last)
                    report "Output data mismatch." severity error;
            else
                report "Unexpected output data." severity error;
            end if;
        end if;

        -- Check the ICMP output stream.
        if (uut_icmp_valid = '1' and uut_icmp_ready = '1') then
            if (ref_icmp_valid = '1') then
                assert (uut_icmp_data = ref_icmp_data
                    and uut_icmp_last = ref_icmp_last)
                    report "ICMP data mismatch." severity error;
            else
                report "Unexpected ICMP data." severity error;
            end if;
        end if;

        -- Count dropped packets.
        if (reset_p = '1') then
            test_drop_ct <= 0;
        elsif (in_drop = '1') then
            test_drop_ct <= test_drop_ct + 1;
        end if;
    end if;
end process;

-- High-level test control
p_test : process
    -- Define a few generic user addresses.
    constant LOCAL1_MAC : mac_addr_t := x"EE1111111111";
    constant LOCAL1_IP  : ip_addr_t  := x"C0A80111";
    constant LOCAL2_MAC : mac_addr_t := x"EE2222222222";
    constant LOCAL2_IP  : ip_addr_t  := x"C0A80122";
    constant OUTER1_MAC : mac_addr_t := x"DD1111111111";
    constant OUTER1_IP  : ip_addr_t  := x"08080801";
    constant OUTER2_MAC : mac_addr_t := x"DD2222222222";
    constant OUTER2_IP  : ip_addr_t  := x"08080802";
    constant MCAST1_IP  : ip_addr_t  := x"E1234567";

    -- Count sent and expected packets.
    variable pkt_sent   : natural := 0;
    variable pkt_reply  : natural := 0;
    variable icmp_ident : bcount_t := (others => '0');

    -- Wrapper functions for various make_xx functions:
    impure function icmp_from_router(
        dstmac  : mac_addr_t;
        opcode  : ethertype;
        ippkt   : std_logic_vector)
        return eth_packet
    is
        variable icmp : ip_packet := make_icmp_reply(
            ROUTER_IPADDR,      -- Packet is from router.
            opcode,             -- ICMP opcode
            icmp_ident,         -- Counter for next reply
            ippkt,              -- Reference IP packet
            ICMP_ECHO_BYTES);   -- Maximum reply length
    begin
        -- Note: Not safe to increment icmp_ident here, because of a bug
        --       in Vivado 2016.4 that causes duplicate calls.
        return make_eth_pkt(dstmac, ROUTER_MACADDR, ETYPE_IPV4, icmp.all);
    end function;

    function ip_to_router(
        srcmac  : mac_addr_t;
        ippkt   : std_logic_vector)
        return eth_packet is
    begin
        return make_eth_pkt(ROUTER_MACADDR, srcmac, ETYPE_IPV4, ippkt);
    end function;

    function ip_forward(
        srcmac  : mac_addr_t;
        ippkt   : std_logic_vector)
        return eth_packet
    is
        variable tmp : eth_packet := make_eth_pkt(
            ROUTER_MACADDR, srcmac, ETYPE_IPV4, ippkt);
    begin
        return decr_ipv4_ttl(tmp.all);
    end function;

    -- Write data to the input stream, with flow-control randomization.
    procedure send_in(x : std_logic_vector) is
        variable bidx : integer := x'length / 8;
        variable rand : real := 0.0;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Send each byte in the packet...
        wait until rising_edge(clk_100);
        while (bidx > 0) loop
            -- Consume the current byte?
            if (in_valid = '1' and in_ready = '1') then
                bidx := bidx - 1;
            end if;
            -- Update the data/last/valid signals.
            if (rand_bit(test_rate_in) = '1' and bidx > 0) then
                -- Emit current/next byte.
                in_data  <= get_byte_s(x, bidx-1);
                in_last  <= bool2bit(bidx = 1);
                in_valid <= '1';
            elsif (in_ready = '1') then
                -- Previous byte consumed.
                in_data  <= (others => '0');
                in_last  <= '0';
                in_valid <= '0';
            end if;
            if (bidx > 0) then
                wait until rising_edge(clk_100);
            end if;
        end loop;
        -- Increment the packet counter.
        pkt_sent := pkt_sent + 1;
    end procedure;

    -- Write reference data to the designated FIFO.
    procedure expect_out(x : std_logic_vector) is
        constant NBYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Load each byte in the packet...
        for n in NBYTES-1 downto 0 loop
            wait until rising_edge(clk_100);
            tst_out_data    <= get_byte_s(x, n);
            tst_out_last    <= bool2bit(n = 0);
            tst_out_write   <= '1';
        end loop;
        wait until rising_edge(clk_100);
        tst_out_data    <= (others => '0');
        tst_out_last    <= '0';
        tst_out_write   <= '0';
        -- Increment the expected-reply counter.
        pkt_reply       := pkt_reply + 1;
    end procedure;

    procedure expect_icmp(x : std_logic_vector) is
        constant NBYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Load each byte in the packet...
        for n in NBYTES-1 downto 0 loop
            wait until rising_edge(clk_100);
            tst_icmp_data   <= get_byte_s(x, n);
            tst_icmp_last   <= bool2bit(n = 0);
            tst_icmp_write  <= '1';
        end loop;
        wait until rising_edge(clk_100);
        tst_icmp_data   <= (others => '0');
        tst_icmp_last   <= '0';
        tst_icmp_write  <= '0';
        -- Increment the expected-reply counter.
        pkt_reply       := pkt_reply + 1;
        icmp_ident      := icmp_ident + 1;
    end procedure;

    -- Get ready to start the next test.
    procedure test_start(print_interval : natural := 1) is
        variable idx_tmp : natural := (test_idx_lo+1) mod print_interval;
    begin
        -- Should we print an announcement?
        wait until rising_edge(clk_100);
        if (idx_tmp = 0) then
            report "Starting test #" & integer'image(test_idx_hi)
                & "." & integer'image(test_idx_lo + 1);
        end if;
        -- Reset test conditions:
        test_idx_lo <= test_idx_lo + 1;
        pkt_sent    := 0;
        pkt_reply   := 0;
        icmp_ident  := (others => '0');
        reset_p     <= '1';
        wait for 0.2 us;
        reset_p     <= '0';
        wait for 0.2 us;
    end procedure;

    -- Wait until both outputs have been idle for N consecutive clocks.
    procedure test_wait(dly : integer := 100) is
        variable ctr : integer := 0;
    begin
        while (ctr < dly) loop
            wait until rising_edge(clk_100);
            if (uut_out_valid = '1' or uut_icmp_valid = '1') then
                ctr := 0;       -- Reset counter
            else
                ctr := ctr + 1; -- Count idle cycles
            end if;
        end loop;
    end procedure;

    -- Close out the current test, and confirm the number of dropped packets.
    procedure test_finish is
        variable ctr : integer := 0;
    begin
        -- Wait for outputs to be idle.
        test_wait(100);
        -- Did we get the expected number of dropped packets?
        assert (pkt_reply + test_drop_ct = pkt_sent)
            report "Mismatch in dropped packet count." severity error;
        -- Did we consume all data from both reference FIFOs?
        assert (ref_out_valid = '0')
            report "Missing output data." severity error;
        assert (ref_icmp_valid = '0')
            report "Missing ICMP data." severity error;
    end procedure;

    -- All-in-one test with a single randomly generated packet.
    procedure test_single(
        opt_num_words   : natural;
        dat_num_bytes   : natural;
        print_interval  : natural := 1)
    is
        variable pkt_ip     : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                OUTER1_IP, LOCAL1_IP,       -- Destination and source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP,                -- Protcol = UDP
                IPFLAG_NORMAL,              -- Fragmentation flags
                1+rand_int(63)),            -- Time-to-live
            rand_vec(8*dat_num_bytes),      -- Packet data
            rand_vec(32*opt_num_words));    -- Extended header options
        variable eth_in     : eth_packet := ip_to_router(LOCAL1_MAC, pkt_ip.all);
        variable eth_out    : eth_packet := decr_ipv4_ttl(eth_in.all);
    begin
        test_start(print_interval);
        expect_out(eth_out.all);
        send_in(eth_in.all);
        test_finish;
    end procedure;

    -- Test N randomly-generated packets.
    procedure test_random(npkt : natural; ri, ro, rc : real := 1.0) is
    begin
        -- Set test conditions and update high/low test index.
        test_idx_hi     <= test_idx_hi + 1;
        test_idx_lo     <= 0;
        test_rate_in    <= ri;
        test_rate_out   <= ro;
        test_rate_icmp  <= rc;
        router_link_ok  <= '1';

        -- Run N tests, each with a single random packet.
        for n in 1 to npkt loop
            test_single(rand_int(11), 1 + rand_int(1400), 20);
        end loop;
    end procedure;

    -- Standard test sequence:
    procedure test_sequence(ri, ro, rc : real) is
        -- Ref1, Ref2: Captured TCP-over-Ethernet frames from my Windows desktop.
        constant REF1 : std_logic_vector(479 downto 0) :=
            x"18_60_24_7e_35_79_00_25_b4_cf_32_c0_08_00_45_00" &
            x"00_28_78_10_40_00_7c_06_6f_9a_ac_11_28_a9_0a_03" &
            x"38_68_eb_97_0d_3d_90_f3_b9_dc_eb_32_de_14_50_10" &
            x"01_00_8a_c2_00_00_5d_b5_87_4d_00_00";
        constant REF2 : std_logic_vector(431 downto 0) :=
            x"00_25_b4_cf_32_c0_18_60_24_7e_35_79_08_00_45_00" &
            x"00_28_12_01_40_00_80_06_d1_a9_0a_03_38_68_ac_11" &
            x"28_a9_0d_3d_eb_97_eb_32_ed_19_90_f3_ba_32_50_10" &
            x"f9_4d_17_40_00_00";
        -- ICMP echo request to the router and to a remote server.
        variable ECHO_ROUTER_SHORT_IP : ip_packet := make_icmp_request(
            ROUTER_IPADDR, LOCAL1_IP, ICMP_TC_ECHORQ, x"ab01", rand_vec(64));
        variable ECHO_ROUTER_LONG_IP : ip_packet := make_icmp_request(
            ROUTER_IPADDR, LOCAL1_IP, ICMP_TC_ECHORQ, x"ab02", rand_vec(16*ICMP_ECHO_BYTES));
        variable ECHO_REMOTE_IP : ip_packet := make_icmp_request(
            OUTER1_IP, LOCAL1_IP, ICMP_TC_ECHORQ, x"ab03", rand_vec(64));
        variable ECHO_BCAST_IP : ip_packet := make_icmp_request(
            IP_BROADCAST, LOCAL1_IP, ICMP_TC_ECHORQ, x"ab04", rand_vec(64));
        -- ICMP timestamp request to the router and to a remote server.
        variable TREQ_ROUTER_IP : ip_packet := make_icmp_request(
            ROUTER_IPADDR, LOCAL2_IP, ICMP_TC_TIMERQ, x"ab04", rand_vec(64) & ZPAD32 & ZPAD32);
        variable TREQ_REMOTE_IP : ip_packet := make_icmp_request(
            OUTER1_IP, LOCAL2_IP, ICMP_TC_TIMERQ, x"ab05", rand_vec(128));
        -- ICMP address-mask request and reply, with TTL = 1 and TTL = 0.
        variable MASKREQ1_IP : ip_packet := make_icmp_request(
            ROUTER_IPADDR, LOCAL2_IP, ICMP_TC_MASKRQ, x"ab04", rand_vec(32) & ROUTER_SUBNET, 1);
        variable MASKREQ0_IP : ip_packet := make_icmp_request(
            ROUTER_IPADDR, LOCAL2_IP, ICMP_TC_MASKRQ, x"ab05", rand_vec(32) & ROUTER_SUBNET, 0);
        -- UDP packets with TTL=1 and TTL=0, respectively.
        variable UDP_TTL1_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, LOCAL1_IP,
                x"ab06", IPPROTO_UDP, IPFLAG_NORMAL, 1), rand_vec(128));
        variable UDP_TTL0_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER2_IP, LOCAL2_IP,
                x"ab07", IPPROTO_UDP, IPFLAG_NORMAL, 0), rand_vec(128));
        -- Packets with illegal source addresses.
        variable UDP_SRCBCAST_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, IP_BROADCAST,
                x"ab08", IPPROTO_UDP, IPFLAG_NORMAL), rand_vec(128));
        variable UDP_SRCMCAST_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, MCAST1_IP,
                x"ab09", IPPROTO_UDP, IPFLAG_NORMAL), rand_vec(128));
        variable UDP_SRCROUTER_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, ROUTER_IPADDR,
                x"ab0a", IPPROTO_UDP, IPFLAG_NORMAL), rand_vec(128));
        -- UDP broadcast and multicast packets.
        variable UDP_BCAST_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_BROADCAST, LOCAL2_IP,
                x"ab0b", IPPROTO_UDP, IPFLAG_NORMAL), rand_vec(128));
        variable UDP_MCAST_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(MCAST1_IP, LOCAL2_IP,
                x"ab0c", IPPROTO_UDP, IPFLAG_NORMAL), rand_vec(128));
        -- Two-part fragmented packet.
        variable UDP_FRAG1_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, LOCAL1_IP,
                x"ab0d", IPPROTO_UDP, IPFLAG_FRAG1), rand_vec(128));
        variable UDP_FRAG2_IP : ip_packet := make_ipv4_pkt(
            make_ipv4_header(OUTER1_IP, LOCAL1_IP,
                x"ab0e", IPPROTO_UDP, IPFLAG_FRAG2), rand_vec(128));
        -- Randomly generated raw-Ethernet traffic.
        variable RAW1_ETH : eth_packet := make_eth_pkt(
            OUTER1_MAC, LOCAL1_MAC, ETYPE_NOIP, rand_vec(64));
        variable RAW2_ETH : eth_packet := make_eth_pkt(
            OUTER2_MAC, LOCAL2_MAC, ETYPE_NOIP, rand_vec(64));
        variable ARP_ETH : eth_packet := make_eth_pkt(
            OUTER1_MAC, LOCAL1_MAC, ETYPE_ARP, rand_vec(64));
        variable BCAST1_ETH : eth_packet := make_eth_pkt(
            MAC_ADDR_BROADCAST, LOCAL1_MAC, ETYPE_NOIP, rand_vec(64));
        variable BCAST2_ETH : eth_packet := make_eth_pkt(
            OUTER2_MAC, MAC_ADDR_BROADCAST, ETYPE_NOIP, rand_vec(64));
    begin
        -- Set test conditions and update high/low test index.
        test_idx_hi     <= test_idx_hi + 1;
        test_idx_lo     <= 0;
        test_rate_in    <= ri;
        test_rate_out   <= ro;
        test_rate_icmp  <= rc;
        router_link_ok  <= '1';

        -- Test #1: Send a few canned frames through the unit under test,
        -- so we can verify checksums against a known-good reference.
        test_start;
        if (not IPV4_DMAC_FILTER) then
            expect_out(decr_ipv4_ttl(REF1).all);
            expect_out(decr_ipv4_ttl(REF2).all);
        end if;
        send_in(REF1);
        send_in(REF2);
        test_finish;

        -- Test #2: ICMP Echo request to the router (should reply)
        test_start;
        expect_icmp(icmp_from_router(
            LOCAL1_MAC, ICMP_TC_ECHORP, ECHO_ROUTER_SHORT_IP.all).all);
        expect_icmp(icmp_from_router(
            LOCAL2_MAC, ICMP_TC_ECHORP, ECHO_ROUTER_SHORT_IP.all).all);
        send_in(ip_to_router(LOCAL1_MAC, ECHO_ROUTER_SHORT_IP.all).all);
        test_wait;
        send_in(ip_to_router(LOCAL2_MAC, ECHO_ROUTER_SHORT_IP.all).all);
        test_finish;

        -- Test #3: Very long ICMP Echo request to the router (should reply)
        test_start;
        expect_icmp(icmp_from_router(
            LOCAL1_MAC, ICMP_TC_ECHORP, ECHO_ROUTER_LONG_IP.all).all);
        expect_icmp(icmp_from_router(
            LOCAL2_MAC, ICMP_TC_ECHORP, ECHO_ROUTER_LONG_IP.all).all);
        send_in(ip_to_router(
            LOCAL1_MAC, ECHO_ROUTER_LONG_IP.all).all);
        test_wait;
        send_in(ip_to_router(
            LOCAL2_MAC, ECHO_ROUTER_LONG_IP.all).all);
        test_finish;

        -- Test #4: ICMP Echo request to remote server (should forward)
        test_start;
        expect_out(ip_forward(LOCAL1_MAC, ECHO_REMOTE_IP.all).all);
        send_in(ip_to_router(LOCAL1_MAC, ECHO_REMOTE_IP.all).all);
        test_finish;

        -- Test #5: ICMP Timestamp request to the router and the remote server.
        test_start;
        expect_out(ip_forward(
            LOCAL1_MAC, TREQ_REMOTE_IP.all).all);
        expect_icmp(icmp_from_router(
            LOCAL2_MAC, ICMP_TC_TIMERP, TREQ_ROUTER_IP.all).all);
        send_in(ip_to_router(
            LOCAL2_MAC, TREQ_ROUTER_IP.all).all);
        send_in(ip_to_router(
            LOCAL1_MAC, TREQ_REMOTE_IP.all).all);
        test_finish;

        -- Test #6: Trigger a "Time exceeded" error.
        test_start;
        expect_out(ip_forward(
            LOCAL1_MAC, UDP_TTL1_IP.all).all);
        expect_icmp(icmp_from_router(
            LOCAL2_MAC, ICMP_TC_TTL, UDP_TTL0_IP.all).all);
        send_in(ip_to_router(LOCAL1_MAC, UDP_TTL1_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_TTL0_IP.all).all);
        test_finish;

        -- Test #7: Trigger a "Destination network unreachable" error.
        router_link_ok <= '0';
        test_start;
        expect_icmp(icmp_from_router(
            LOCAL1_MAC, ICMP_TC_DNU, UDP_TTL1_IP.all).all);
        send_in(ip_to_router(
            LOCAL1_MAC, UDP_TTL1_IP.all).all);
        test_finish;
        router_link_ok <= '1';

        -- Test #8: Send several types of non-IPv4 frames.
        test_start;
        if (not NOIP_BLOCK_ALL) then
            expect_out(RAW1_ETH.all);
            expect_out(RAW2_ETH.all);
            if (not NOIP_BLOCK_ARP) then
                expect_out(ARP_ETH.all);
            end if;
            if (not NOIP_BLOCK_BCAST) then
                expect_out(BCAST1_ETH.all);
            end if;
        end if;
        send_in(RAW1_ETH.all);      -- Generic non-IPv4 (depends on rules)
        send_in(RAW2_ETH.all);      -- Generic non-IPv4 (depends on rules)
        send_in(ARP_ETH.all);       -- ARP message (depends on rules)
        send_in(BCAST1_ETH.all);    -- Dst = BCAST (depends on rules)
        send_in(BCAST2_ETH.all);    -- Src = BCAST (always blocked)
        test_finish;

        -- Test #9: Extended test forwarding many back-to-back IPv4 frames.
        test_start;
        for n in 1 to 50 loop
            expect_out(ip_forward(LOCAL1_MAC, ECHO_REMOTE_IP.all).all);
        end loop;
        for n in 1 to 50 loop
            send_in(ip_to_router(LOCAL1_MAC, ECHO_REMOTE_IP.all).all);
        end loop;
        test_finish;

        -- Test #10: Back-to-back ICMP replies should drop the second frame.
        -- (Except under conditions where input is much slower than control port.)
        test_start;
        expect_icmp(icmp_from_router(
            LOCAL1_MAC, ICMP_TC_TTL, UDP_TTL0_IP.all).all);
        if (2.0*ri < ro) then
            expect_icmp(icmp_from_router(
                LOCAL2_MAC, ICMP_TC_TTL, UDP_TTL0_IP.all).all);
        end if;
        send_in(ip_to_router(LOCAL1_MAC, UDP_TTL0_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_TTL0_IP.all).all);
        test_finish;

        -- Test #11: Forbidden cases for the MAC broadcast address.
        test_start;
        send_in(make_eth_pkt(MAC_ADDR_BROADCAST, LOCAL2_MAC, ETYPE_IPV4, UDP_TTL1_IP.all).all);
        send_in(ip_to_router(MAC_ADDR_BROADCAST, UDP_TTL1_IP.all).all);
        test_finish;

        -- Test #12: Forbidden IP source-address
        test_start;
        send_in(ip_to_router(LOCAL2_MAC, UDP_SRCBCAST_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_SRCMCAST_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_SRCROUTER_IP.all).all);
        test_finish;

        -- Test #13: IP limited-broadcast, multicast, and fragment rules.
        test_start;
        if (not IPV4_BLOCK_MCAST) then
            expect_out(ip_forward(LOCAL2_MAC, UDP_MCAST_IP.all).all);
        end if;
        if (not IPV4_BLOCK_FRAGMENT) then
            expect_out(ip_forward(LOCAL2_MAC, UDP_FRAG1_IP.all).all);
            expect_out(ip_forward(LOCAL2_MAC, UDP_FRAG2_IP.all).all);
        end if;
        send_in(ip_to_router(LOCAL2_MAC, UDP_BCAST_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_MCAST_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_FRAG1_IP.all).all);
        send_in(ip_to_router(LOCAL2_MAC, UDP_FRAG2_IP.all).all);
        test_finish;

        -- Test #14: Maximum-length UDP packet, with options field.
        test_single(10, 1400);

        -- Test #15: ICMP address-mask request, with TTL = 1 and TTL = 0.
        test_start;
        expect_icmp(icmp_from_router(LOCAL1_MAC, ICMP_TC_MASKRP, MASKREQ1_IP.all).all);
        expect_icmp(icmp_from_router(LOCAL2_MAC, ICMP_TC_MASKRP, MASKREQ0_IP.all).all);
        send_in(ip_to_router(LOCAL1_MAC, MASKREQ1_IP.all).all);
        test_wait;
        send_in(ip_to_router(LOCAL2_MAC, MASKREQ0_IP.all).all);
        test_finish;

        -- Test #16: Echo request to the limited-broadcast IP.
        test_start;
        expect_icmp(icmp_from_router(LOCAL1_MAC, ICMP_TC_ECHORP, ECHO_BCAST_IP.all).all);
        send_in(make_eth_pkt(MAC_ADDR_BROADCAST, LOCAL1_MAC, ETYPE_IPV4, ECHO_BCAST_IP.all).all);
        test_finish;
    end procedure;
begin
    -- Run the same test sequence under different flow-control conditions.
    test_sequence(1.0, 1.0, 1.0);
    test_sequence(0.2, 1.0, 1.0);
    test_sequence(1.0, 0.2, 1.0);
    test_sequence(1.0, 1.0, 0.2);

    -- Monte-carlo testing with many generated packets:
    test_random(1000);

    report "All tests completed.";
    wait;
end process;

end tb;
