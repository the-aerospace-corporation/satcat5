--------------------------------------------------------------------------
-- Copyright 2019-2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the 2-port switch_dual.
--
-- Framework code is the same as the switch_core test, so some signals are unnecessary.
-- Test passes if the number of packets received on port 0/1 equals the number sent on port 1/0.
--
-- The complete test takes about 12 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.switch_types.all;

entity switch_dual_tb is
    -- Unit testbench top level, no I/O ports
end switch_dual_tb;

architecture tb of switch_dual_tb is

constant PORT_COUNT : integer := 2;

-- Clock and reset generation.
signal clk_100          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Source traffic generation.
subtype mac8_t is unsigned(7 downto 0);
type mac8_array is array(PORT_COUNT-1 downto 0) of mac8_t;
type count_array is array(PORT_COUNT-1 downto 0) of integer;
signal pkt_start        : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal pkt_dst          : mac8_array := (others => (others => '0'));
signal pkt_expect       : count_array := (others => 0);
signal pkt_rcvd         : count_array := (others => 0);
signal pkt_sent         : count_array := (others => 0);

-- Unit under test.
signal ports_rx_data    : array_rx_m2s(PORT_COUNT-1 downto 0);
signal ports_tx_data    : array_tx_s2m(PORT_COUNT-1 downto 0);
signal ports_tx_ctrl    : array_tx_m2s(PORT_COUNT-1 downto 0);

-- Overall test control.
signal test_phase       : integer := 0;
signal test_clr         : std_logic := '1';
signal test_run         : std_logic := '0';
signal scrub_req_t      : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

p_scrub : process
begin
    wait for 500 us;
    scrub_req_t <= not scrub_req_t;
end process;

-- Generate source and sink for each port.
gen_ports : for n in PORT_COUNT-1 downto 0 generate
    ports_tx_ctrl(n).clk     <= clk_100;
    ports_tx_ctrl(n).ready   <= '1';
    ports_tx_ctrl(n).txerr   <= '0';
    ports_tx_ctrl(n).reset_p <= reset_p;

    p_port : process(clk_100)
        constant MAC_LOCAL  : mac8_t := to_unsigned(n+1, 8);
        constant MAC_BCAST  : mac8_t := (others => '1');
        variable seed1      : positive := 1234;
        variable seed2      : positive := 5678;
        variable rand       : real := 0.0;
        variable temp       : integer := 0;
        variable valid_req  : std_logic := '0';
        variable pend_1st   : std_logic := '1';
    begin
        if rising_edge(clk_100) then
            -- Generate the packet-start strobe.
            pkt_start(n) <= '0';
            if (test_run = '0') then
                -- Traffic paused.
                pend_1st := '1';
            elsif (test_phase = 0) then
                -- Initial phase: Broadcast packets, one-by-one.
                pkt_dst(n) <= x"FF";
                if (pend_1st = '1' and (n = 0 or ports_rx_data(n-1).last = '1')) then
                    pkt_start(n) <= '1';
                    pend_1st := '0';
                end if;
            elsif (pend_1st = '1' or ports_rx_data(n).last = '1') then
                -- Continuous traffic to random destinations.
                uniform(seed1, seed2, rand);
                temp := integer(floor(rand*real(PORT_COUNT)));
                pkt_dst(n) <= to_unsigned(temp+1, 8);
                pkt_start(n) <= '1';
                pend_1st := '0';
            end if;

            -- Check for buffer under-run.  (Once a packet starts, new data must
            -- be ready on every clock or RGMII/SGMII interfaces will underflow.)
            if (valid_req = '1' and ports_tx_data(n).valid = '0') then
                report "Output buffer underrun" severity error;
            end if;
            valid_req := ports_tx_data(n).valid and not ports_tx_data(n).last;

            -- Count packets sent by this port.
            if (test_clr = '1') then
                pkt_sent(n) <= 0;
            elsif (ports_rx_data(n).write = '1' and ports_rx_data(n).last = '1') then
                pkt_sent(n) <= pkt_sent(n) + 1;
            end if;

            -- Count packets that we expect to receive on this port.
            if (test_clr = '1') then
                pkt_expect(n) <= 0;
            else
                temp := 0;
                for p in pkt_start'range loop
                    if (pkt_start(p) = '1') then
                        if (pkt_dst(p) = MAC_LOCAL) then
                            temp := temp + 1;   -- Sent to our port
                        elsif (pkt_dst(p) = MAC_BCAST and n /= p) then
                            temp := temp + 1;   -- Broadcast (except our own)
                        end if;
                    end if;
                end loop;
                pkt_expect(n) <= pkt_expect(n) + temp;
            end if;

            -- Count packets actually received by this port.
            if (test_clr = '1') then
                pkt_rcvd(n) <= 0;
            elsif (ports_tx_data(n).valid = '1' and ports_tx_data(n).last = '1') then
                pkt_rcvd(n) <= pkt_rcvd(n) + 1;
            end if;
        end if;
    end process;

    u_src : entity work.eth_traffic_sim
        generic map(
        INIT_SEED1  => (n+1)*12345,
        INIT_SEED2  => (n+1)*54321,
        AUTO_START  => false)
        port map(
        clk         => clk_100,
        reset_p     => reset_p,
        pkt_start   => pkt_start(n),
        mac_dst     => pkt_dst(n),
        mac_src     => to_unsigned(n+1, 8),
        out_rate    => 0.40,
        out_port    => ports_rx_data(n));
end generate;

-- Unit under test
uut : entity work.switch_dual
    generic map(
    ALLOW_RUNT      => false,
    OBUF_KBYTES     => 16)
    port map(
    ports_rx_data   => ports_rx_data,
    ports_tx_data   => ports_tx_data,
    ports_tx_ctrl   => ports_tx_ctrl,
    errvec_t        => open);

-- Overall test control.
p_testctrl : process
    procedure run_trial(nwait : integer) is
    begin
        -- Announce start of traffic generation.
        report "Starting phase " & integer'image(test_phase);
        test_clr <= '0';
        test_run <= '1';

        -- Wait for designated number of sent packets.
        -- (For simplicity, only check the last port is above threshold.)
        wait until rising_edge(clk_100) and (pkt_sent(PORT_COUNT-1) >= nwait);
        test_run <= '0';

        -- Wait a little longer for pipeline to flush, then check counts.
        wait for 100 us;
        for n in pkt_rcvd'range loop
            assert (pkt_rcvd(n) = pkt_expect(n))
                report "Packet-count mismatch on port " & integer'image(n)
                    & ": " & integer'image(pkt_rcvd(n))
                    & " vs. " & integer'image(pkt_expect(n))
                severity error;
        end loop;
        test_clr   <= '1';
        test_phase <= test_phase + 1;
        wait until rising_edge(clk_100);
        wait until rising_edge(clk_100);
    end procedure;
begin
    -- Reset plus a brief startup delay.
    test_phase  <= 0;
    test_clr    <= '1';
    test_run    <= '0';
    wait until reset_p = '0';
    wait for 1 us;

    -- Start the broadcast / learning phase.
    -- (Each input port sends a single broadcast packet,
    --  so each output port receives N-1 packets.)
    run_trial(1);

    -- Run each normal test phase.
    for n in 1 to 5 loop
        run_trial(10*n*n);
    end loop;

    report "All tests completed.";
    wait;
end process;

end tb;
