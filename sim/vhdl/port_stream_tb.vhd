--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the AXI-stream transceiver port
--
-- This is a unit test for the adapter that converts AXI-stream to the
-- generic SatCat5 port format and vice-versa.  It tests several build-time
-- configurations for DELAY_REG, RX_HAS_FCS, and TX_HAS_FCS.
--
-- The complete test takes less than 0.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

-- Test a single build-time configuration.
entity port_stream_tb_single is
    generic (
    AXI_HAS_FCS : boolean := false;     -- Does AXI Tx/Rx data include FCS?
    DELAY_REG   : boolean := false;     -- Include a buffer register?
    RATE_MBPS   : integer := 1000);     -- Estimated/typical data rate
    port (test_done : out std_logic);
end port_stream_tb_single;

architecture port_stream_tb_single of port_stream_tb_single is

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- AXI stream is connected in loopback.
signal axi_data     : byte_t;
signal axi_last     : std_logic;
signal axi_valid    : std_logic;
signal axi_ready    : std_logic;

-- Network port
signal prx_data     : port_rx_m2s;
signal prx_dly      : port_rx_m2s := RX_M2S_IDLE;
signal ptx_data     : port_tx_s2m;
signal ptx_ctrl     : port_tx_m2s;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Test data source and verification.
u_src : entity work.port_test_common
    port map(
    txdata  => ptx_data,
    txctrl  => ptx_ctrl,
    rxdata  => prx_dly,
    rxdone  => test_done,
    rxcount => 100);

-- Unit under test with Tx/Rx in loopback.
uut : entity work.port_stream
    generic map(
    DELAY_REG   => DELAY_REG,       -- Set by user
    RX_MIN_FRM  => 0,               -- No padding (loopback mode)
    RX_HAS_FCS  => AXI_HAS_FCS,     -- Set by user
    TX_HAS_FCS  => AXI_HAS_FCS)     -- Must match (loopback mode)
    port map(
    rx_clk      => clk_100,
    rx_data     => axi_data,
    rx_last     => axi_last,
    rx_valid    => axi_valid,
    rx_ready    => axi_ready,
    rx_reset    => reset_p,
    tx_clk      => clk_100,
    tx_data     => axi_data,
    tx_last     => axi_last,
    tx_valid    => axi_valid,
    tx_ready    => axi_ready,
    tx_reset    => reset_p,
    prx_data    => prx_data,
    ptx_data    => ptx_data,
    ptx_ctrl    => ptx_ctrl);

-- Delay received data by a few clock cycles.
-- (The "port_test_common" block can't handle the zero-delay case.)
prx_dly.clk     <= prx_data.clk;
prx_dly.rxerr   <= prx_data.rxerr;
prx_dly.rate    <= prx_data.rate;
prx_dly.status  <= prx_data.status;
prx_dly.reset_p <= prx_data.reset_p;

p_dly : process(prx_data.clk)
    variable d1, d2 : byte_t := (others => '0');
    variable l1, l2 : std_logic := '0';
    variable w1, w2 : std_logic := '0';
begin
    if rising_edge(prx_data.clk) then
        prx_dly.data    <= d2;
        prx_dly.last    <= l2;
        prx_dly.write   <= w2;
        d2  := d1;
        l2  := l1;
        w2  := w1;
        d1  := prx_data.data;
        l1  := prx_data.last;
        w1  := prx_data.write;
    end if;
end process;

end port_stream_tb_single;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;

entity port_stream_tb is
    -- Unit testbench top level, no I/O ports
end port_stream_tb;

architecture tb of port_stream_tb is

signal test_done : std_logic_vector(3 downto 0);

begin

-- Instntiate each test configuration.
uut0 : entity work.port_stream_tb_single
    generic map(
    AXI_HAS_FCS => false,
    DELAY_REG   => false)
    port map (test_done => test_done(0));

uut1 : entity work.port_stream_tb_single
    generic map(
    AXI_HAS_FCS => false,
    DELAY_REG   => true)
    port map (test_done => test_done(1));

uut2 : entity work.port_stream_tb_single
    generic map(
    AXI_HAS_FCS => true,
    DELAY_REG   => false)
    port map (test_done => test_done(2));

uut3 : entity work.port_stream_tb_single
    generic map(
    AXI_HAS_FCS => true,
    DELAY_REG   => true)
    port map (test_done => test_done(3));

-- Give the "all tests completed" message once done.
p_done : process
begin
    wait until and_reduce(test_done) = '1';
    report "All tests completed!";
    wait;
end process;

end tb;
