--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus-controlled UART peripheral
--
-- This is a unit test for the ConfigBus-controlled UART peripheral.
-- It sends a series of read and write commands and verifies that they
-- are executed correctly and that the replies are correct.
--
-- The complete test takes 1.4 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_multiserial_helper.all;
use     work.cfgbus_sim_tools.all;
use     work.router_sim_tools.all;

entity cfgbus_uart_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_uart_tb;

architecture tb of cfgbus_uart_tb is

-- Unit under test
signal uut_txd      : std_logic;
signal uut_rxd      : std_logic;
signal uut_ack      : cfgbus_ack;

-- Simulated peripheral.
signal dev_rate     : unsigned(15 downto 0) := (others => '1');
signal dev_tx_data  : cfgms_data;
signal dev_tx_valid : std_logic;
signal dev_tx_ready : std_logic;
signal dev_rx_data  : cfgms_data;
signal dev_rx_write : std_logic;
signal dev_ack      : cfgbus_ack;

-- Command interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;

begin

-- Clock and reset generation.
u_clk : cfgbus_clock_source
    port map(clk_out => cfg_cmd.clk);

-- Unit under test.
uut : entity work.cfgbus_uart
    generic map(DEVADDR => DEVADDR_UUT)
    port map(
    uart_txd    => uut_txd,
    uart_rxd    => uut_rxd,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => uut_ack);

-- Simulated peripheral.
u_dev_tx : entity work.io_uart_tx
    port map(
    uart_txd    => uut_rxd, -- Crossover
    tx_data     => dev_tx_data,
    tx_valid    => dev_tx_valid,
    tx_ready    => dev_tx_ready,
    rate_div    => dev_rate,
    refclk      => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

u_dev_rx : entity work.io_uart_rx
    port map(
    uart_rxd    => uut_txd, -- Crossover
    rx_data     => dev_rx_data,
    rx_write    => dev_rx_write,
    rate_div    => dev_rate,
    refclk      => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

u_dev_fifo : entity work.cfgbus_fifo
    generic map(
    DEVADDR     => DEVADDR_UUT,
    REGADDR     => REGADDR_REF,
    WR_DEPTH    => 6,
    WR_DWIDTH   => 8,
    RD_DEPTH    => 6,
    RD_DWIDTH   => 8,
    RD_MWIDTH   => 1,
    RD_FLAGS    => false)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => dev_ack,
    cfg_clear   => open,
    cfg_wr_full => open,
    cfg_rd_rdy  => open,
    wr_clk      => cfg_cmd.clk,
    wr_data     => dev_tx_data,
    wr_valid    => dev_tx_valid,
    wr_ready    => dev_tx_ready,
    rd_clk      => cfg_cmd.clk,
    rd_data     => dev_rx_data,
    rd_meta(0)  => '1',
    rd_valid    => dev_rx_write,
    rd_ready    => open);

-- Command interface.
cfg_ack <= cfgbus_merge(uut_ack, dev_ack);

p_test : process
    -- Set UART clock-divider.
    procedure configure(clkdiv : positive) is
        constant rate_word : cfgbus_word := i2s(clkdiv, CFGBUS_WORD_SIZE);
    begin
        dev_rate <= to_unsigned(clkdiv, dev_rate'length);
        cfgms_configure(cfg_cmd, rate_word);
    end procedure;

    -- Increment the test index and print a status message.
    procedure test_next is
    begin
        report "Test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;
    end procedure;

    -- Transmit a block of data from UUT to peripheral.
    procedure test_tx(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to UUT and begin transfer.
        cfgms_write_uut(cfg_cmd, OPCODE_NONE, data);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '0') report "Unexpected Tx-IRQ.";
        -- Confirm data received by DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF, data);
    end procedure;

    -- Transmit a block of data from Peripheral to UUT.
    procedure test_rx(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to DEV and begin transfer.
        cfgms_write_ref(cfg_cmd, data);
        -- Wait for transfer to complete, then confirm IRQ.
        wait until (dev_tx_valid = '0' and dev_tx_ready = '1');
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Rx-IRQ.";
        -- Confirm data received by UUT.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
    end procedure;
begin
    -- Set UART rate to 2 Mbps (divide by 50)
    cfgbus_reset(cfg_cmd);
    wait for 1 us;
    configure(50);

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(10);
        test_rx(10);
    end loop;

    -- Set UART to a higher rate (divide by 10)
    configure(10);

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(10);
        test_rx(10);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
