--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Unit test for the ECN-RED block:
-- Explicit Congestion Notification (ECN) with Random Early Detection (RED)
--
-- This test generates a variety of Ethernet and IP packets, with or without
-- the ECN flag.  It confirms that the output exactly matches expectations
-- by overriding the operation of the internal PRNG.  Tests are repeated
-- under a variety of randomized flow-control conditions.
--
-- The complete test takes 2.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.router2_common.all;

entity router2_ecn_red_tb_single is
    generic (
    IO_BYTES    : positive;
    TEST_ITER   : positive);
end router2_ecn_red_tb_single;

architecture single of router2_ecn_red_tb_single is

-- Note: Assigning REGADDR > 255 results in truncation on Vivado 2019.1.
--   This is a platform-specific bug. As workaround, use a different value.
constant DEVADDR : integer := 42;
constant REGADDR : integer := 47;

-- Shortcuts for various types:
-- Metadata contains the drop flag, PRNG state, and queue state.
-- Note: Large LOAD_BYTES reduces downtime during test setup.
constant LOAD_BYTES : positive := 8;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype load_t is std_logic_vector(8*LOAD_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(17 downto 0);

-- Clock and reset generation.
signal clk          : std_logic := '0';
signal reset_p      : std_logic := '1';

-- FIFO for loading test data.
signal fifo_din     : load_t := (others => '0');
signal fifo_dref    : load_t := (others => '0');
signal fifo_meta    : meta_t := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal ref_data     : data_t;
signal ref_meta     : meta_t;
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;
signal ref_drop     : std_logic;

-- Unit under test.
signal in_data      : data_t;
signal in_meta      : meta_t;
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_write     : std_logic;
signal in_dreq      : std_logic;
signal in_prng      : unsigned(7 downto 0);
signal in_qdepth    : unsigned(7 downto 0);
signal out_data     : data_t;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_write    : std_logic;
signal out_drop     : std_logic;

-- High-level test control.
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;
signal cfg_cmd      : cfgbus_cmd := CFGBUS_CMD_NULL;

begin

-- Clock generation
clk <= not clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
cfg_cmd.clk <= to_01_std(clk);

-- FIFO for loading test data.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => fifo_meta'length)
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
    META_WIDTH      => fifo_meta'length)
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

ref_drop    <= ref_meta(17);
in_dreq     <= in_meta(16) when (in_write = '1' and in_nlast > 0) else '0';
in_prng     <= unsigned(in_meta(15 downto 8));
in_qdepth   <= unsigned(in_meta(7 downto 0));

-- Unit under test.
uut : entity work.router2_ecn_red
    generic map(
    IO_BYTES    => IO_BYTES,
    META_WIDTH  => 8*IO_BYTES,
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_drop     => in_dreq,
    in_meta     => in_data,
    in_write    => in_write,
    in_qdepth   => in_qdepth,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_drop    => out_drop,
    out_meta    => open,
    out_write   => out_write,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,
    sim_mode    => '1',
    sim_prng    => in_prng,
    clk         => clk,
    reset_p     => reset_p);

-- Check the output stream against the reference.
-- (The "drop" flag is metadata that is only guaranteed at end-of-frame.)
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
        end if;

        if (out_write = '1' and out_nlast > 0) then
            assert (out_drop = ref_drop)
                report "DROP mismatch" severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Global counter for packet IDENT field.
    variable ident  : uint16 := (others => '0');

    -- For simplicity, all packets use the same placeholder addresses.
    constant DSTIP  : ip_addr_t := x"C0A80002";
    constant SRCIP  : ip_addr_t := x"C0A80001";
    constant SRCMAC : mac_addr_t := x"DEADBEEFCAFE";

    -- Pack metadata arguments.
    procedure load_meta(qdepth, prng: natural; drop, dreq: std_logic) is
    begin
        fifo_meta <= drop & dreq & i2s(prng, 8) & i2s(qdepth, 8);
    end procedure;

    -- Load configuration through ConfigBus interface.
    -- Arguments: mark threshold, mark slope, drop threshold, drop slope
    variable mark_t, mark_s, drop_t, drop_s : integer := 0;
    procedure load_cfg(mt, ms, dt, ds : natural) is
        variable cfg1 : cfgbus_word := x"00" & i2s(mt, 8) & i2s(ms, 16);
        variable cfg2 : cfgbus_word := x"00" & i2s(dt, 8) & i2s(ds, 16);
    begin
        mark_t := mt;   -- Save for use with predict_mark(...)
        mark_s := ms;
        drop_t := dt;   -- Save for use with predict_drop(...)
        drop_s := ds;
        cfgbus_write(cfg_cmd, DEVADDR, REGADDR, cfg1);
        cfgbus_write(cfg_cmd, DEVADDR, REGADDR, cfg2);
        cfgbus_read(cfg_cmd, DEVADDR, REGADDR);
    end procedure;

    -- Predict mark or drop probability.
    impure function predict_mark(ecn, qdepth, prng: natural) return std_logic is
        variable pmark : integer := ((qdepth - mark_t) * mark_s) / 256;
    begin
        return bool2bit(ecn > 0 and prng < pmark);
    end function;

    impure function predict_drop(ecn, qdepth, prng: natural) return std_logic is
        variable pdrop : integer := ((qdepth - drop_t) * drop_s) / 256;
        variable pmark : integer := ((qdepth - mark_t) * mark_s) / 256;
    begin
        return bool2bit(ecn = 0 and prng < pmark) or bool2bit(prng < pdrop);
    end function;

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
        variable qdepth : natural := rand_int(256);
        variable prng   : natural := rand_int(256);
        variable dreq   : std_logic := rand_bit(0.05);
        variable drop   : std_logic := predict_drop(0, qdepth, prng) or dreq;
        variable data   : std_logic_vector(8*dlen-1 downto 0) := rand_bytes(dlen);
        variable ethpkt : eth_packet := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_ARP, data);
    begin
        -- For Ethernet packets, input and expected output are the same.
        load_meta(qdepth, prng, drop, dreq);
        load_pkt(ethpkt.all, ethpkt.all);
    end procedure;

    procedure gen_ipv4_pair(ecn, dlen: natural) is
        constant bidx : integer := 8 * IP_HDR_DSCP_ECN + 6;
        variable qdepth : natural := rand_int(256);
        variable prng   : natural := rand_int(256);
        variable dreq   : std_logic := rand_bit(0.05);
        variable drop   : std_logic := predict_drop(ecn, qdepth, prng) or dreq;
        variable mark   : std_logic := predict_mark(ecn, qdepth, prng);
        variable iphdr  : ipv4_header := make_ipv4_header(DSTIP, SRCIP, ident, IPPROTO_UDP, ecn => ecn);
        variable ippkt  : ip_packet := make_ipv4_pkt(iphdr, rand_bytes(dlen));
        variable eth0, eth1 : eth_packet;
    begin
        -- Make the input packet using specified parameters.
        eth0 := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_IPV4, ippkt.all);
        -- Update ECN field before generating the output packet.
        -- (To mimic UUT, do not recalculate the checksum.)
        eth1 := make_eth_pkt(MAC_ADDR_BROADCAST, SRCMAC, ETYPE_IPV4, ippkt.all);
        if (mark = '1') then eth1(eth1'left-bidx downto eth1'left-bidx-1) := (others => '1'); end if;
        -- Load packets and metadata into the test FIFO.
        load_meta(qdepth, prng, drop, dreq);
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
        for n in 1 to 8 loop
            gen_eth_pair(rand_int(100));        -- Ethernet has no ECN
            gen_ipv4_pair(0, rand_int(100));    -- ECN disabled
            gen_ipv4_pair(1, rand_int(100));    -- ECN supported
            gen_ipv4_pair(2, rand_int(100));    -- ECN supported
            gen_ipv4_pair(3, rand_int(100));    -- ECN marked
        end loop;
        test_wait(rr);
    end procedure;
begin
    -- Drive the ConfigBus reset signal.
    cfgbus_reset(cfg_cmd, 100 ns);
    wait for 100 ns;

    -- Load default configuration:
    -- * Mark = Threshold 127, slope 128/128 = 1.0 --> 256
    -- * Drop = Threshold 191, slope 128/64  = 2.0 --> 512
    load_cfg(127, 256, 191, 512);

    -- Repeat tests under various flow-control conditions.
    for n in 1 to TEST_ITER loop
        test_run(1.0);
        test_run(0.5);
    end loop;

    report "All tests completed!";
    wait;
end process;

end single;

--------------------------------------------------------------------------

entity router2_ecn_red_tb is
    -- Testbench --> No I/O ports
end router2_ecn_red_tb;

architecture tb of router2_ecn_red_tb is

begin

-- Demonstrate operation at different pipeline widths.
uut0 : entity work.router2_ecn_red_tb_single
    generic map(IO_BYTES => 1, TEST_ITER => 25);
uut1 : entity work.router2_ecn_red_tb_single
    generic map(IO_BYTES => 2, TEST_ITER => 45);
uut2 : entity work.router2_ecn_red_tb_single
    generic map(IO_BYTES => 4, TEST_ITER => 70);
uut3 : entity work.router2_ecn_red_tb_single
    generic map(IO_BYTES => 8, TEST_ITER => 100);

end tb;
