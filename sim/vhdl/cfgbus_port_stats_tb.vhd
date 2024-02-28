--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for port traffic statistics with ConfigBus interface.
--
-- This is a unit test for the traffic statistics block. It generates a
-- stream of random frame traffic on several ports, then pauses to read
-- back statistics and confirm expected values.
--
-- The complete test takes about 2.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity cfgbus_port_stats_tb is
    generic (
    PORT_COUNT  : integer := 3;
    COUNT_WIDTH : integer := 24;
    ADDR_WIDTH  : integer := 16);
    -- Unit testbench top level, no I/O ports
end cfgbus_port_stats_tb;

architecture tb of cfgbus_port_stats_tb is

-- Total number of registers to read.
constant REG_PER_PORT : positive := 16;
constant CFG_WORDS    : positive := PORT_COUNT * REG_PER_PORT;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Tx and Rx data streams.
signal rx_data      : array_rx_m2s(PORT_COUNT-1 downto 0);
signal tx_data      : array_tx_s2m(PORT_COUNT-1 downto 0);
signal tx_ctrl      : array_tx_m2s(PORT_COUNT-1 downto 0);
signal txrx_done    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');

-- Reference counters.
type count_array is array(0 to PORT_COUNT-1) of natural;
signal ref_bcbyte   : count_array := (others => 0);
signal ref_bcfrm    : count_array := (others => 0);
signal ref_rxbyte   : count_array := (others => 0);
signal ref_rxfrm    : count_array := (others => 0);
signal ref_txbyte   : count_array := (others => 0);
signal ref_txfrm    : count_array := (others => 0);
signal ref_status   : port_status_t;

-- ConfigBus interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_wrcmd    : std_logic := '0';
signal cfg_rdcmd    : std_logic := '0';

-- High-level test control.
signal test_index   : integer := 0;
signal test_rate    : real := 0.0;
signal test_run     : std_logic := '0';
signal test_wdone   : std_logic := '0';
signal test_read    : std_logic := '0';
signal test_rdone   : std_logic := '0';
signal test_arcount : natural := 0;     -- Read-requests sent
signal test_rcount  : natural := 0;     -- Read-replies received

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
reset_p <= '0' after 1 us;

-- Status word is just the current test index.
ref_status <= i2s(test_index, 8);

-- Traffic generation and reference counters for each port.
gen_ports : for n in 0 to PORT_COUNT-1 generate
    u_port : entity work.port_stats_refsrc
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
        rx_status   => ref_status,
        rx_rate     => test_rate,
        tx_rate     => test_rate,
        burst_run   => test_run,
        burst_done  => txrx_done(n),
        clk         => clk_100,
        reset_p     => reset_p);
end generate;

-- Unit under test
uut : entity work.cfgbus_port_stats
    generic map(
    PORT_COUNT  => PORT_COUNT,
    CFG_DEVADDR => CFGBUS_ADDR_ANY,
    COUNT_WIDTH => COUNT_WIDTH)
    port map(
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    err_ports   => (others => PORT_ERROR_NONE),
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- ConfigBus query state machine.
-- Starting at rising edge of test_read, write once and then read
-- the entire result array.  As we do so, cross-check results against
-- the reference counter values.
cfg_cmd.clk     <= clk_100;
cfg_cmd.devaddr <= 0;
cfg_cmd.regaddr <= test_arcount;
cfg_cmd.wdata   <= (others => '0');
cfg_cmd.wstrb   <= (others => '1');
cfg_cmd.wrcmd   <= cfg_wrcmd;
cfg_cmd.rdcmd   <= cfg_rdcmd;
cfg_cmd.reset_p <= reset_p;

p_query : process(cfg_cmd.clk)
    variable seed1  : positive := 687051;
    variable seed2  : positive := 180213;
    variable rand   : real := 0.0;
    variable prt    : natural := 0;
    variable delay  : natural := 0;
    variable test_read_d : std_logic := '0';
begin
    if rising_edge(cfg_cmd.clk) then
        -- Issue the write and read command sequence.
        cfg_wrcmd   <= '0';
        cfg_rdcmd   <= '0';
        if (reset_p = '1') then
            test_arcount <= 0;
        elsif (test_read = '1' and test_read_d = '0') then
            -- Rising edge -> Issue write + short delay.
            cfg_wrcmd    <= '1';
            test_arcount <= 0;
            delay        := 10;
        elsif (delay > 0) then
            -- Short delay before the first read.
            delay := delay - 1;
            if (delay = 0) then
                cfg_rdcmd <= '1';
            end if;
        elsif (cfg_rdcmd = '1' and test_arcount < CFG_WORDS) then
            -- Read in progress; increment address as each command is accepted.
            -- Note: Read one word past end of array, to test handling.
            cfg_rdcmd    <= '1';    -- Read next word.
            test_arcount <= test_arcount + 1;
        end if;

        -- Cross-check read data.
        if (test_read = '1' and test_read_d = '0') then
            -- Rising edge -> Reset read counter.
            test_rcount <= 0;
        elsif (cfg_ack.rdack = '0') then
            null;   -- No new data this cycle.
        elsif (test_rcount < CFG_WORDS) then
            -- Compare read data to the appropriate reference counter:
            prt := test_rcount / REG_PER_PORT;
            case (test_rcount mod REG_PER_PORT) is
                when 0 =>   assert(u2i(cfg_ack.rdata) = ref_bcbyte(prt))
                                report "RxBcast-Bytes mismatch" severity error;
                when 1 =>   assert(u2i(cfg_ack.rdata) = ref_bcfrm(prt))
                                report "RxBcast-Frames mismatch" severity error;
                when 2 =>   assert(u2i(cfg_ack.rdata) = ref_rxbyte(prt))
                                report "RxTot-Bytes mismatch" severity error;
                when 3 =>   assert(u2i(cfg_ack.rdata) = ref_rxfrm(prt))
                                report "RxTot-Frames mismatch" severity error;
                when 4 =>   assert(u2i(cfg_ack.rdata) = ref_txbyte(prt))
                                report "TxTot-Bytes mismatch" severity error;
                when 5 =>   assert(u2i(cfg_ack.rdata) = ref_txfrm(prt))
                                report "TxTot-Frames mismatch" severity error;
                when 6 =>   assert(u2i(cfg_ack.rdata) = 0)
                                report "ErrCount mismatch" severity error;
                when 8 =>   assert(u2i(cfg_ack.rdata(7 downto 0)) = test_index)
                                report "Status mismatch" severity error;
                when others => null;
            end case;
            -- Increment read counter.
            test_rcount <= test_rcount + 1;
        else
            -- Reading past end of array?
            assert (u2i(cfg_ack.rdata) = 0)
                report "Read past end of array should return zero." severity error;
            assert (test_rcount <= CFG_WORDS)
                report "Unexpected read data." severity error;
            -- Increment read counter.
            test_rcount <= test_rcount + 1;
        end if;

        -- Delayed copy for detecting rising edge.
        test_read_d := test_read;
    end if;
end process;

-- High-level test control.
test_wdone  <= and_reduce(txrx_done);
test_rdone  <= bool2bit(test_rcount >= CFG_WORDS + 1);

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
