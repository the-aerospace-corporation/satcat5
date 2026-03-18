--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for SGMII shared logic (no SERDES)
--
-- This is a unit test for the platform independent ("common") section of the
-- SGMII interface.  It connects two such transceivers back-to-back to confirm
-- link establishment and data transfer capability.
--
-- The complete test takes about 1.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_sgmii_common_tb is
    -- Unit testbench top level, no I/O ports
end port_sgmii_common_tb;

architecture tb of port_sgmii_common_tb is

-- Number of packets before declaring "done".
constant NUM_TESTS          : integer := 4;
constant RX_PACKETS_1000    : integer := 200;
constant RX_PACKETS_100     : integer := 20;
constant TX_CFG_PHY_1000    : std_logic_vector(15 downto 0) := x"D801";
constant TX_CFG_PHY_100     : std_logic_vector(15 downto 0) := x"D401";

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal clk_250      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Simulate data sync recovery in Rx clock domain.
signal rxlock_a, rxlock_b   : std_logic := '0';
signal rxcken_a, rxcken_b   : std_logic := '0';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : array_tx_s2m(NUM_TESTS-1 downto 0);
signal txctrl_a, txctrl_b   : array_tx_m2s(NUM_TESTS-1 downto 0);
signal rxdata_a, rxdata_b   : array_rx_m2s(NUM_TESTS-1 downto 0);
signal rxdone_a, rxdone_b   : std_logic_vector(NUM_TESTS-1 downto 0);

-- Two units under test, connected back-to-back.
type array_sgmii_par_t is array(natural range<>) of std_logic_vector(9 downto 0);
signal sgmii_a2b, sgmii_b2a : array_sgmii_par_t(NUM_TESTS-1 downto 0);

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
clk_250 <= not clk_250 after 2 ns;
reset_p <= '0' after 1 us;

-- Simulate data sync recovery in Rx clock domain.
p_sync : process(clk_250)
    variable count_a, count_b : integer := 0;
begin
    if rising_edge(clk_250) then
        -- Out-of-phase alternating clock enables.
        rxcken_a <=     rxcken_b;
        rxcken_b <= not rxcken_b;

        -- Declare "lock" N clock cycles after reset.
        if (reset_p = '1') then
            count_a := 321;
        elsif (count_a > 0) then
            count_a := count_a - 1;
        end if;

        if (reset_p = '1') then
            count_b := 321;
        elsif (count_b > 0) then
            count_b := count_b - 1;
        end if;

        rxlock_a <= bool2bit(count_a = 0);
        rxlock_b <= bool2bit(count_b = 0);
    end if;
end process;

-- Test 1: MAC-to-MAC 1000 Mbps

-- Streaming source and sink for each link:
u_src_1a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a(0),
    txctrl  => txctrl_a(0),
    rxdata  => rxdata_b(0),
    rxdone  => rxdone_b(0),
    rxcount => RX_PACKETS_1000);

u_src_1b2a : entity work.port_test_common
    generic map(
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b(0),
    txctrl  => txctrl_b(0),
    rxdata  => rxdata_a(0),
    rxdone  => rxdone_a(0),
    rxcount => RX_PACKETS_1000);

-- Two units under test, connected back-to-back.
uut_1a : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true,
    TX_RATE_RST => get_rate_word(1000))
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_a2b(0),
    rx_clk      => clk_250,
    rx_cken     => rxcken_a,
    rx_lock     => rxlock_a,
    rx_data     => sgmii_b2a(0),
    prx_data    => rxdata_a(0),
    ptx_data    => txdata_a(0),
    ptx_ctrl    => txctrl_a(0),
    reset_p     => reset_p);

uut_1b : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_b2a(0),
    rx_clk      => clk_250,
    rx_cken     => rxcken_b,
    rx_lock     => rxlock_b,
    rx_data     => sgmii_a2b(0),
    prx_data    => rxdata_b(0),
    ptx_data    => txdata_b(0),
    ptx_ctrl    => txctrl_b(0),
    reset_p     => reset_p);

-- Test 2: MAC-to-MAC 100 Mbps

u_src_2a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a(1),
    txctrl  => txctrl_a(1),
    rxdata  => rxdata_b(1),
    rxdone  => rxdone_b(1),
    rxcount => RX_PACKETS_100);

u_src_2b2a : entity work.port_test_common
    generic map(
    DSEED1  => 91011,
    DSEED2  => 1213)
    port map(
    txdata  => txdata_b(1),
    txctrl  => txctrl_b(1),
    rxdata  => rxdata_a(1),
    rxdone  => rxdone_a(1),
    rxcount => RX_PACKETS_100);

uut_2a : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true,
    TX_RATE_RST => get_rate_word(100))
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_a2b(1),
    rx_clk      => clk_250,
    rx_cken     => rxcken_a,
    rx_lock     => rxlock_a,
    rx_data     => sgmii_b2a(1),
    prx_data    => rxdata_a(1),
    ptx_data    => txdata_a(1),
    ptx_ctrl    => txctrl_a(1),
    reset_p     => reset_p);

uut_2b : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_b2a(1),
    rx_clk      => clk_250,
    rx_cken     => rxcken_b,
    rx_lock     => rxlock_b,
    rx_data     => sgmii_a2b(1),
    prx_data    => rxdata_b(1),
    ptx_data    => txdata_b(1),
    ptx_ctrl    => txctrl_b(1),
    reset_p     => reset_p);

-- Test 3: PHY-to-MAC 1000 Mbps

u_src_3a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1415,
    DSEED2  => 1617)
    port map(
    txdata  => txdata_a(2),
    txctrl  => txctrl_a(2),
    rxdata  => rxdata_b(2),
    rxdone  => rxdone_b(2),
    rxcount => RX_PACKETS_1000);

u_src_3b2a : entity work.port_test_common
    generic map(
    DSEED1  => 1819,
    DSEED2  => 2021)
    port map(
    txdata  => txdata_b(2),
    txctrl  => txctrl_b(2),
    rxdata  => rxdata_a(2),
    rxdone  => rxdone_a(2),
    rxcount => RX_PACKETS_1000);

uut_3a : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true,
    TX_RATE_RST => get_rate_word(1000),
    TX_CFG_REG  => TX_CFG_PHY_1000)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_a2b(2),
    rx_clk      => clk_250,
    rx_cken     => rxcken_a,
    rx_lock     => rxlock_a,
    rx_data     => sgmii_b2a(2),
    prx_data    => rxdata_a(2),
    ptx_data    => txdata_a(2),
    ptx_ctrl    => txctrl_a(2),
    reset_p     => reset_p);

uut_3b : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => false)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_b2a(2),
    rx_clk      => clk_250,
    rx_cken     => rxcken_b,
    rx_lock     => rxlock_b,
    rx_data     => sgmii_a2b(2),
    prx_data    => rxdata_b(2),
    ptx_data    => txdata_b(2),
    ptx_ctrl    => txctrl_b(2),
    reset_p     => reset_p);

-- Test 1: PHY-to-MAC 100 Mbps

u_src_4a2b : entity work.port_test_common
    generic map(
    DSEED1  => 2223,
    DSEED2  => 2425)
    port map(
    txdata  => txdata_a(3),
    txctrl  => txctrl_a(3),
    rxdata  => rxdata_b(3),
    rxdone  => rxdone_b(3),
    rxcount => RX_PACKETS_100);

u_src_4b2a : entity work.port_test_common
    generic map(
    DSEED1  => 2627,
    DSEED2  => 2829)
    port map(
    txdata  => txdata_b(3),
    txctrl  => txctrl_b(3),
    rxdata  => rxdata_a(3),
    rxdone  => rxdone_a(3),
    rxcount => RX_PACKETS_100);

uut_4a : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => true,
    TX_RATE_RST => get_rate_word(100),
    TX_CFG_REG  => TX_CFG_PHY_100)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_a2b(3),
    rx_clk      => clk_250,
    rx_cken     => rxcken_a,
    rx_lock     => rxlock_a,
    rx_data     => sgmii_b2a(3),
    prx_data    => rxdata_a(3),
    ptx_data    => txdata_a(3),
    ptx_ctrl    => txctrl_a(3),
    reset_p     => reset_p);

uut_4b : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true,
    AUTO_RATE   => false)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_b2a(3),
    rx_clk      => clk_250,
    rx_cken     => rxcken_b,
    rx_lock     => rxlock_b,
    rx_data     => sgmii_a2b(3),
    prx_data    => rxdata_b(3),
    ptx_data    => txdata_b(3),
    ptx_ctrl    => txctrl_b(3),
    reset_p     => reset_p);

p_done : process
begin
    wait until (and_reduce(rxdone_a) = '1' and and_reduce(rxdone_b) = '1');
    report "Test completed.";
    wait;
end process;

end tb;
