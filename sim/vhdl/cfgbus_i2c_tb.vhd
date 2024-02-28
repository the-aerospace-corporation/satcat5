--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus-controlled I2C controller
--
-- This is a unit test for the ConfigBus-controlled I2C controller.
-- It sends a series of read and write commands and verifies that they
-- are executed correctly and that the replies are correct.
--
-- The complete test takes 1.7 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_multiserial_helper.all;
use     work.cfgbus_sim_tools.all;
use     work.i2c_constants.all;
use     work.router_sim_tools.all;

entity cfgbus_i2c_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_i2c_tb;

architecture tb of cfgbus_i2c_tb is

-- Set address of the simulated I2C peripheral:
constant I2C_ADDR   : i2c_addr_t := "1010101";
constant I2C_ADDR_R : cfgms_data := I2C_ADDR & '1';
constant I2C_ADDR_W : cfgms_data := I2C_ADDR & '0';

-- Unit under test
signal i2c_sclk_o   : std_logic_vector(1 downto 0);
signal i2c_sclk_i   : std_logic;
signal i2c_sdata_o  : std_logic_vector(1 downto 0);
signal i2c_sdata_i  : std_logic;
signal uut_ack      : cfgbus_ack;

-- Simulated peripheral.
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

-- Simulate the I2C bus with pullups:
i2c_sclk_i  <= and_reduce(i2c_sclk_o);
i2c_sdata_i <= and_reduce(i2c_sdata_o);

-- Unit under test.
uut : entity work.cfgbus_i2c_controller
    generic map(DEVADDR => DEVADDR_UUT)
    port map(
    sclk_o      => i2c_sclk_o(0),
    sclk_i      => i2c_sclk_i,
    sdata_o     => i2c_sdata_o(0),
    sdata_i     => i2c_sdata_i,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => uut_ack);

-- Simulated peripheral.
u_dev_i2c : entity work.io_i2c_peripheral
    port map(
    sclk_o      => i2c_sclk_o(1),
    sclk_i      => i2c_sclk_i,
    sdata_o     => i2c_sdata_o(1),
    sdata_i     => i2c_sdata_i,
    i2c_addr    => I2C_ADDR,
    rx_data     => dev_rx_data,
    rx_write    => dev_rx_write,
    tx_data     => dev_tx_data,
    tx_valid    => dev_tx_valid,
    tx_ready    => dev_tx_ready,
    ref_clk     => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

u_fifo : entity work.cfgbus_fifo
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
    -- Set UUT clock-divider.
    procedure configure(clkdiv : i2c_clkdiv_t) is
        constant rate_word : cfgbus_word :=
            std_logic_vector(resize(clkdiv, CFGBUS_WORD_SIZE));
    begin
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
        cfgms_write_uut(cfg_cmd, CMD_START,     NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_TXBYTE,    I2C_ADDR_W);
        cfgms_write_uut(cfg_cmd, CMD_TXBYTE,    data);
        cfgms_write_uut(cfg_cmd, CMD_STOP,      NULL_BYTE);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Tx-IRQ.";
        -- Confirm data received by DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF, data);
    end procedure;

    -- Transmit a block of data from Peripheral to UUT.
    procedure test_rx(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to DEV.
        cfgms_write_ref(cfg_cmd, data);
        -- Command UUT to read the data.
        cfgms_write_uut(cfg_cmd, CMD_START,     NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_TXBYTE,    I2C_ADDR_R);
        for n in 1 to nbytes-1 loop
            cfgms_write_uut(cfg_cmd, CMD_RXBYTE, NULL_BYTE);
        end loop;
        cfgms_write_uut(cfg_cmd, CMD_RXFINAL,   NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_STOP,      NULL_BYTE);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Rx-IRQ.";
        -- Confirm data received by UUT.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
    end procedure;
begin
    -- Set I2C baud-rate to 2 Mbps (divide by 40)
    cfgbus_reset(cfg_cmd);
    wait for 1 us;
    configure(i2c_get_clkdiv(100_000_000, 2_000_000));

    -- Send a few messages back and forth.
    for n in 1 to 10 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_tx(3);
        test_tx(3);
        test_tx(10);
        test_rx(10);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
