--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for insertion of 802.1Q Virtual-LAN tags
--
-- This testbench generates a series of Ethernet frames with VLAN metadata,
-- and confirms the expected outputs under each possible VLAN tag-policy
-- configuration.
--
-- The complete test takes less than 0.8 milliseconds.
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

entity eth_frame_vtag_tb_single is
    generic (
    IO_BYTES    : positive;         -- Set pipeline width
    PORT_INDEX  : natural := 42);   -- Configuration address
    port (
    test_done   : out std_logic);
end eth_frame_vtag_tb_single;

architecture single of eth_frame_vtag_tb_single is

-- System clock and reset
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input stream
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_vtag      : vlan_hdr_t;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal in_nlast     : integer range 0 to IO_BYTES;

-- Reference stream
signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_valid    : std_logic;

-- Output stream
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic := '0';
signal out_next     : std_logic;

-- Test control.
constant LOAD_BYTES : positive := IO_BYTES;
signal cfg_cmd      : cfgbus_cmd;
signal rate_in      : real := 0.0;
signal rate_out     : real := 0.0;
signal load_data    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal load_vtag    : vlan_hdr_t := (others => '0');
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
u_ififo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => VLAN_HDR_WIDTH)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_meta         => load_vtag,
    in_write        => load_wr_in,
    out_clk         => clk100,
    out_data        => in_data,
    out_nlast       => in_nlast,
    out_meta        => in_vtag,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_rate        => rate_in,
    reset_p         => reset_p);

u_rfifo : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES)
    port map(
    in_clk          => clk100,
    in_data         => load_data,
    in_nlast        => load_nlast,
    in_write        => load_wr_ref,
    out_clk         => clk100,
    out_data        => ref_data,
    out_nlast       => ref_nlast,
    out_valid       => ref_valid,
    out_ready       => out_next,
    reset_p         => reset_p);

-- Flow-control randomization.
out_next <= out_valid and out_ready;

p_flow : process(clk100)
begin
    if rising_edge(clk100) then
        out_ready <= rand_bit(rate_out);
    end if;
end process;

-- Unit under test.
uut : entity work.eth_frame_vtag
    generic map(
    DEV_ADDR    => CFGBUS_ADDR_ANY,
    REG_ADDR    => CFGBUS_ADDR_ANY,
    PORT_INDEX  => PORT_INDEX,
    IO_BYTES    => IO_BYTES)
    port map(
    in_data     => in_data,
    in_vtag     => in_vtag,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    cfg_cmd     => cfg_cmd,
    clk         => clk100,
    reset_p     => reset_p);

-- Verify outputs.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (out_next = '1' and ref_valid = '1') then
            assert (out_data = ref_data)
                report "DATA mismatch." severity error;
            assert (out_nlast = ref_nlast)
                report "NLAST mismatch." severity error;
        elsif (out_next = '1') then
            report "Unexpected output data." severity error;
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
    -- Mask for nulling the VID field in a VLAN tag.
    constant VID_MASK : vlan_hdr_t := "1111000000000000";

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
    procedure wait_done(rate : real) is
        variable idle_count : natural := 0;
    begin
        -- Wait a few clock cycles for all FIFOs to be ready.
        for n in 1 to 10 loop
            wait until rising_edge(clk100);
        end loop;
        -- Start transmission of test data.
        rate_in  <= 1.0;
        rate_out <= rate;
        -- Wait until N consecutive idle cycles.
        while (idle_count < 100) loop
            wait until rising_edge(clk100);
            if (in_valid = '1' or out_valid = '1') then
                idle_count := 0;
            else
                idle_count := idle_count + 1;
            end if;
        end loop;
        -- Post-test cleanup.
        assert (ref_valid = '0')
            report "Output too short" severity error;
        rate_in  <= 0.0;
        rate_out <= 0.0;
    end procedure;

    -- Write to ConfigBus register.
    procedure configure(vtag_policy : tag_policy_t) is
        constant cmd_word : cfgbus_word :=
            i2s(PORT_INDEX, 8) & "00" & vtag_policy & i2s(0, 20);
    begin
        cfgbus_write(cfg_cmd, 0, 0, cmd_word);
    end procedure;

    -- Generate and load input and reference packets.
    procedure load_pkt(policy : tag_policy_t; data : std_logic_vector) is
        -- Randomize header fields.
        variable dst    : mac_addr_t := rand_vec(48);
        variable src    : mac_addr_t := rand_vec(48);
        variable tag    : vlan_hdr_t := rand_vec(16);
        -- Construct untagged, full-tagged, and priority-tagged packets.
        variable pkt1   : eth_packet :=
            make_eth_pkt(dst, src, ETYPE_IPV4, data);
        variable pkt2   : eth_packet :=
            make_vlan_pkt(dst, src, tag, ETYPE_IPV4, data);
        variable pkt3   : eth_packet :=
            make_vlan_pkt(dst, src, tag and VID_MASK, ETYPE_IPV4, data);
    begin
        -- Input is always the untagged packet.
        load_vtag <= tag;               -- Frame metadata
        load(LOAD_IN, pkt1.all);        -- Input = Untagged

        -- Expected output depends on policy.
        if (policy = VTAG_ADMIT_ALL) then
            load(LOAD_REF, pkt1.all);   -- Output = Untagged
        elsif (policy = VTAG_MANDATORY) then
            load(LOAD_REF, pkt2.all);   -- Output = Full tag
        else
            load(LOAD_REF, pkt3.all);   -- Output = Priority only
        end if;
    end procedure;

    -- Stress-tests with a mixture of very short and long frames.
    procedure test_policy(rate : real; policy : tag_policy_t) is
    begin
        -- Set policy for subsequent tests.
        configure(policy);

        -- Series of three frames (short/long/short)
        load_pkt(policy, x"12345678");
        load_pkt(policy, rand_vec(1024));
        load_pkt(policy, x"90ABCDEF");
        wait_done(rate);

        -- Series of many short frames
        for n in 0 to 32 loop
            load_pkt(policy, rand_vec(8*n));
        end loop;
        wait_done(rate);
    end procedure;

    -- Full test sequence
    procedure test_full(rate : real) is
    begin
        -- Run basic tests in each policy mode.
        test_policy(rate, VTAG_ADMIT_ALL);
        test_policy(rate, VTAG_PRIORITY);
        test_policy(rate, VTAG_MANDATORY);
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

entity eth_frame_vtag_tb is
    -- Testbench has no top-level I/O.
end eth_frame_vtag_tb;

architecture tb of eth_frame_vtag_tb is

-- Note: Default here only matters if we comment out some of the test blocks.
signal test_done : std_logic_vector(0 to 6) := (others => '1');

begin

uut1 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 1)
    port map(test_done => test_done(0));
uut2 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 2)
    port map(test_done => test_done(1));
uut3 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 3)
    port map(test_done => test_done(2));
uut5 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 5)
    port map(test_done => test_done(3));
uut8 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 8)
    port map(test_done => test_done(4));
uut13 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 13)
    port map(test_done => test_done(5));
uut16 : entity work.eth_frame_vtag_tb_single
    generic map(IO_BYTES => 16)
    port map(test_done => test_done(6));

p_done : process(test_done)
begin
    if (and_reduce(test_done) = '1') then
        report "All tests completed!";
    end if;
end process;

end tb;
