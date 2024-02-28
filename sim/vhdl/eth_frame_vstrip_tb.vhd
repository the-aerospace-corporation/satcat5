--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the Virtual-LAN tag parsing block
--
-- This testbench streams traffic with a mixture of tagged and untagged
-- traffic, and confirms that it strips the 802.1Q tags, reports metadata
-- as expected, and enforces tag policies correctly.
--
-- The complete test takes less than 0.2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity eth_frame_vstrip_tb_single is
    generic (
    IO_BYTES    : positive;         -- Set pipeline width
    PORT_INDEX  : natural := 42);   -- Configuration address
    port (
    test_done   : out std_logic);
end eth_frame_vstrip_tb_single;

architecture single of eth_frame_vstrip_tb_single is

-- System clock and reset
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_write     : std_logic;
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_commit    : std_logic;

-- Reference stream
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_vtag     : vlan_hdr_t;
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_commit   : std_logic;
signal ref_revert   : std_logic;
signal ref_error    : std_logic;
signal ref_valid    : std_logic;

-- Output stream
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_vtag     : vlan_hdr_t;
signal out_write    : std_logic;
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_commit   : std_logic;
signal out_revert   : std_logic;
signal out_error    : std_logic;

-- Test control.
constant LOAD_BYTES : positive := IO_BYTES;
signal cfg_cmd      : cfgbus_cmd;
signal rate_in      : real := 0.0;
signal ignore_data  : std_logic := '0';
signal load_data    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal load_meta    : std_logic_vector(18 downto 0) := (others => '0');
signal load_nlast   : integer range 0 to LOAD_BYTES := 0;
signal load_wr_in   : std_logic := '0';
signal load_wr_ref  : std_logic := '0';
signal test_done_i  : std_logic := '0';

begin

-- Clock and reset generation.
clk100  <= not clk100 after 5 ns;   -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
cfg_cmd.clk <= clk100;

-- Input and reference queues.
in_commit <= in_write and bool2bit(in_nlast > 0);

u_ififo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_write        => load_wr_in,
    out_clk         => clk100,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_valid       => in_write,
    out_ready       => '1',
    out_rate        => rate_in,
    reset_p         => reset_p);

u_rfifo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => 19)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_meta         => load_meta,
    in_write        => load_wr_ref,
    out_clk         => clk100,
    out_data        => ref_data,
    out_nlast       => ref_nlast,
    out_meta(18)    => ref_commit,
    out_meta(17)    => ref_revert,
    out_meta(16)    => ref_error,
    out_meta(15 downto 0) => ref_vtag,
    out_valid       => ref_valid,
    out_ready       => out_write,
    reset_p         => reset_p);

-- Unit under test.
uut : entity work.eth_frame_vstrip
    generic map(
    DEVADDR     => CFGBUS_ADDR_ANY,
    REGADDR     => CFGBUS_ADDR_ANY,
    IO_BYTES    => IO_BYTES,
    PORT_INDEX  => PORT_INDEX)
    port map(
    in_data     => in_data,
    in_write    => in_write,
    in_nlast    => in_nlast,
    in_commit   => in_commit,
    in_revert   => '0',     -- Not tested
    in_error    => '0',     -- Not tested
    out_data    => out_data,
    out_vtag    => out_vtag,
    out_write   => out_write,
    out_nlast   => out_nlast,
    out_commit  => out_commit,
    out_revert  => out_revert,
    out_error   => out_error,
    cfg_cmd     => cfg_cmd,
    clk         => clk100,
    reset_p     => reset_p);

-- Verify outputs.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (out_write = '1' and ref_valid = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
        elsif (out_write = '1' and ignore_data = '0') then
            report "Unexpected output data." severity error;
        end if;

        if (out_write = '1' and out_nlast > 0) then
            if (ref_valid = '1') then
                assert (out_commit = '0' or out_vtag = ref_vtag)
                    report "VTAG mismatch." severity error;
                assert (out_commit = ref_commit
                    and out_revert = ref_revert
                    and out_error = ref_error)
                    report "Frame status mismatch." severity error;
            elsif (ignore_data = '1') then
                assert (out_revert = '1' and out_error = '1')
                    report "Missing ERROR strobe." severity error;
            else
                report "Unexpected end-of-frame." severity error;
            end if;
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
    -- Define success/error codes for the commit, revert, and error strobes.
    subtype errcode_t is std_logic_vector(2 downto 0);
    constant RESULT_COMMIT  : errcode_t := "100";   -- Commit = 1, Revert = 0, Error = 0
    constant RESULT_DROP    : errcode_t := "010";   -- Commit = 0, Revert = 1, Error = 0
    constant RESULT_ERROR   : errcode_t := "011";   -- Commit = 0, Revert = 1, Error = 1

    -- Load test data into designated FIFO.
    type load_dst is (LOAD_IN, LOAD_REF);
    procedure load(dst : load_dst; data : std_logic_vector) is
        constant LOAD_BITS : positive := LOAD_BYTES * 8;
        variable brem : integer := data'length;
    begin
        wait until rising_edge(clk100);
        load_wr_in  <= bool2bit(dst = LOAD_IN);
        load_wr_ref <= bool2bit(dst = LOAD_REF);
        while (brem > 0) loop
            if (brem > LOAD_BITS) then
                load_data   <= data(brem-1 downto brem-LOAD_BITS);
                load_nlast  <= 0;
            else
                load_data   <= data(brem-1 downto 0) & i2s(0, LOAD_BITS-brem);
                load_nlast  <= brem / 8;
            end if;
            wait until rising_edge(clk100);
            brem := brem - LOAD_BITS;
        end loop;
        load_data   <= (others => '0');
        load_nlast  <= 0;
        load_wr_in  <= '0';
        load_wr_ref <= '0';
    end procedure;

    -- Start experiment and run until completed.
    procedure wait_done(rate : real; ignore : std_logic) is
        variable idle_count : natural := 0;
    begin
        -- Wait a few clock cycles for all FIFOs to be ready.
        for n in 1 to 10 loop
            wait until rising_edge(clk100);
        end loop;
        -- Start transmission of test data.
        rate_in <= rate;
        ignore_data <= ignore;
        -- Wait until N consecutive idle cycles.
        while (idle_count < 100) loop
            wait until rising_edge(clk100);
            if (in_write = '1' or out_write = '1') then
                idle_count := 0;
            else
                idle_count := idle_count + 1;
            end if;
        end loop;
        -- Post-test cleanup.
        assert (ref_valid = '0')
            report "Output too short" severity error;
        rate_in <= 0.0;
    end procedure;

    -- Write to ConfigBus register.
    procedure configure(
        vtag_policy  : tag_policy_t;
        vtag_default : vlan_hdr_t)
    is
        constant cmd_word : cfgbus_word :=
            i2s(PORT_INDEX, 8) & "000000" & vtag_policy & vtag_default;
    begin
        cfgbus_write(cfg_cmd, 0, 0, cmd_word);
    end procedure;

    -- Basic functional tests with specified VLAN policy.
    procedure test_policy(rate : real; policy : tag_policy_t) is
        variable dst    : mac_addr_t := rand_vec(48);
        variable src    : mac_addr_t := rand_vec(48);
        variable data   : crc_word_t := rand_vec(32);
        -- Randomized tags: Default, user, priority, priority + default VID.
        variable tag_d  : vlan_hdr_t := rand_vec(16);
        variable tag_u  : vlan_hdr_t := rand_vec(16);
        variable tag_p1 : vlan_hdr_t := vlan_get_hdr(
            vlan_get_pcp(tag_u), vlan_get_dei(tag_u), VID_NONE);
        variable tag_p2 : vlan_hdr_t := vlan_get_hdr(
            vlan_get_pcp(tag_u), vlan_get_dei(tag_u), vlan_get_vid(tag_d));
        -- Construct untagged, full-tagged, and priority-tagged packets.
        variable pkt1   : eth_packet :=
            make_eth_pkt(dst, src, ETYPE_IPV4, data);
        variable pkt2   : eth_packet :=
            make_vlan_pkt(dst, src, tag_u, ETYPE_IPV4, data);
        variable pkt3   : eth_packet :=
            make_vlan_pkt(dst, src, tag_p1, ETYPE_IPV4, data);
    begin
        -- Set policy and default tag for subsequent tasks.
        configure(policy, tag_d);

        -- Untagged input frame should result in default tag metadata.
        if (policy = VTAG_MANDATORY) then
            load_meta <= RESULT_ERROR & tag_d;
        else
            load_meta <= RESULT_COMMIT & tag_d;
        end if;
        load(LOAD_IN,   pkt1.all);  -- Input = Untagged
        load(LOAD_REF,  pkt1.all);  -- Output = Input
        wait_done(rate, '0');

        -- Full-tagged input frame should set all metadata fields.
        if (policy = VTAG_PRIORITY) then
            load_meta <= RESULT_ERROR & tag_u;
        else
            load_meta <= RESULT_COMMIT & tag_u;
        end if;
        load(LOAD_IN,   pkt2.all);  -- Input = Full tag
        load(LOAD_REF,  pkt1.all);  -- Output = Input - tag
        wait_done(rate, '0');

        -- Priority-tagged input frame should set PCP and DEI only, default VID.
        if (policy = VTAG_MANDATORY) then
            load_meta <= RESULT_ERROR & tag_p2;
        else
            load_meta <= RESULT_COMMIT & tag_p2;
        end if;
        load(LOAD_IN,   pkt3.all);  -- Input = Priority tag
        load(LOAD_REF,  pkt1.all);  -- Output = Input - tag
        wait_done(rate, '0');
    end procedure;

    -- Basic functional tests with incomplete VTAG fields.
    procedure test_badtag(rate : real; nbytes : integer) is
        constant dst : mac_addr_t := rand_vec(48);
        constant src : mac_addr_t := rand_vec(48);
        variable pkt : eth_packet;
    begin
        -- Set EType = VLAN Tag (0x8100) but truncate the tag field.
        configure(VTAG_ADMIT_ALL, VHDR_NONE);
        pkt := make_eth_pkt(dst, src, ETYPE_VLAN, rand_vec(8*nbytes));
        load_meta <= (others => '0');   -- Not used in this test
        load(LOAD_IN, pkt.all);         -- Load input only, no reference
        wait_done(rate, '1');           -- Test packet should be rejected
    end procedure;

    -- Stress-tests with a mixture of very short and long frames.
    procedure test_mixedlen(rate : real) is
        variable dst    : mac_addr_t := rand_vec(48);
        variable src    : mac_addr_t := rand_vec(48);
        variable tag1   : vlan_hdr_t := rand_vec(16);
        variable tag2   : vlan_hdr_t := rand_vec(16);
        variable pkt1, pkt2 : eth_packet;
    begin
        -- Set default configuration = Tag1
        configure(VTAG_ADMIT_ALL, tag1);

        -- Series of three frames (short/long/short)
        pkt1 := make_eth_pkt(dst, src, ETYPE_IPV4, x"12345678");
        pkt2 := make_vlan_pkt(dst, src, tag2, ETYPE_IPV4, x"12345678");
        load_meta <= RESULT_COMMIT & tag2;  -- Meta = User-specified
        load(LOAD_IN,   pkt2.all);          -- Input = Tagged frame
        load(LOAD_REF,  pkt1.all);          -- Output = Input - tag
        pkt1 := make_eth_pkt(dst, src, ETYPE_IPV4, rand_vec(1024));
        load_meta <= RESULT_COMMIT & tag1;  -- Meta = Default
        load(LOAD_IN,   pkt1.all);          -- Input = Long untagged frame
        load(LOAD_REF,  pkt1.all);          -- Output = Input
        pkt1 := make_eth_pkt(dst, src, ETYPE_IPV4, x"90ABCDEF");
        pkt2 := make_vlan_pkt(dst, src, tag2, ETYPE_IPV4, x"90ABCDEF");
        load_meta <= RESULT_COMMIT & tag2;  -- Meta = User-specified
        load(LOAD_IN,   pkt2.all);          -- Input = Tagged frame
        load(LOAD_REF,  pkt1.all);          -- Output = Input - tag
        wait_done(rate, '0');

        -- Series of many short frames
        pkt1 := make_eth_pkt(dst, src, ETYPE_IPV4, x"");
        pkt2 := make_vlan_pkt(dst, src, tag2, ETYPE_IPV4, x"");
        load_meta <= RESULT_COMMIT & tag2;  -- Meta = User-specified
        load(LOAD_IN,   pkt2.all);          -- Input = Tagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input - tag
        load_meta <= RESULT_COMMIT & tag1;  -- Meta = Default
        load(LOAD_IN,   pkt1.all);          -- Input = Untagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input
        load_meta <= RESULT_COMMIT & tag2;  -- Meta = User-specified
        load(LOAD_IN,   pkt2.all);          -- Input = Tagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input - tag
        load_meta <= RESULT_COMMIT & tag1;  -- Meta = Default
        load(LOAD_IN,   pkt1.all);          -- Input = Untagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input
        load_meta <= RESULT_COMMIT & tag2;  -- Meta = User-specified
        load(LOAD_IN,   pkt2.all);          -- Input = Tagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input - tag
        load_meta <= RESULT_COMMIT & tag1;  -- Meta = Default
        load(LOAD_IN,   pkt1.all);          -- Input = Untagged
        load(LOAD_REF,  pkt1.all);          -- Output = Input
        wait_done(rate, '0');
    end procedure;

    -- Full test sequence
    procedure test_full(rate : real) is
    begin
        -- Run basic tests in each policy mode.
        test_policy(rate, VTAG_ADMIT_ALL);
        test_policy(rate, VTAG_PRIORITY);
        test_policy(rate, VTAG_MANDATORY);

        -- Test all possible truncated-tag edge cases.
        for n in 0 to 3 loop
            test_badtag(rate, n);
        end loop;

        -- Test consecutive short and long frames.
        test_mixedlen(rate);
    end procedure;
begin
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Run test sequence at various rates.
    test_full(1.0);
    test_full(0.5);
    test_full(0.1);

    report "Test completed, IO_BYTES = " & integer'image(IO_BYTES);
    test_done_i <= '1';
    wait;
end process;

test_done <= test_done_i;

end single;

--------------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

entity eth_frame_vstrip_tb is
    -- Testbench has no top-level I/O.
end eth_frame_vstrip_tb;

architecture tb of eth_frame_vstrip_tb is

-- Note: Default here only matters if we comment out some of the test blocks.
signal test_done : std_logic_vector(0 to 6) := (others => '1');

begin

uut1 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 1)
    port map(test_done => test_done(0));
uut2 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 2)
    port map(test_done => test_done(1));
uut3 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 3)
    port map(test_done => test_done(2));
uut5 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 5)
    port map(test_done => test_done(3));
uut8 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 8)
    port map(test_done => test_done(4));
uut13 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 13)
    port map(test_done => test_done(5));
uut16 : entity work.eth_frame_vstrip_tb_single
    generic map(IO_BYTES => 16)
    port map(test_done => test_done(6));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
