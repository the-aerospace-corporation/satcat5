--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
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
-- Testbench for the RGMII transceiver port
--
-- This is a unit test for the RGMII transceiver, which connects two
-- blocks back-to-back to confirm correct operation under a variety
-- of conditions, including inactive ports.
--
-- The complete test takes about 0.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_rgmii_tb is
    -- Unit testbench top level, no I/O ports
end port_rgmii_tb;

architecture tb of port_rgmii_tb is

-- Number of packets before declaring "done".
constant RX_PACKETS : integer := 100;

-- Define a record to simplify port declarations.
type rgmii_t is record
    clk     : std_logic;
    data    : std_logic_vector(3 downto 0);
    ctl     : std_logic;
end record;

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal reset_a      : std_logic := '1';
signal reset_b      : std_logic := '1';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_m2s;
signal txctrl_a, txctrl_b   : port_tx_s2m;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal rgmii_a2b, rgmii_b2a : rgmii_t;
signal delay_a2b, delay_b2a : rgmii_t;

begin

-- Clock and reset generation.
-- (Staggered reset avoids lockstep synchronization.)
clk_125 <= not clk_125 after 4 ns;
reset_a <= '0' after 1 us;
reset_b <= '0' after 9 us;

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

-- Two-nanosecond clock delay, per RGMII specification.
delay_a2b.clk   <= rgmii_a2b.clk after 2 ns;
delay_a2b.data  <= rgmii_a2b.data;
delay_a2b.ctl   <= rgmii_a2b.ctl;
delay_b2a.clk   <= rgmii_b2a.clk after 2 ns;
delay_b2a.data  <= rgmii_b2a.data;
delay_b2a.ctl   <= rgmii_b2a.ctl;

-- Two units under test, connected back-to-back.
uut_a : entity work.port_rgmii
    generic map(
    RXCLK_ALIGN => false,
    RXCLK_LOCAL => false,
    RXCLK_GLOBL => false)
    port map(
    rgmii_txc   => rgmii_a2b.clk,
    rgmii_txd   => rgmii_a2b.data,
    rgmii_txctl => rgmii_a2b.ctl,
    rgmii_rxc   => delay_b2a.clk,
    rgmii_rxd   => delay_b2a.data,
    rgmii_rxctl => delay_b2a.ctl,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    clk_125     => clk_125,
    clk_txc     => clk_125,
    reset_p     => reset_a);

uut_b : entity work.port_rgmii
    generic map(
    RXCLK_ALIGN => false,
    RXCLK_LOCAL => false,
    RXCLK_GLOBL => false)
    port map(
    rgmii_txc   => rgmii_b2a.clk,
    rgmii_txd   => rgmii_b2a.data,
    rgmii_txctl => rgmii_b2a.ctl,
    rgmii_rxc   => delay_a2b.clk,
    rgmii_rxd   => delay_a2b.data,
    rgmii_rxctl => delay_a2b.ctl,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    clk_125     => clk_125,
    clk_txc     => clk_125,
    reset_p     => reset_b);

-- Inspect raw waveforms to verify various constraints.
p_inspect : process(rgmii_a2b.clk)
    variable idle_count : integer := 0;
    variable nybb_count : integer := 0;
begin
    if rising_edge(rgmii_a2b.clk) then
        -- Inter-packet gap >= 12 clocks.
        if (rgmii_a2b.ctl = '1') then
            if (idle_count /= 0) then
                assert (idle_count >= 12)
                    report "Inter-packet gap violation: " & integer'image(idle_count)
                    severity error;
            end if;
            idle_count := 0;
        else
            idle_count := idle_count + 1;
        end if;

        -- Verify preamble insertion.
        if (rgmii_a2b.ctl = '1') then
            nybb_count := nybb_count + 1;
            if (nybb_count < 16) then
                assert (rgmii_a2b.data = x"5")
                    report "Missing preamble" severity error;
            end if;
        else
            nybb_count := 0;
        end if;
    elsif falling_edge(rgmii_a2b.clk) then
        -- Verify preamble insertion.
        if (rgmii_a2b.ctl = '1') then
            assert (nybb_count > 0)
                report "Unexpected error strobe (DV=0)" severity error;
            nybb_count := nybb_count + 1;
            if (nybb_count < 16) then
                assert (rgmii_a2b.data = x"5")
                    report "Missing preamble" severity error;
            elsif (nybb_count = 16) then
                assert (rgmii_a2b.data = x"D")
                    report "Missing start-of-frame" severity error;
            end if;
        else
            assert (nybb_count = 0)
                report "Unexpected error strobe (DV=1)" severity error;
        end if;
    end if;
end process;

p_done : process
begin
    wait until (rxdone_a = '1' and rxdone_b = '1');
    report "Test completed.";
    wait;
end process;

end tb;
