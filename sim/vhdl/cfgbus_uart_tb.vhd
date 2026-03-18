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
-- The complete test takes 2 milliseconds.
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

constant UUT_FIFO_LOG2 : integer := 6;

-- Unit under test
signal uut_txd      : std_logic;
signal uut_rxd      : std_logic;
signal uut_cts_n    : std_logic := '0';
signal uut_rts_n    : std_logic;
signal uut_ack      : cfgbus_ack;

-- Simulated peripheral.
signal dev_rate     : unsigned(15 downto 0) := (others => '1');
signal dev_tx_data  : cfgms_data;
signal dev_tx_valid : std_logic;
signal dev_tx_ready : std_logic;
signal dev_rx_data  : cfgms_data;
signal dev_rx_write : std_logic;
signal dev_rd_rdy   : std_logic;
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
    generic map(
    DEVADDR   => DEVADDR_UUT,
    FIFO_LOG2 => UUT_FIFO_LOG2)
    port map(
    uart_txd    => uut_txd,
    uart_rxd    => uut_rxd,
    uart_cts_n  => uut_cts_n,
    uart_rts_n  => uut_rts_n,
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
    cfg_rd_rdy  => dev_rd_rdy,
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
    procedure configure(ignore_cts : std_logic; clkdiv : positive) is
        constant cfg_word : cfgbus_word := ignore_cts
                                          & i2s(clkdiv, CFGBUS_WORD_SIZE-1);
    begin
        dev_rate <= to_unsigned(clkdiv, dev_rate'length);
        cfgms_configure(cfg_cmd, cfg_word);
    end procedure;

    -- Increment the test index and print a status message.
    procedure test_next is
    begin
        report "Test #" & integer'image(test_index + 1);
        test_index <= test_index + 1;
    end procedure;

    procedure tx(nbytes : positive; data : out std_logic_vector) is
        variable v_data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to UUT and begin transfer.
        cfgms_write_uut(cfg_cmd, OPCODE_NONE, v_data);
        -- Pass data to return parameter
        data := v_data;
    end procedure;

    -- Transmit a block of data from UUT to peripheral.
    procedure test_tx(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0);
    begin
        -- Transmit from UUT to peripheral.
        tx(nbytes, data);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '0') report "Unexpected Tx-IRQ.";
        -- Confirm data received by DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF, data);
    end procedure;

    -- Attempt transmit from UUT to peripheral, but expect UUT to be busy.
    procedure test_tx_busy(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0);
    begin
        tx(nbytes, data);
        wait for 10 us;
        -- Confirm UUT busy status.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_STATUS, b"0100");
        -- Confirm no data in DEV.
        assert (dev_rd_rdy = '0') report "Unexpected DEV Rx.";
    end procedure;

    procedure rx(nbytes : positive; data : out std_logic_vector) is
        variable v_data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to DEV and begin transfer.
        cfgms_write_ref(cfg_cmd, v_data);
        -- Wait for transfer to complete, then confirm IRQ.
        wait until (dev_tx_valid = '0' and dev_tx_ready = '1');
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Rx-IRQ.";
        -- Pass data to return parameter
        data := v_data;
    end procedure;

    -- Transmit a block of data from Peripheral to UUT and confirm received.
    procedure test_rx(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0);
    begin
        -- Transmit from Peripheral to UUT.
        rx(nbytes, data);
        -- Confirm data received by UUT.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
    end procedure;

    procedure test_rx_full is
        variable data : std_logic_vector(8*(2**UUT_FIFO_LOG2)-1 downto 0);
    begin
        assert (uut_rts_n = '0') report "UUT rts_n should be active.";
        rx(2**UUT_FIFO_LOG2, data);
        wait for 10 us;
        assert (uut_rts_n = '1') report "UUT rts_n should NOT be active.";
        -- Confirm data received by UUT.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
        assert (uut_rts_n = '0') report "UUT rts_n should be active again.";
    end procedure;

begin
    -- Set UART rate to 2 Mbps (divide by 50)
    cfgbus_reset(cfg_cmd);
    wait for 1 us;
    configure('1', 50);

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(10);
        test_rx(10);
    end loop;

    -- Set UART to a higher rate (divide by 10)
    configure('1', 10);

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(10);
        test_rx(10);
    end loop;

    -- Enable CTS
    configure('0', 10);

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(10);
        test_rx(10);
    end loop;

    -- Test when CTS is de-asserted.
    uut_cts_n <= '1';
    for n in 1 to 4 loop
        test_next;
        test_tx_busy(1);
        test_tx_busy(10);
    end loop;

    -- Test RTS is asserted, when buffer is full.
    for n in 1 to 4 loop
        test_next;
        test_rx_full;
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
