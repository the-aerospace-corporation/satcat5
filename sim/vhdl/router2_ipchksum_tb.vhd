--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Unit test for the IPv4 header checksum adjustment block
--
-- This test generates a variety of IP packets with junk checksums, and
-- verifies that the outputs have correct checksums.  Tests cover a variety
-- of build configurations and flow-control conditions.
--
-- The complete test takes 2.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.router2_common.all;

entity router2_ipchksum_tb_single is
    generic (
    IO_BYTES    : positive;
    META_WIDTH  : natural;
    TEST_ITER   : positive);
end router2_ipchksum_tb_single;

architecture single of router2_ipchksum_tb_single is

-- Shortcuts for various types:
-- Note: Large LOAD_BYTES reduces downtime during test setup.
constant LOAD_BYTES : positive := 8;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype load_t is std_logic_vector(8*LOAD_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- FIFO for loading test data.
signal fifo_din     : load_t := (others => '0');
signal fifo_dref    : load_t := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal fifo_meta    : meta_t := (others => '0');
signal ref_data     : data_t;
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;
signal ref_meta     : meta_t;

-- Unit under test.
signal in_data      : data_t;
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_write     : std_logic;
signal in_meta      : meta_t;
signal out_data     : data_t;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_meta     : meta_t;
signal out_write    : std_logic;
signal out_match    : std_logic;
signal out_error    : std_logic;

-- High-level test control.
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal count_match  : natural := 0;
signal count_error  : natural := 0;

begin

-- Clock generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- FIFO for loading test data.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_din,
    in_meta         => fifo_meta,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => in_data,
    out_meta        => in_meta,
    out_nlast       => in_nlast,
    out_valid       => in_write,
    out_ready       => '1',
    out_rate        => test_rate,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_dref,
    in_meta         => fifo_meta,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => ref_data,
    out_meta        => ref_meta,
    out_nlast       => ref_nlast,
    out_valid       => ref_valid,
    out_ready       => out_write,
    reset_p         => reset_p);

-- Unit under test (adjustment mode).
uut1 : entity work.router2_ipchksum
    generic map (
    ADJ_MODE    => true,
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => META_WIDTH)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_meta     => in_meta,
    in_write    => in_write,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_meta    => out_meta,
    out_write   => out_write,
    clk         => clk,
    reset_p     => reset_p);

-- Unit under test (validation mode).
uut2 : entity work.router2_ipchksum
    generic map (
    ADJ_MODE    => false,
    IO_BYTES    => IO_BYTES)
    port map(
    in_data     => out_data,
    in_nlast    => out_nlast,
    in_write    => out_write,
    early_match => out_match,
    early_error => out_error,
    clk         => clk,
    reset_p     => reset_p);

-- Check the output stream against the reference.
p_check : process(clk)
begin
    if rising_edge(clk) then
        if (out_write = '1') then
            assert (ref_valid = '1')
                report "Unexpected output" severity error;
            assert (out_data = ref_data)
                report "DATA mismatch" severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch" severity error;
            assert (out_meta = ref_meta)
                report "META mismatch" severity error;
        end if;

        if (reset_p = '1') then
            count_match <= 0;
            count_error <= 0;
        else
            count_match <= count_match + u2i(out_match);
            count_error <= count_error + u2i(out_error);
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Global counter for packet IDENT field.
    variable ident : uint16 := (others => '0');

    -- For simplicity, all packets use the same placeholder addresses.
    constant DSTIP  : ip_addr_t := x"C0A80002";
    constant SRCIP  : ip_addr_t := x"C0A80001";
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

    -- Generate and load packets of various types.
    procedure gen_eth_pair(dlen: natural) is
        variable data : std_logic_vector(8*dlen-1 downto 0) := rand_bytes(dlen);
        variable pkt : eth_packet := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_ARP, data);
    begin
        -- For Ethernet packets, input and expected output are the same.
        fifo_meta <= rand_vec(META_WIDTH);
        load_pkt(pkt.all, pkt.all);
    end procedure;

    procedure gen_ipv4_pair(dlen : natural) is
        variable iphdr : ipv4_header := make_ipv4_header(DSTIP, SRCIP, ident, IPPROTO_UDP);
        variable ippkt : ip_packet := make_ipv4_pkt(iphdr, rand_bytes(dlen));
        variable eth0 : eth_packet := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_IPV4, ippkt.all);
        variable eth1 : eth_packet := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_IPV4, ippkt.all);
        constant bidx : natural := eth0'left - 8*IP_HDR_CHECKSUM;
    begin
        -- Randomize the checksum of the input packet before loading.
        eth0(bidx downto bidx-15) := rand_bytes(2);
        load_pkt(eth0.all, eth1.all);
        ident := ident + 1;
    end procedure;

    -- Wait for reference FIFO to be empty.
    procedure test_wait(rr: real) is
        variable timeout : integer := 2000;
    begin
        -- Start the test, then wait for the reference FIFO to empty.
        test_rate <= rr;
        while (timeout > 0 and ref_valid = '1') loop
            wait for 0.1 us;
            timeout := timeout - 1;
        end loop;
        assert (out_write = '0' and ref_valid = '0' and timeout > 0)
            report "Timeout waiting for output data." severity error;
        test_rate <= 0.0;
    end procedure;

    -- Run a series of tests with various packet types.
    procedure test_run(rr: real) is
    begin
        -- Reset test state.
        reset_p     <= '1';
        test_index  <= test_index + 1;
        test_rate   <= 0.0;
        wait for 100 ns;
        reset_p     <= '0';
        wait for 100 ns;
        -- Generate and load test packets...
        gen_eth_pair(46);
        gen_eth_pair(1500);
        test_wait(rr);
        gen_ipv4_pair(8);
        gen_ipv4_pair(1400);
        test_wait(rr);
        for n in 1 to 8 loop
            gen_eth_pair(rand_int(100));
            gen_ipv4_pair(rand_int(100));
        end loop;
        test_wait(rr);
        -- Confirm outputs from validation mode.
        wait for 1 us;
        assert (count_match = 10 and count_error = 0)
            report "Output mismatch in validation mode." severity error;
    end procedure;
begin
    for n in 1 to TEST_ITER loop
        test_run(1.0);
        test_run(0.5);
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity router2_ipchksum_tb is
    -- Testbench --> No I/O ports
end router2_ipchksum_tb;

architecture tb of router2_ipchksum_tb is

begin

-- Demonstrate operation at different pipeline widths.
uut0 : entity work.router2_ipchksum_tb_single
    generic map(IO_BYTES => 1, META_WIDTH => 1, TEST_ITER => 12);
uut1 : entity work.router2_ipchksum_tb_single
    generic map(IO_BYTES => 2, META_WIDTH => 2, TEST_ITER => 24);
uut2 : entity work.router2_ipchksum_tb_single
    generic map(IO_BYTES => 4, META_WIDTH => 4, TEST_ITER => 44);
uut3 : entity work.router2_ipchksum_tb_single
    generic map(IO_BYTES => 8, META_WIDTH => 8, TEST_ITER => 70);

end tb;
