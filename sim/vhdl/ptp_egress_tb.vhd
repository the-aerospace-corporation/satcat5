--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PTP "egress" module (last-second per-port adjustments)
--
-- This unit test generates a variety of randomized traffic (regular, PTP-L2,
-- and PTP-L3) and confirms that the unit under test makes the required
-- adjustments.  The test is run in parallel with various build-time
-- parameters, including IO_BYTES settings that span the expected range.
--
-- The complete test takes 4.8 milliseconds.
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

entity ptp_egress_tb_single is
    generic (
    IO_BYTES    : positive;
    TEST_ITER   : positive);
end ptp_egress_tb_single;

architecture single of ptp_egress_tb_single is

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- FIFO for loading test data.
signal fifo_din     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal fifo_dref    : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal fifo_nlast   : integer range 0 to IO_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal fifo_mvec_i  : std_logic_vector(SWITCH_META_WIDTH-1 downto 0) := (others => '0');
signal fifo_mvec_p  : std_logic_vector(SWITCH_META_WIDTH-1 downto 0) := (others => '0');
signal ref_mvec     : std_logic_vector(SWITCH_META_WIDTH-1 downto 0) := (others => '0');
signal ref_meta     : switch_meta_t := SWITCH_META_NULL;
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;
signal ref_ready    : std_logic;

-- Unit under test.
signal port_tnow    : tstamp_t;
signal in_mvec      : std_logic_vector(SWITCH_META_WIDTH-1 downto 0);
signal in_meta      : switch_meta_t := SWITCH_META_NULL;
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_error    : std_logic;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_vtag     : vlan_hdr_t;

-- High-level test control.
signal test_index   : natural := 0;
signal test_2step   : std_logic := '0';
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;
signal test_meta_i  : switch_meta_t := SWITCH_META_NULL;
signal test_meta_p  : switch_meta_t := SWITCH_META_NULL;

begin

-- Clock and reset generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

-- FIFO for loading test data.
fifo_mvec_i <= switch_m2v(test_meta_i);
fifo_mvec_p <= switch_m2v(test_meta_p);
in_meta     <= switch_v2m(in_mvec);
ref_meta    <= switch_v2m(ref_mvec);
ref_ready   <= out_valid and out_ready;

u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => SWITCH_META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_din,
    in_nlast        => fifo_nlast,
    in_meta         => fifo_mvec_i,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_meta        => in_mvec,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_rate        => test_rate_i,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => SWITCH_META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_dref,
    in_nlast        => fifo_nlast,
    in_meta         => fifo_mvec_p,
    in_write        => fifo_write,
    out_clk         => clk,
    out_data        => ref_data,
    out_nlast       => ref_nlast,
    out_meta        => ref_mvec,
    out_valid       => ref_valid,
    out_ready       => ref_ready,
    reset_p         => reset_p);

-- Unit under test.
uut : entity work.ptp_egress
    generic map(
    IO_BYTES    => IO_BYTES,
    PTP_DOPPLER => true,
    PTP_STRICT  => true)
    port map(
    port_tnow   => ref_meta.tstamp,
    port_tfreq  => ref_meta.tfreq,
    port_pstart => '1',     -- Not tested
    port_dvalid => out_valid,
    in_meta     => in_meta,
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_vtag    => out_vtag,
    out_data    => out_data,
    out_error   => out_error,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    cfg_2step   => test_2step,
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
            assert (out_vtag = ref_meta.vtag)
                report "VTAG mismatch" severity error;
        end if;

        -- Flow-control randomization.
        out_ready <= rand_bit(test_rate_o);
    end if;
end process;

-- High-level test control.
p_test : process
    -- Load packet into the input and reference FIFOs.
    type ptp_mode_t is (PTP_MODE_NONE, PTP_MODE_ETH, PTP_MODE_UDP);
    procedure wr_pkt(typ: ptp_mode_t; din: std_logic_vector; tstamp_err, tfreq_err: boolean) is
        variable tmp1, tmp2 : byte_t := (others => '0');
        variable dref   : std_logic_vector(din'range) := din;
        variable nbytes : integer := (din'length) / 8;
        variable rdpos  : natural := 0;
        variable pktpos : natural := 0;
        variable tlvpos : natural := 0;
        variable bitpos : natural := 0;
        variable tcorr  : signed(63 downto 0) := (others => '0');
        variable tfreq  : signed(47 downto 0) := (others => '0');
        variable vtag   : vlan_hdr_t := rand_vec(VLAN_HDR_WIDTH);
    begin
        -- Set start position for the PTP message and Doppler TLV.
        if (typ = PTP_MODE_ETH) then
            pktpos := ETH_HDR_DATA;
        elsif (typ = PTP_MODE_UDP) then
            pktpos := UDP_HDR_DAT(IP_IHL_MIN);
        end if;
        if (tfreq_err or rand_float > 0.5) then
            tlvpos := pktpos + 16;
        end if;

        -- Configure test parameters and packet metadata.
        test_2step          <= rand_bit;
        test_meta_i.pmsg    <= bidx_to_tlvpos(pktpos);
        test_meta_i.pfreq   <= bidx_to_tlvpos(tlvpos);
        test_meta_i.tstamp  <= unsigned(rand_vec(TSTAMP_WIDTH));
        test_meta_i.tfreq   <= signed(rand_vec(TFREQ_WIDTH));
        test_meta_i.vtag    <= vtag;
        test_meta_p.pmsg    <= bidx_to_tlvpos(pktpos);
        test_meta_p.pfreq   <= bidx_to_tlvpos(tlvpos);
        test_meta_p.vtag    <= vtag;
        if (tstamp_err) then
            test_meta_p.tstamp <= TSTAMP_DISABLED;
        else
            test_meta_p.tstamp <= unsigned(rand_vec(TSTAMP_WIDTH));
        end if;
        if (tfreq_err) then
            test_meta_p.tfreq <= TFREQ_DISABLED;
        else
            test_meta_p.tfreq <= signed(rand_vec(TFREQ_WIDTH));
        end if;
        wait until rising_edge(clk);

        -- Calculate and apply the new correctionField value(s).
        tcorr := resize(signed(test_meta_i.tstamp + test_meta_p.tstamp), tcorr'length);
        if (pktpos > 0) then
            bitpos := dref'length - (tcorr'length + 8*(pktpos + PTP_HDR_CORR));
            dref(bitpos+63 downto bitpos) := std_logic_vector(tcorr);
        end if;

        tfreq := resize(signed(test_meta_i.tfreq + test_meta_p.tfreq), tfreq'length);
        if (tlvpos > 0) then
            bitpos := dref'length - (tfreq'length + 8*tlvpos);
            dref(bitpos+47 downto bitpos) := std_logic_vector(tfreq);
        end if;

        -- If applicable, apply the new twoStepFlag.
        if (pktpos > 0 and test_2step = '1') then
            bitpos := dref'length - 8 * (pktpos + PTP_HDR_FLAG + 1);
            dref(bitpos+1) := '1';       -- Set the "twoStep" bit.
        end if;

        -- Write packets to both test FIFOs concurrently.
        while (rdpos < nbytes) loop
            if (rdpos + IO_BYTES >= nbytes) then
                fifo_nlast  <= nbytes - rdpos;
                fifo_write  <= '1';     -- Last word in frame
            else
                fifo_nlast  <= 0;
                fifo_write  <= '1';     -- Normal write
            end if;
            for n in 0 to IO_BYTES-1 loop
                tmp1 := strm_byte_zpad(rdpos, din);
                tmp2 := strm_byte_zpad(rdpos, dref);
                fifo_din(8*IO_BYTES-8*n-1 downto 8*IO_BYTES-8*n-8)  <= tmp1;
                fifo_dref(8*IO_BYTES-8*n-1 downto 8*IO_BYTES-8*n-8) <= tmp2;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk);
        end loop;

        -- Revert to idle state.
        fifo_din    <= (others => '0');
        fifo_dref   <= (others => '0');
        fifo_nlast  <= 0;
        fifo_write  <= '0';
        wait until rising_edge(clk);
    end procedure;

    -- Run a complete test with a single packet.
    procedure test_single(ri, ro: real; typ: ptp_mode_t; pkt: std_logic_vector; tstamp_err, tfreq_err:boolean) is
        variable timeout : natural := 10_000;
    begin
        -- Pre-test setup.
        test_index  <= test_index + 1;
        test_rate_i <= 0.0;
        test_rate_o <= 0.0;
        wait for 1 us;
        wr_pkt(typ, pkt, tstamp_err, tfreq_err);
        -- Run test to completion or timeout.
        wait for 1 us;
        test_rate_i <= ri;
        test_rate_o <= ro;
        while (timeout > 0 and ref_valid = '1') loop
            timeout := timeout - 1;
            if (ref_nlast /= 0) then
                assert (out_error = bool2bit(tstamp_err or tfreq_err))
                    report "ptp timestamp error undetected" severity error;
            end if;
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

    -- Run test with a randomized packet (Non-PTP, PTP-L2, or PTP-L3).
    procedure test_no(ri, ro: real; nbytes: natural) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_ARP, rand_vec(8*nbytes));
    begin
        -- no timestamp error for non-ptp packet
        test_single(ri, ro, PTP_MODE_NONE, eth.all, false, false);
    end procedure;

    procedure test_l2(ri, ro: real; nbytes: natural; tstamp_err, tfreq_err: boolean) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_PTP, rand_vec(8*nbytes));
    begin
        test_single(ri, ro, PTP_MODE_ETH, eth.all, tstamp_err, tfreq_err);
    end procedure;

    procedure test_l3(ri, ro: real; nbytes: natural; tstamp_err, tfreq_err: boolean) is
        variable udp : std_logic_vector(63 downto 0) :=
            rand_vec(16) & x"013F" & rand_vec(32);
        variable ip : ip_packet := make_ipv4_pkt(
            IP_HDR, udp & rand_vec(8*nbytes));
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_IPV4, ip.all);
    begin
        test_single(ri, ro, PTP_MODE_UDP, eth.all, tstamp_err, tfreq_err);
    end procedure;
begin
    reset_p <= '1';
    wait for 1 us;
    reset_p <= '0';
    wait for 1 us;

    for n in 1 to TEST_ITER loop
        test_no(0.1, 0.9, 64);
        test_no(0.9, 0.1, 64);
        test_no(0.9, 0.9, 128);
        test_l2(0.1, 0.9, 64,  false, false);
        test_l2(0.9, 0.1, 64,  false, false);
        test_l2(0.9, 0.9, 128, false, false);
        test_l2(0.9, 0.9, 128, false, true);
        test_l3(0.1, 0.9, 64,  false, false);
        test_l3(0.9, 0.1, 64,  false, false);
        test_l3(0.9, 0.9, 128, false, false);
        test_l3(0.9, 0.9, 128, false, true);
        test_l2(0.1, 0.9, 64,  true,  false);
        test_l2(0.9, 0.1, 64,  true,  false);
        test_l2(0.9, 0.9, 128, true,  false);
        test_l3(0.1, 0.9, 64,  true,  false);
        test_l3(0.9, 0.1, 64,  true,  false);
        test_l3(0.9, 0.9, 128, true,  false);
        if (n mod 10 = 0) then
            report "Completed run #" & integer'image(n);
        end if;
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity ptp_egress_tb is
    -- Testbench --> No I/O ports
end ptp_egress_tb;

architecture tb of ptp_egress_tb is

begin

-- Demonstrate operation at different pipeline widths.
uut0 : entity work.ptp_egress_tb_single
    generic map(IO_BYTES => 1, TEST_ITER => 25);
uut1 : entity work.ptp_egress_tb_single
    generic map(IO_BYTES => 2, TEST_ITER => 40);
uut2 : entity work.ptp_egress_tb_single
    generic map(IO_BYTES => 4, TEST_ITER => 55);
uut3 : entity work.ptp_egress_tb_single
    generic map(IO_BYTES => 8, TEST_ITER => 70);

end tb;
