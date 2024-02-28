--------------------------------------------------------------------------
-- Copyright 2020-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ARP-Update
--
-- This is a unit test for the ARP-Update block, which verifies that:
--  * Non-ARP traffic is completely ignored.
--  * ARP Requests trigger an update for Sender if inside subnet.
--  * ARP Replies trigger an update for Sender and Target if inside subnet.
--  * Valid update commands are sent under all flow-control conditions.
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_arp_update_tb is
    -- Testbench, no I/O ports
end router_arp_update_tb;

architecture tb of router_arp_update_tb is

-- Local subnet = 192.168.1.*
constant SUBNET_INNER   : boolean := true;
constant SUBNET_ADDR    : ip_addr_t := x"C0A80100";
constant SUBNET_MASK    : ip_addr_t := x"FFFFFF00";

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '0';

-- Network interface to unit under test
signal pkt_rx_data      : byte_t := (others => '0');
signal pkt_rx_last      : std_logic := '0';
signal pkt_rx_write     : std_logic := '0';

-- Update commands from unit under test
signal update_first     : std_logic;    -- First-byte strobe
signal update_addr      : byte_t;       -- IPv4 then MAC
signal update_valid     : std_logic;
signal update_ready     : std_logic := '0';

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

-- Receive update commands
signal rcvd_ctr         : bcount_t := (others => '0');
signal rcvd_rdy         : std_logic := '0';
signal rcvd_ip          : ip_addr_t := (others => '0');
signal rcvd_mac         : mac_addr_t := (others => '0');

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
uut : entity work.router_arp_update
    generic map(
    SUBNET_INNER    => SUBNET_INNER)
    port map(
    arp_rx_data     => arp_rx_data,
    arp_rx_first    => arp_rx_first,
    arp_rx_last     => arp_rx_last,
    arp_rx_write    => arp_rx_write,
    subnet_addr     => SUBNET_ADDR,
    subnet_mask     => SUBNET_MASK,
    update_first    => update_first,
    update_addr     => update_addr,
    update_valid    => update_valid,
    update_ready    => update_ready,
    clk             => clk_100,
    reset_p         => reset_p);

-- Receive update commands
p_update : process(clk_100)
    variable seed1  : positive := 1821507;
    variable seed2  : positive := 6157657;
    variable rand   : real := 0.0;
    variable sreg   : std_logic_vector(79 downto 0) := (others => '0');
    variable bcount : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Flow control randomization.
        uniform(seed1, seed2, rand);
        update_ready <= bool2bit(rand < rate_out);

        -- For each received byte...
        rcvd_rdy <= '0'; -- Set default
        if (update_valid = '1' and update_ready = '1') then
            -- Receive data into a big shift register...
            sreg := sreg(71 downto 0) & update_addr;
            -- Update received byte count.
            if (update_first = '1') then
                bcount := 1;
            else
                bcount := bcount + 1;
            end if;
            -- If that was the last byte, latch all the individual fields.
            if (bcount = 10) then
                rcvd_ctr <= rcvd_ctr + 1;
                rcvd_rdy <= '1';
                rcvd_ip  <= sreg(79 downto 48);
                rcvd_mac <= sreg(47 downto  0);
            elsif (bcount > 10) then
                report "Invalid update command" severity error;
            end if;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    variable seed1  : positive := 12345;
    variable seed2  : positive := 67890;
    variable rand   : real := 0.0;
    variable refct  : bcount_t := (others => '0');

    -- Reset unit under test.
    procedure restart is
    begin
        report "Starting test #" & integer'image(test_idx+1);
        test_idx <= test_idx + 1;
        reset_p  <= '1';
        wait for 1 us;
        reset_p  <= '0';
        wait for 1 us;
        refct := rcvd_ctr;
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

    -- Confirm update matches expected format.
    procedure check_next_update is
        variable timeout : integer := 1000;
    begin
        -- Wait for update or timeout countdown, whichever comes first...
        while (rcvd_rdy = '0' and timeout > 0) loop
            wait until rising_edge(clk_100);
            timeout := timeout - 1;
        end loop;
        -- If we got a reply, check the contents.
        if (timeout = 0) then
            report "Timeout waiting for reply." severity error;
        else
            assert (rcvd_ip = query_spa and rcvd_mac = query_sha)
                or (rcvd_ip = query_tpa and rcvd_mac = query_tha)
                report "Update IP/MAC mismatch" severity error;
        end if;
    end procedure;

    -- Send an ARP message and check response.
    procedure send_arp(ptype:pkt_type_t; subnet_spa, subnet_tpa:std_logic) is
    begin
        -- Wait for previous query to finish + margin.
        while (query_busy = '1') loop
            wait until rising_edge(clk_100);
        end loop;
        for n in 1 to 20 loop
            wait until rising_edge(clk_100);
        end loop;

        -- Randomize query parameters.
        wait until rising_edge(clk_100);
        query_start <= '1';
        query_type  <= ptype;
        query_sha   <= rand_vec(48);
        query_spa   <= rand_ip_sub(SUBNET_ADDR, SUBNET_MASK, subnet_spa);
        query_tha   <= rand_vec(48);
        query_tpa   <= rand_ip_sub(SUBNET_ADDR, SUBNET_MASK, subnet_tpa);
        wait until rising_edge(clk_100);
        query_start <= '0';

        -- Confirm reply for each valid IP in subnet.
        if (subnet_spa = '1') then
            check_next_update;
        end if;
        if (subnet_tpa = '1' and ptype = PKT_ARP_RESPONSE) then
            check_next_update;
        end if;
    end procedure;

    -- Confirm number of update commands received since last call to restart.
    procedure check_rcvd_count(ref:integer) is
        variable rcvd : integer := 0;
    begin
        wait for 1 us;
        rcvd := to_integer(rcvd_ctr - refct);
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

        -- Test #1: Simple Request
        restart;
        send_arp(PKT_ARP_REQUEST, '1', '1');
        check_rcvd_count(1);

        -- Test #2: Simple Response
        restart;
        send_arp(PKT_ARP_RESPONSE, '1', '1');
        check_rcvd_count(2);

        -- Test #3: A series of in-subnet and out-of-subnet Requests.
        restart;
        send_arp(PKT_ARP_REQUEST, '0', '0');
        send_arp(PKT_ARP_REQUEST, '1', '0');
        send_arp(PKT_ARP_REQUEST, '0', '1');
        check_rcvd_count(1);

        -- Test #4: A series of in-subnet and out-of-subnet Responses.
        restart;
        send_arp(PKT_ARP_RESPONSE, '0', '0');
        send_arp(PKT_ARP_RESPONSE, '1', '0');
        send_arp(PKT_ARP_RESPONSE, '0', '1');
        check_rcvd_count(2);

        -- Test #5: 50 junk packets interspersed with queries.
        restart;
        send_junk(20);
        send_arp(PKT_ARP_REQUEST, '1', '1');
        send_junk(10);
        send_arp(PKT_ARP_RESPONSE, '1', '1');
        send_junk(20);
        check_rcvd_count(3);
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
