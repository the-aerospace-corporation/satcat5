--------------------------------------------------------------------------
-- Copyright 2020-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the inline status-injection block
--
-- This testbench pushes random traffic through the port_inline_status block
-- in each direction, and confirms that those packets are received intact
-- along with the newly injected status frames.
--
-- The complete test sequence takes just under 4.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_inline_status_tb is
    generic (
    SEND_EGRESS     : boolean := true;
    SEND_INGRESS    : boolean := true);
    -- Unit testbench, no I/O ports.
end port_inline_status_tb;

architecture tb of port_inline_status_tb is

-- For simplicity, test message is static.
constant MSG_BYTES      : integer := 8;
constant MSG_ETYPE      : mac_type_t := x"5C00";
constant MAC_DEST       : mac_addr_t := x"FFFFFFFFFFFF";
constant MAC_SOURCE     : mac_addr_t := x"5A5ADEADBEEF";
constant MSG_DATA       : std_logic_vector(8*MSG_BYTES-1 downto 0) := x"0123456789ABCDEF";

-- Convert bool to integer (0/1)
function b2i(x : boolean) return natural is
begin
    if (x) then
        return 1;
    else
        return 0;
    end if;
end function;

-- Clock and reset generation
signal clk_100          : std_logic := '0';
signal clk_102          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Unit under test
signal lcl_tx_temp      : port_rx_m2s;
signal lcl_tx_valid     : std_logic;
signal lcl_tx_ready     : std_logic;
signal lcl_rx_data      : port_rx_m2s;  -- Ingress data out
signal lcl_tx_data      : port_tx_s2m;  -- Egress data in
signal lcl_tx_ctrl      : port_tx_m2s;
signal net_rx_data      : port_rx_m2s;  -- Ingress data in
signal net_tx_data      : port_tx_s2m;  -- Egress data out
signal net_tx_ctrl      : port_tx_m2s;

-- Frame-check sequence
signal net_tx_write     : std_logic;
signal out_eg_data      : byte_t;
signal out_eg_write     : std_logic;
signal out_eg_commit    : std_logic;
signal out_eg_revert    : std_logic;
signal out_ig_data      : byte_t;
signal out_ig_write     : std_logic;
signal out_ig_commit    : std_logic;
signal out_ig_revert    : std_logic;

-- Overall test control
signal test_rate_in     : real := 0.0;
signal test_rate_out    : real := 0.0;
signal test_count_rst   : std_logic := '0';
signal eg_count_pri     : integer := 0;
signal eg_count_aux     : integer := 0;
signal ig_count_pri     : integer := 0;
signal ig_count_aux     : integer := 0;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5.0 ns;
clk_102 <= not clk_102 after 4.9 ns;
reset_p <= '0' after 1 us;

-- Baseline traffic generation.
u_gen_eg : entity work.eth_traffic_sim
    generic map(
    INIT_SEED1          => 17501785,
    INIT_SEED2          => 57082951)
    port map(
    clk                 => clk_100,
    reset_p             => reset_p,
    pkt_etype           => true,
    mac_dst             => x"AA",   -- Destination (repeat 6x)
    mac_src             => x"BB",   -- Source (repeat 6x)
    out_rate            => test_rate_in,
    out_port            => lcl_tx_temp,
    out_bcount          => open,
    out_valid           => lcl_tx_valid,
    out_ready           => lcl_tx_ready);

u_gen_ig : entity work.eth_traffic_sim
    generic map(
    INIT_SEED1          => 85018771,
    INIT_SEED2          => 13287401)
    port map(
    clk                 => clk_102,
    reset_p             => reset_p,
    pkt_etype           => true,
    mac_dst             => x"BB",   -- Destination (repeat 6x)
    mac_src             => x"AA",   -- Source (repeat 6x)
    out_rate            => test_rate_in,
    out_port            => net_rx_data,
    out_bcount          => open,
    out_valid           => open,
    out_ready           => open);

-- Format conversion for "lcl_rx_temp"
-- (Some care required to avoid clock-to-data simulation artifacts.)
net_tx_ctrl.clk     <= lcl_tx_temp.clk;
lcl_tx_data.data    <= lcl_tx_temp.data;
lcl_tx_data.last    <= lcl_tx_temp.last;
lcl_tx_data.valid   <= lcl_tx_valid;
lcl_tx_ready        <= lcl_tx_ctrl.ready;
net_tx_ctrl.pstart  <= '1';
net_tx_ctrl.tnow    <= lcl_tx_temp.tsof;
net_tx_ctrl.txerr   <= lcl_tx_temp.rxerr;
net_tx_ctrl.reset_p <= lcl_tx_temp.reset_p;

-- Unit under test
uut : entity work.port_inline_status
    generic map(
    SEND_EGRESS     => SEND_EGRESS,
    SEND_INGRESS    => SEND_INGRESS,
    MSG_BYTES       => MSG_BYTES,
    MSG_ETYPE       => MSG_ETYPE,
    MAC_DEST        => MAC_DEST,
    MAC_SOURCE      => MAC_SOURCE,
    AUTO_DELAY_CLKS => 1000)
    port map(
    lcl_rx_data     => lcl_rx_data,
    lcl_tx_data     => lcl_tx_data,
    lcl_tx_ctrl     => lcl_tx_ctrl,
    net_rx_data     => net_rx_data,
    net_tx_data     => net_tx_data,
    net_tx_ctrl     => net_tx_ctrl,
    status_val      => MSG_DATA);

-- Flow-control randomization.
p_flow : process(net_tx_ctrl.clk)
    variable seed1  : positive := 57109;
    variable seed2  : positive := 87150;
    variable rand   : real := 0.0;
begin
    if rising_edge(net_tx_ctrl.clk) then
        uniform(seed1, seed2, rand);
        net_tx_ctrl.ready <= bool2bit(rand < test_rate_out);
    end if;
end process;

-- Verify frame-check sequence (FCS).
net_tx_write <= net_tx_data.valid and net_tx_ctrl.ready;
u_fcs_eg : entity work.eth_frame_check
    generic map(
    ALLOW_RUNT  => true,
    STRIP_FCS   => true)
    port map(
    in_data     => net_tx_data.data,
    in_last     => net_tx_data.last,
    in_write    => net_tx_write,
    out_data    => out_eg_data,
    out_write   => out_eg_write,
    out_commit  => out_eg_commit,
    out_revert  => out_eg_revert,
    clk         => net_tx_ctrl.clk,
    reset_p     => net_tx_ctrl.reset_p);

u_fcs_ig : entity work.eth_frame_check
    generic map(
    ALLOW_RUNT  => true,
    STRIP_FCS   => true)
    port map(
    in_data     => lcl_rx_data.data,
    in_last     => lcl_rx_data.last,
    in_write    => lcl_rx_data.write,
    out_data    => out_ig_data,
    out_write   => out_ig_write,
    out_commit  => out_ig_commit,
    out_revert  => out_ig_revert,
    clk         => lcl_rx_data.clk,
    reset_p     => lcl_rx_data.reset_p);

-- Count the number of valid packets of each type.
-- (Byte-for-byte checks already covered at the unit level.)
p_count_eg : process(net_tx_ctrl.clk)
    variable bcount : integer := 0;
    variable is_pri, is_aux : boolean := false;
begin
    if rising_edge(net_tx_ctrl.clk) then
        -- Check for error strobes.
        assert (out_eg_revert = '0') report "EG-FCS error" severity error;
        assert (lcl_tx_ctrl.txerr = '0') report "EG-PHY error" severity error;

        -- Count packets of each type.
        if (test_count_rst = '1') then
            eg_count_pri <= 0;
            eg_count_aux <= 0;
        elsif (out_eg_write = '1' and (out_eg_commit = '1' or out_eg_revert = '1')) then
            eg_count_pri <= eg_count_pri + b2i(is_pri);
            eg_count_aux <= eg_count_aux + b2i(is_aux);
        end if;

        -- Filter by Ethertype:
        if (out_eg_write = '1' and bcount = 12) then
            is_pri := (out_eg_data = x"EE");
            is_aux := (out_eg_data = x"5C");
        end if;

        -- Update per-packet byte count.
        if (reset_p = '1') then
            bcount := 0;                -- Global reset
        elsif (out_eg_write = '1') then
            if (out_eg_commit = '1' or out_eg_revert = '1') then
                bcount := 0;            -- End of frame
            else
                bcount := bcount + 1;   -- Next data byte
            end if;
        end if;
    end if;
end process;

p_count_ig : process(lcl_rx_data.clk)
    variable bcount : integer := 0;
    variable is_pri, is_aux : boolean := false;
begin
    if rising_edge(lcl_rx_data.clk) then
        -- Check for error strobes.
        assert (out_ig_revert = '0') report "IG-FCS error" severity error;
        assert (lcl_rx_data.rxerr = '0') report "IG-PHY error" severity error;

        -- Count packets of each type.
        if (test_count_rst = '1') then
            ig_count_pri <= 0;
            ig_count_aux <= 0;
        elsif (out_ig_write = '1' and (out_ig_commit = '1' or out_ig_revert = '1')) then
            ig_count_pri <= ig_count_pri + b2i(is_pri);
            ig_count_aux <= ig_count_aux + b2i(is_aux);
        end if;

        -- Filter by Ethertype:
        if (out_ig_write = '1' and bcount = 12) then
            is_pri := (out_ig_data = x"EE");
            is_aux := (out_ig_data = x"5C");
        end if;

        -- Update per-packet byte count.
        if (reset_p = '1') then
            bcount := 0;                -- Global reset
        elsif (out_ig_write = '1') then
            if (out_ig_commit = '1' or out_ig_revert = '1') then
                bcount := 0;            -- End of frame
            else
                bcount := bcount + 1;   -- Next data byte
            end if;
        end if;
    end if;
end process;

-- Overall test control.
p_test : process
begin
    wait until falling_edge(reset_p);
    for n in 2 to 9 loop
        -- Set test conditions and reset counters.
        report "Starting test #" & integer'image(n);
        test_rate_in    <= real(n) / 10.0;
        test_rate_out   <= 1.0;
        test_count_rst  <= '1';
        wait for 100 ns;
        test_count_rst  <= '0';

        -- After a delay, check counters.
        wait for 499 us;

        if (SEND_EGRESS) then
            assert (eg_count_pri > eg_count_aux and eg_count_aux > 0)
                report "Egress packet-count error." severity error;
        else
            assert (eg_count_aux = 0)
                report "Unexpected egress packets." severity error;
        end if;

        if (SEND_INGRESS) then
            assert (ig_count_pri > ig_count_aux and ig_count_aux > 0)
                report "Ingress packet-count error." severity error;
        else
            assert (ig_count_aux = 0)
                report "Unexpected ingress packets." severity error;
        end if;
    end loop;
    report "All tests finished.";
    wait;
end process;

end tb;
