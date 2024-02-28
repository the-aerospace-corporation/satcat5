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
-- The complete test takes less than 1.6 milliseconds.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_arp_cache_tb is
    -- Testbench, no I/O ports
end router_arp_cache_tb;

architecture tb of router_arp_cache_tb is

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '0';

-- Query/reply interface
signal query_addr       : byte_t := (others => '0');
signal query_first      : std_logic := '0';
signal query_valid      : std_logic := '0';
signal query_ready      : std_logic;
signal reply_first      : std_logic;
signal reply_match      : std_logic;
signal reply_addr       : byte_t;
signal reply_write      : std_logic;

-- Table update interface.
signal request_addr     : byte_t;
signal request_first    : std_logic;
signal request_write    : std_logic;
signal update_addr      : byte_t := (others => '0');
signal update_first     : std_logic := '0';
signal update_valid     : std_logic := '0';
signal update_ready     : std_logic;

-- Shift-registers for sending and receiving data.
signal send_query_ip    : ip_addr_t := (others => '0');
signal send_update_ip   : ip_addr_t := (others => '0');
signal send_update_mac  : mac_addr_t := (others => '0');
signal rcvd_reply_ok    : std_logic := '0';
signal rcvd_reply_match : std_logic := '0';
signal rcvd_reply_mac   : mac_addr_t := (others => '0');
signal rcvd_request_ok  : std_logic := '0';
signal rcvd_request_ip  : ip_addr_t := (others => '0');

-- High-level test control.
signal test_index       : integer := 0;
signal test_rate        : real := 0.0;
signal query_start      : std_logic := '0';
signal query_busy       : std_logic := '0';
signal update_start     : std_logic := '0';
signal update_busy      : std_logic := '0';

begin

-- Clock generator
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Unit under test
uut : entity work.router_arp_cache
    generic map(TABLE_SIZE => 4)
    port map(
    query_first     => query_first,
    query_addr      => query_addr,
    query_valid     => query_valid,
    query_ready     => query_ready,
    reply_first     => reply_first,
    reply_match     => reply_match,
    reply_addr      => reply_addr,
    reply_write     => reply_write,
    request_first   => request_first,
    request_addr    => request_addr,
    request_write   => request_write,
    update_first    => update_first,
    update_addr     => update_addr,
    update_valid    => update_valid,
    update_ready    => update_ready,
    clk             => clk_100,
    reset_p         => reset_p);

-- Logic for serializing sent addresses.
p_send : process(clk_100)
    -- Flow control randomization.
    variable seed1 : positive := 12345;
    variable seed2 : positive := 67890;
    variable rand  : real := 0.0;
    impure function send_next_byte(valid, ready:std_logic) return boolean is
    begin
        uniform(seed1, seed2, rand);
        if (valid = '1' and ready = '0') then
            return false;   -- Keep current byte
        elsif (rand < test_rate) then
            return true;    -- Generate new byte
        else
            return false;   -- Idle
        end if;
    end function;

    variable query_bidx  : integer := 0;
    variable update_bidx : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Query = IP only (4 bytes)
        if (reset_p = '1') then
            query_bidx := 0;
        elsif (query_start = '1') then
            query_bidx := 4;
        elsif (query_valid = '1' and query_ready = '1' and query_bidx > 0) then
            query_bidx := query_bidx - 1;
        end if;

        query_busy <= bool2bit(query_bidx > 0);
        if (send_next_byte(query_valid, query_ready)) then
            query_valid <= bool2bit(query_bidx > 0);
            query_first <= bool2bit(query_bidx = 4);
            query_addr  <= get_byte_s(send_query_ip, query_bidx-1);
        elsif (query_ready = '1') then
            query_valid <= '0'; -- Previous byte consumed
        end if;

        -- Update = IP + MAC (10 bytes total)
        if (reset_p = '1') then
            update_bidx := 0;
        elsif (update_start = '1') then
            update_bidx := 10;
        elsif (update_valid = '1' and update_ready = '1' and update_bidx > 0) then
            update_bidx := update_bidx - 1;
        end if;

        update_busy <= bool2bit(update_bidx > 0);
        if (send_next_byte(update_valid, update_ready)) then
            update_valid <= bool2bit(update_bidx > 0);
            update_first <= bool2bit(update_bidx = 10);
            if (update_bidx >= 7) then
                update_addr <= get_byte_s(send_update_ip, update_bidx-7);
            else
                update_addr <= get_byte_s(send_update_mac, update_bidx-1);
            end if;
        elsif (update_ready = '1') then
            update_valid <= '0'; -- Previous byte consumed
        end if;
    end if;
end process;

-- Shift-registers for received addresses.
p_recv : process(clk_100)
    variable send_query_rem     : integer := 0;
    variable send_update_rem    : integer := 0;
    variable rcvd_reply_rem     : integer := 0;
    variable rcvd_request_rem   : integer := 0;
begin
    if rising_edge(clk_100) then
        -- Update remaining-bytes counter state and latch the "match" flag.
        if (query_start = '1') then
            rcvd_reply_ok    <= '0';
            rcvd_reply_match <= '0';
            rcvd_reply_rem   := 0;
        elsif (reply_first = '1') then
            rcvd_reply_ok    <= '0';
            rcvd_reply_match <= reply_match;
            rcvd_reply_rem   := 6;
        end if;

        if (query_start = '1') then
            rcvd_request_ok  <= '0';
            rcvd_request_rem := 0;
        elsif (request_first = '1') then
            rcvd_request_ok  <= '0';
            rcvd_request_rem := 4;
        end if;

        -- Accept bytes into each receive shift register, MSB-first.
        if (reply_write = '1' and rcvd_reply_rem > 0) then
            rcvd_reply_ok   <= bool2bit(rcvd_reply_rem = 1); -- Last byte?
            rcvd_reply_mac  <= rcvd_reply_mac(39 downto 0) & reply_addr;
            rcvd_reply_rem  := rcvd_reply_rem - 1;
        end if;

        if (request_write = '1' and rcvd_request_rem > 0) then
            rcvd_request_ok  <= bool2bit(rcvd_request_rem = 1); -- Last byte?
            rcvd_request_ip  <= rcvd_request_ip(23 downto 0) & request_addr;
            rcvd_request_rem := rcvd_request_rem - 1;
        end if;
    end if;
end process;

-- High-level test control
p_test : process
    constant MAC_NO_MATCH   : mac_addr_t := (others => '0');

    -- Issue reset, and optionally wait for update_ready flag.
    procedure restart(wait_ready : boolean := true) is
    begin
        wait until rising_edge(clk_100);
        report "Starting test #" & integer'image(test_index + 1);
        reset_p     <= '1';
        test_index  <= test_index + 1;
        wait until rising_edge(clk_100);
        reset_p     <= '0';
        if wait_ready then
            wait until rising_edge(update_ready);
        end if;
    end procedure;

    -- Wait until all updates are complete.
    procedure wait_update is
    begin
        wait until rising_edge(clk_100);
        while (update_start = '1' or update_busy = '1' or update_ready = '0') loop
            wait until rising_edge(clk_100);
        end loop;
    end procedure;

    -- Update cached IP/MAC address pair.
    procedure update(
        constant ip     : ip_addr_t;
        constant mac    : mac_addr_t) is
    begin
        -- Wait until we've finished sending the previous update.
        wait_update;
        -- Initiate the update command.
        update_start    <= '1';
        send_update_ip  <= ip;
        send_update_mac <= mac;
        wait until rising_edge(clk_100);
        update_start    <= '0';
    end procedure;

    -- Search for IP address, confirm we get the expected MAC.
    -- (Or specify MAC_NO_MATCH if no match is expected.)
    procedure query(
        constant ip     : ip_addr_t;
        constant ref    : mac_addr_t;
        constant uwait  : boolean := false) is
    begin
        -- If flag is set, wait for all pending updates to finish.
        if (uwait) then
            wait_update;
        end if;
        -- Initiate the query command.
        wait until rising_edge(clk_100);
        query_start     <= '1';
        send_query_ip   <= ip;
        wait until rising_edge(clk_100);
        query_start     <= '0';
        -- Wait for reply, then check contents.
        wait until rising_edge(rcvd_reply_ok);
        -- Check the returned MAC address.
        if (ref = MAC_NO_MATCH) then
            if (rcvd_reply_match = '1') then
                report "Reply: Unexpected MAC match." severity error;
            elsif (rcvd_reply_mac /= MAC_ADDR_BROADCAST) then
                report "Reply: Incorrect no-match MAC." severity error;
            end if;
        else
            if (rcvd_reply_match = '0') then
                report "Reply: Missing MAC match." severity error;
            elsif (rcvd_reply_mac /= ref) then
                report "Reply: Wrong MAC address." severity error;
            end if;
        end if;
        -- Check the forwarded request, if any.
        if (ref = MAC_NO_MATCH) then
            if (rcvd_request_ok = '0') then
                report "Request: Missing ARP request." severity error;
            elsif (rcvd_request_ip /= ip) then
                report "Request: Incorrect IP." severity error;
            end if;
        elsif (rcvd_request_ok = '1') then
            report "Unexpected ARP request." severity error;
        end if;
    end procedure;

    -- Predefine random MAC/IP pairs.
    -- (First byte is easy to read, rest are random data.
    constant IP_ADDR_0  : ip_addr_t := x"00C6123C";
    constant IP_ADDR_1  : ip_addr_t := x"110A17CE";
    constant IP_ADDR_2  : ip_addr_t := x"2214679D";
    constant IP_ADDR_3  : ip_addr_t := x"33457604";
    constant IP_ADDR_4  : ip_addr_t := x"444DED14";
    constant IP_ADDR_5  : ip_addr_t := x"557BA8E7";
    constant IP_ADDR_6  : ip_addr_t := x"557BA8E8";
    constant MAC_ADDR_0 : mac_addr_t := x"6612C5397483";
    constant MAC_ADDR_1 : mac_addr_t := x"77FFE314855B";
    constant MAC_ADDR_2 : mac_addr_t := x"88594920D610";
    constant MAC_ADDR_3 : mac_addr_t := x"99B247FAD0CF";
    constant MAC_ADDR_4 : mac_addr_t := x"AA70E5171F9F";
    constant MAC_ADDR_5 : mac_addr_t := x"BB7FC00719FC";
    constant MAC_ADDR_6 : mac_addr_t := x"BB7FC00719FD";
begin
    -- Repeat the entire sequence at different flow rates:
    for r in 20 downto 1 loop
        -- Set rate for this iteration:
        test_rate <= 0.05 * real(r);

        -- Test 1: Empty table should return no-match, even before init complete.
        restart(false);
        query(IP_ADDR_0, MAC_NO_MATCH);
        query(IP_ADDR_1, MAC_NO_MATCH);
        wait_update;
        query(IP_ADDR_0, MAC_NO_MATCH);
        query(IP_ADDR_1, MAC_NO_MATCH);

        -- Test 2: Table with a single entry.
        restart;
        update(IP_ADDR_0, MAC_ADDR_0);
        query(IP_ADDR_0, MAC_ADDR_0, true);
        query(IP_ADDR_1, MAC_NO_MATCH);

        -- Test 3: Full table (4 entries).
        restart;
        update(IP_ADDR_0, MAC_ADDR_0);
        update(IP_ADDR_1, MAC_ADDR_1);
        update(IP_ADDR_2, MAC_ADDR_2);
        update(IP_ADDR_3, MAC_ADDR_3);
        query(IP_ADDR_0, MAC_ADDR_0, true);
        query(IP_ADDR_1, MAC_ADDR_1);
        query(IP_ADDR_2, MAC_ADDR_2);
        query(IP_ADDR_3, MAC_ADDR_3);
        query(IP_ADDR_4, MAC_NO_MATCH);

        -- Test 4: Overflow handling (5 entries)
        restart;
        update(IP_ADDR_0, MAC_ADDR_0);
        update(IP_ADDR_1, MAC_ADDR_1);
        update(IP_ADDR_2, MAC_ADDR_2);
        update(IP_ADDR_3, MAC_ADDR_3);
        update(IP_ADDR_4, MAC_ADDR_4);
        query(IP_ADDR_0, MAC_NO_MATCH, true);
        query(IP_ADDR_1, MAC_ADDR_1);
        query(IP_ADDR_2, MAC_ADDR_2);
        query(IP_ADDR_3, MAC_ADDR_3);
        query(IP_ADDR_4, MAC_ADDR_4);
        query(IP_ADDR_2, MAC_ADDR_2);
        query(IP_ADDR_3, MAC_ADDR_3);
        query(IP_ADDR_0, MAC_NO_MATCH);
        query(IP_ADDR_4, MAC_ADDR_4);
        query(IP_ADDR_1, MAC_ADDR_1);
        query(IP_ADDR_4, MAC_ADDR_4);
        query(IP_ADDR_3, MAC_ADDR_3);
        query(IP_ADDR_2, MAC_ADDR_2);
        query(IP_ADDR_1, MAC_ADDR_1);
        query(IP_ADDR_0, MAC_NO_MATCH);

        -- Test 5: Interleaved update/query
        restart;
        update(IP_ADDR_0, MAC_ADDR_0);
        query(IP_ADDR_0, MAC_ADDR_0, true);
        query(IP_ADDR_1, MAC_NO_MATCH);
        update(IP_ADDR_1, MAC_ADDR_1);
        query(IP_ADDR_0, MAC_ADDR_0);
        query(IP_ADDR_1, MAC_ADDR_1, true);

        -- Test 6: Two very similar IP addresses.
        restart;
        update(IP_ADDR_5, MAC_ADDR_5);
        update(IP_ADDR_6, MAC_ADDR_6);
        wait_update;
        query(IP_ADDR_5, MAC_ADDR_5);
        query(IP_ADDR_6, MAC_ADDR_6);
        query(IP_ADDR_5, MAC_ADDR_5);
    end loop;

    -- Done.
    report "All tests completed.";
    wait;
end process;

end tb;
