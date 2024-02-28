--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Proxy-ARP
--
-- This is a unit test for the Proxy-ARP block, which verifies that:
--  * Non-ARP traffic is completely ignored.
--  * A response is sent only for ARP queries within the specified subnet.
--  * Valid responses are sent under all flow-control conditions.
--
-- The complete test takes less than 1.5 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_arp_proxy_tb is
    -- Testbench, no I/O ports
end router_arp_proxy_tb;

architecture tb of router_arp_proxy_tb is

-- Local subnet = 192.168.1.*
-- Proxy subnet = Everything else (outer match)
constant SUBNET_INNER   : boolean := false;
constant SUBNET_ADDR    : ip_addr_t := x"C0A80100";
constant SUBNET_MASK    : ip_addr_t := x"FFFFFF00";

-- Other constants:
constant ROUTER_MAC     : mac_addr_t := x"DEADBEEFCAFE";
constant ROUTER_IP      : ip_addr_t := x"D00D1234";

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '0';

-- Network interface to unit under test
signal pkt_rx_data      : byte_t := (others => '0');
signal pkt_rx_last      : std_logic := '0';
signal pkt_rx_write     : std_logic := '0';
signal pkt_tx_data      : byte_t;
signal pkt_tx_last      : std_logic;
signal pkt_tx_valid     : std_logic;
signal pkt_tx_ready     : std_logic := '0';

-- Pre-parser
signal arp_rx_data      : byte_t := (others => '0');
signal arp_rx_first     : std_logic := '0';
signal arp_rx_last      : std_logic := '0';
signal arp_rx_write     : std_logic := '0';

-- Generate network packets
signal query_type       : pkt_type_t := PKT_JUNK;
signal query_start      : std_logic := '0';
signal query_busy       : std_logic := '0';
signal query_sha        : mac_addr_t := (others => '0');
signal query_spa        : ip_addr_t := (others => '0');
signal query_tha        : mac_addr_t := (others => '0');
signal query_tpa        : ip_addr_t := (others => '0');

-- Receive network packets
signal reply_ctr        : bcount_t := (others => '0');
signal reply_rdy        : std_logic := '0';
signal reply_dst        : mac_addr_t := (others => '0');
signal reply_src        : mac_addr_t := (others => '0');
signal reply_hdr        : std_logic_vector(79 downto 0) := (others => '0');
signal reply_sha        : mac_addr_t := (others => '0');
signal reply_spa        : ip_addr_t := (others => '0');
signal reply_tha        : mac_addr_t := (others => '0');
signal reply_tpa        : ip_addr_t := (others => '0');

-- High-level test control
signal test_idx         : integer := 0;
signal rate_in          : real := 0.0;
signal rate_out         : real := 0.0;

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Generate network packets
u_query : router_sim_pkt_gen
    port map(
    tx_clk      => clk_100,
    tx_data     => pkt_rx_data,
    tx_last     => pkt_rx_last,
    tx_write    => pkt_rx_write,
    cmd_type    => query_type,
    cmd_rate    => rate_in,
    cmd_start   => query_start,
    cmd_busy    => query_busy,
    cmd_sha     => query_sha,
    cmd_spa     => query_spa,
    cmd_tha     => query_tha,
    cmd_tpa     => query_tpa);

-- Pre-parser
pre : entity work.router_arp_parse
    port map(
    pkt_rx_data     => pkt_rx_data,
    pkt_rx_last     => pkt_rx_last,
    pkt_rx_write    => pkt_rx_write,
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    clk             => clk_100,
    reset_p         => reset_p);

-- Unit under test
uut : entity work.router_arp_proxy
    generic map(
    SUBNET_INNER    => SUBNET_INNER,
    LOCAL_MACADDR   => ROUTER_MAC)
    port map(
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    pkt_tx_data     => pkt_tx_data,
    pkt_tx_last     => pkt_tx_last,
    pkt_tx_valid    => pkt_tx_valid,
    pkt_tx_ready    => pkt_tx_ready,
    router_addr     => ROUTER_IP,
    subnet_addr     => SUBNET_ADDR,
    subnet_mask     => SUBNET_MASK,
    clk             => clk_100,
    reset_p         => reset_p);

-- Receive network packets
p_reply : process(clk_100)
    variable seed1  : positive := 1821507;
    variable seed2  : positive := 6157657;
    variable rand   : real := 0.0;
    variable sreg   : std_logic_vector(335 downto 0) := (others => '0');
begin
    if rising_edge(clk_100) then
        -- Flow control randomization.
        uniform(seed1, seed2, rand);
        pkt_tx_ready <= bool2bit(rand < rate_out);

        -- Receive data into a big shift register...
        if (pkt_tx_valid = '1' and pkt_tx_ready = '1') then
            sreg := sreg(327 downto 0) & pkt_tx_data;
        end if;

        -- If that was the last byte, latch all the individual fields.
        -- TODO: Do we need to test the zero-padding function?
        if (pkt_tx_last = '1' and pkt_tx_valid = '1' and pkt_tx_ready = '1') then
            reply_ctr <= reply_ctr + 1;
            reply_rdy <= '1';
            reply_dst <= sreg(335 downto 288);
            reply_src <= sreg(287 downto 240);
            reply_hdr <= sreg(239 downto 160);
            reply_sha <= sreg(159 downto 112);
            reply_spa <= sreg(111 downto  80);
            reply_tha <= sreg( 79 downto  32);
            reply_tpa <= sreg( 31 downto   0);
        else
            reply_rdy <= '0';
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    variable refct : bcount_t := (others => '0');

    -- Reset unit under test.
    procedure restart is
    begin
        report "Starting test #" & integer'image(test_idx+1);
        test_idx <= test_idx + 1;
        reset_p  <= '1';
        wait for 1 us;
        reset_p  <= '0';
        wait for 1 us;
        refct := reply_ctr;
    end procedure;

    -- Send N frames of non-ARP data.
    procedure send_junk(njunk : integer := 1) is
    begin
        for n in 1 to njunk loop
            wait until rising_edge(clk_100);
            query_start <= '1';
            query_type  <= PKT_JUNK;
            wait until rising_edge(clk_100);
            query_start <= '0';
            wait until falling_edge(query_busy);
        end loop;
    end procedure;

    -- Confirm reply matches expected format.
    procedure check_next_reply is
        variable timeout : integer := 1000;
    begin
        -- Wait for reply or timeout countdown, whichever comes first...
        while (reply_rdy = '0' and timeout > 0) loop
            wait until rising_edge(clk_100);
            timeout := timeout - 1;
        end loop;
        -- If we got a reply, check the contents.
        if (timeout = 0) then
            report "Timeout waiting for reply." severity error;
        else
            assert((reply_dst = query_sha)
               and (reply_src = ROUTER_MAC)
               and (reply_hdr = ARP_REPLY_HDR)
               and (reply_sha = ROUTER_MAC)
               and (reply_spa = query_tpa)
               and (reply_tha = query_sha)
               and (reply_tpa = query_spa))
                report "Reply format mismatch!" severity error;
        end if;
    end procedure;

    -- Send an ARP query in or out of subnet.
    -- Note: Special value "X" is used to indicate the router IP.
    procedure send_query(
        in_subnet   : std_logic;
        ptype       : pkt_type_t) is
    begin
        -- Wait for previous query to finish...
        while (query_busy = '1') loop
            wait until rising_edge(clk_100);
        end loop;

        -- Randomize query parameters.
        wait until rising_edge(clk_100);
        query_start <= '1';
        query_type  <= ptype;
        query_sha   <= rand_vec(48);
        query_spa   <= rand_vec(32);
        query_tha   <= rand_vec(48);
        if (in_subnet = 'X') then
            query_tpa <= ROUTER_IP;
        else
            query_tpa <= rand_ip_sub(SUBNET_ADDR, SUBNET_MASK, in_subnet);
        end if;
        wait until rising_edge(clk_100);
        query_start <= '0';

        -- If we expect a reply, wait for it and confirm format.
        -- Otherwise, just wait for query to finish.
        if ((ptype = PKT_ARP_REQUEST) and (in_subnet = '1')) then
            check_next_reply;   -- Normal query
        elsif ((ptype = PKT_ARP_REQUEST) and (in_subnet = 'X') and (ROUTER_IP /= IP_NOT_VALID)) then
            check_next_reply;   -- Router query
        else
            wait until falling_edge(query_busy);
        end if;
    end procedure;

    -- Confirm number of replies received since last call to restart.
    procedure check_reply_count(ref:integer) is
        variable rcvd : integer := 0;
    begin
        wait for 1 us;
        rcvd := to_integer(reply_ctr - refct);
        assert (rcvd = ref)
            report "Reply count mismatch = " & integer'image(rcvd)
            severity error;
    end procedure;

    -- Standard test sequence:
    procedure test_sequence(ri, ro: real) is
    begin
        -- Set flow-control conditions:
        rate_in     <= ri;
        rate_out    <= ro;

        -- Test #1: Simple query/reply with no fluff.
        restart;
        send_query('1', PKT_ARP_REQUEST);
        check_reply_count(1);

        -- Test #2: A series of in-subnet and out-of-subnet queries.
        restart;
        send_query('0', PKT_ARP_REQUEST);
        send_query('1', PKT_ARP_REQUEST);
        send_query('0', PKT_ARP_REQUEST);
        send_query('1', PKT_ARP_REQUEST);
        send_query('1', PKT_ARP_REQUEST);
        send_query('0', PKT_ARP_REQUEST);
        check_reply_count(3);

        -- Test #3: 50 junk packets with a query in the middle.
        restart;
        send_junk(25);
        send_query('1', PKT_ARP_REQUEST);
        send_junk(25);
        check_reply_count(1);

        -- Test #4: 50 junk packets with a response in the middle.
        restart;
        send_junk(25);
        send_query('1', PKT_ARP_RESPONSE);
        send_junk(25);
        check_reply_count(0);

        -- Test #5: Simple query/reply against the router IP.
        restart;
        send_query('X', PKT_ARP_REQUEST);
        check_reply_count(1);
    end procedure;
begin
    -- Repeat standard test sequence in different flow conditions:
    test_sequence(1.0, 1.0);
    test_sequence(1.0, 0.8);
    test_sequence(1.0, 0.2);
    test_sequence(0.8, 1.0);
    test_sequence(0.8, 0.8);
    test_sequence(0.8, 0.2);
    test_sequence(0.2, 1.0);
    test_sequence(0.2, 0.8);
    test_sequence(0.2, 0.2);
    report "All tests completed!";
    wait;
end process;

end tb;
