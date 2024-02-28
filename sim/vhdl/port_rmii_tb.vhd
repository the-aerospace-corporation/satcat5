--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the RMII transceiver port
--
-- This is a unit test for the RMII transceiver, which connects two
-- blocks back-to-back to confirm correct operation under a variety
-- of conditions, including inactive ports.
--
-- The complete test takes about 29 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity port_rmii_tb is
    -- Unit testbench top level, no I/O ports
end port_rmii_tb;

architecture tb of port_rmii_tb is

-- Clock and reset generation.
signal clk_50               : std_logic := '0';
signal reset_p              : std_logic := '1';

-- Source and sink streams.
signal rxdata_a, rxdata_b   : port_rx_m2s;
signal txdata_a, txdata_b   : port_tx_s2m;
signal txctrl_a, txctrl_b   : port_tx_m2s;
signal rxdone_a, rxdone_b   : std_logic;
signal rxcount              : integer := 0;

-- RMII link between the two units under test.
signal a2b_clk              : std_logic;
signal a2b_data, b2a_data   : std_logic_vector(1 downto 0);
signal a2b_en,   b2a_en     : std_logic;
signal a2b_er,   b2a_er     : std_logic;
signal mode_slow            : std_logic := '0';
signal run_b2a              : std_logic := '0';

begin

-- Clock generation.
clk_50 <= not clk_50 after 10 ns;

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
    rxdata  => rxdata_b,
    rxdone  => rxdone_b,
    rxcount => rxcount);

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
    rxcount => rxcount);

-- Two units under test, connected back-to-back.
-- Note: Only Node A overrides transmit rate ("force_10m").
uut_a : entity work.port_rmii
    generic map(MODE_CLKOUT => true)
    port map(
    rmii_txd    => a2b_data,
    rmii_txen   => a2b_en,
    rmii_txer   => a2b_er,
    rmii_rxd    => b2a_data,
    rmii_rxen   => b2a_en,
    rmii_rxer   => b2a_er,
    rmii_clkin  => clk_50,
    rmii_clkout => a2b_clk,
    rx_data     => rxdata_a,
    tx_data     => txdata_a,
    tx_ctrl     => txctrl_a,
    force_10m   => mode_slow,
    lock_refclk => clk_50,
    reset_p     => reset_p);

uut_b : entity work.port_rmii
    generic map(MODE_CLKOUT => false)
    port map(
    rmii_txd    => b2a_data,
    rmii_txen   => b2a_en,
    rmii_txer   => b2a_er,
    rmii_rxd    => a2b_data,
    rmii_rxen   => a2b_en,
    rmii_rxer   => a2b_er,
    rmii_clkin  => a2b_clk,
    rmii_clkout => open,
    rx_data     => rxdata_b,
    tx_data     => txdata_b,
    tx_ctrl     => txctrl_b,
    lock_refclk => clk_50,
    reset_p     => reset_p);

-- Inspect raw waveforms to verify various constraints.
p_inspect : process(a2b_clk)
    variable clk_repeat : integer := 0;
    variable idle_count : integer := 0;
    variable nybb_count : integer := 0;
begin
    if falling_edge(a2b_clk) then
        -- Check if this is 10 Mbps or 100 Mbps mode.
        if (mode_slow = '0') then
            clk_repeat := 1;
        else
            clk_repeat := 10;
        end if;

        -- Inter-packet gap >= 12 bytes (48 clocks).
        if (a2b_en = '1') then
            if (idle_count /= 0) then
                assert (idle_count >= 48*clk_repeat)
                    report "Inter-packet gap violation: " & integer'image(idle_count)
                    severity error;
            end if;
            idle_count := 0;
        else
            idle_count := idle_count + 1;
        end if;

        -- Verify preamble insertion.
        if (a2b_en = '1') then
            nybb_count := nybb_count + 1;
            if (nybb_count <= 31*clk_repeat) then
                assert (a2b_data = "01")
                    report "Missing preamble" severity error;
            elsif (nybb_count <= 32*clk_repeat) then
                assert (a2b_data = "11")
                    report "Missing start-of-frame" severity error;
            end if;
        else
            nybb_count := 0;
        end if;
    end if;
end process;

p_done : process
    procedure run(mode : std_logic; count : positive) is
    begin
        -- Set test conditions and pause B2A transmission.
        reset_p     <= '1';
        mode_slow   <= mode;
        run_b2a     <= '0';
        rxcount     <= count;
        wait for 1 us;
        -- Wait for end of first A2B frame.
        reset_p     <= '0';
        wait until falling_edge(a2b_en);
        -- Unlock B2A transmission and wait for test completion.
        run_b2a     <= '1';
        wait until (rxdone_a = '1' and rxdone_b = '1');
    end procedure;
begin
    run('1', 30);   report "Finished 10 Mbps test.";
    run('0', 100);  report "Finished 100 Mbps test.";
    report "All tests completed!";
    wait;
end process;

end tb;
