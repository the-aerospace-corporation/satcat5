--------------------------------------------------------------------------
-- Copyright 2020-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the top-level IP router
--
-- This testbench simulates the end-to-end behavior of the inline IP router,
-- by instantiating a simulated endpoint on each side of the router interface.
-- These endpoints execute a series of ARP and IP exchanges to verify the
-- high-level proxy-ARP IP router functionality.  The test focuses on emergent
-- behavior and is not as throrough as individual lower-level tests.
--
-- Terminology used throughput this file:
--  * Client    = Endpoint attached to the local interface.
--                (i.e., The local subnet 192.168.0.*)
--  * Server    = Endpoint attached to the remote interface.
--  * Egress    = Client to router to server.
--  * Ingress   = Server to router to client.
--
-- The complete test takes about 1.4 milliseconds depending on PRNG.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity router_inline_top_tb is
    -- No I/O ports
end router_inline_top_tb;

architecture tb of router_inline_top_tb is

-- Arbitrary addresses for the router:
constant ROUTER_MACADDR : mac_addr_t := x"DEADBEEFCAFE";
constant CLIENT_MACADDR : mac_addr_t := x"CC0123456789";
constant SERVER_MACADDR : mac_addr_t := x"DD0123456789";

constant ROUTER_SUBNET  : ip_addr_t := x"C0A80000";
constant ROUTER_SUBMASK : ip_addr_t := x"FFFF0000";
constant ROUTER_IPADDR  : ip_addr_t := x"C0A80101";
constant CLIENT_IPADDR  : ip_addr_t := x"C0A80102";
constant SERVER_IPADDR  : ip_addr_t := x"AABBCCDD";

-- Set minimum delay before ICMP "Destination Host Unreachable"
constant PROXY_RETRY_DELAY : natural := 200;

-- System clock and reset.
signal clk_100          : std_logic := '0';
signal clk_102          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Local switch port.
signal lcl_rx_data      : port_rx_m2s;  -- Ingress data out
signal lcl_tx_data      : port_tx_s2m;  -- Egress data in
signal lcl_tx_ctrl      : port_tx_m2s;

-- Remote network port.
signal net_rx_data      : port_rx_m2s;  -- Ingress data in
signal net_tx_data      : port_tx_s2m;  -- Egress data out
signal net_tx_ctrl      : port_tx_m2s;
signal net_tx_ready     : std_logic := '0';

-- Data to the UUT from client and server.
signal server_clk       : std_logic;
signal server_data      : byte_t := (others => '0');
signal server_last      : std_logic := '0';
signal server_write     : std_logic := '0';
signal client_clk       : std_logic;
signal client_data      : byte_t := (others => '0');
signal client_last      : std_logic := '0';
signal client_valid     : std_logic := '0';
signal client_ready     : std_logic := '0';

-- Ingress stream verification (to local port)
signal tst_ig_data      : byte_t := (others => '0');
signal tst_ig_last      : std_logic := '0';
signal tst_ig_write     : std_logic := '0';
signal ref_ig_data      : byte_t;
signal ref_ig_last      : std_logic;
signal ref_ig_valid     : std_logic;
signal uut_ig_clk       : std_logic;
signal uut_ig_data      : byte_t;
signal uut_ig_last      : std_logic;
signal uut_ig_write     : std_logic;

-- Egress stream verification (to remote port)
signal tst_eg_data      : byte_t := (others => '0');
signal tst_eg_last      : std_logic := '0';
signal tst_eg_write     : std_logic := '0';
signal ref_eg_data      : byte_t;
signal ref_eg_last      : std_logic;
signal ref_eg_valid     : std_logic;
signal uut_eg_clk       : std_logic;
signal uut_eg_data      : byte_t;
signal uut_eg_last      : std_logic;
signal uut_eg_write     : std_logic;

-- High-level test control
signal test_idx_hi      : natural := 0;
signal test_idx_lo      : natural := 0;
signal test_rate_eg     : real := 0.0;
signal test_eg_error    : std_logic;
signal test_eg_reset    : std_logic;
signal test_ig_error    : std_logic;
signal test_ig_reset    : std_logic;

begin

-- Clock generation.
clk_100 <= not clk_100 after 5.0 ns;  -- 1 / (2*5.0ns) = 100 MHz
clk_102 <= not clk_102 after 4.9 ns;  -- 1 / (2*4.9ns) = 102 MHz

-- Breakout the port signals.
-- Note: Slight delay on selected clocks to avoid simulation artifacts.
lcl_tx_data.data    <= client_data;
lcl_tx_data.last    <= client_last;
lcl_tx_data.valid   <= client_valid;
client_clk          <= lcl_tx_ctrl.clk;
client_ready        <= lcl_tx_ctrl.ready;
test_eg_error       <= lcl_tx_ctrl.txerr;
test_eg_reset       <= lcl_tx_ctrl.reset_p;

uut_ig_clk          <= lcl_rx_data.clk;
uut_ig_data         <= lcl_rx_data.data;
uut_ig_last         <= lcl_rx_data.last;
uut_ig_write        <= lcl_rx_data.write;
test_ig_error       <= lcl_rx_data.rxerr;
test_ig_reset       <= lcl_rx_data.reset_p;

uut_eg_clk          <= clk_100;
uut_eg_data         <= net_tx_data.data;
uut_eg_last         <= net_tx_data.last;
uut_eg_write        <= net_tx_data.valid and net_tx_ready;
net_tx_ctrl.clk     <= clk_100;
net_tx_ctrl.ready   <= net_tx_ready;
net_tx_ctrl.txerr   <= '0';
net_tx_ctrl.reset_p <= reset_p;

server_clk          <= clk_102;
net_rx_data.clk     <= clk_102 after 1 ns;
net_rx_data.data    <= server_data;
net_rx_data.last    <= server_last;
net_rx_data.write   <= server_write;
net_rx_data.rxerr   <= '0';
net_rx_data.reset_p <= reset_p;

-- Unit under test
-- Note: Must manually specify egress MAC because PROXY_EN_INGRESS = false.
--       (The ingress MAC is automatically determined via ARP handshake.)
uut : entity work.router_inline_top
    generic map(
    ROUTER_MACADDR      => ROUTER_MACADDR,
    SUBNET_IS_LCL_PORT  => true,
    PROXY_EN_EGRESS     => true,
    PROXY_EN_INGRESS    => false,
    PROXY_RETRY_KBYTES  => 2,
    PROXY_RETRY_DELAY   => PROXY_RETRY_DELAY,
    PROXY_CACHE_SIZE    => 4,
    IPV4_BLOCK_MCAST    => true,
    IPV4_BLOCK_FRAGMENT => true,
    IPV4_DMAC_FILTER    => true,
    IPV4_DMAC_REPLACE   => true,
    IPV4_SMAC_REPLACE   => true,
    NOIP_BLOCK_ALL      => true,
    NOIP_BLOCK_ARP      => true,
    NOIP_BLOCK_BCAST    => true,
    LCL_FRAME_BYTES_MIN => 0,
    NET_FRAME_BYTES_MIN => 0)
    port map(
    lcl_rx_data         => lcl_rx_data,
    lcl_tx_data         => lcl_tx_data,
    lcl_tx_ctrl         => lcl_tx_ctrl,
    net_rx_data         => net_rx_data,
    net_tx_data         => net_tx_data,
    net_tx_ctrl         => net_tx_ctrl,
    ipv4_dmac_egress    => SERVER_MACADDR,
    router_ip_addr      => ROUTER_IPADDR,
    router_sub_addr     => ROUTER_SUBNET,
    router_sub_mask     => ROUTER_SUBMASK,
    router_time_msec    => (others => '0'));

-- Reference FIFO and cross-check for the ingress stream.
u_fifo_ig : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => 8,
    FIFO_DEPTH  => 4096)
    port map(
    in_data     => tst_ig_data,
    in_last     => tst_ig_last,
    in_write    => tst_ig_write,
    out_data    => ref_ig_data,
    out_last    => ref_ig_last,
    out_valid   => ref_ig_valid,
    out_ready   => uut_ig_write,
    clk         => uut_ig_clk,
    reset_p     => reset_p);

u_check_ig : process(uut_ig_clk)
begin
    if rising_edge(uut_ig_clk) then
        if (uut_ig_write = '1') then
            if (ref_ig_valid = '1') then
                assert (uut_ig_data = ref_ig_data
                    and uut_ig_last = ref_ig_last)
                    report "Ingress data mismatch." severity error;
            else
                report "Unexpected ingress data." severity error;
            end if;
        end if;

        assert (test_ig_error = '0')
            report "Unexpected ingress error." severity error;
    end if;
end process;

-- Reference FIFO and cross-check for the egress stream.
u_fifo_eg : entity work.fifo_large_sync
    generic map(
    FIFO_WIDTH  => 8,
    FIFO_DEPTH  => 4096)
    port map(
    in_data     => tst_eg_data,
    in_last     => tst_eg_last,
    in_write    => tst_eg_write,
    out_data    => ref_eg_data,
    out_last    => ref_eg_last,
    out_valid   => ref_eg_valid,
    out_ready   => uut_eg_write,
    clk         => uut_eg_clk,
    reset_p     => reset_p);

p_check_eg : process(uut_eg_clk)
begin
    if rising_edge(uut_eg_clk) then
        net_tx_ready <= rand_bit(test_rate_eg);

        if (uut_eg_write = '1') then
            if (ref_eg_valid = '1') then
                assert (uut_eg_data = ref_eg_data
                    and uut_eg_last = ref_eg_last)
                    report "Egress data mismatch." severity error;
            else
                report "Unexpected egress data." severity error;
            end if;
        end if;
    end if;
end process;

-- Sanity check on the egress error strobe.
p_check_err : process(client_clk)
begin
    if rising_edge(client_clk) then
        assert (test_eg_error = '0')
            report "Unexpected egress error." severity error;
    end if;
end process;

-- High-level test control
p_test : process
    -- Wrapper functions for various make_xx functions:
    function make_arp_request return eth_packet is
    begin
        -- ARP request from router to client.
        return make_arp_pkt(ARP_REQUEST,
            ROUTER_MACADDR, ROUTER_IPADDR,
            MAC_ADDR_BROADCAST, CLIENT_IPADDR);
    end function;

    function make_arp_reply return eth_packet is
    begin
        -- ARP reply from client to router.
        return make_arp_pkt(ARP_REPLY,
            CLIENT_MACADDR, CLIENT_IPADDR,
            ROUTER_MACADDR, ROUTER_IPADDR);
    end function;

    impure function client_to_router(
        ndat : natural := 64)
        return eth_packet
    is
        -- Generate a random outbound packet.
        variable pkt : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                SERVER_IPADDR,              -- Destination
                CLIENT_IPADDR,              -- Source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP),               -- Protcol = UDP
            rand_vec(8*ndat));              -- Random data
    begin
        -- Wrap it in an Ethernet frame on the local subnet.
        return make_eth_fcs(ROUTER_MACADDR, CLIENT_MACADDR, ETYPE_IPV4, pkt.all);
    end function;

    function router_to_server(
        eth : std_logic_vector) 
        return eth_packet
    is
        -- First, decrement the TTL field.
        variable pkt : eth_packet := decr_ipv4_ttl(eth);
        variable len : natural := pkt.all'length;
    begin
        -- Second, replace both MAC addresses and recalculate FCS.
        return make_eth_fcs(SERVER_MACADDR, ROUTER_MACADDR, ETYPE_IPV4,
            pkt.all(len-113 downto 32));
    end function;

    impure function server_to_router(
        ndat : natural := 64)
        return eth_packet
    is
        -- Generate a random inbound packet.
        variable pkt : ip_packet := make_ipv4_pkt(
            make_ipv4_header(
                CLIENT_IPADDR,              -- Destination
                SERVER_IPADDR,              -- Source
                unsigned(rand_vec(16)),     -- Identifier field
                IPPROTO_UDP),               -- Protcol = UDP
            rand_vec(8*ndat));              -- Random data
    begin
        -- Wrap it in an Ethernet frame on the remote subnet.
        return make_eth_fcs(ROUTER_MACADDR, SERVER_MACADDR, ETYPE_IPV4, pkt.all);
    end function;

    function router_to_client(
        eth : std_logic_vector) 
        return eth_packet
    is
        -- First, decrement the TTL field.
        variable pkt : eth_packet := decr_ipv4_ttl(eth);
        variable len : natural := pkt.all'length;
    begin
        -- Second, replace both MAC address fields and recalculate FCS.
        return make_eth_fcs(CLIENT_MACADDR, ROUTER_MACADDR, ETYPE_IPV4,
            pkt.all(len-113 downto 32));
    end function;

    -- Write data from server or client to the router.
    procedure server_send(x : std_logic_vector) is
        constant NBYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Send each byte in the packet...
        for n in NBYTES-1 downto 0 loop
            wait until rising_edge(server_clk);
            server_data     <= get_byte_s(x, n);
            server_last     <= bool2bit(n = 0);
            server_write    <= '1';
        end loop;
        wait until rising_edge(server_clk);
        server_data     <= (others => '0');
        server_last     <= '0';
        server_write    <= '0';
    end procedure;

    procedure client_send(x : std_logic_vector) is
        variable bidx : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Send each byte in the packet...
        wait until rising_edge(client_clk);
        while (bidx > 0) loop
            -- Consume the current byte?
            if (client_valid = '1' and client_ready = '1') then
                bidx := bidx - 1;
            end if;
            -- Update the data/last/valid signals.
            if (bidx > 0) then
                -- Emit next byte.
                client_data  <= get_byte_s(x, bidx-1);
                client_last  <= bool2bit(bidx = 1);
                client_valid <= '1';
            elsif (client_ready = '1') then
                -- Previous byte consumed.
                client_data  <= (others => '0');
                client_last  <= '0';
                client_valid <= '0';
            end if;
            if (bidx > 0) then
                wait until rising_edge(client_clk);
            end if;
        end loop;
    end procedure;

    -- Write reference data to the designated FIFO.
    procedure expect_server(x : std_logic_vector) is
        constant NBYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Send each byte in the packet...
        for n in NBYTES-1 downto 0 loop
            wait until rising_edge(uut_eg_clk);
            tst_eg_data     <= get_byte_s(x, n);
            tst_eg_last     <= bool2bit(n = 0);
            tst_eg_write    <= '1';
        end loop;
        wait until rising_edge(uut_eg_clk);
        tst_eg_data     <= (others => '0');
        tst_eg_last     <= '0';
        tst_eg_write    <= '0';
    end procedure;

    procedure expect_client(x : std_logic_vector) is
        constant NBYTES : integer := x'length / 8;
    begin
        -- Sanity check before we start.
        assert (check_vector(x)) report "Bad input" severity failure;
        -- Send each byte in the packet...
        for n in NBYTES-1 downto 0 loop
            wait until rising_edge(uut_ig_clk);
            tst_ig_data     <= get_byte_s(x, n);
            tst_ig_last     <= bool2bit(n = 0);
            tst_ig_write    <= '1';
        end loop;
        wait until rising_edge(uut_ig_clk);
        tst_ig_data     <= (others => '0');
        tst_ig_last     <= '0';
        tst_ig_write    <= '0';
    end procedure;

    -- Get ready to start the next test.
    procedure test_start is
    begin
        -- Print an announcement
        wait until rising_edge(clk_100);
        report "Starting test #" & integer'image(test_idx_hi)
            & "." & integer'image(test_idx_lo + 1);
        -- Reset test conditions:
        test_idx_lo <= test_idx_lo + 1;
        reset_p     <= '1';
        wait for 0.2 us;
        reset_p     <= '0';
        wait for 0.2 us;
        -- Wait for UUT to indicate reset finished.
        while (test_eg_reset = '1' or test_ig_reset = '1') loop
            wait until rising_edge(clk_100);
        end loop;
        -- Fixed delay for ARP-Cache init.
        for n in 1 to 1024 loop
            wait until rising_edge(clk_100);
        end loop;
    end procedure;

    -- Wait until all outputs have been idle for N consecutive clocks.
    procedure test_wait(dly : integer := 100) is
        variable ctr : integer := 0;
    begin
        while (ctr < dly) loop
            wait until rising_edge(clk_100);
            if (uut_ig_write = '1' or uut_eg_write = '1') then
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
        test_wait(2*PROXY_RETRY_DELAY);
        -- Did we consume all data from both reference FIFOs?
        assert (ref_ig_valid = '0')
            report "Missing ingress data." severity error;
        assert (ref_eg_valid = '0')
            report "Missing egress data." severity error;
    end procedure;

    -- Standard test sequence:
    procedure test_sequence(rg : real) is
        -- Pre-generate random packets of varying lengths.
        variable ARP_REQ    : eth_packet := make_arp_request;
        variable ARP_REP    : eth_packet := make_arp_reply;
        variable C2R_UDP1   : eth_packet := client_to_router(64);
        variable C2R_UDP2   : eth_packet := client_to_router(128);
        variable C2R_UDP3   : eth_packet := client_to_router(256);
        variable C2R_UDP4   : eth_packet := client_to_router(512);
        variable S2R_UDP1   : eth_packet := server_to_router(64);
        variable S2R_UDP2   : eth_packet := server_to_router(128);
        variable S2R_UDP3   : eth_packet := server_to_router(256);
        variable S2R_UDP4   : eth_packet := server_to_router(512);
    begin
        -- Set high/low test index.
        test_idx_hi     <= test_idx_hi + 1;
        test_idx_lo     <= 0;
        test_rate_eg    <= rg;

        -- Test #1: The router should always block ARP frames.
        test_start;
        server_send(ARP_REQ.all);
        server_send(ARP_REP.all);
        client_send(ARP_REQ.all);
        client_send(ARP_REP.all);
        test_finish;

        -- Test #2: Send a UDP frame from client to server.
        test_start;
        expect_server(router_to_server(C2R_UDP1.all).all);
        client_send(C2R_UDP1.all);
        test_finish;

        -- Test #3: Send a UDP frame from server to client.
        -- (For simplicity, pre-announce ARP cache info.)
        test_start;
        client_send(ARP_REP.all);   -- Pre-announce
        expect_client(router_to_client(S2R_UDP1.all).all);
        server_send(S2R_UDP1.all);
        test_finish;

        -- Test #4: Send a UDP frame from server to client.
        -- (More complex case with ARP request/reply and retry.)
        test_start;
        expect_client(ARP_REQ.all);
        expect_client(router_to_client(S2R_UDP2.all).all);
        server_send(S2R_UDP2.all);
        test_wait(100);
        client_send(ARP_REP.all);
        test_finish;

        -- Test #5: Send a longer series of packets back and forth.
        -- (Pre-announce to ensure in-order delivery of all packets.)
        test_start;
        client_send(ARP_REP.all);   -- Pre-announce
        expect_client(router_to_client(S2R_UDP1.all).all);
        expect_client(router_to_client(S2R_UDP2.all).all);
        expect_client(router_to_client(S2R_UDP3.all).all);
        expect_client(router_to_client(S2R_UDP4.all).all);
        expect_server(router_to_server(C2R_UDP1.all).all);
        expect_server(router_to_server(C2R_UDP2.all).all);
        expect_server(router_to_server(C2R_UDP3.all).all);
        expect_server(router_to_server(C2R_UDP4.all).all);
        server_send(S2R_UDP1.all);
        client_send(C2R_UDP1.all);
        server_send(S2R_UDP2.all);
        client_send(C2R_UDP2.all);
        server_send(S2R_UDP3.all);
        client_send(C2R_UDP3.all);
        server_send(S2R_UDP4.all);
        client_send(C2R_UDP4.all);
        test_finish;
    end procedure;
begin
    -- Repeat the test under different flow-control conditions.
    test_sequence(1.0);
    test_sequence(0.9);
    test_sequence(0.8);
    test_sequence(0.7);
    test_sequence(0.6);
    test_sequence(0.5);
    test_sequence(0.4);
    test_sequence(0.3);
    test_sequence(0.2);

    report "All tests completed.";
    wait;
end process;

end tb;
