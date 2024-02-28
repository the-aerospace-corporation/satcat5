--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Ethernet-over-Serial UART port, 2-wire variant
--
-- This is a self-checking unit test for the Ethernet-over-Serial UART port.
-- It connects two transceivers back to back to confirm operation, with a
-- separate emulated controller to randomize flow-control.
--
-- The complete test takes about 470 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.all;

entity port_serial_uart_2wire_tb is
    -- Unit testbench top level, no I/O ports
end port_serial_uart_2wire_tb;

architecture tb of port_serial_uart_2wire_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 25;

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';
signal req_now      : std_logic := '0';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal uart_a2b, uart_b2a   : std_logic;

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

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
uut_a : entity work.port_serial_uart_2wire
    generic map(
    CLKREF_HZ   => 125000000,
    BAUD_HZ     => 921600)
    port map(
    uart_txd    => uart_a2b,
    uart_rxd    => uart_b2a,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    req_now     => req_now,
    refclk      => clk_125,
    reset_p     => reset_p);

uut_b : entity work.port_serial_uart_2wire
    generic map(
    CLKREF_HZ   => 125000000,
    BAUD_HZ     => 921600)
    port map(
    uart_txd    => uart_b2a,
    uart_rxd    => uart_a2b,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    refclk      => clk_125,
    reset_p     => reset_p);

-- High-level test control.
p_ctrl : process
begin
    -- Manually force the first query.
    -- After this, they should ping-pong back and forth forever.
    wait for 2 us;
    wait until rising_edge(clk_125);
    req_now <= '1';
    wait until rising_edge(clk_125);
    req_now <= '0';
    -- Print "done" message when both links have received N packets.
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
