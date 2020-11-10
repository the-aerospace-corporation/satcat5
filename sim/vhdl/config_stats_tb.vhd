--------------------------------------------------------------------------
-- Copyright 2020 The Aerospace Corporation
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
-- Testbench for port traffic statistics with AXI or UART interface.
--
-- This is a unit test for the traffic statistics block. It generates a
-- stream of random frame traffic on several ports, then pauses to read
-- back statistics and confirm expected values.
--
-- The complete test takes about 2.9 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity config_stats_tb is
    generic (
    PORT_COUNT  : integer := 3;
    COUNT_WIDTH : integer := 24;
    ADDR_WIDTH  : integer := 16);
    -- Unit testbench top level, no I/O ports
end config_stats_tb;

architecture tb of config_stats_tb is

constant UART_BAUD  : integer := 10_000_000;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';
signal reset_n      : std_logic;

-- Tx and Rx data streams.
signal rx_data      : array_rx_m2s(PORT_COUNT-1 downto 0);
signal tx_data      : array_tx_m2s(PORT_COUNT-1 downto 0);
signal tx_ctrl      : array_tx_s2m(PORT_COUNT-1 downto 0);
signal txrx_done    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');

-- Reference counters.
type count_array is array(0 to PORT_COUNT-1) of natural;
signal ref_bcbyte   : count_array := (others => 0);
signal ref_bcfrm    : count_array := (others => 0);
signal ref_rxbyte   : count_array := (others => 0);
signal ref_rxfrm    : count_array := (others => 0);
signal ref_txbyte   : count_array := (others => 0);
signal ref_txfrm    : count_array := (others => 0);

-- AXI-Lite interface
signal axi_clk      : std_logic;
signal axi_awvalid  : std_logic;
signal axi_awready  : std_logic;
signal axi_araddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_arvalid  : std_logic;
signal axi_arready  : std_logic;
signal axi_rdata    : std_logic_vector(31 downto 0);
signal axi_rvalid   : std_logic;
signal axi_rready   : std_logic;

-- UART interface.
signal uart_txd     : std_logic;
signal uart_rxd     : std_logic;
signal uart_txen    : std_logic := '0';
signal uart_rxbyte  : std_logic_vector(7 downto 0);
signal uart_rxen    : std_logic;

-- High-level test control.
signal test_index   : integer := 0;
signal test_rate    : real := 0.0;
signal test_run     : std_logic := '0';
signal test_wdone   : std_logic := '0';
signal test_read    : std_logic := '0';
signal test_rdone   : std_logic := '0';
signal test_arcount : natural := 0;     -- AXI requests sent
signal test_rcount  : natural := 0;     -- AXI replies received
signal test_ucount  : natural := 0;     -- UART bytes received

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
axi_clk <= clk_100 after 1 ns;
reset_p <= '0' after 1 us;
reset_n <= not reset_p;

-- Traffic generation and reference counters for each port.
gen_ports : for n in 0 to PORT_COUNT-1 generate
    u_port : entity work.config_stats_refsrc
        generic map(
        COUNT_WIDTH => COUNT_WIDTH,
        PRNG_SEED1  => 1234 * (n+1),
        PRNG_SEED2  => 5678 * (n+1))
        port map(
        prx_data    => rx_data(n),
        ptx_data    => tx_data(n),
        ptx_ctrl    => tx_ctrl(n),
        ref_bcbyte  => ref_bcbyte(n),
        ref_bcfrm   => ref_bcfrm(n),
        ref_rxbyte  => ref_rxbyte(n),
        ref_rxfrm   => ref_rxfrm(n),
        ref_txbyte  => ref_txbyte(n),
        ref_txfrm   => ref_txfrm(n),
        rx_rate     => test_rate,
        tx_rate     => test_rate,
        burst_run   => test_run,
        burst_done  => txrx_done(n),
        clk         => clk_100,
        reset_p     => reset_p);
end generate;

-- Unit under test (AXI)
uut_axi : entity work.config_stats_axi
    generic map(
    PORT_COUNT  => PORT_COUNT,
    COUNT_WIDTH => COUNT_WIDTH,
    ADDR_WIDTH  => ADDR_WIDTH)
    port map(
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    axi_clk     => axi_clk,
    axi_aresetn => reset_n,
    axi_awaddr  => (others => '0'), -- Don't-care
    axi_awvalid => axi_awvalid,
    axi_awready => axi_awready,
    axi_wdata   => (others => '0'), -- Not tested
    axi_wvalid  => '0',
    axi_wready  => open,
    axi_bresp   => open,            -- Not tested
    axi_bvalid  => open,
    axi_bready  => '1',
    axi_araddr  => axi_araddr,
    axi_arvalid => axi_arvalid,
    axi_arready => axi_arready,
    axi_rdata   => axi_rdata,
    axi_rresp   => open,            -- Not tested
    axi_rvalid  => axi_rvalid,
    axi_rready  => axi_rready);

-- AXI-query state machine.
-- Starting at rising edge of test_read, write once and then read
-- 4*PORT_COUNT words.  As we do so, cross-check results against
-- the reference counter values.
axi_araddr <= i2s(4 * test_arcount, ADDR_WIDTH);

p_axi_query : process(axi_clk)
    variable seed1  : positive := 687051;
    variable seed2  : positive := 180213;
    variable rand   : real := 0.0;
    variable prt    : natural := 0;
    variable delay  : natural := 0;
    variable test_read_d : std_logic := '0';
begin
    if rising_edge(axi_clk) then
        -- Issue the write and read command sequence.
        if (reset_p = '1') then
            axi_awvalid  <= '0';
            axi_arvalid  <= '0';
            test_arcount <= 0;
        elsif (test_read = '1' and test_read_d = '0') then
            -- Rising edge -> Issue write.
            axi_awvalid  <= '1';
            axi_arvalid  <= '0';
            test_arcount <= 0;
        elsif (axi_awvalid = '1') then
            -- Write in progress; hold until command is accepted.
            if (axi_awready = '1') then
                axi_awvalid <= '0';
                delay       := 10;
            end if;
        elsif (delay > 0) then
            -- Short delay before the first read.
            delay := delay - 1;
            if (delay = 0) then
                axi_arvalid <= '1';
            end if;
        elsif (axi_arvalid = '1' and axi_arready = '1') then
            -- Read in progress; increment address as each command is accepted.
            -- Note: Read one word past end of array, to test handling.
            if (test_arcount < 6*PORT_COUNT) then
                axi_arvalid  <= '1';    -- Read next word.
                test_arcount <= test_arcount + 1;
            else
                axi_arvalid  <= '0';    -- Done with reads.
            end if;
        end if;

        -- Cross-check read data.
        if (test_read = '1' and test_read_d = '0') then
            -- Rising edge -> Reset read counter.
            test_rcount <= 0;
        elsif (axi_rvalid = '0' or axi_rready = '0') then
            null;   -- No new data this cycle.
        elsif (test_rcount < 6*PORT_COUNT) then
            -- Compare read data to the appropriate reference counter:
            prt := test_rcount / 6;
            case (test_rcount mod 6) is
                when 0 =>   assert(u2i(axi_rdata) = ref_bcbyte(prt))
                                report "RxBcast-Bytes mismatch" severity error;
                when 1 =>   assert(u2i(axi_rdata) = ref_bcfrm(prt))
                                report "RxBcast-Frames mismatch" severity error;
                when 2 =>   assert(u2i(axi_rdata) = ref_rxbyte(prt))
                                report "RxTot-Bytes mismatch" severity error;
                when 3 =>   assert(u2i(axi_rdata) = ref_rxfrm(prt))
                                report "RxTot-Frames mismatch" severity error;
                when 4 =>   assert(u2i(axi_rdata) = ref_txbyte(prt))
                                report "TxTot-Bytes mismatch" severity error;
                when 5 =>   assert(u2i(axi_rdata) = ref_txfrm(prt))
                                report "TxTot-Frames mismatch" severity error;
                when others => null;
            end case;
            -- Increment read counter.
            test_rcount <= test_rcount + 1;
        else
            -- Reading past end of array?
            assert (u2i(axi_rdata) = 0)
                report "Read past end of array should return zero." severity error;
            assert (test_rcount <= 6*PORT_COUNT)
                report "Unexpected read data." severity error;
            -- Increment read counter.
            test_rcount <= test_rcount + 1;
        end if;

        -- Flow-control randomization for read process.
        uniform(seed1, seed2, rand);
        axi_rready <= bool2bit(rand < 0.5) and not reset_p;

        -- Delayed copy for detecting rising edge.
        test_read_d := test_read;
    end if;
end process;

-- Unit under test (UART)
uut_uart : entity work.config_stats_uart
    generic map(
    PORT_COUNT  => PORT_COUNT,
    COUNT_WIDTH => COUNT_WIDTH,
    BAUD_HZ     => UART_BAUD,
    REFCLK_HZ   => 100_000_000)
    port map(
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    uart_txd    => uart_txd,
    uart_rxd    => uart_rxd,
    refclk      => clk_100,
    reset_p     => reset_p);

-- Command and reply UARTs.
u_uart_tx : entity work.io_uart_tx
    generic map(
    CLKREF_HZ   => 100_000_000,
    BAUD_HZ     => UART_BAUD)
    port MAP(
    uart_txd    => uart_rxd,    -- Tx/Rx crossover
    tx_data     => x"FF",       -- Query all channels
    tx_valid    => uart_txen,
    tx_ready    => open,
    refclk      => clk_100,
    reset_p     => reset_p);

u_uart_rx : entity work.io_uart_rx
    generic map(
    CLKREF_HZ   => 100_000_000,
    BAUD_HZ     => UART_BAUD)
    port map(
    uart_rxd    => uart_txd,    -- Tx/Rx crossover
    rx_data     => uart_rxbyte,
    rx_write    => uart_rxen,
    refclk      => clk_100,
    reset_p     => reset_p);

-- UART-query state machine.
p_uart_query : process(clk_100)
    variable uart_sreg   : std_logic_vector(31 downto 0) := (others => '0');
    variable port_idx    : natural := 0;
    variable word_idx    : natural := 0;
    variable test_read_d : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Issue the UART query and parse replies.
        uart_txen <= '0';
        if (reset_p = '1') then
            -- Global reset
            test_ucount <= 0;
        elsif (test_read = '1' and test_read_d = '0') then
            -- Rising edge -> Start new query.
            test_ucount <= 0;
            uart_txen   <= '1';
        elsif (uart_rxen = '1') then
            -- Byte received, add it to the shift register.
            uart_sreg := uart_sreg(23 downto 0) & uart_rxbyte;
            -- Compare each received word against reference.
            if ((test_ucount mod 4) = 3) then
                word_idx := (test_ucount - 3) / 4;
                port_idx := word_idx / 6;
                case (word_idx mod 6) is
                    when 0 =>   assert(u2i(uart_sreg) = ref_bcbyte(port_idx))
                                    report "RxBcast-Bytes mismatch" severity error;
                    when 1 =>   assert(u2i(uart_sreg) = ref_bcfrm(port_idx))
                                    report "RxBcast-Frames mismatch" severity error;
                    when 2 =>   assert(u2i(uart_sreg) = ref_rxbyte(port_idx))
                                    report "RxTot-Bytes mismatch" severity error;
                    when 3 =>   assert(u2i(uart_sreg) = ref_rxfrm(port_idx))
                                    report "RxTot-Frames mismatch" severity error;
                    when 4 =>   assert(u2i(uart_sreg) = ref_txbyte(port_idx))
                                    report "TxTot-Bytes mismatch" severity error;
                    when 5 =>   assert(u2i(uart_sreg) = ref_txfrm(port_idx))
                                    report "TxTot-Frames mismatch" severity error;
                    when others => null;
                end case;
            end if;
            test_ucount <= test_ucount + 1;
        end if;

        -- Detect rising edge of test_read.
        test_read_d := test_read;
    end if;
end process;

-- High-level test control.
test_wdone  <= and_reduce(txrx_done);
test_rdone  <= bool2bit(test_rcount >= 6*PORT_COUNT + 1)
           and bool2bit(test_ucount >= 24*PORT_COUNT);

p_test : process
    procedure run_test(rate : real) is
    begin
        -- Set test conditions and initiate data transfer.
        report "Starting test #" & integer'image(test_index + 1);
        test_index  <= test_index + 1;
        test_rate   <= rate;
        test_run    <= '1';
        test_read   <= '0';

        -- Request pause and wait for it to halt.
        wait for 500 us;
        test_run    <= '0';
        wait until rising_edge(test_wdone);

        -- After a short pause, initiate readback.
        wait for 1 us;
        test_read   <= '1';
        wait until rising_edge(test_rdone);
        wait for 1 us;
    end procedure;
begin
    wait until falling_edge(reset_p);
    wait for 1 us;

    run_test(0.1);
    run_test(0.3);
    run_test(0.5);
    run_test(0.7);
    run_test(0.9);

    report "All tests completed!" severity note;
    wait;
end process;

end tb;
