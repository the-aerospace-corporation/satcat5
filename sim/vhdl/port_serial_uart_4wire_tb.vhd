--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for Ethernet-over-Serial UART port, 4-wire variant
--
-- This is a self-checking unit test for the Ethernet-over-Serial UART port.
-- It connects two transceivers back to back to confirm operation, with a
-- separate emulated controller to randomize flow-control.
--
-- The complete test takes about 700 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.all;

entity port_serial_uart_4wire_tb is
    -- Unit testbench top level, no I/O ports
end port_serial_uart_4wire_tb;

architecture tb of port_serial_uart_4wire_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 50;

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal uart_a2b, uart_b2a   : std_logic;
signal uart_rtsa_n          : std_logic;
signal uart_rtsb_n          : std_logic;
signal uart_cts_n           : std_logic := '1';

-- Countdown to next flow-control change.
signal  flow_ctr   : integer := 0;

-- Countdowns related to flow-control rules check.
signal  idle_ctra  : integer := 0;
signal  idle_ctrb  : integer := 0;
signal  stop_ctr   : integer := 0;

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Flow control randomization and rules check.
p_uart_control: process(clk_125)
    -- PRNG state:
    variable  seed1      : positive := 1234;
    variable  seed2      : positive := 5678;
    variable  rand       : real := 0.0;
begin
    if rising_edge(clk_125) then
        -- Toggle the CTS signal at random intervals.
        if (reset_p = '1') then
            -- Reset always enters "halt" state.
            uart_cts_n  <= '1';
            flow_ctr    <= 1000;
        elsif (flow_ctr > 0) then
            -- Countdown to next state change.
            flow_ctr    <= flow_ctr - 1;
        elsif (uart_cts_n = '1') then
            -- Entering "run" state, set random duration.
            -- Note: One byte at 921600 baud = 1400 clock cycles
            uniform(seed1, seed2, rand);
            uart_cts_n  <= '0';
            flow_ctr    <= 20000 + integer(floor(40000.0 * rand));
        else
            -- Entering "halt" state, set random duration.
            uniform(seed1, seed2, rand);
            uart_cts_n  <= '1';
            flow_ctr    <= 10000 + integer(floor(10000.0 * rand));
        end if;

        -- Confirm prompt service when CTS_n = '0' and RTS_n = '0'.
        -- (Track each UART separately.)
        if (uart_a2b = '1' and uart_cts_n = '0' and uart_rtsa_n = '0') then
            assert (idle_ctra /= 2500)
                report "Excess idle-time violation on UART-A2B." severity error;
            idle_ctra <= idle_ctra + 1;
        else
            idle_ctra <= 0; -- Reset counter on UART activity or flow-control stop.
        end if;

        if (uart_b2a = '1' and uart_cts_n = '0' and uart_rtsb_n = '0') then
            assert (idle_ctrb /= 2500)
                report "Excess idle-time violation on UART-B2A." severity error;
            idle_ctrb <= idle_ctrb + 1;
        else
            idle_ctrb <= 0; -- Reset counter on UART activity or flow-control stop.
        end if;

        -- Confirm output halts promptly prompt when CTS_n = '1'.
        if (uart_cts_n = '0') then
            -- CTS asserted, reset countdown.
            stop_ctr <= 3000;
        elsif (stop_ctr > 0) then
            -- Allow a brief window before we enforce the flow-control rules.
            -- (Allows UART to finish byte in progress, plus margin.)
            stop_ctr <= stop_ctr - 1;
        else
            -- Grace period elapsed, make sure both UARTs are idle.
            assert (uart_a2b = '1')
                report "Clear-to-send violation on UART-A2B." severity error;
            assert (uart_b2a = '1')
                report "Clear-to-send violation on UART-B2A." severity error;
        end if;
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
uut_a : entity work.port_serial_uart_4wire
    generic map(
    CLKREF_HZ   => 125000000,
    BAUD_HZ     => 921600)
    port map(
    uart_txd    => uart_a2b,
    uart_rxd    => uart_b2a,
    uart_rts_n  => uart_rtsa_n,
    uart_cts_n  => uart_cts_n,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    refclk      => clk_125,
    reset_p     => reset_p);

uut_b : entity work.port_serial_uart_4wire
    generic map(
    CLKREF_HZ   => 125000000,
    BAUD_HZ     => 921600)
    port map(
    uart_txd    => uart_b2a,
    uart_rxd    => uart_a2b,
    uart_rts_n  => uart_rtsb_n,
    uart_cts_n  => uart_cts_n,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    refclk      => clk_125,
    reset_p     => reset_p);

-- Print "done" message when both links have received N packets.
p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
