--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Helper functions for blocks based on "cfgbus_multiserial"
--
-- This package defines helper functions for operating blocks based on
-- "cfgbus_multiserial", such as I2C, SPI, and UART controllers.

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;

package cfgbus_multiserial_helper is
    -- ConfigBus device address for UUT, and various register addresses.
    constant DEVADDR_UUT    : cfgbus_devaddr := 42; -- Unit under test
    constant REGADDR_IRQ    : cfgbus_regaddr := 0;  -- Part of UUT
    constant REGADDR_CONFIG : cfgbus_regaddr := 1;  -- Part of UUT
    constant REGADDR_STATUS : cfgbus_regaddr := 2;  -- Part of UUT
    constant REGADDR_DATA   : cfgbus_regaddr := 3;  -- Part of UUT
    constant REGADDR_REF    : cfgbus_regaddr := 99; -- Reference data FIFO

    -- Placeholder for command opcodes.
    subtype cfgms_opcode is std_logic_vector(3 downto 0);
    subtype cfgms_data is std_logic_vector(7 downto 0);
    constant OPCODE_NONE : cfgms_opcode := (others => '0');
    constant NULL_BYTE  : cfgms_data := (others => '0');

    -- Enable interrupts and clear any prior events.
    procedure cfgms_irq_clear(
        signal cfg_cmd  : inout cfgbus_cmd);

    -- Set configuration and reset FIFOs.
    procedure cfgms_configure(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant newcfg : in    cfgbus_word);

    -- Poll status register until it reports idle.
    procedure cfgms_wait_done(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack);

    -- Write a block of data to the UUT-Tx-FIFO.
    procedure cfgms_write_uut(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant opcode : in    cfgms_opcode;
        constant data   : in    std_logic_vector);

    -- Write a block of data to the Ref-Tx-FIFO.
    procedure cfgms_write_ref(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant data   : in    std_logic_vector);

    -- Read a block of data from the designated FIFO and confirm contents.
    procedure cfgms_read_data(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant raddr  : in    cfgbus_regaddr;
        constant refdat : in    std_logic_vector);
end package;

---------------------------------------------------------------------

package body cfgbus_multiserial_helper is
    procedure cfgms_irq_clear(
        signal cfg_cmd  : inout cfgbus_cmd) is
    begin
        cfgbus_write(cfg_cmd, DEVADDR_UUT, REGADDR_IRQ, x"00000001");
    end procedure;

    procedure cfgms_configure(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant newcfg : in    cfgbus_word) is
    begin
        cfgbus_write(cfg_cmd, DEVADDR_UUT, REGADDR_CONFIG, newcfg);
        wait for 1 us;  -- Wait for resets to clear, etc.
    end procedure;

    procedure cfgms_wait_done(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack)
    is
        variable timeout : natural := 10_000;
    begin
        -- Start reading.
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
        while (timeout > 0 and cfg_ack.rdata(2) = '0') loop
            wait until rising_edge(cfg_cmd.clk);
            timeout := timeout - 1;
        end loop;
        -- Poll until BUSY = '0'...
        while (timeout > 0 and cfg_ack.rdata(2) = '1') loop
            wait until rising_edge(cfg_cmd.clk);
            timeout := timeout - 1;
        end loop;
        -- Cleanup:
        cfg_cmd.rdcmd   <= '0';
        wait until rising_edge(cfg_cmd.clk);
        wait until rising_edge(cfg_cmd.clk);
        assert (timeout > 0) report "Done-timeout." severity error;
    end procedure;

    procedure cfgms_write_uut(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant opcode : in    cfgms_opcode;
        constant data   : in    std_logic_vector)
    is
        constant nbytes : positive := data'length / 8;
        variable dbyte  : cfgms_data := (others => '0');
        variable dword  : cfgbus_word := (others => '0');
    begin
        assert (to_01_vec(data) = data) report "Invalid input argument.";
        for n in nbytes-1 downto 0 loop
            dbyte := data(n*8+7 downto n*8);
            dword := resize(opcode, 24) & dbyte;
            cfgbus_write(cfg_cmd, DEVADDR_UUT, REGADDR_DATA, dword);
        end loop;
    end procedure;

    procedure cfgms_write_ref(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant data   : in    std_logic_vector)
    is
        constant nbytes : positive := data'length / 8;
        variable dbyte  : cfgms_data := (others => '0');
        variable dword  : cfgbus_word := (others => '0');
    begin
        assert (to_01_vec(data) = data) report "Invalid input argument.";
        for n in nbytes-1 downto 0 loop
            dbyte := data(n*8+7 downto n*8);
            dword := resize(dbyte, 32);
            cfgbus_write(cfg_cmd, DEVADDR_UUT, REGADDR_REF, dword);
        end loop;
    end procedure;

    procedure cfgms_read_data(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant raddr  : in    cfgbus_regaddr;
        constant refdat : in    std_logic_vector)
    is
        constant nbytes : positive := refdat'length / 8;
        variable rbyte  : cfgms_data := (others => '0');
    begin
        assert (to_01_vec(refdat) = refdat) report "Invalid input argument.";
        -- Start reading.
        cfg_cmd.clk     <= 'Z';
        cfg_cmd.devaddr <= DEVADDR_UUT;
        cfg_cmd.regaddr <= raddr;
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '0';
        cfg_cmd.wdata   <= (others => '0');
        cfg_cmd.wstrb   <= (others => '0');
        cfg_cmd.reset_p <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.rdcmd   <= '1';
        -- Check each read-response...
        for n in nbytes downto 0 loop
            wait until rising_edge(cfg_cmd.clk);
            wait for 1 ns;
            if (cfg_ack.rderr /= '0') then
                report "Unexpected Read-ERR." severity error;
            elsif (cfg_ack.rdack /= '1') then
                report "Missing Read-ACK." severity error;
            elsif (n = 0) then
                assert (cfg_ack.rdata(8) = '0')
                    report "Unexpected Read-VALID." severity error;
            elsif (cfg_ack.rdata(8) /= '1') then
                report "Missing Read-VALID." severity error;
            else
                rbyte := refdat(8*n-1 downto 8*n-8);
                assert (cfg_ack.rdata(7 downto 0) = rbyte)
                    report "Read mismatch @" & integer'image(n) severity error;
            end if;
        end loop;
        cfg_cmd.rdcmd   <= '0';
        wait until rising_edge(cfg_cmd.clk);
    end procedure;
end package body;
