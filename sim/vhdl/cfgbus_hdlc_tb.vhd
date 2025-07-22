--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus-controlled HDLC peripheral
--
-- Sends a series of read and write commands and verifies that they
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
use     work.cfgbus_hdlc_constants.all;
use     work.cfgbus_multiserial_helper.all;
use     work.cfgbus_sim_tools.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;

entity cfgbus_hdlc_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_hdlc_tb;

architecture tb of cfgbus_hdlc_tb is

constant ETH_PYLD_BYTES : positive := 46;

constant FCS_ENABLE  : boolean   := true;
constant SLIP_ENABLE : boolean   := true;
constant FRAME_BYTES : integer   := 2*(14 + ETH_PYLD_BYTES);
constant MSB_FIRST   : boolean   := true;
constant FIFO_LOG2   : integer   := log2_ceil(2*FRAME_BYTES);

-- Unit under test
signal hdlc_clk   : std_logic;
signal hdlc_bits  : std_logic;
signal hdlc_ready : std_logic := '1';

-- Command interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;

begin

-- Clock and reset generation.
u_clk : cfgbus_clock_source
    port map(clk_out => cfg_cmd.clk);

-- Unit under test.
uut : entity work.cfgbus_hdlc
    generic map(
    DEVADDR       => DEVADDR_UUT,
    FCS_ENABLE    => FCS_ENABLE,
    SLIP_ENABLE   => SLIP_ENABLE,
    INJECT_ENABLE => false,
    CMD_CODE      => x"03",
    FRAME_BYTES   => FRAME_BYTES,
    MSB_FIRST     => MSB_FIRST,
    FIFO_LOG2     => FIFO_LOG2)
    port map(
    hdlc_txclk   => hdlc_clk,
    hdlc_txdata  => hdlc_bits,
    hdlc_txready => hdlc_ready,
    hdlc_rxclk   => hdlc_clk,
    hdlc_rxdata  => hdlc_bits,
    cfg_cmd      => cfg_cmd,
    cfg_ack      => cfg_ack);

p_test : process
    -- Set UART clock-divider.
    procedure configure(clkdiv : positive) is
        constant rate_word : cfgbus_word := i2s(clkdiv, CFGBUS_WORD_SIZE);
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
    procedure test_loopback(nbytes : positive) is
        variable data : std_logic_vector(8*(14 + nbytes)-1 downto 0) :=
            make_eth_pkt(MAC_ADDR_NONE, MAC_ADDR_NONE, ETYPE_NOIP,
                         rand_vec(8*nbytes)).all;
    begin
        -- Reset IRQ state.
        cfgms_irq_clear(cfg_cmd);
        -- Write data to UUT and begin transfer.
        cfgms_write_uut(cfg_cmd, CMD_WR,  data);
        cfgms_write_uut(cfg_cmd, CMD_EOF, NULL_BYTE);

        -- Wait for transfer to complete, then confirm IRQ.
        cfg_cmd.clk     <= 'Z';
        cfg_cmd.devaddr <= DEVADDR_UUT;
        cfg_cmd.regaddr <= REGADDR_STATUS;
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '0';
        cfg_cmd.wdata   <= (others => '0');
        cfg_cmd.wstrb   <= (others => '0');
        cfg_cmd.reset_p <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.rdcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        -- Poll until BUSY = '1'...
        while (cfg_ack.rdata(2) = '0') loop
            wait until rising_edge(cfg_cmd.clk);
        end loop;
        -- Poll until BUSY = '0'...
        while (cfg_ack.rdata(2) = '1') loop
            wait until rising_edge(cfg_cmd.clk);
        end loop;
        -- Cleanup:
        cfg_cmd.rdcmd   <= '0';
        wait until rising_edge(cfg_cmd.clk);
        wait until rising_edge(cfg_cmd.clk);
        wait until (cfg_ack.irq = '1');
        cfgms_read_data(cfg_cmd, cfg_ack, REGADDR_DATA, data);
    end procedure;

    begin
        -- Set bit rate to 2 Mbps (divide by 50)
        cfgbus_reset(cfg_cmd);
        wait for 1 us;
        configure(50);

        -- Send a few messages back and forth.
        for n in 1 to 2 loop
            test_next;
            test_loopback(ETH_PYLD_BYTES);
        end loop;

        -- Set to a higher rate (divide by 10)
        configure(10);

        -- Send a few messages back and forth.
        for n in 1 to 6 loop
            test_next;
            test_loopback(ETH_PYLD_BYTES);
        end loop;

        report "All tests completed!";
        wait;
    end process;

    end tb;
