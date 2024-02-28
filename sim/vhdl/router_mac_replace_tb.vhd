--------------------------------------------------------------------------
-- Copyright 2020-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the MAC-address Replacement block
--
-- This is the unit test for the router_mac_replace block.  It drives a
-- series of IPv4 and non-IPv4 packets into the input, and checks that each
-- packet is forwarded, modified, or dropped accordingly, including the
-- generation of ICMP errors when applicable.  A preset test sequence is
-- repeated under different flow-control conditions, followed by a longer
-- Monte-Carlo test.
--
-- The complete test takes about 10.3 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_mac_replace_tb is
    generic (
    -- Adjust generics to test different configurations.
    QUERY_DELAY     : natural := 10;
    RETRY_KBYTES    : natural := 2;
    ICMP_ECHO_BYTES : natural := 64;
    NOIP_BLOCK_ALL  : boolean := false);
    -- No I/O ports
end router_mac_replace_tb;

architecture tb of router_mac_replace_tb is

-- Arbitrary addresses for the router and test sources:
constant ROUTER_MACADDR : mac_addr_t := x"DEADBEEFCAFE";
constant ROUTER_IPADDR  : ip_addr_t := x"C0A80101";
constant TEST_SRC_MAC   : mac_addr_t := x"EE1111111111";
constant TEST_SRC_IP    : ip_addr_t := x"DD111111";
constant TEST_DST_MAC   : mac_addr_t := x"EE2222222222";
constant TEST_DST_IP    : ip_addr_t := x"DD222222";

-- Make the retry delay very short for simulation purposes.
constant RETRY_DLY_CLKS : natural := 200;

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Input stream (from source)
signal in_data          : byte_t := (others => '0');
signal in_last          : std_logic := '0';
signal in_valid         : std_logic := '0';
signal in_ready         : std_logic;

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

-- Query / reply interface to the ARP-Cache.
signal query_addr       : byte_t;
signal query_first      : std_logic;
signal query_valid      : std_logic;
signal query_ready      : std_logic := '0';
signal reply_addr       : byte_t := (others => '0');
signal reply_first      : std_logic := '0';
signal reply_match      : std_logic := '0';
signal reply_write      : std_logic := '0';

-- Other status indicators.
signal uut_pkt_drop     : std_logic;
signal uut_pkt_error    : std_logic;

-- High-level test control
signal test_idx_hi      : natural := 0;
signal test_idx_lo      : natural := 0;
signal test_rate_in     : real := 0.0;
signal test_rate_out    : real := 0.0;
signal test_rate_icmp   : real := 0.0;
signal test_drop_ct     : natural := 0;
signal test_arp_match   : std_logic := '0';

begin

-- Clock generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Unit under test
uut : entity work.router_mac_replace
    generic map(
    ROUTER_MACADDR  => ROUTER_MACADDR,
    RETRY_KBYTES    => RETRY_KBYTES,
    RETRY_DLY_CLKS  => RETRY_DLY_CLKS,
    ICMP_ECHO_BYTES => ICMP_ECHO_BYTES,
    NOIP_BLOCK_ALL  => NOIP_BLOCK_ALL)
    port map(
    in_data         => in_data,
    in_last         => in_last,
    in_valid        => in_valid,
    in_ready        => in_ready,
    out_data        => uut_out_data,
    out_last        => uut_out_last,
    out_valid       => uut_out_valid,
    out_ready       => uut_out_ready,
    icmp_data       => uut_icmp_data,
    icmp_last       => uut_icmp_last,
    icmp_valid      => uut_icmp_valid,
    icmp_ready      => uut_icmp_ready,
    query_addr      => query_addr,
    query_first     => query_first,
    query_valid     => query_valid,
    query_ready     => query_ready,
    reply_addr      => reply_addr,
    reply_first     => reply_first,
    reply_match     => reply_match,
    reply_write     => reply_write,
    router_ipaddr   => ROUTER_IPADDR,
    pkt_drop        => uut_pkt_drop,
    pkt_error       => uut_pkt_error,
    clk             => clk_100,
    reset_p         => reset_p);

-- Emulate the ARP query/response.
p_cache : process(clk_100)
    variable arp_match  : std_logic := '0';
    variable rx_count   : integer := 0;
    variable tx_count   : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Compare query against expected value.
        if (query_valid = '1' and query_ready = '1') then
            assert (query_first = bool2bit(rx_count = 0))
                report "Query missing first strobe." severity error;
            assert (query_addr = get_byte_s(TEST_DST_IP, 3-rx_count))
                report "Query address mismatch." severity error;
        end if;

        -- Latch the "match" flag at the start of the query.
        if (query_valid = '1' and query_ready = '1' and query_first = '1') then
            arp_match := test_arp_match;
        end if;

        -- Update the transmit state.
        if (reset_p = '1') then
            tx_count := 0;                  -- Idle
        elsif (query_valid = '1' and query_ready = '1' and rx_count = 3) then
            tx_count := 6 + QUERY_DELAY;    -- Start of new query
        elsif (tx_count > 0) then
            tx_count := tx_count - 1;       -- Countdown to zero.
        end if;

        -- New transmit state determines outputs.
        if (1 <= tx_count and tx_count <= 6) then
            if (arp_match = '1') then
                reply_addr <= get_byte_s(TEST_DST_MAC, tx_count-1);
            else
                reply_addr <= (others => '0');
            end if;
            reply_match <= arp_match;
            reply_first <= bool2bit(tx_count = 6);
            reply_write <= '1';
        else
            reply_addr  <= (others => '0');
            reply_first <= '0';
            reply_match <= '0';
            reply_write <= '0';
        end if;
        query_ready <= bool2bit(tx_count = 0);

        -- Count received bytes.
        if (reset_p = '1') then
            rx_count := 0;
        elsif (query_valid = '1' and query_ready = '1') then
            rx_count := (rx_count + 1) mod 4;
        end if;
    end if;
end process;

-- FIFOs for the two test streams.
ref_out_ready <= uut_out_valid and uut_out_ready;
u_fifo_out : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => 8,
    FIFO_DEPTH  => 2048)
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
        elsif (uut_pkt_drop = '1') then
            test_drop_ct <= test_drop_ct + 1;
        end if;

        -- Error strobe shoould never be asserted.
        assert (reset_p = '1' or uut_pkt_error = '0')
            report "Unexpected internal error." severity error;
    end if;
end process;

-- High-level test control
p_test : process
    -- Count sent and expected packets.
    variable pkt_sent   : natural := 0;
    variable pkt_reply  : natural := 0;
    variable icmp_ident : bcount_t := (others => '0');

    -- Wrapper functions for various make_xx functions:
    impure function icmp_from_uut(
        ippkt   : std_logic_vector)
        return eth_packet
    is
        variable icmp : ip_packet := make_icmp_reply(
            ROUTER_IPADDR,      -- Packet is from router.
            ICMP_TC_DHU,        -- "Destination host unreachable"
            icmp_ident,         -- Counter for next reply
            ippkt,              -- Reference IP packet
            ICMP_ECHO_BYTES);   -- Maximum reply length
    begin
        -- Note: Not safe to increment icmp_ident here, because of a bug
        --       in Vivado 2016.4 that causes duplicate calls.
        return make_eth_pkt(TEST_SRC_MAC, ROUTER_MACADDR, ETYPE_IPV4, icmp.all);
    end function;

    function ip_to_uut(
        ippkt   : std_logic_vector)
        return eth_packet is
    begin
        return make_eth_pkt(ROUTER_MACADDR, TEST_SRC_MAC, ETYPE_IPV4, ippkt);
    end function;

    function ip_from_uut(
        ippkt   : std_logic_vector)
        return eth_packet is
    begin
        return make_eth_pkt(TEST_DST_MAC, TEST_SRC_MAC, ETYPE_IPV4, ippkt);
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
        constant NUM_BYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Load each byte in the packet...
        for n in NUM_BYTES-1 downto 0 loop
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

    procedure expect_out_if(x : std_logic_vector; en : boolean) is
    begin
        if (en) then
            expect_out(x);
        end if;
    end procedure;

    procedure expect_icmp(x : std_logic_vector) is
        constant NUM_BYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Load each byte in the packet...
        for n in NUM_BYTES-1 downto 0 loop
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

    procedure expect_icmp_if(x : std_logic_vector; en : boolean) is
    begin
        if (en) then
            expect_icmp(x);
        end if;
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
    procedure test_wait(dly : integer) is
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
        test_wait(2*RETRY_DLY_CLKS);
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
        variable pkt_ip : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                TEST_DST_IP, TEST_SRC_IP,   -- Destination and source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP,                -- Protcol = UDP
                IPFLAG_NORMAL,              -- Fragmentation flags
                1+rand_int(63)),            -- Time-to-live
            rand_vec(8*dat_num_bytes),      -- Packet data
            rand_vec(32*opt_num_words));    -- Extended header options
    begin
        test_start(print_interval);
        if (test_arp_match = '1') then
            expect_out(ip_from_uut(pkt_ip.all).all);
        elsif (RETRY_KBYTES > 0) then
            expect_icmp(icmp_from_uut(pkt_ip.all).all);
        end if;
        send_in(ip_to_uut(pkt_ip.all).all);
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
        test_arp_match  <= '1';

        -- Run N tests, each with a single random packet.
        for n in 1 to npkt loop
            test_single(rand_int(11), 1 + rand_int(1400), 20);
        end loop;
    end procedure;

    -- Standard test sequence:
    procedure test_sequence(ri, ro, rc : real) is
        variable NOIP_SHORT : eth_packet := make_eth_pkt(
            TEST_DST_MAC, TEST_SRC_MAC, ETYPE_NOIP, rand_vec(64));
        variable NOIP_LONG  : eth_packet := make_eth_pkt(
            TEST_DST_MAC, TEST_SRC_MAC, ETYPE_NOIP, rand_vec(8192));
        variable IP_PKT1    : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                TEST_DST_IP, TEST_SRC_IP,   -- Destination and source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP,                -- Protcol = UDP
                IPFLAG_NORMAL,              -- Fragmentation flags
                1+rand_int(63)),            -- Time-to-live
            rand_vec(64));                  -- Packet data
        variable IP_PKT2    : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                TEST_DST_IP, TEST_SRC_IP,   -- Destination and source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP,                -- Protcol = UDP
                IPFLAG_NORMAL,              -- Fragmentation flags
                1+rand_int(63)),            -- Time-to-live
            rand_vec(64));                  -- Packet data
    begin
        -- Set test conditions and update high/low test index.
        test_idx_hi     <= test_idx_hi + 1;
        test_idx_lo     <= 0;
        test_rate_in    <= ri;
        test_rate_out   <= ro;
        test_rate_icmp  <= rc;
        test_arp_match  <= '1';

        -- Test #1: Send a few non-IPv4 packets.
        test_start;
        expect_out_if(NOIP_SHORT.all, not NOIP_BLOCK_ALL);
        expect_out_if(NOIP_LONG.all,  not NOIP_BLOCK_ALL);
        expect_out_if(NOIP_SHORT.all, not NOIP_BLOCK_ALL);
        send_in(NOIP_SHORT.all);
        send_in(NOIP_LONG.all);
        send_in(NOIP_SHORT.all);
        test_finish;

        -- Test #2: Basic test with two cached IP addresses.
        test_start;
        test_arp_match <= '1';
        expect_out(ip_from_uut(IP_PKT1.all).all);
        expect_out(ip_from_uut(IP_PKT2.all).all);
        send_in(ip_to_uut(IP_PKT1.all).all);
        send_in(ip_to_uut(IP_PKT2.all).all);
        test_finish;

        -- Test #3: Basic test with two non-cached IP addresses.
        -- Note: Back-to-back loss + rate limiting drops the second ICMP reply,
        --       except when input is much slower than the ICMP port.
        test_start;
        test_arp_match <= '0';
        expect_icmp_if(icmp_from_uut(IP_PKT1.all).all, RETRY_KBYTES > 0);
        expect_icmp_if(icmp_from_uut(IP_PKT2.all).all, RETRY_KBYTES > 0 and rc > 2.0*ri);
        send_in(ip_to_uut(IP_PKT1.all).all);
        send_in(ip_to_uut(IP_PKT2.all).all);
        test_finish;

        -- Test #4: Same as previous, but with a short gap.
        -- Note: With this gap, both ICMP replies can be sent, except when
        --       ICMP output is much slower than the input.
        test_start;
        test_arp_match <= '0';
        expect_icmp_if(icmp_from_uut(IP_PKT1.all).all, RETRY_KBYTES > 0);
        expect_icmp_if(icmp_from_uut(IP_PKT2.all).all, RETRY_KBYTES > 0 and ri < 2.0*rc);
        send_in(ip_to_uut(IP_PKT1.all).all);
        test_wait(RETRY_DLY_CLKS / 2);
        send_in(ip_to_uut(IP_PKT2.all).all);
        test_finish;

        -- Test #5: A compound test where the cache is updated during the retry delay.
        test_start;
        test_arp_match <= '0';
        expect_out_if(ip_from_uut(IP_PKT1.all).all, RETRY_KBYTES > 0);
        send_in(ip_to_uut(IP_PKT1.all).all);
        test_wait(QUERY_DELAY / 2);
        test_arp_match <= '1';
        test_finish;

        -- Test #6: Back-to-back test a mixture of packet types.
        test_start;
        test_arp_match <= '1';

        expect_out(ip_from_uut(IP_PKT1.all).all);
        expect_out(ip_from_uut(IP_PKT2.all).all);
        expect_out_if(NOIP_SHORT.all, not NOIP_BLOCK_ALL);
        expect_out(ip_from_uut(IP_PKT1.all).all);
        expect_out(ip_from_uut(IP_PKT2.all).all);
        expect_out_if(NOIP_SHORT.all, not NOIP_BLOCK_ALL);
        expect_out(ip_from_uut(IP_PKT1.all).all);
        expect_out(ip_from_uut(IP_PKT2.all).all);
        expect_out_if(NOIP_SHORT.all, not NOIP_BLOCK_ALL);
        
        send_in(ip_to_uut(IP_PKT1.all).all);
        send_in(ip_to_uut(IP_PKT2.all).all);
        send_in(NOIP_SHORT.all);
        send_in(ip_to_uut(IP_PKT1.all).all);
        send_in(ip_to_uut(IP_PKT2.all).all);
        send_in(NOIP_SHORT.all);
        send_in(ip_to_uut(IP_PKT1.all).all);
        send_in(ip_to_uut(IP_PKT2.all).all);
        send_in(NOIP_SHORT.all);

        test_finish;

        -- Test #7: Max-length IPv4 packet.
        test_single(10, 1400);
    end procedure;
begin
    -- Run the same test sequence under different flow-control conditions.
    test_sequence(1.0, 1.0, 1.0);
    test_sequence(0.2, 1.0, 1.0);
    test_sequence(1.0, 0.2, 1.0);
    test_sequence(1.0, 1.0, 0.2);

    -- Monte-carlo testing with many generated packets:
    test_random(500);

    report "All tests completed.";
    wait;
end process;

end tb;
