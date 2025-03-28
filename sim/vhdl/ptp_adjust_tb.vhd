--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the PTP "adjust" block (MAC pipeline processing)
--
-- This unit test generates a variety of randomized traffic (regular, PTP-L2,
-- and PTP-L3) and confirms that the unit under test makes the required
-- adjustments.  The test is run in parallel with various build-time
-- parameters, including IO_BYTES settings that span the expected range.
--
-- The complete test takes 9 milliseconds.
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

entity ptp_adjust_tb_single is
    generic (
    IO_BYTES    : positive;
    MIXED_STEP  : boolean;
    TEST_ITER   : positive);
end ptp_adjust_tb_single;

architecture single of ptp_adjust_tb_single is

constant PORT_COUNT     : positive := 5;
constant PKMETA_WIDTH   : positive := PORT_COUNT + SWITCH_META_WIDTH;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype mask_t is std_logic_vector(PORT_COUNT-1 downto 0);
subtype pkmeta_t is std_logic_vector(PKMETA_WIDTH-1 downto 0);
subtype swmeta_t is std_logic_vector(SWITCH_META_WIDTH-1 downto 0);

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Test data FIFO (packet metadata)
--  * PIN = Pre-input (FIFO to unit under test)
--  * PRF = Pre-reference (FIFO to output checking)
--  * REF = Expected output (PRF after FIFO)
--  * FRM = Output from unit under test
signal pin_meta     : switch_meta_t := SWITCH_META_NULL;
signal pin_mvec     : swmeta_t;
signal prf_meta     : switch_meta_t := SWITCH_META_NULL;
signal prf_pmask    : mask_t := (others => '0');
signal prf_pkmeta   : pkmeta_t;
signal ref_pkmeta   : pkmeta_t;
signal ref_pkvalid  : std_logic;
signal frm_pkmeta   : pkmeta_t;
signal fifo_wr_pkt  : std_logic;
signal fifo_rd_pkt  : std_logic;

-- Test data FIFO (streaming data)
signal fifo_data    : data_t := (others => '0');
signal fifo_nlast   : integer range 0 to IO_BYTES := 0;
signal fifo_wr_in   : std_logic := '0';
signal fifo_wr_ref  : std_logic := '0';
signal ref_data     : data_t;
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_mvec     : swmeta_t;
signal ref_valid    : std_logic;
signal ref_ready    : std_logic;

-- Unit under test.
signal in_mvec      : swmeta_t;
signal in_meta      : switch_meta_t;
signal in_data      : data_t;
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal out_meta     : switch_meta_t;
signal out_mvec     : swmeta_t;
signal out_data     : data_t;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal frm_pmask    : mask_t;
signal frm_meta     : switch_meta_t;
signal frm_valid    : std_logic;
signal frm_ready    : std_logic := '0';

-- High-level test control
signal test_index   : natural := 0;
signal test_2step   : mask_t := (others => '0');
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;
signal test_rate_f  : real := 0.0;
signal test_tfreq   : tfreq_t := TFREQ_DISABLED;
signal test_tstamp  : tstamp_t := TSTAMP_DISABLED;

begin

-- Clock and reset generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz

--------------- Input & Reference Data FIFO ---------------
-- Convert data structures to std_logic_vector.
in_meta     <= switch_v2m(in_mvec);
pin_mvec    <= switch_m2v(pin_meta);
out_mvec    <= switch_m2v(out_meta);
ref_ready   <= out_valid and out_ready;

-- Buffer the input to the unit under test.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => SWITCH_META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_data,   -- Data from test controller
    in_nlast        => fifo_nlast,
    in_meta         => pin_mvec,    -- Metadata from test controller
    in_write        => fifo_wr_in,
    out_clk         => clk,
    out_data        => in_data,     -- Input to unit under test
    out_nlast       => in_nlast,    -- (Data + metadata)
    out_meta        => in_mvec,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_rate        => test_rate_i,
    reset_p         => reset_p);

-- Reference for checking the "out_data" and "out_mvec" outputs, which are
-- delayed verbatim copies of the original input stream and its metadata.
u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => IO_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => SWITCH_META_WIDTH)
    port map(
    in_clk          => clk,
    in_data         => fifo_data,   -- Data from test controller
    in_nlast        => fifo_nlast,
    in_meta         => pin_mvec,    -- Metadata from test controller
    in_write        => fifo_wr_ref,
    out_clk         => clk,
    out_data        => ref_data,    -- Reference for checking UUT output
    out_nlast       => ref_nlast,   -- (Data + unmodified metadata)
    out_meta        => ref_mvec,
    out_valid       => ref_valid,
    out_ready       => ref_ready,
    reset_p         => reset_p);

----------------- Adjusted Metadata FIFO ------------------
-- Reference for the the "frm" output from the unit under test.
-- This stream contains modified packet metadata.  Because it uses separate
-- flow-control signals, the reference signals require a separate FIFO.
fifo_wr_pkt <= fifo_wr_ref and bool2bit(fifo_nlast > 0);
fifo_rd_pkt <= frm_valid and frm_ready;
prf_pkmeta  <= prf_pmask & switch_m2v(prf_meta);
frm_pkmeta  <= frm_pmask & switch_m2v(frm_meta);

u_fifo_frm : entity work.fifo_smol_sync
    generic map(IO_WIDTH => PKMETA_WIDTH)
    port map(
    in_data     => prf_pkmeta,      -- Adjusted metadata from test controller
    in_write    => fifo_wr_pkt,
    out_data    => ref_pkmeta,      -- Reference for checking UUT output
    out_valid   => ref_pkvalid,
    out_read    => fifo_rd_pkt,
    clk         => clk,
    reset_p     => reset_p);

------------------- Unit under test -----------------------
uut : entity work.ptp_adjust
    generic map(
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    MIXED_STEP  => MIXED_STEP,
    PTP_DOPPLER => true,
    PTP_STRICT  => true,
    SUPPORT_L2  => true,
    SUPPORT_L3  => true)
    port map(
    in_meta     => in_meta,         -- Buffered input from test controller
    in_psrc     => 0,
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_meta    => out_meta,
    out_psrc    => open,            -- Not tested
    out_data    => out_data,        -- Output for further packet processing
    out_nlast   => out_nlast,       -- (Data + unmodified metadata)
    out_valid   => out_valid,
    out_ready   => out_ready,
    cfg_2step   => test_2step,
    frm_pmask   => frm_pmask,       -- Adjusted metadata
    frm_meta    => frm_meta,
    frm_valid   => frm_valid,
    frm_ready   => frm_ready,
    clk         => clk,
    reset_p     => reset_p);

------------------- Test Control ------------------------

-- Low-level test control.
p_check : process(clk)
    -- Sticky flag, only print one error per packet.
    variable meta_ignore : boolean := false;
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
            assert (out_mvec = ref_mvec or meta_ignore)
                report "META mismatch" severity error;
            if (out_nlast > 0) then
                meta_ignore := false;
            elsif (out_mvec /= ref_mvec) then
                meta_ignore := true;
            end if;
        end if;

        -- Check frame metadata against the reference.
        if (frm_valid = '1' and frm_ready = '1') then
            assert (ref_pkvalid = '1')
                report "Unexpected metadata" severity error;
            assert (frm_pkmeta = ref_pkmeta)
                report "Metadata mismatch" severity error;
        end if;

        -- Flow-control randomization.
        out_ready <= rand_bit(test_rate_o);
        frm_ready <= rand_bit(test_rate_f);
    end if;
end process;

-- High-level test control.
p_test : process
    -- Load one packet into the active FIFO.
    -- (User should set fifo_wr_* as needed before calling.)
    procedure wr_pkt(din: std_logic_vector) is
        variable nbytes : integer := (din'length) / 8;
        variable rdpos  : natural := 0;
        variable btmp   : byte_t := (others => '0');
    begin
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
    end procedure;

    -- Load packet(s) into the input and reference FIFOs.
    type ptp_mode_t is (PTP_MODE_NONE, PTP_MODE_ETH, PTP_MODE_UDP);
    procedure wr_all(typ: ptp_mode_t; din: std_logic_vector ; tstamp_err, tfreq_err: boolean) is
        variable dref   : std_logic_vector(din'range) := din;
        variable dcpy   : std_logic_vector(din'range) := din;
        variable pktpos : natural := 0;
        variable tlvpos : natural := 0;
        variable bitpos : natural := 0;
        variable pcmd   : nybb_t := (others => '0');
        variable padj   : std_logic := '0';
        variable pcopy  : std_logic := '0';
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

        -- Configure input metadata for this packet.
        pin_meta.pmsg   <= bidx_to_tlvpos(pktpos);
        pin_meta.pfreq  <= bidx_to_tlvpos(tlvpos);
        pin_meta.vtag   <= rand_vec(VLAN_HDR_WIDTH);
        if (tstamp_err) then
            pin_meta.tstamp <= TSTAMP_DISABLED;
        else
            pin_meta.tstamp <= unsigned(rand_vec(TSTAMP_WIDTH));
        end if;
        if (tfreq_err) then
            pin_meta.tfreq <= TFREQ_DISABLED;
        else
            pin_meta.tfreq <= signed(rand_vec(TFREQ_WIDTH));
        end if;

        -- Write the raw packet to the input FIFO.
        wait until rising_edge(clk);
        fifo_wr_in <= '1';
        wr_pkt(din);
        fifo_wr_in <= '0';

        -- Replace UDP checksum, if applicable.
        if (typ = PTP_MODE_UDP) then
            bitpos := din'length - 8 * (UDP_HDR_CHK(IP_IHL_MIN) + 2);
            dref(bitpos+15 downto bitpos) := (others => '0');
            dcpy(bitpos+15 downto bitpos) := (others => '0');
        end if;

        -- Extract and modify fields of interest from the PTP message.
        if (pktpos > 0) then
            -- Read correctionField, and replace it in the cloned message.
            -- Note: correctionField is 64 bits regardless of TSTAMP_WIDTH.
            bitpos  := din'length - 8 * (pktpos + PTP_HDR_CORR + 8);
            test_tstamp <= unsigned(din(bitpos+TSTAMP_WIDTH-1 downto bitpos));
            dcpy(bitpos+63 downto bitpos) := (others => '0');
            -- Extract the messageType from the PTP header.
            bitpos  := din'length - 8 * (pktpos + PTP_HDR_TYPE + 1);
            pcmd    := din(bitpos+3 downto bitpos);
            -- Is this one of the message types that needs adjustment?
            padj    := bool2bit(pcmd = PTP_MSG_SYNC
                             or pcmd = PTP_MSG_DLYREQ
                             or pcmd = PTP_MSG_PDLYREQ
                             or pcmd = PTP_MSG_PDLYRSP);
            -- Read twoStepFlag and decide if we should clone this frame.
            bitpos  := din'length - 8 * (pktpos + PTP_HDR_FLAG + 1);
            pcopy   := or_reduce(test_2step) and not din(bitpos + 1);
            -- Replace the messageType field in the cloned message.
            bitpos  := din'length - 8 * (pktpos + PTP_HDR_TYPE + 1);
            if (pcmd = PTP_MSG_SYNC) then
                dcpy(bitpos+3 downto bitpos) := PTP_MSG_FOLLOW;
            elsif (pcmd = PTP_MSG_PDLYRSP) then
                dcpy(bitpos+3 downto bitpos) := PTP_MSG_PDLYRFU;
            else
                pcopy := '0';   -- Non-cloned message type
            end if;
        end if;

        -- Extract the doppler field, and replace it in the cloned message.
        -- Note: This field is 48 bits regardless of TFREQ_WIDTH.
        if (tlvpos > 0) then
            bitpos := din'length - 8 * (tlvpos + 6);
            test_tfreq <= signed(din(bitpos+TFREQ_WIDTH-1 downto bitpos));
            dcpy(bitpos+47 downto bitpos) := (others => '0');
        end if;

        -- Set expected adjusted-result metadata for this frame.
        wait until rising_edge(clk);
        prf_meta.vtag <= pin_meta.vtag;
        if (padj = '0') then
            -- No adjustment needed
            prf_pmask       <= (others => '1');
            prf_meta.pmsg   <= TLVPOS_NONE;
            prf_meta.pfreq  <= TLVPOS_NONE;
            prf_meta.tstamp <= TSTAMP_DISABLED;
            prf_meta.tfreq  <= TFREQ_DISABLED;
        elsif (tstamp_err or tfreq_err) then
            -- Error during adjustment, missing info.
            prf_pmask       <= (others => '0');
            prf_meta.pmsg   <= TLVPOS_NONE;
            prf_meta.pfreq  <= TLVPOS_NONE;
            prf_meta.tstamp <= TSTAMP_DISABLED;
            prf_meta.tfreq  <= TFREQ_DISABLED;
        elsif (tlvpos > 0) then
            -- Normal case with all fields.
            prf_pmask       <= (others => '1');
            prf_meta.pmsg   <= pin_meta.pmsg;
            prf_meta.pfreq  <= pin_meta.pfreq;
            prf_meta.tstamp <= test_tstamp - pin_meta.tstamp;
            prf_meta.tfreq  <= test_tfreq - pin_meta.tfreq;
        else
            -- Normal case without frequency tag.
            prf_pmask       <= (others => '1');
            prf_meta.pmsg   <= pin_meta.pmsg;
            prf_meta.pfreq  <= pin_meta.pfreq;
            prf_meta.tstamp <= test_tstamp - pin_meta.tstamp;
            prf_meta.tfreq  <= TFREQ_DISABLED;
        end if;

        -- Write the modified packet to the reference FIFO.
        wait until rising_edge(clk);
        fifo_wr_ref <= '1';
        wr_pkt(dref);
        fifo_wr_ref <= '0';

        -- If applicable, write the cloned packet to the reference FIFO.
        if (MIXED_STEP and pcopy = '1') then
            wait until rising_edge(clk);
            prf_pmask       <= test_2step;
            prf_meta.pmsg   <= TLVPOS_NONE;
            prf_meta.pfreq  <= TLVPOS_NONE;
            prf_meta.tstamp <= TSTAMP_DISABLED;
            prf_meta.tfreq  <= TFREQ_DISABLED;
            fifo_wr_ref     <= '1';
            wr_pkt(dcpy);
            fifo_wr_ref     <= '0';
        end if;
    end procedure;

    -- Run a complete test with a single packet.
    procedure test_single(
            ri, ro: real;
            typ: ptp_mode_t;
            pkt: std_logic_vector;
            tstamp_err, tfreq_err: boolean) is
        variable timeout : natural := 10_000;
    begin
        -- Pre-test setup.
        test_index  <= test_index + 1;
        test_2step  <= rand_vec(PORT_COUNT);
        test_rate_i <= 0.0;
        test_rate_o <= 0.0;
        test_rate_f <= 0.0;
        test_tfreq  <= TFREQ_DISABLED;
        test_tstamp <= TSTAMP_DISABLED;
        wait for 1 us;
        wr_all(typ, pkt, tstamp_err, tfreq_err);
        -- Run test to completion or timeout.
        wait for 1 us;
        test_rate_i <= ri;
        test_rate_o <= ro;
        test_rate_f <= ro * 0.1;
        while (timeout > 0 and (ref_valid = '1' or ref_pkvalid = '1')) loop
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

    -- Create a PTP message with a random type and length.
    impure function random_ptp_msg return std_logic_vector is
        variable typ : nybb_t := rand_vec(4);   -- PTP Message type
        variable len : integer := 32 + rand_int(32);
    begin
        return rand_vec(4) & typ & rand_vec(8*len);
    end function;

    -- Run test with a randomized packet (Non-PTP, PTP-L2, or PTP-L3).
    procedure test_no(ri, ro: real; nbytes: natural) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_ARP, rand_vec(8*nbytes));
    begin
        test_single(ri, ro, PTP_MODE_NONE, eth.all, false, false);
    end procedure;

    procedure test_l2(ri, ro: real; tstamp_err, tfreq_err:boolean) is
        variable eth : eth_packet := make_eth_fcs(
            MAC_DST, MAC_SRC, ETYPE_PTP, random_ptp_msg);
    begin
        test_single(ri, ro, PTP_MODE_ETH, eth.all, tstamp_err, tfreq_err);
    end procedure;

    procedure test_l3(ri, ro: real; tstamp_err, tfreq_err:boolean) is
        variable udp : std_logic_vector(63 downto 0) :=
            rand_vec(16) & x"013F" & rand_vec(32);
        variable ip : ip_packet := make_ipv4_pkt(
            IP_HDR, udp & random_ptp_msg);
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
        test_l2(0.1, 0.9, false, false);
        test_l2(0.9, 0.1, false, false);
        test_l2(0.9, 0.9, false, false);
        test_l3(0.1, 0.9, false, false);
        test_l3(0.9, 0.1, false, false);
        test_l3(0.9, 0.9, false, false);
        test_l2(0.1, 0.9, true, false);
        test_l2(0.9, 0.1, true, false);
        test_l2(0.9, 0.9, true, false);
        test_l3(0.1, 0.9, true, false);
        test_l3(0.9, 0.1, true, false);
        test_l3(0.9, 0.9, true, false);
        test_l3(0.9, 0.9, true, true);
        if (n mod 10 = 0) then
            report "Completed run #" & integer'image(n);
        end if;
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity ptp_adjust_tb is
    -- Testbench --> No I/O ports
end ptp_adjust_tb;

architecture tb of ptp_adjust_tb is

begin

-- Demonstrate operation at different pipeline widths.

uut0 : entity work.ptp_adjust_tb_single
    generic map(IO_BYTES => 1, MIXED_STEP => true, TEST_ITER => 42);
uut1 : entity work.ptp_adjust_tb_single
    generic map(IO_BYTES => 4, MIXED_STEP => false, TEST_ITER => 100);
uut2 : entity work.ptp_adjust_tb_single
    generic map(IO_BYTES => 32, MIXED_STEP => true, TEST_ITER => 150);

end tb;
