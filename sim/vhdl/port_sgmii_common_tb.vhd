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
-- The complete test takes about 0.8 milliseconds.
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
constant RX_PACKETS : integer := 100;

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal clk_250      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Simulate data sync recovery in Rx clock domain.
signal rxlock_a, rxlock_b   : std_logic := '0';
signal rxcken_a, rxcken_b   : std_logic := '0';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal sgmii_a2b, sgmii_b2a : std_logic_vector(9 downto 0);

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

-- Streaming source and sink for each link:
u_src_a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a,
    txctrl  => txctrl_a,
    rxdata  => rxdata_b,
    rxdone  => rxdone_b,
    rxcount => RX_PACKETS);

u_src_b2a : entity work.port_test_common
    generic map(
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b,
    txctrl  => txctrl_b,
    rxdata  => rxdata_a,
    rxdone  => rxdone_a,
    rxcount => RX_PACKETS);

-- Two units under test, connected back-to-back.
uut_a : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_a2b,
    rx_clk      => clk_250,
    rx_cken     => rxcken_a,
    rx_lock     => rxlock_a,
    rx_data     => sgmii_b2a,
    prx_data    => rxdata_a,
    ptx_data    => txdata_a,
    ptx_ctrl    => txctrl_a,
    reset_p     => reset_p);

uut_b : entity work.port_sgmii_common
    generic map(
    SHAKE_WAIT  => true)
    port map(
    tx_clk      => clk_125,
    tx_data     => sgmii_b2a,
    rx_clk      => clk_250,
    rx_cken     => rxcken_b,
    rx_lock     => rxlock_b,
    rx_data     => sgmii_a2b,
    prx_data    => rxdata_b,
    ptx_data    => txdata_b,
    ptx_ctrl    => txctrl_b,
    reset_p     => reset_p);

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
