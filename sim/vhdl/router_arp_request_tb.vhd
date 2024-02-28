--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Address Resolution Cache
--
-- This is a unit test for the ARP-Cache block, which verifies that:
--  * New MAC/IPv4 address pairs are stored correctly.
--  * Duplicate or updated entries are stored correctly.
--  * Overflow of table evicts data in first-in / first-out order.
--  * Search function correctly returns match/no-match results.
--
-- The complete test takes less than 0.5 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_arp_request_tb is
    -- Testbench, no I/O ports
end router_arp_request_tb;

architecture tb of router_arp_request_tb is

-- Address constants:
constant ROUTER_MAC     : mac_addr_t := x"DEADBEEFCAFE";
constant ROUTER_IP      : ip_addr_t := x"D00D1234";

-- Set timeout to 200 usec = 20k clocks for simulation purposes.
-- Must be long enough to not matter in normal tests.)
constant HIST_COUNT     : integer := 4;
constant HIST_TIMEOUT   : integer := 20_000;

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '0';

-- Network interface
signal pkt_tx_data      : byte_t;
signal pkt_tx_last      : std_logic;
signal pkt_tx_valid     : std_logic;
signal pkt_tx_ready     : std_logic := '0';

-- Requests from ARP-Table
signal cmd_first        : std_logic := '0';
signal cmd_byte         : byte_t := (others => '0');
signal cmd_write        : std_logic := '0';

-- Receive network packets
signal arp_rdy          : std_logic := '0';
signal arp_dst          : mac_addr_t := (others => '0');
signal arp_src          : mac_addr_t := (others => '0');
signal arp_hdr          : std_logic_vector(79 downto 0) := (others => '0');
signal arp_sha          : mac_addr_t := (others => '0');
signal arp_spa          : ip_addr_t := (others => '0');
signal arp_tha          : mac_addr_t := (others => '0');
signal arp_tpa          : ip_addr_t := (others => '0');

-- High-level test control
signal test_idx         : integer := 0;
signal rate_in          : real := 0.0;
signal rate_out         : real := 0.0;
signal req_start        : std_logic := '0';
signal req_busy         : std_logic := '0';
signal req_ipaddr       : ip_addr_t := (others => '0');

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Generate requests on command:
p_req : process(clk_100)
    variable seed1  : positive := 1324107;
    variable seed2  : positive := 6709871;
    variable rand   : real := 0.0;
    variable bidx   : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Accept legal commands:
        if (reset_p = '1') then
            bidx := 0;          -- Reset / idle
        elsif (bidx = 0 and req_start = '1') then
            bidx := 4;          -- Start new command
        end if;
        req_busy <= bool2bit(bidx > 0);

        -- Drive each byte, with flow control randomization.
        uniform(seed1, seed2, rand);
        if ((bidx > 0) and (rand < rate_in)) then
            cmd_byte    <= get_byte_s(req_ipaddr, bidx-1);
            cmd_first   <= bool2bit(bidx = 4);
            cmd_write   <= '1';
            bidx := bidx - 1;
        else
            cmd_byte    <= (others => '0');
            cmd_first   <= '0';
            cmd_write   <= '0';
        end if;
    end if;
end process;

-- Unit under test:
uut : entity work.router_arp_request
    generic map(
    LOCAL_MACADDR   => ROUTER_MAC,
    HISTORY_COUNT   => HIST_COUNT,
    HISTORY_TIMEOUT => HIST_TIMEOUT)
    port map(
    pkt_tx_data     => pkt_tx_data,
    pkt_tx_last     => pkt_tx_last,
    pkt_tx_valid    => pkt_tx_valid,
    pkt_tx_ready    => pkt_tx_ready,
    request_first   => cmd_first,
    request_addr    => cmd_byte,
    request_write   => cmd_write,
    router_ipaddr   => ROUTER_IP,
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
            arp_rdy <= '1';
            arp_dst <= sreg(335 downto 288);
            arp_src <= sreg(287 downto 240);
            arp_hdr <= sreg(239 downto 160);
            arp_sha <= sreg(159 downto 112);
            arp_spa <= sreg(111 downto  80);
            arp_tha <= sreg( 79 downto  32);
            arp_tpa <= sreg( 31 downto   0);
        else
            arp_rdy <= '0';
        end if;
    end if;
end process;

-- High-level test control
p_test : process
    -- Reset unit under test.
    procedure restart is
    begin
        report "Starting test #" & integer'image(test_idx+1);
        test_idx <= test_idx + 1;
        reset_p  <= '1';
        wait for 1 us;
        reset_p  <= '0';
        wait for 1 us;
    end procedure;

    -- Confirm request matches expected format.
    procedure check_next_arp(reply : std_logic) is
        variable timeout : integer := integer(100.0 / rate_out);
    begin
        -- Wait for reply or timeout countdown, whichever comes first...
        while (arp_rdy = '0' and timeout > 0) loop
            wait until rising_edge(clk_100);
            timeout := timeout - 1;
        end loop;
        -- If we got a reply, check the contents.
        if (reply = '0') then
            assert (timeout = 0)
                report "Unexpected ARP request." severity error;
        elsif (timeout = 0) then
            report "Missing ARP request." severity error;
        else
            assert((arp_dst = MAC_ADDR_BROADCAST)
               and (arp_src = ROUTER_MAC)
               and (arp_hdr = ARP_QUERY_HDR)
               and (arp_sha = ROUTER_MAC)
               and (arp_spa = ROUTER_IP)
               and (arp_tpa = req_ipaddr))
                report "Reply format mismatch!" severity error;
        end if;
    end procedure;

    -- Issue a command and check the resulting ARP packet, if any.
    procedure send_query(
        addr    : ip_addr_t;
        reply   : std_logic) is
    begin
        -- Wait for previous request to finish...
        while (req_busy = '1') loop
            wait until rising_edge(clk_100);
        end loop;

        -- Randomize query parameters.
        wait until rising_edge(clk_100);
        req_start  <= '1';
        req_ipaddr <= addr;
        wait until rising_edge(clk_100);
        req_start <= '0';

        -- Wait for reply, if any.
        check_next_arp(reply);
    end procedure;

    -- Standard test sequence:
    procedure test_sequence(ri, ro: real) is
    begin
        -- Set flow-control conditions:
        rate_in     <= ri;
        rate_out    <= ro;

        -- Test #1: Simple request with no fluff.
        restart;
        send_query(x"12345678", '1');

        -- Test #2: A series of unique requests.
        restart;
        send_query(x"11111111", '1');
        send_query(x"22222222", '1');
        send_query(x"33333333", '1');
        send_query(x"44444444", '1');
        send_query(x"55555555", '1');
        send_query(x"66666666", '1');

        -- Test #3: Duplicate request, including overflow.
        restart;
        send_query(x"11111111", '1');
        send_query(x"11111111", '0');
        send_query(x"22222222", '1');
        send_query(x"11111111", '0');
        send_query(x"33333333", '1');
        send_query(x"11111111", '0');
        send_query(x"44444444", '1');
        send_query(x"11111111", '0');
        send_query(x"55555555", '1');
        send_query(x"11111111", '1');
    end procedure;

    -- Special test for timeouts:
    procedure test_timeout(ri, ro: real) is
    begin
        -- Set flow-control conditions:
        rate_in     <= ri;
        rate_out    <= ro;

        -- Send a duplicate query and confirm blocked.
        restart;
        send_query(x"87654321", '1');
        send_query(x"87654321", '0');

        -- Query at a 1/3, 2/3, and after timeout.
        wait for 70 us;
        send_query(x"87654321", '0');
        wait for 70 us;
        send_query(x"87654321", '0');
        wait for 70 us;
        send_query(x"87654321", '1');
    end procedure;
begin
    -- Repeat standard test sequence in different flow conditions:
    test_sequence(1.0, 1.0);
    test_sequence(1.0, 0.8);
    test_sequence(1.0, 0.3);
    test_sequence(0.8, 1.0);
    test_sequence(0.8, 0.8);
    test_sequence(0.8, 0.3);
    test_sequence(0.3, 1.0);
    test_sequence(0.3, 0.8);
    test_sequence(0.3, 0.3);
    test_timeout(1.0, 1.0);
    report "All tests completed!";
    wait;
end process;

end tb;
