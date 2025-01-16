--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PTP "ingress" block (Initial packet processing)
--
-- This unit test generates a variety of randomized traffic (regular, PTP-L2,
-- and PTP-L3) and confirms that the unit under test correctly identifies
-- the packet type and any attached TLVs.  The test is run in parallel with
-- various build-time parameters that span the expected range.
--
-- The complete test takes 8 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity ptp_ingress_tb_single is
    generic (
    IO_BYTES    : positive;
    TEST_ITER   : positive);
end ptp_ingress_tb_single;

architecture single of ptp_ingress_tb_single is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Test data FIFO (streaming data)
signal fifo_data    : data_t := (others => '0');
signal fifo_nlast   : integer range 0 to IO_BYTES := 0;
signal fifo_wr      : std_logic := '0';

-- Unit under test.
signal in_data      : data_t;
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_write     : std_logic;
signal out_pmsg     : tlvpos_t;
signal out_tlv0     : tlvpos_t;
signal out_tlv1     : tlvpos_t;
signal out_tlv2     : tlvpos_t;
signal out_tlv3     : tlvpos_t;
signal out_tlv4     : tlvpos_t;
signal out_tlv5     : tlvpos_t;
signal out_tlv6     : tlvpos_t;
signal out_tlv7     : tlvpos_t;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_rcvd     : std_logic := '0';

-- Reference signals
signal ref_pmsg     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv0     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv1     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv2     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv3     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv4     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv5     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv6     : tlvpos_t := TLVPOS_NONE;
signal ref_tlv7     : tlvpos_t := TLVPOS_NONE;

-- High-level test control
signal test_index   : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;

begin

-- Clock and reset generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- Test data FIFO (streaming data)
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk,
    in_data         => fifo_data,
    in_nlast        => fifo_nlast,
    in_write        => fifo_wr,
    out_clk         => clk,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_valid       => in_write,
    out_ready       => '1',
    out_rate        => test_rate_i,
    reset_p         => reset_p);

-- Unit under test.
uut : entity work.ptp_ingress
    generic map(
    IO_BYTES    => IO_BYTES,
    TLV_ID0     => x"0100",
    TLV_ID1     => x"0101",
    TLV_ID2     => x"0102",
    TLV_ID3     => x"0103",
    TLV_ID4     => x"0104",
    TLV_ID5     => x"0105",
    TLV_ID6     => x"0106",
    TLV_ID7     => x"0107")
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_pmsg    => out_pmsg,
    out_tlv0    => out_tlv0,
    out_tlv1    => out_tlv1,
    out_tlv2    => out_tlv2,
    out_tlv3    => out_tlv3,
    out_tlv4    => out_tlv4,
    out_tlv5    => out_tlv5,
    out_tlv6    => out_tlv6,
    out_tlv7    => out_tlv7,
    out_valid   => out_valid,
    out_ready   => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- Low-level test control.
p_check : process(clk)
begin
    if rising_edge(clk) then
        -- Check each output word against the reference.
        if (reset_p = '1' or fifo_wr = '1') then
            out_rcvd <= '0';    -- Clear at start of test.
        elsif (out_valid = '1' and out_ready = '1') then
            assert(out_pmsg = ref_pmsg) report "PMSG mismatch" severity error;
            assert(out_tlv0 = ref_tlv0) report "TLV0 mismatch" severity error;
            assert(out_tlv1 = ref_tlv1) report "TLV1 mismatch" severity error;
            assert(out_tlv2 = ref_tlv2) report "TLV2 mismatch" severity error;
            assert(out_tlv3 = ref_tlv3) report "TLV3 mismatch" severity error;
            assert(out_tlv4 = ref_tlv4) report "TLV4 mismatch" severity error;
            assert(out_tlv5 = ref_tlv5) report "TLV5 mismatch" severity error;
            assert(out_tlv6 = ref_tlv6) report "TLV6 mismatch" severity error;
            assert(out_tlv7 = ref_tlv7) report "TLV7 mismatch" severity error;
            out_rcvd <= '1';    -- Packet metadata received
        end if;

        -- Flow-control randomization.
        out_ready <= rand_bit(test_rate_o);
    end if;
end process;

-- High-level test control.
p_test : process
    -- PTP packet length, including placeholder for undefined types.
    function ptp_msg_len2(msg_type: nybb_t) return positive is
        variable tmp : natural := ptp_msg_len(msg_type);
    begin
        if (tmp = 0) then tmp := 42; end if;
        return tmp;
    end function;

    -- Load a packet into the input FIFO.
    procedure wr_pkt(din: std_logic_vector) is
        variable nbytes : integer := (din'length) / 8;
        variable rdpos  : natural := 0;
        variable btmp   : byte_t := (others => '0');
    begin
        wait until rising_edge(clk);
        fifo_wr <= '1';
        while (rdpos < nbytes) loop
            if (rdpos + IO_BYTES >= nbytes) then
                fifo_nlast  <= nbytes - rdpos;  -- Last word in frame
            else
                fifo_nlast  <= 0;               -- Frame continues...
            end if;
            for n in 0 to IO_BYTES-1 loop
                btmp := strm_byte_zpad(rdpos, din);
                fifo_data(8*IO_BYTES-8*n-1 downto 8*IO_BYTES-8*n-8) <= btmp;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk);
        end loop;
        fifo_wr <= '0';
    end procedure;

    -- Load a packet and set reference outputs.
    type ptp_mode_t is (PTP_MODE_NONE, PTP_MODE_ETH, PTP_MODE_UDP);
    procedure wr_all(typ: ptp_mode_t; din: std_logic_vector) is
        variable nbytes : positive := din'length / 8 - 4;
        variable dout   : std_logic_vector(din'range) := din;
        variable pktpos : natural := 0;
        variable bitpos : natural := 0;
        variable tlvpos : natural := 0;
        variable tlvtyp : tlvtype_t := (others => '0');
        variable tlvlen : natural := 0;
    begin
        -- Calculate start position of the PTP message, if applicable.
        if (typ = PTP_MODE_ETH) then
            pktpos := ETH_HDR_DATA;             -- Start of PTP-L2 frame
        elsif (typ = PTP_MODE_UDP) then
            pktpos := UDP_HDR_DAT(IP_IHL_MIN);  -- Start of PTP-L3 frame
        end if;

        -- Read the PTP message header.
        if (pktpos > 0) then
            -- Read messageType and determine length.
            bitpos := din'length - 8 * (pktpos + PTP_HDR_TYPE + 1);
            tlvpos := ptp_msg_len(din(bitpos+3 downto bitpos));
            -- Replace the messageLength field.
            -- (Easier here than during initial randomization.)
            bitpos := din'length - 8 * (pktpos + PTP_HDR_LEN + 2);
            dout(bitpos+15 downto bitpos) := i2s(nbytes - pktpos, 16);
        end if;

        -- Write the raw packet to the input FIFO.
        wr_pkt(dout);

        -- Reset all reference outputs:
        ref_pmsg <= bidx_to_tlvpos(pktpos);
        ref_tlv0 <= TLVPOS_NONE;
        ref_tlv1 <= TLVPOS_NONE;
        ref_tlv2 <= TLVPOS_NONE;
        ref_tlv3 <= TLVPOS_NONE;
        ref_tlv4 <= TLVPOS_NONE;
        ref_tlv5 <= TLVPOS_NONE;
        ref_tlv6 <= TLVPOS_NONE;
        ref_tlv7 <= TLVPOS_NONE;

        -- Parse TLVs and update reference outputs.
        while (0 < tlvpos and pktpos+tlvpos+4 <= nbytes) loop
            -- Read the next TLV type + length.
            bitpos := din'length - 8 * (pktpos + tlvpos + 4);
            tlvtyp := din(bitpos+31 downto bitpos+16);
            tlvlen := u2i(din(bitpos+15 downto bitpos));
            tlvpos := tlvpos + 4;
            -- Any matching tags?
            case tlvtyp is
            when x"0100" => ref_tlv0 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0101" => ref_tlv1 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0102" => ref_tlv2 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0103" => ref_tlv3 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0104" => ref_tlv4 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0105" => ref_tlv5 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0106" => ref_tlv6 <= bidx_to_tlvpos(pktpos + tlvpos);
            when x"0107" => ref_tlv7 <= bidx_to_tlvpos(pktpos + tlvpos);
            when others =>  -- No effect
            end case;
            -- Skip ahead to the next tag.
            tlvpos := tlvpos + tlvlen;
        end loop;
    end procedure;

    -- Run a complete test with a single packet.
    procedure test_single(
            ri:  real;
            typ: ptp_mode_t;
            pkt: std_logic_vector) is
        variable timeout : natural := 10_000;
    begin
        -- Pre-test setup.
        test_index  <= test_index + 1;
        test_rate_i <= 0.0;
        test_rate_o <= 0.0;
        wait for 1 us;
        wr_all(typ, pkt);
        -- Run test to completion or timeout.
        wait for 1 us;
        test_rate_i <= ri;
        test_rate_o <= 0.1 * ri;
        while (timeout > 0 and out_rcvd = '0') loop
            timeout := timeout - 1;
            wait until rising_edge(clk);
        end loop;
        -- Test completed successfully?
        if (timeout = 0) then
            report "Timeout waiting for packet." severity error;
            reset_p <= '1';     -- Purge Ref and UUT
            wait until rising_edge(clk);
            reset_p <= '0';
        end if;
        wait for 1 us;
    end procedure;

    -- Address parameters.
    constant MAC_DST    : mac_addr_t := x"FFFFFFFFFFFF";
    constant MAC_SRC    : mac_addr_t := x"DEADBEEFCAFE";
    constant IP_HDR     : ipv4_header := make_ipv4_header(
        x"12345678", x"12345678", x"1234", IPPROTO_UDP);

    -- Randomly generate a PTP type-length-value (TLV) tag with specified ID.
    impure function random_ptp_tag(tag_id: natural) return std_logic_vector is
        variable tag_typ : tlvtype_t := i2s(255 + tag_id, 16);
        variable tag_len : natural := 2 * rand_int(8);
    begin
        return tag_typ & i2s(tag_len, 16) & rand_vec(8*tag_len);
    end function;

    -- Create 0-3 random TLV tags, interspersed with the tag of interest.
    impure function random_ptp_tags(tag_id: natural) return std_logic_vector is
        variable qty : integer range 0 to 3 := rand_int(4);        -- N = 0/1/2/3
        variable idx : integer range 0 to 3 := rand_int(qty+1);    -- n = 0 to N
    begin
        case qty is
        when 0 => return "";
        when 1 => return random_ptp_tag(tag_id);
        when 2 => return random_ptp_tag(tag_id * u2i(idx = 0))
                       & random_ptp_tag(tag_id * u2i(idx > 0));
        when 3 => return random_ptp_tag(tag_id * u2i(idx = 0))
                       & random_ptp_tag(tag_id * u2i(idx = 1))
                       & random_ptp_tag(tag_id * u2i(idx > 1));
        end case;
    end function;

    -- Create a PTP message with a random type, with the specified tag ID.
    impure function random_ptp_msg(tag_id: natural) return std_logic_vector is
        variable typ : nybb_t := rand_vec(4);   -- PTP Message type
        variable len : integer := ptp_msg_len2(typ);
    begin
        if (len = 0) then len := 42; end if;
        return rand_vec(4) & typ & rand_vec(8*(len-1)) & random_ptp_tags(tag_id);
    end function;

    -- Run test with a randomized packet (Non-PTP, PTP-L2, or PTP-L3).
    procedure test_no(ri: real; nbytes: positive) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_ARP, rand_vec(8*nbytes));
    begin
        test_single(ri, PTP_MODE_NONE, eth.all);
    end procedure;

    procedure test_l2(ri: real; tag_id: natural) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_PTP, random_ptp_msg(tag_id));
    begin
        test_single(ri, PTP_MODE_ETH, eth.all);
    end procedure;

    procedure test_l3(ri: real; tag_id: natural) is
        variable udp : std_logic_vector(63 downto 0) :=
            rand_vec(16) & x"013F" & rand_vec(32);
        variable ip : ip_packet := make_ipv4_pkt(
            IP_HDR, udp & random_ptp_msg(tag_id));
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_IPV4, ip.all);
    begin
        test_single(ri, PTP_MODE_UDP, eth.all);
    end procedure;
begin
    reset_p <= '1';
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    for n in 1 to TEST_ITER loop
        test_no(0.1,  42);
        test_no(0.5,  64);
        test_no(1.0,  128);
        test_l2(0.1,  42);
        test_l2(0.9,  1);
        test_l2(1.0,  2);
        test_l3(0.1,  3);
        test_l3(0.9,  4);
        test_l3(1.0,  5);
        test_l2(0.1,  6);
        test_l2(0.9,  7);
        test_l2(1.0,  8);
        if (n mod 10 = 0) then
            report "Completed run #" & integer'image(n);
        end if;
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity ptp_ingress_tb is
    -- Testbench --> No I/O ports
end ptp_ingress_tb;

architecture tb of ptp_ingress_tb is

begin

-- Demonstrate operation at different pipeline widths.

uut0 : entity work.ptp_ingress_tb_single
    generic map(IO_BYTES => 1, TEST_ITER => 75);
uut1 : entity work.ptp_ingress_tb_single
    generic map(IO_BYTES => 3, TEST_ITER => 120);
uut2 : entity work.ptp_ingress_tb_single
    generic map(IO_BYTES => 8, TEST_ITER => 150);

end tb;
