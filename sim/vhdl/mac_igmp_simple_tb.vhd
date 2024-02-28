--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the simplified IGMP-snooping block
--
-- This testbench streams a mixture of regular, IGMP, and IP-multicast
-- traffic through the "mac_igmp_simple" block, and confirms that the
-- destination-mask for each frame matches expectations.
--
-- The complete test takes less than 0.5 milliseconds @ IO_BYTES = 8.
-- The complete test takes less than 3.4 milliseconds @ IO_BYTES = 1.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity mac_igmp_simple_tb_single is
    generic (
    IO_BYTES : positive := 8);   -- Set pipeline width
    -- Testbench has no top-level I/O.
end mac_igmp_simple_tb_single;

architecture single of mac_igmp_simple_tb_single is

-- Some test parameters are fixed:
constant PORT_COUNT     : positive := 4;    -- Number of test ports
constant IGMP_TIMEOUT   : positive := 3;    -- Timeout for stale IGMP
subtype port_index is integer range 0 to PORT_COUNT-1;
subtype port_mask is std_logic_vector(PORT_COUNT-1 downto 0);
type port_state is array(PORT_COUNT-1 downto 0) of natural;

-- Clock and reset.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input and output streams.
signal in_psrc      : port_index := 0;
signal in_wcount    : mac_bcount_t := 0;
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal in_last      : std_logic := '0';
signal in_write     : std_logic := '0';
signal in_busy      : std_logic := '0';
signal out_count    : natural := 0;
signal out_pdst     : port_mask;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_error    : std_logic;

-- FIFO for reference stream
signal ref_pdst     : port_mask;
signal ref_valid    : std_logic;

-- Test control
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal test_sof     : std_logic := '0';
signal test_mcast   : port_mask := (others => '0');
signal test_psrc    : port_index := 0;
signal test_pdst    : port_mask := (others => '0');
signal test_state   : port_state := (others => 0);
signal test_scrub   : std_logic := '0';
shared variable test_frame : eth_packet := null;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5.0 ns;    -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Input stream generation:
p_in : process(clk_100)
    variable temp   : byte_t := (others => '0');
    variable btmp   : natural := 0;
    variable bcount : natural := 0;
    variable blen   : natural := 0;
begin
    if rising_edge(clk_100) then
        -- Start of frame?
        if (test_sof = '1') then
            assert (bcount >= blen)
                report "Packet generator still busy!" severity error;
            in_psrc <= test_psrc;
            bcount  := 0;
            blen    := test_frame.all'length / 8;
        end if;

        -- Flow control and output-data randomization
        if (bcount < blen and rand_bit(test_rate) = '1') then
            -- Drive the "last" and "write" strobes.
            in_last  <= bool2bit(bcount + IO_BYTES >= blen);
            in_write <= '1';
            -- Word-counter for packet parsing.
            in_wcount <= int_min(bcount / IO_BYTES, IP_HDR_MAX);
            -- Relay each byte.
            for b in IO_BYTES-1 downto 0 loop
                if (bcount < blen) then
                    btmp := 8 * (blen - bcount);
                    temp := test_frame.all(btmp-1 downto btmp-8);
                else
                    temp := (others => '0');
                end if;
                in_data(8*b+7 downto 8*b) <= temp;
                bcount := bcount + 1;
            end loop;
        else
            -- No new data this clock.
            in_data  <= (others => '0');
            in_last  <= '0';
            in_write <= '0';
        end if;
        in_busy <= bool2bit(bcount < blen);
    end if;
end process;

-- FIFO for reference data (one "high" or "low" flag per frame).
out_ready <= ref_valid and out_valid;

u_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => PORT_COUNT)
    port map(
    in_data     => test_pdst,
    in_write    => test_sof,
    out_data    => ref_pdst,
    out_valid   => ref_valid,
    out_read    => out_ready,
    clk         => clk_100,
    reset_p     => reset_p);

-- Unit under test
uut : entity work.mac_igmp_simple
    generic map(
    IO_BYTES        => IO_BYTES,
    PORT_COUNT      => PORT_COUNT,
    IGMP_TIMEOUT    => IGMP_TIMEOUT)
    port map(
    in_psrc         => in_psrc,
    in_wcount       => in_wcount,
    in_data         => in_data,
    in_last         => in_last,
    in_write        => in_write,
    out_pdst        => out_pdst,
    out_valid       => out_valid,
    out_ready       => out_ready,
    out_error       => out_error,
    scrub_req       => test_scrub,
    clk             => clk_100,
    reset_p         => reset_p);

-- Check output against reference.
p_out : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_valid = '1' and ref_valid = '1') then
            assert (out_pdst = ref_pdst)
                report "Output mismatch @" & integer'image(out_count) severity error;
            out_count <= out_count + 1;
        else
            assert (out_valid = '0')
                report "Unexpected output." severity error;
        end if;
    end if;
end process;

-- Reference mask for IGMP-aware ports.
p_mask : process(test_state)
begin
    for n in test_mcast'range loop
        test_mcast(n) <= bool2bit(test_state(n) > 0);
    end loop;
end process;

-- High-level test control.
p_test : process
    -- Generate a random L3-multicast MAC address.
    impure function rand_mcast return mac_addr_t is
        constant addr : mac_addr_t := x"01005E" & rand_vec(24);
    begin
        return addr;
    end function;

    -- Generate a random Ethernet frame.
    impure function test_pkt_eth(dst : mac_addr_t) return eth_packet is
        -- Randomize frame length from 1-128 payload bytes.
        constant len : positive := 1 + rand_int(128);
        constant src : mac_addr_t := rand_vec(48);
    begin
        return make_eth_pkt(dst, src, ETYPE_NOIP, rand_vec(8*len));
    end function;

    -- Create a valid IGMP frame (IP).
    impure function test_pkt_igmp_inner return ip_packet is
        constant PROTO_IGMP : byte_t := x"02";
        constant OP_IGMPV1  : byte_t := x"12";
        constant dst : ip_addr_t := rand_ip_any;
        constant src : ip_addr_t := rand_ip_any;
        constant idn : bcount_t := unsigned(rand_vec(16));
        constant hdr : ipv4_header :=
            make_ipv4_header(dst, src, idn, PROTO_IGMP);
    begin
        return make_ipv4_pkt(hdr, OP_IGMPV1 & rand_vec(56));
    end function;

    -- Create a valid IGMP frame (Eth)
    impure function test_pkt_igmp(dst : mac_addr_t) return eth_packet is
        constant src : mac_addr_t := rand_vec(48);
        constant typ : mac_type_t := rand_vec(16);
        variable pkt : ip_packet := test_pkt_igmp_inner;
    begin
        return make_eth_pkt(dst, src, ETYPE_IPV4, pkt.all);
    end function;

    -- Trigger a counter-decrement event.
    procedure test_decr(decr : positive := 1) is
    begin
        -- Decrement the test state.
        for n in test_state'range loop
            if (test_state(n) > decr) then
                test_state(n) <= test_state(n) - decr;
            else
                test_state(n) <= 0;
            end if;
        end loop;
        -- Assert "scrub" line for N clock cycles.
        wait until rising_edge(clk_100);
        test_scrub <= '1';
        for n in 1 to decr loop
            wait until rising_edge(clk_100);
        end loop;
        test_scrub <= '0';
    end procedure;

    -- Reset UUT before each test.
    procedure test_start(rate : real) is
    begin
        -- Increment test index and set flow-control conditions.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        test_rate   <= rate;
        test_state  <= (others => 0);
        -- Reset UUT internal state.
        test_decr(IGMP_TIMEOUT + 1);
    end procedure;

    -- Define the various types of test frames:
    type test_frame_t is (
        PKT_NORMAL, -- Normal unicast frame
        PKT_BCAST,  -- Broadcast frame
        PKT_MCAST,  -- Layer-3 multicast frame
        PKT_IGMP);  -- IGMP membership report

    -- Send an Ethernet frame from the designated port.
    procedure test_send(psrc:port_index; typ:test_frame_t) is
    begin
        -- Assert start-of-frame-strobe.
        wait until rising_edge(clk_100);
        test_sof    <= '1';
        test_psrc   <= psrc;
        -- Generate the frame data and expected destination mask.
        case typ is
            when PKT_NORMAL =>
                test_frame  := test_pkt_eth(rand_vec(48));
                test_pdst   <= (others => '1');
            when PKT_BCAST =>
                test_frame  := test_pkt_eth(MAC_ADDR_BROADCAST);
                test_pdst   <= (others => '1');
            when PKT_MCAST =>
                test_frame  := test_pkt_eth(rand_mcast);
                test_pdst   <= test_mcast;
            when PKT_IGMP =>
                test_frame  := test_pkt_igmp(MAC_ADDR_BROADCAST);
                test_pdst   <= (others => '1');
                test_state(psrc) <= IGMP_TIMEOUT;
        end case;
        -- Wait for packet to finish sending.
        wait until rising_edge(clk_100);
        test_sof <= '0';
        wait until rising_edge(clk_100);
        while (in_busy = '1') loop
            wait until rising_edge(clk_100);
        end loop;
    end procedure;

    -- Send a few of each non-IGMP frame from each port.
    procedure test_send_seq(npkt : positive) is
    begin
        for n in 1 to npkt loop
            for p in 0 to PORT_COUNT-1 loop
                test_send(p, PKT_NORMAL);
                test_send(p, PKT_BCAST);
                test_send(p, PKT_MCAST);
            end loop;
        end loop;
    end procedure;
begin
    wait for 2 us;

    -- Repeat the sequence at different rates.
    for r in 1 to 10 loop
        -- Test #1: No IGMP-aware ports.
        test_start(0.1 * real(r));
        test_send_seq(5);

        -- Test #2: One IGMP-aware port.
        test_start(0.1 * real(r));
        test_send(0, PKT_IGMP);
        for n in 1 to IGMP_TIMEOUT loop
            test_decr(1);
            test_send_seq(1);
        end loop;

        -- Test #3: Staggered IGMP-aware ports.
        test_start(0.1 * real(r));
        test_send(1, PKT_IGMP);
        test_send_seq(1);
        test_decr(1);
        test_send(2, PKT_IGMP);
        for n in 1 to IGMP_TIMEOUT loop
            test_decr(1);
            test_send_seq(1);
        end loop;
    end loop;

    report "All tests completed, B = " & integer'image(IO_BYTES);
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity mac_igmp_simple_tb is
    -- Testbench has no top-level I/O.
end mac_igmp_simple_tb;

architecture tb of mac_igmp_simple_tb is
begin
    uut1 : entity work.mac_igmp_simple_tb_single
        generic map(IO_BYTES => 1);
    uut8 : entity work.mac_igmp_simple_tb_single
        generic map(IO_BYTES => 8);
end tb;
