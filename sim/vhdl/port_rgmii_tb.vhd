--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the RGMII transceiver port
--
-- This is a unit test for the RGMII transceiver, which connects two
-- blocks back-to-back to confirm correct operation under a variety
-- of conditions, including inactive ports.
--
-- The complete test takes about 10.3 milliseconds.
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

-- Define a record to simplify port declarations.
type rgmii_t is record
    clk     : std_logic;
    data    : std_logic_vector(3 downto 0);
    ctl     : std_logic;
end record;

-- Clock and reset generation.
signal clk_125      : std_logic := '0';
signal clk_125_d    : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Other control signals
signal mode_10m     : std_logic := '0';
signal mode_100m    : std_logic := '0';
signal run_a2b      : std_logic := '0';
signal run_b2a      : std_logic := '0';

-- Streaming source and sink for each link:
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal rxdone_a, rxdone_b   : std_logic;

-- Two units under test, connected back-to-back.
signal rgmii_a2b, rgmii_b2a : rgmii_t;
signal delay_a2b, delay_b2a : rgmii_t;
signal rx_packets           : positive := 100;

begin

-- Clock and reset generation.
clk_125 <= not clk_125 after 4 ns;
clk_125_d <= clk_125 after 2 ns;

-- Streaming source and sink for each link:
-- Note: Node A always starts transmission first, to set the rate used for
--       both nodes for the remainder of the test. (i.e., B auto-detects.)
u_src_a2b : entity work.port_test_common
    generic map(
    DSEED1  => 1234,
    DSEED2  => 5678)
    port map(
    txdata  => txdata_a,
    txctrl  => txctrl_a,
    txrun   => run_a2b,
    rxdata  => rxdata_b,
    rxdone  => rxdone_b,
    rxcount => rx_packets);

u_src_b2a : entity work.port_test_common
    generic map(
    DSEED1  => 67890,
    DSEED2  => 12345)
    port map(
    txdata  => txdata_b,
    txctrl  => txctrl_b,
    txrun   => run_b2a,
    rxdata  => rxdata_a,
    rxdone  => rxdone_a,
    rxcount => rx_packets);

-- A2B path applies two-nanosecond clock delay, per RGMII specification.
-- B2A path has equal delay, per RGMII-ID specification (Figure 3)
delay_a2b.clk   <= rgmii_a2b.clk after 2 ns;
delay_a2b.data  <= rgmii_a2b.data;
delay_a2b.ctl   <= rgmii_a2b.ctl;
delay_b2a.clk   <= rgmii_b2a.clk after 1 ns;
delay_b2a.data  <= rgmii_b2a.data after 1 ns;
delay_b2a.ctl   <= rgmii_b2a.ctl after 1 ns;

-- Two units under test, connected back-to-back.
-- Note: Only Node A overrides transmit rate ("force_10m", "force_100m").
--       This is required because link-rate is normally set by the PHY.
--       We are testing in MAC-to-MAC mode, so there is no PHY.  Instead,
--       we force Node A to transmit at the desired rate, and confirm that
--       Node B follows suit as planned.
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
    force_10m   => mode_10m,
    force_100m  => mode_100m,
    clk_125     => clk_125,     -- Tx/Rx clock aligned
    clk_txc     => clk_125,     -- (2.0 nsec external delay)
    reset_p     => reset_p);

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
    clk_125     => clk_125,     -- Tx clock delayed 2 nsec
    clk_txc     => clk_125_d,   -- (Matched delay on this path)
    reset_p     => reset_p);

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
                    report "Missing preamble (RE)" severity error;
            elsif (nybb_count = 16) then
                assert (rgmii_a2b.data = x"D")
                    report "Missing start-of-frame (RE)" severity error;
            end if;
        else
            nybb_count := 0;
        end if;
    elsif falling_edge(rgmii_a2b.clk) then
        -- Increment byte-count only in DDR mode.
        if (rgmii_a2b.ctl = '1' and mode_10m = '0' and mode_100m = '0') then
            nybb_count := nybb_count + 1;
        end if;
        -- Verify preamble insertion and check for ERR strobes.
        if (rgmii_a2b.ctl = '1') then
            assert (nybb_count > 0)
                report "Unexpected error strobe (DV=0)" severity error;
            if (nybb_count < 16) then
                assert (rgmii_a2b.data = x"5")
                    report "Missing preamble (FE)" severity error;
            elsif (nybb_count = 16) then
                assert (rgmii_a2b.data = x"D")
                    report "Missing start-of-frame (FE)" severity error;
            end if;
        else
            assert (nybb_count = 0)
                report "Unexpected error strobe (DV=1)" severity error;
        end if;
    end if;
end process;

p_done : process
    procedure run(rate, count : positive) is
    begin
        -- Set test conditions and put both blocks in reset.
        -- (Mode flags force Node A to desired Tx-rate; Node B should follow.)
        reset_p     <= '1';
        mode_10m    <= bool2bit(rate = 10);
        mode_100m   <= bool2bit(rate = 100);
        run_a2b     <= '0';
        run_b2a     <= '0';
        rx_packets  <= count;
        -- Release from reset.
        wait for 1 us;
        reset_p     <= '0';
        wait for 1 us;
        -- Unlock A2B transmission and wait for end of first frame.
        run_a2b     <= '1';
        wait until falling_edge(rgmii_a2b.ctl);
        -- Unlock B2A transmission and wait for test completion.
        run_b2a     <= '1';
        wait until (rxdone_a = '1' and rxdone_b = '1');
    end procedure;
begin
    run(1000, 200);     report "Completed 1000 Mbps test.";
    run(100,  40);      report "Completed 100 Mbps test.";
    run(10,   8);       report "Completed 10 Mbps test.";
    report "All tests completed!";
    wait;
end process;

end tb;
