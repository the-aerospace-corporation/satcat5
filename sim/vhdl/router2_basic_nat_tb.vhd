--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Unit test for the Basic Network Address Translation (NAT) block
--
-- This test generates a variety of IP, TCP, and UDP packets, passes them
-- through the unit under test, and confirms that the results exactly match
-- the expected stream.  The test is repeated under a variety of randomized
-- flow-control conditions.
--
-- The complete test takes 5.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router2_common.ip_addr_t;
use     work.router2_common.ip_prefix2mask;
use     work.router_sim_tools.all;

entity router2_basic_nat_tb_single is
    generic (
    IO_BYTES    : positive;
    TEST_ITER   : positive);
end router2_basic_nat_tb_single;

architecture single of router2_basic_nat_tb_single is

-- For simplicity, use a fixed address mapping.
constant ADDR_EXT   : ip_addr_t := x"C0A86400";    -- 192.168.100.*
constant ADDR_INT   : ip_addr_t := x"C0A80100";    -- 192.168.1.*
constant ADDR_PLEN  : natural := 24;
constant ADDR_MASK  : ip_addr_t := ip_prefix2mask(ADDR_PLEN);

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- FIFO for loading test data.
-- Note: Large LOAD_BYTES reduces downtime during test setup.
constant LOAD_BYTES : positive := 8;
signal fifo_din     : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_dref    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;
signal ref_ready    : std_logic;

-- Unit under test.
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';

-- High-level test control.
signal test_index   : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;

begin

-- Clock generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- FIFO for loading test data.
ref_ready <= out_valid and out_ready;

u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk,
    in_data         => fifo_din,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_rate        => test_rate_i,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk,
    in_data         => fifo_dref,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => ref_data,
    out_nlast       => ref_nlast,
    out_valid       => ref_valid,
    out_ready       => ref_ready,
    reset_p         => reset_p);

-- Unit under test.
-- Note: Not testing the ConfigBus interface.
uut : entity work.router2_basic_nat
    generic map(
    IO_BYTES    => IO_BYTES,
    MODE_IG     => true,
    ADDR_INT    => ADDR_INT,
    ADDR_EXT    => ADDR_EXT,
    ADDR_PLEN   => ADDR_PLEN)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Low-level test control.
p_check : process(clk)
begin
    if rising_edge(clk) then
        -- Check each output word against the reference.
        if (out_valid = '1' and out_ready = '1') then
            assert (ref_valid = '1')
                report "Unexpected output" severity error;
            assert (out_data = ref_data)
                report "DATA mismatch" severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch" severity error;
        end if;

        -- Flow-control randomization.
        out_ready <= rand_bit(test_rate_o);
    end if;
end process;

-- High-level test control.
p_test : process
    -- Global counter for packet IDENT field.
    variable ident : uint16 := (others => '0');

    -- For simplicity, all packets use the same placeholder MAC address.
    constant SRCMAC : mac_addr_t := x"DEADBEEFCAFE";

    -- Load a matched pair of packets into the input and reference FIFOs.
    procedure load_pkt(pkt_in, pkt_ref: std_logic_vector) is
        variable nbytes : natural := (pkt_in'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp1, tmp2 : byte_t := (others => '0');
    begin
        wait until rising_edge(clk);
        while (rdpos < nbytes) loop
            if (rdpos + LOAD_BYTES >= nbytes) then
                fifo_nlast  <= nbytes - rdpos;
                fifo_write  <= '1';     -- Last word in frame
            else
                fifo_nlast  <= 0;
                fifo_write  <= '1';     -- Normal write
            end if;
            for n in 0 to LOAD_BYTES-1 loop
                tmp1 := strm_byte_zpad(rdpos, pkt_in);
                tmp2 := strm_byte_zpad(rdpos, pkt_ref);
                fifo_din(8*LOAD_BYTES-8*n-1 downto 8*LOAD_BYTES-8*n-8)  <= tmp1;
                fifo_dref(8*LOAD_BYTES-8*n-1 downto 8*LOAD_BYTES-8*n-8) <= tmp2;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk);
        end loop;
        fifo_write <= '0';
        wait until rising_edge(clk);
    end procedure;

    -- Generate a packet with the given parameters and data.
    -- (Several flavors available for ARP, IPv4, etc.)
    function gen_arp_pkt(spa, tpa : ip_addr_t; vtag: vlan_hdr_t) return eth_packet is
    begin
        return make_arp_pkt(ARP_REQUEST, SRCMAC, spa, MAC_ADDR_BROADCAST, tpa, true, vtag);
    end function;

    impure function gen_ipv4_pkt(
        dst, src    : ip_addr_t;
        proto       : byte_t;
        vtag        : vlan_hdr_t;
        data        : std_logic_vector)
        return eth_packet
    is
        constant SRCPORT    : uint16 := x"1234";
        constant DSTPORT    : uint16 := x"5678";
        variable iphdr      : ipv4_header := make_ipv4_header(dst, src, ident, proto);
        variable pkt_tmp    : ip_packet;
    begin
        -- Form the contents of the IPv4 packet.
        -- (Use TCP or UDP, with UDP doubling as a stand-in for everything else.)
        if (proto = IPPROTO_TCP) then
            pkt_tmp := make_tcp_pkt(
                iphdr, SRCPORT, DSTPORT,
                resize(ident, 32),
                resize(ident, 32),
                ZPAD16, ident, data);
        else
            pkt_tmp := make_udp_pkt(SRCPORT, DSTPORT, data);
        end if;
        -- Add the IPv4 header.
        pkt_tmp := make_ipv4_pkt(iphdr, pkt_tmp.all);
        -- Add the Ethernet header and footer, with optional VLAN tag.
        if (vtag = VHDR_NONE) then
            return make_eth_fcs(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_IPV4, pkt_tmp.all);
        else
            return make_vlan_fcs(MAC_ADDR_BROADCAST, SRCMAC, vtag, ETYPE_IPV4, pkt_tmp.all);
        end if;
    end function;

    -- Check an address, and perform network translation if needed.
    function ref_nat(x : ip_addr_t) return ip_addr_t is
        variable y : ip_addr_t := x xor ADDR_EXT xor ADDR_INT;
    begin
        if ip_in_subnet(x, ADDR_INT, ADDR_MASK) then
            return y;   -- Translated
        else
            return x;   -- As-is
        end if;
    end function;

    -- Call "gen_xx_pkt" with pseudorandom parameters, then "load_pkt".
    -- Automatically handles address translation as needed.
    -- (Several flavors available for ARP, IPv4, etc.)
    procedure gen_arp_pair(spa, tpa : ip_addr_t; vtag: vlan_hdr_t) is
        variable spa2 : ip_addr_t := ref_nat(spa);
        variable tpa2 : ip_addr_t := ref_nat(tpa);
        variable pkt_in  : eth_packet := gen_arp_pkt(spa,  tpa,  vtag);
        variable pkt_out : eth_packet := gen_arp_pkt(spa2, tpa2, vtag);
    begin
        load_pkt(pkt_in.all, pkt_out.all);
    end procedure;

    procedure gen_ipv4_pair(
        dst, src    : ip_addr_t;
        proto       : byte_t;
        vtag        : vlan_hdr_t;
        dlen        : natural)
    is
        variable data : std_logic_vector(8*dlen-1 downto 0) := rand_bytes(dlen);
        variable dst2 : ip_addr_t := ref_nat(dst);
        variable src2 : ip_addr_t := ref_nat(src);
        variable pkt_in  : eth_packet := gen_ipv4_pkt(dst,  src,  proto, vtag, data);
        variable pkt_out : eth_packet := gen_ipv4_pkt(dst2, src2, proto, vtag, data);
    begin
        load_pkt(pkt_in.all, pkt_out.all);
        ident := ident + 1;
    end procedure;

    -- Set flow-control conditions and execute a series of tests.
    procedure test_run(ri, ro: real) is
        constant VHDR_SOME : vlan_hdr_t := x"AE20";
        variable timeout : integer := 2000;
    begin
        -- Reset test state.
        reset_p     <= '1';
        test_index  <= test_index + 1;
        test_rate_i <= 0.0;
        test_rate_o <= 0.0;
        wait for 100 ns;
        reset_p     <= '0';
        wait for 100 ns;
        -- Generate and load test packets...
        gen_arp_pair(x"DEADBEEF", x"DEADBEEF", VHDR_NONE);
        gen_arp_pair(x"DEADBEEF", x"C0A80101", VHDR_NONE);
        gen_arp_pair(x"C0A80102", x"DEADBEEF", VHDR_NONE);
        gen_arp_pair(x"C0A80102", x"C0A80101", VHDR_NONE);
        gen_arp_pair(x"DEADBEEF", x"DEADBEEF", VHDR_SOME);
        gen_arp_pair(x"DEADBEEF", x"C0A80101", VHDR_SOME);
        gen_arp_pair(x"C0A80102", x"DEADBEEF", VHDR_SOME);
        gen_arp_pair(x"C0A80102", x"C0A80101", VHDR_SOME);
        gen_ipv4_pair(x"DEADBEEF", x"DEADBEEF", IPPROTO_TCP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"C0A80101", IPPROTO_TCP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"DEADBEEF", IPPROTO_TCP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"C0A80101", IPPROTO_TCP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"DEADBEEF", IPPROTO_UDP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"C0A80101", IPPROTO_UDP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"DEADBEEF", IPPROTO_UDP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"C0A80101", IPPROTO_UDP, VHDR_NONE, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"DEADBEEF", IPPROTO_TCP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"C0A80101", IPPROTO_TCP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"DEADBEEF", IPPROTO_TCP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"C0A80101", IPPROTO_TCP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"DEADBEEF", IPPROTO_UDP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"DEADBEEF", x"C0A80101", IPPROTO_UDP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"DEADBEEF", IPPROTO_UDP, VHDR_SOME, rand_int(64));
        gen_ipv4_pair(x"C0A80102", x"C0A80101", IPPROTO_UDP, VHDR_SOME, rand_int(64));
        -- Execute the test, waiting for the reference FIFO to empty.
        test_rate_i <= ri;
        test_rate_o <= ro;
        while (timeout > 0 and ref_valid = '1') loop
            wait for 0.1 us;
            timeout := timeout - 1;
        end loop;
        assert (out_valid = '0' and ref_valid = '0' and timeout > 0)
            report "Timeout waiting for output data." severity error;
    end procedure;
begin
    for n in 1 to TEST_ITER loop
        test_run(1.0, 1.0);
        test_run(0.1, 0.9);
        test_run(0.9, 0.1);
        test_run(0.9, 0.9);
        if (n mod 10 = 0) then
            report "Completed run #" & integer'image(n);
        end if;
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity router2_basic_nat_tb is
    -- Testbench --> No I/O ports
end router2_basic_nat_tb;

architecture tb of router2_basic_nat_tb is

begin

-- Demonstrate operation at different pipeline widths.
uut0 : entity work.router2_basic_nat_tb_single
    generic map(IO_BYTES => 1, TEST_ITER => 12);
uut1 : entity work.router2_basic_nat_tb_single
    generic map(IO_BYTES => 2, TEST_ITER => 24);
uut2 : entity work.router2_basic_nat_tb_single
    generic map(IO_BYTES => 4, TEST_ITER => 44);
uut3 : entity work.router2_basic_nat_tb_single
    generic map(IO_BYTES => 8, TEST_ITER => 70);

end tb;
