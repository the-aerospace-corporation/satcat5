--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Testbench for the Virtual-LAN rate-limiter block
--
-- This testbench configures a VLAN rate-limiter block, and confirms
-- that the it correctly executes the "token bucket" algorithm even
-- in high-throughput corner cases.
--
-- The complete test takes less than 1.8 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity mac_vlan_rate_tb is
    generic(
    ACCUM_WIDTH : positive := 16;
    IO_BYTES    : positive := 64;
    PORT_COUNT  : positive := 8;
    VID_MAX     : positive := 15);
    -- Testbench has no top-level I/O.
end mac_vlan_rate_tb;

architecture tb of mac_vlan_rate_tb is

constant MODE_UNLIM  : natural := 0;
constant MODE_DEMOTE : natural := 1;
constant MODE_STRICT : natural := 2;
constant MODE_AUTO   : natural := 3;

subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- Clock and reset generation
signal clk100       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Input, reference, and output streams.
signal in_vtag      : vlan_hdr_t := (others => '0');
signal in_nlast     : integer range 0 to IO_BYTES := 0;
signal in_write     : std_logic := '0';
signal ref_pmask    : port_mask_t;
signal ref_himask   : std_logic;
signal ref_valid    : std_logic;
signal out_pmask    : port_mask_t;
signal out_himask   : std_logic;
signal out_next     : std_logic;

-- Configuration interface (write-only).
signal cfg_cmd      : cfgbus_cmd;
signal debug_scan   : std_logic;
signal test_index   : natural := 0;
signal test_write   : std_logic := '0';
signal test_pmask   : std_logic := '0';
signal test_himask  : std_logic := '0';
signal test_ptemp   : port_mask_t;

begin

-- Clock and reset generation
clk100 <= not clk100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
cfg_cmd.clk <= clk100;

-- Unit under test
-- Note: Scale reported clock frequency 10x for accelerated testing.
--  (i.e., Credits accrue every 100 usec instead of every millisecond.)
uut : entity work.mac_vlan_rate
    generic map(
    DEV_ADDR    => CFGBUS_ADDR_ANY,
    REG_ADDR    => CFGBUS_ADDR_ANY,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    CORE_CLK_HZ => 10_000_000,
    ACCUM_WIDTH => ACCUM_WIDTH,
    SIM_STRICT  => true)
    port map(
    in_vtag     => in_vtag,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_pmask   => out_pmask,
    out_himask  => out_himask,
    out_valid   => out_next,
    out_ready   => '1',
    debug_scan  => debug_scan,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => open,
    clk         => clk100,
    reset_p     => reset_p);

-- Check output against reference.
p_check : process(clk100)
begin
    if rising_edge(clk100) then
        if (out_next = '1') then
            assert (ref_valid = '1')
                report "Unexpected output" severity error;
            assert (out_pmask = ref_pmask)
                report "PMASK mismatch" severity error;
            assert (out_himask = ref_himask)
                report "HIMASK mismatch" severity error;
        end if;
    end if;
end process;

test_ptemp <= (others => test_pmask);

u_ref_fifo : entity work.fifo_smol_sync
    generic map(
    DEPTH_LOG2  => 6,
    IO_WIDTH    => PORT_COUNT)
    port map(
    in_data     => test_ptemp,
    in_last     => test_himask,
    in_write    => test_write,
    out_data    => ref_pmask,
    out_last    => ref_himask,
    out_valid   => ref_valid,
    out_read    => out_next,
    clk         => clk100,
    reset_p     => reset_p);

-- High-level test control.
p_test : process
    -- Store the current state for each token bucket.
    type param_array is array(0 to VID_MAX) of natural;
    variable cfg_count  : param_array := (others => 0);
    variable cfg_mode   : param_array := (others => 0);
    variable cfg_rate   : param_array := (others => 0);
    variable cfg_rmax   : param_array := (others => 0);
    variable cfg_scale  : param_array := (others => 0);

    -- Other temporary variables.
    variable tmp_dei    : natural := 0;
    variable tmp_vid    : natural := 0;
    variable tmp_len    : natural := 0;

    -- Convert length to cost based on scale setting.
    impure function get_cost(vid, len: natural) return positive is
        variable scale : positive := 2**cfg_scale(vid);
    begin
        return (len + scale - 1) / scale;
    end function;

    -- Configure the designated VID.
    procedure configure(vid, mode, rate, rmax, scale: natural) is
        variable cfg : cfgbus_word :=
            "10" & i2s(mode,2) & i2s(scale,4) & i2s(vid,24);
    begin
        -- Sanity check before we start...
        assert (vid < VID_MAX);
        assert (mode < 4);
        assert (rate < 2**ACCUM_WIDTH);
        assert (rmax < 2**ACCUM_WIDTH);
        assert (scale = 0 or scale = 8);
        -- Copy the new setting to the test state.
        cfg_mode(vid)   := mode;
        cfg_rate(vid)   := rate;
        cfg_rmax(vid)   := rmax;
        cfg_scale(vid)  := scale;
        -- Write the new setting to the unit under test.
        cfgbus_write(cfg_cmd, 0, 0, i2s(rate, 32));
        cfgbus_write(cfg_cmd, 0, 0, i2s(rmax, 32));
        cfgbus_write(cfg_cmd, 0, 0, cfg);
    end procedure;

    -- Wait for unit under test to distribute new tokens,
    -- then update our expected test state accordingly.
    procedure refresh is
    begin
        wait until rising_edge(clk100) and debug_scan = '1';
        wait until rising_edge(clk100) and debug_scan = '0';
        for n in 0 to VID_MAX loop
            cfg_count(n) := int_min(cfg_rmax(n), cfg_count(n) + cfg_rate(n));
        end loop;
    end procedure;

    -- Load a reference packet with the designated parameters,
    -- automatically predicting the expected outputs.
    procedure load_ref(dei, vid, len: natural) is
        variable cost : positive := get_cost(vid, len);
        variable mode : natural := cfg_mode(vid);
    begin
        assert (vid < VID_MAX);
        -- How should we handle this packet?
        if (cost <= cfg_count(vid)) then
            cfg_count(vid) := cfg_count(vid) - cost;
            test_pmask  <= '1';
            test_himask <= '1'; -- Normal case (rate limit OK)
        elsif (mode = MODE_UNLIM) then
            test_pmask  <= '1';
            test_himask <= '1'; -- Allow anyway (unlimited)
        elsif (mode = MODE_DEMOTE) then
            test_pmask  <= '1';
            test_himask <= '0'; -- Reduce priority (demote)
        elsif (mode = MODE_STRICT) then
            test_pmask  <= '0';
            test_himask <= '0'; -- Drop packet (strict)
        elsif (mode = MODE_AUTO) then
            test_pmask  <= bool2bit(dei = 0);
            test_himask <= '0'; -- Demote or strict based on DEI
        end if;
        -- Write this result to the reference FIFO.
        test_write  <= '1';
        wait until rising_edge(clk100);
        test_write  <= '0';
    end procedure;

    -- Send a packet with the designated parameters.
    procedure send_pkt(dei, vid, len: natural) is
        variable vlan_dei : vlan_dei_t := bool2bit(dei > 0);
        variable vlan_vid : vlan_vid_t := to_unsigned(vid, 12);
        variable rem_bytes : natural := len;
    begin
        in_vtag  <= vlan_get_hdr(PCP_NONE, vlan_dei, vlan_vid);
        in_write <= '1';
        while (rem_bytes > 0) loop
            if (rem_bytes > IO_BYTES) then
                in_nlast  <= 0;
                rem_bytes := rem_bytes - IO_BYTES;
            else
                in_nlast  <= rem_bytes;
                rem_bytes := 0;
            end if;
            wait until rising_edge(clk100);
        end loop;
        in_vtag  <= (others => '0');
        in_nlast <= 0;
        in_write <= '0';
    end procedure;

    -- Cleanup after each test segment.
    procedure test_cleanup is
    begin
        wait for 1 us;
        assert (ref_valid = '0')
            report "Missing query result(s)." severity error;
        test_index <= test_index + 1;
    end procedure;

    -- The first four VIDs are used to test rapidly-interleaved
    -- sequences of packets, so threshold is linked to IO_BYTES.
    constant ONE_PKT : positive := IO_BYTES;
begin
    -- Load initial configuration.
    -- VID 1..7 are configured with various limits.  8+ = Unlimited.
    cfgbus_reset(cfg_cmd);
    wait for 1 us;
    configure(1, MODE_STRICT, ONE_PKT, ONE_PKT, 0);
    configure(2, MODE_STRICT, ONE_PKT, ONE_PKT, 0);
    configure(3, MODE_STRICT, ONE_PKT, ONE_PKT, 0);
    configure(4, MODE_STRICT, ONE_PKT, ONE_PKT, 0);
    configure(5, MODE_STRICT, 100, 200, 8);
    configure(6, MODE_DEMOTE, 500, 500, 0);
    configure(7, MODE_AUTO,   500, 500, 0);

    -- Simple test: For each VID 1-4, send two short packets.
    -- The first should be allowed, and the second should be dropped.
    refresh;
    for n in 1 to 4 loop
        load_ref(0, n, IO_BYTES);
        assert (test_pmask = '1' and test_himask = '1');
        load_ref(0, n, IO_BYTES);
        assert (test_pmask = '0' and test_himask = '0');
    end loop;
    for n in 1 to 4 loop
        send_pkt(0, n, IO_BYTES);
        send_pkt(0, n, IO_BYTES);
    end loop;
    test_cleanup;

    -- Quick test of demote mode; no need to wait for refresh.
    load_ref(0, 6, 256);
    assert (test_pmask = '1' and test_himask = '1');
    load_ref(0, 6, 256);
    assert (test_pmask = '1' and test_himask = '0');
    send_pkt(0, 6, 256);
    send_pkt(0, 6, 256);
    test_cleanup;

    -- Quick test of auto mode (DEI = 0).
    load_ref(0, 7, 256);
    assert (test_pmask = '1' and test_himask = '1');
    load_ref(0, 7, 256);
    assert (test_pmask = '1' and test_himask = '0');
    send_pkt(0, 7, 256);
    send_pkt(0, 7, 256);
    test_cleanup;

    -- Back-to-back test: For each VID 1-4, rapidly send three short packets.
    refresh;
    for n in 1 to 4 loop
        load_ref(0, n, IO_BYTES/2);
        load_ref(0, n, IO_BYTES/2);
        load_ref(0, n, IO_BYTES/2);
    end loop;
    for n in 1 to 4 loop
        send_pkt(0, n, IO_BYTES/2);
        send_pkt(0, n, IO_BYTES/2);
        send_pkt(0, n, IO_BYTES/2);
    end loop;
    test_cleanup;

    -- Interleaved A/B/A/B test, followed by another auto test.
    refresh;
    load_ref(1, 1, IO_BYTES);
    load_ref(1, 2, IO_BYTES);
    load_ref(1, 1, IO_BYTES);
    load_ref(1, 2, IO_BYTES);
    send_pkt(1, 1, IO_BYTES);
    send_pkt(1, 2, IO_BYTES);
    send_pkt(1, 1, IO_BYTES);
    send_pkt(1, 2, IO_BYTES);
    test_cleanup;

    -- Quick test of demote mode.
    load_ref(1, 6, 256);
    assert (test_pmask = '1' and test_himask = '1');
    load_ref(1, 6, 256);
    assert (test_pmask = '1' and test_himask = '0');
    send_pkt(1, 6, 256);
    send_pkt(1, 6, 256);
    test_cleanup;

    -- Quick test of auto mode (DEI = 1).
    load_ref(1, 7, 256);
    assert (test_pmask = '1' and test_himask = '1');
    load_ref(1, 7, 256);
    assert (test_pmask = '0' and test_himask = '0');
    send_pkt(1, 7, 256);
    send_pkt(1, 7, 256);
    test_cleanup;

    -- Interleaved A/B/C/A/B/C test.
    refresh;
    load_ref(0, 1, IO_BYTES);
    load_ref(0, 2, IO_BYTES);
    load_ref(0, 3, IO_BYTES);
    load_ref(0, 1, IO_BYTES);
    load_ref(0, 2, IO_BYTES);
    load_ref(0, 3, IO_BYTES);
    send_pkt(0, 1, IO_BYTES);
    send_pkt(0, 2, IO_BYTES);
    send_pkt(0, 3, IO_BYTES);
    send_pkt(0, 1, IO_BYTES);
    send_pkt(0, 2, IO_BYTES);
    send_pkt(0, 3, IO_BYTES);
    test_cleanup;

    -- Interleaved A/B/C/D/A/B/C/D test.
    refresh;
    load_ref(0, 1, IO_BYTES);
    load_ref(0, 2, IO_BYTES);
    load_ref(0, 3, IO_BYTES);
    load_ref(0, 4, IO_BYTES);
    load_ref(0, 1, IO_BYTES);
    load_ref(0, 2, IO_BYTES);
    load_ref(0, 3, IO_BYTES);
    load_ref(0, 4, IO_BYTES);
    send_pkt(0, 1, IO_BYTES);
    send_pkt(0, 2, IO_BYTES);
    send_pkt(0, 3, IO_BYTES);
    send_pkt(0, 4, IO_BYTES);
    send_pkt(0, 1, IO_BYTES);
    send_pkt(0, 2, IO_BYTES);
    send_pkt(0, 3, IO_BYTES);
    send_pkt(0, 4, IO_BYTES);
    test_cleanup;

    -- Quick test of an unlimited VID.
    for n in 1 to 60 loop
        load_ref(0, 8, IO_BYTES);
        assert (test_pmask = '1' and test_himask = '1');
    end loop;
    for n in 1 to 60 loop
        send_pkt(0, 8, IO_BYTES);
    end loop;
    test_cleanup;

    -- Run the scaled test (VID=5) to exhaustion.
    -- (4 tokens each --> 50 packets from initial state.)
    refresh;
    for n in 1 to 60 loop
        load_ref(0, 5, 1024);
    end loop;
    for n in 1 to 60 loop
        send_pkt(0, 5, 1024);
    end loop;
    test_cleanup;

    -- Repeat the test but with slightly longer packets.
    -- (5 tokens each --> 20 more packets after a refresh.)
    refresh;
    for n in 1 to 25 loop
        load_ref(0, 5, 1025);
    end loop;
    for n in 1 to 25 loop
        send_pkt(0, 5, 1025);
    end loop;
    test_cleanup;

    -- Randomized test sequences.
    for iter in 1 to 10 loop
        refresh;
        for pkt in 1 to 20 loop
            tmp_dei := rand_int(2);
            tmp_vid := rand_int(9);
            tmp_len := rand_int(1024);
            load_ref(tmp_dei, tmp_vid, tmp_len);
            send_pkt(tmp_dei, tmp_vid, tmp_len);
        end loop;
        test_cleanup;
    end loop;

    report "All tests completed!";
end process;

end tb;
