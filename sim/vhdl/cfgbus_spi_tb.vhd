--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus-controlled SPI controller
--
-- This is a unit test for the ConfigBus-controlled SPI controller.
-- It sends a series of read and write commands and verifies that they
-- are executed correctly and that the replies are correct.
--
-- The complete test takes 0.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_multiserial_helper.all;
use     work.cfgbus_sim_tools.all;
use     work.cfgbus_spi_constants.all;
use     work.router_sim_tools.all;

entity cfgbus_spi_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_spi_tb;

architecture tb of cfgbus_spi_tb is

-- Unit under test
signal uut_csb      : std_logic;
signal uut_sck      : std_logic;
signal uut_sdo      : std_logic;
signal uut_sdi      : std_logic;
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

-- Unit under test.
uut : entity work.cfgbus_spi_controller
    generic map(DEVADDR => DEVADDR_UUT)
    port map(
    spi_csb(0)  => uut_csb,
    spi_sck     => uut_sck,
    spi_sdo     => uut_sdo,
    spi_sdi     => uut_sdi,
    spi_sdt     => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => uut_ack);

-- Simulated peripheral.
u_dev_spi : entity work.io_spi_peripheral
    port map(
    spi_csb     => uut_csb,
    spi_sclk    => uut_sck,
    spi_sdi     => uut_sdo,
    spi_sdo     => uut_sdi,
    spi_sdt     => open,
    tx_data     => dev_tx_data,
    tx_valid    => dev_tx_valid,
    tx_ready    => dev_tx_ready,
    rx_data     => dev_rx_data,
    rx_write    => dev_rx_write,
    cfg_mode    => 3,
    cfg_gdly    => (others => '0'),
    refclk      => cfg_cmd.clk);

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
    -- Set UART clock-divider.
    procedure configure(mode : natural; clkdiv : positive) is
        constant cfg_word : cfgbus_word := i2s(mode, 24) & i2s(clkdiv, 8);
    begin
        cfgms_configure(cfg_cmd, cfg_word);
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
        cfgms_write_uut(cfg_cmd, CMD_SEL, NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_WR,  data);
        cfgms_write_uut(cfg_cmd, CMD_EOF, NULL_BYTE);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Tx-IRQ.";
        -- Confirm data received by DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF, data);
    end procedure;

    -- Transmit a block of data from Peripheral to UUT.
    procedure test_rx(nbytes : positive) is
        -- Note: Weird XSIM bugs if we declare "data" as constant.
        variable data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
        variable zpad : std_logic_vector(8*nbytes-1 downto 0) := (others => '0');
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to DEV.
        cfgms_write_ref(cfg_cmd, data);
        -- Command UUT to read the data.
        cfgms_write_uut(cfg_cmd, CMD_SEL, NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_RD,  zpad);
        cfgms_write_uut(cfg_cmd, CMD_EOF, NULL_BYTE);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing Rx-IRQ.";
        -- Confirm data received by UUT and DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF,  zpad);
    end procedure;

    -- Transmit a simultaneous read/write transfer.
    procedure test_bd(nbytes : positive) is
        variable data : std_logic_vector(8*nbytes-1 downto 0) := rand_vec(8*nbytes);
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to DEV.
        cfgms_write_ref(cfg_cmd, data);
        -- Command UUT to read the data.
        cfgms_write_uut(cfg_cmd, CMD_SEL, NULL_BYTE);
        cfgms_write_uut(cfg_cmd, CMD_RW,  data);
        cfgms_write_uut(cfg_cmd, CMD_EOF, NULL_BYTE);
        -- Wait for transfer to complete, then confirm IRQ.
        cfgms_wait_done(cfg_cmd, cfg_ack);
        wait for 0.1 us;
        assert (cfg_ack.irq = '1') report "Missing TxRx-IRQ.";
        -- Confirm data received by UUT and DEV.
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_REF, data);
    end procedure;
begin
    -- Set UART rate to 10 Mbps (divide by 5)
    cfgbus_reset(cfg_cmd);
    wait for 1 us;
    configure(3, 5);

    -- Send a few messages back and forth.
    for n in 1 to 20 loop
        test_next;
        test_tx(1);
        test_rx(1);
        test_bd(1);
        test_tx(10);
        test_rx(10);
        test_bd(10);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
