--------------------------------------------------------------------------
-- Copyright 2021-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for various blocks defined in "cfgbus_common.vhd"
--
-- This is a unit test for the following ConfigBus blocks:
--  * cfgbus_readonly
--  * cfgbus_register
--  * cfgbus_timeout
--
-- The complete test takes less than 0.2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;

entity cfgbus_common_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_common_tb;

architecture tb of cfgbus_common_tb is

constant A_DEV      : natural := 123;
constant A_REG_RW   : natural := 42;
constant A_REG_RD   : natural := 47;
constant A_REG_IRQ  : natural := 52;
constant A_REG_WDWR : natural := 55;
constant A_REG_WDRD : natural := 57;
constant RD_TIMEOUT : positive := 10;
constant WIDE_BITS  : positive := 112;
constant WIDE_BITX  : positive := CFGBUS_WORD_SIZE * div_ceil(WIDE_BITS, CFGBUS_WORD_SIZE);
subtype cfgbus_wide is std_logic_vector(WIDE_BITS-1 downto 0);
subtype cfgbus_xwide is std_logic_vector(WIDE_BITX-1 downto 0);

-- Unit under test: Timeout
signal time_test_index  : natural := 0;
signal time_host_cmd    : cfgbus_cmd;
signal time_host_ack    : cfgbus_ack;
signal time_host_wait   : std_logic;
signal time_cfg_cmd     : cfgbus_cmd;
signal time_cfg_ack     : cfgbus_ack;
signal time_ref_wait    : std_logic := '0';
signal time_count_ack   : natural := 0;
signal time_count_err   : natural := 0;

-- Unit under test: Register blocks
signal reg_val_rw       : cfgbus_word;
signal reg_cfg_cmd      : cfgbus_cmd;
signal reg_cfg_acks     : cfgbus_ack_array(0 to 4);
signal reg_cfg_ack      : cfgbus_ack;
signal reg_readval      : cfgbus_word := (others => '0');
signal reg_wideval      : cfgbus_wide := (others => '0');
signal reg_wideref      : cfgbus_xwide := (others => '0');
signal reg_irq_toggle   : std_logic := '0';
signal reg_irq_enable   : std_logic := '0';

begin

-- Clock and reset generation.
u_clk0 : cfgbus_clock_source
    port map(
    clk_out => time_host_cmd.clk,
    reset_p => time_host_cmd.reset_p);

u_clk1 : cfgbus_clock_source
    port map(
    clk_out => reg_cfg_cmd.clk,
    reset_p => open);

-- Unit under test: Timeout
uut1 : cfgbus_timeout
    generic map(RD_TIMEOUT => RD_TIMEOUT)
    port map(
    host_cmd    => time_host_cmd,
    host_ack    => time_host_ack,
    host_wait   => time_host_wait,
    cfg_cmd     => time_cfg_cmd,
    cfg_ack     => time_cfg_ack);

-- Verification state machine.
p_time_count : process(time_cfg_cmd.clk)
begin
    if rising_edge(time_cfg_cmd.clk) then
        assert (time_cfg_ack.irq = '0')
            report "Unexpected IRQ flag." severity error;
        assert (time_host_wait = time_ref_wait)
            report "Mismatch in WAIT flag." severity error;

        -- Count ACK and ERR strobes
        if (time_cfg_cmd.reset_p = '1') then
            time_count_ack <= 0;
            time_count_err <= 0;
        elsif (time_host_cmd.wrcmd = '1' or time_host_cmd.rdcmd = '1') then
            time_count_ack <= u2i(time_host_ack.rdack);
            time_count_err <= u2i(time_host_ack.rderr);
        else
            time_count_ack <= u2i(time_host_ack.rdack) + time_count_ack;
            time_count_err <= u2i(time_host_ack.rderr) + time_count_err;
        end if;

        -- Update expected WAIT signal.
        if (time_cfg_cmd.reset_p = '1') then
            time_ref_wait <= '0';   -- Global reset
        elsif (time_host_ack.rdack = '1' or time_host_ack.rderr = '1') then
            time_ref_wait <= '0';   -- Read completed
        elsif (time_host_cmd.rdcmd = '1') then
            time_ref_wait <= '1';   -- Read pending
        end if;
    end if;
end process;

-- Test control
time_host_cmd.devaddr   <= 123;
time_host_cmd.regaddr   <= 234;
time_host_cmd.wdata     <= (others => '0');
time_cfg_ack.rdata      <= (others => '0');
time_cfg_ack.irq        <= '0';

p_time_control : process
    -- Issue a read command and assert an ACK, two ACKs, an ACK and an
    -- error, etc. at the assigned time.  (-1 = no pulse.)
    procedure read_reply(
        ack1 : integer := -1;
        ack2 : integer := -1;
        err1 : integer := -1;
        err2 : integer := -1)
    is
        variable count : natural := 0;
    begin
        time_test_index <= time_test_index + 1;
        for dly in 0 to 16 loop
            wait until rising_edge(time_cfg_cmd.clk);
            time_cfg_ack.rdack  <= bool2bit(dly = ack1 or dly = ack2);
            time_cfg_ack.rderr  <= bool2bit(dly = err1 or dly = err2);
            time_host_cmd.rdcmd <= bool2bit(dly = 0);
        end loop;
    end procedure;
begin
    time_test_index     <= 0;
    time_cfg_ack.rdack  <= '0';
    time_cfg_ack.rderr  <= '0';
    time_host_cmd.wstrb <= (others => '0');
    time_host_cmd.wrcmd <= '0';
    time_host_cmd.rdcmd <= '0';
    wait for 2 us;

    -- Confirm timeout threshold
    for dly in 0 to 15 loop
        read_reply(ack1 => dly);
        if (dly <= RD_TIMEOUT) then
            assert (time_count_ack = 1 and time_count_err = 0)
                report "Missing ACK @ " & integer'image(dly);
        else
            assert (time_count_ack = 0 and time_count_err = 1)
                report "Missing ERR @ " & integer'image(dly);
        end if;
    end loop;

    -- Check a few cases with simultaneous or staggered replies.
    read_reply(ack1 => 0, ack2 => 1);
    assert (time_count_ack = 1 and time_count_err = 0)
        report "Dual-pulse 0 mismatch" severity error;

    read_reply(ack1 => 0, err1 => 0);
    assert (time_count_ack <= 1 and time_count_err = 1)
        report "Dual-pulse 1 mismatch" severity error;

    read_reply(ack1 => 1, err1 => 1);
    assert (time_count_ack <= 1 and time_count_err = 1)
        report "Dual-pulse 2 mismatch" severity error;

    read_reply(ack1 => 0, err1 => 1);
    assert (time_count_ack = 1 and time_count_err = 0)
        report "Dual-pulse 3 mismatch" severity error;

    read_reply(ack1 => 1, err1 => 0);
    assert (time_count_ack = 0 and time_count_err = 1)
        report "Dual-pulse 4 mismatch" severity error;

    read_reply(err1 => 1, err2 => 2);
    assert (time_count_ack = 0 and time_count_err = 1)
        report "Dual-pulse 5 mismatch" severity error;

    report "Time tests completed.";
    wait;
end process;

-- Unit under test: Register (Read/Write)
uut2 : cfgbus_register
    generic map(
    DEVADDR     => A_DEV,
    REGADDR     => A_REG_RW)
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_acks(0),
    reg_val     => reg_val_rw);

-- Unit under test: Register (Read Only)
uut3 : cfgbus_readonly
    generic map(
    DEVADDR     => A_DEV,
    REGADDR     => A_REG_RD)
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_acks(1),
    reg_val     => reg_val_rw);

-- Unit under test: Interrupt controller
uut4 : cfgbus_interrupt
    generic map(
    DEVADDR     => A_DEV,
    REGADDR     => A_REG_IRQ,
    INITMODE    => '0')
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_acks(2),
    ext_toggle  => reg_irq_toggle);

-- Unit under test: Register (Wide write-only)
uut5 : cfgbus_register_wide
    generic map(
    DWIDTH      => WIDE_BITS,
    DEVADDR     => A_DEV,
    REGADDR     => A_REG_WDWR)
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_acks(3),
    sync_clk    => reg_cfg_cmd.clk,
    sync_val    => reg_wideval);

-- Unit under test: Register (Wide read-only)
uut6 : cfgbus_readonly_wide
    generic map(
    DWIDTH      => WIDE_BITS,
    DEVADDR     => A_DEV,
    REGADDR     => A_REG_WDRD)
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_acks(4),
    sync_clk    => reg_cfg_cmd.clk,
    sync_val    => reg_wideval);

-- Latch the recombined read value.
reg_cfg_ack <= cfgbus_merge(reg_cfg_acks);

u_reg_read : cfgbus_read_latch
    port map(
    cfg_cmd     => reg_cfg_cmd,
    cfg_ack     => reg_cfg_ack,
    readval     => reg_readval);

-- Test control
p_reg_control : process
begin
    cfgbus_reset(reg_cfg_cmd);
    wait for 1 us;

    -- Interleaved tests of the read-write register, read-only
    -- register, and the generic interrupt controller.
    for n in 1 to 255 loop
        -- Confirm that interrupt controller is quiescent,
        -- then trigger an interrupt event.
        cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_IRQ);
        cfgbus_wait(reg_cfg_cmd, reg_cfg_ack);
        assert (reg_cfg_ack.irq = '0')
            report "Irq1 mismatch" severity error;
        assert (reg_readval(0) = reg_irq_enable)
            report "Irq2 mismatch" severity error;
        assert (reg_readval(1) = '0')
            report "Irq3 mismatch" severity error;
        reg_irq_toggle <= not reg_irq_toggle;

        -- Write a new value to the read-write register.
        cfgbus_write(reg_cfg_cmd, A_DEV, A_REG_RW, i2s(n, 32));
        wait until rising_edge(reg_cfg_cmd.clk);
        assert (u2i(reg_val_rw) = n)
            report "Write mismatch" severity error;

        -- Confirm interrupt controller received the event.
        cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_IRQ);
        cfgbus_wait(reg_cfg_cmd, reg_cfg_ack);
        assert (reg_readval(0) = reg_irq_enable)
            report "Irq4 mismatch" severity error;
        assert (reg_readval(1) = '1')
            report "Irq5 mismatch" severity error;
        assert (reg_cfg_ack.irq = reg_irq_enable)
            report "Irq6 mismatch" severity error;

        -- Clear service-request flag and toggle enable flag.
        reg_irq_enable <= not reg_irq_enable;
        wait until rising_edge(reg_cfg_cmd.clk);
        cfgbus_write(reg_cfg_cmd, A_DEV, A_REG_IRQ, (0 => reg_irq_enable, others => '0'));

        -- Confirm readback from the read-write register.
        cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_RW);
        cfgbus_wait(reg_cfg_cmd, reg_cfg_ack);
        assert (u2i(reg_readval) = n)
            report "Read1 mismatch" severity error;

        -- Confirm readback from the read-only register.
        cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_RD);
        cfgbus_wait(reg_cfg_cmd, reg_cfg_ack);
        assert (u2i(reg_readval) = n)
            report "Read2 mismatch" severity error;

        -- Write a new value to the wide-write register.
        for w in 3 downto 0 loop
            reg_wideref(32*w+31 downto 32*w) <= i2s(n+w, 32);
            cfgbus_write(reg_cfg_cmd, A_DEV, A_REG_WDWR, i2s(n+w, 32));
        end loop;
        cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_WDWR);
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        assert (reg_wideval = resize(reg_wideref, WIDE_BITS))
            report "WideWrite mismatch" severity error;

        -- Read a new value from the wide-read register.
        cfgbus_write(reg_cfg_cmd, A_DEV, A_REG_WDRD, i2s(0, 32));
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        wait until rising_edge(reg_cfg_cmd.clk);
        for w in 3 downto 0 loop
            cfgbus_read(reg_cfg_cmd, A_DEV, A_REG_WDRD);
            cfgbus_wait(reg_cfg_cmd, reg_cfg_ack);
            assert (u2i(reg_readval) = n+w)
                report "WideRead mismatch" severity error;
        end loop;
    end loop;

    report "Register tests completed.";
    wait;
end process;

end tb;
