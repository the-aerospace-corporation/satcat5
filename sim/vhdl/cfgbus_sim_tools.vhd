--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Tools for use in various ConfigBus simulations
--
-- Includes procedures to write and read from bus, as well as a drop-in
-- block that can latch the last read reply for verification.  These
-- tools are not intended to be synthesizable.
--

library ieee;
use     ieee.math_real.all;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

package cfgbus_sim_tools is
    -- Hold ConfigBus in reset briefly (default 1 microsecond).
    procedure cfgbus_reset(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant DELAY  : time := 1.0 us);

    -- Send a ConfigBus write command.
    -- Note: Assumes parent module drives the ConfigBus clock.
    procedure cfgbus_write(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr;
        constant data   : in    cfgbus_word);

    -- Send a ConfigBus read command.
    -- Note: Assumes parent module drives the ConfigBus clock.
    procedure cfgbus_read(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr);

    -- Wait for a ConfigBus reply.
    -- Note: Assumes parent module drives the ConfigBus clock.
    procedure cfgbus_wait(
        signal cfg_cmd  : in    cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant ERR_OK : boolean := false);

    -- Combined read + wait operation.
    procedure cfgbus_readwait(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr;
        constant ERR_OK : boolean := false);

    -- Generic clock and reset source.
    -- (User must attach clock and reset signals manually, because each
    --  signal in the the record must be driven by the same entity.)
    component cfgbus_clock_source is
        generic (
        CLK_PERIOD  : time := 10.0 ns;
        RESET_DELAY : time := 1.0 us);
        port (
        clk_out : out std_logic;
        reset_p : out std_logic);
    end component;

    -- Simple block that latches the last reply value.
    component cfgbus_read_latch is
        generic (
        ERR_OK  : boolean := false);
        port (
        cfg_cmd : in  cfgbus_cmd;
        cfg_ack : in  cfgbus_ack;
        readval : out cfgbus_word;
        readerr : out std_logic);
    end component;
end package;

---------------------------------------------------------------------

package body cfgbus_sim_tools is
    procedure cfgbus_reset(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant DELAY  : time := 1.0 us) is
    begin
        cfg_cmd.clk     <= 'Z';
        cfg_cmd.devaddr <= 0;
        cfg_cmd.regaddr <= 0;
        cfg_cmd.wdata   <= (others => '0');
        cfg_cmd.wstrb   <= (others => '0');
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '0';
        cfg_cmd.reset_p <= '1';
        wait for DELAY;
        cfg_cmd.reset_p <= '0';
    end procedure;

    procedure cfgbus_write(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr;
        constant data   : in    cfgbus_word) is
    begin
        cfg_cmd.clk     <= 'Z';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.devaddr <= dev;
        cfg_cmd.regaddr <= reg;
        cfg_cmd.wdata   <= data;
        cfg_cmd.wstrb   <= (others => '1');
        cfg_cmd.wrcmd   <= '1';
        cfg_cmd.rdcmd   <= '0';
        cfg_cmd.reset_p <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '0';
    end procedure;

    procedure cfgbus_read(
        signal cfg_cmd  : inout cfgbus_cmd;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr) is
    begin
        cfg_cmd.clk     <= 'Z';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.devaddr <= dev;
        cfg_cmd.regaddr <= reg;
        cfg_cmd.wdata   <= (others => '0');
        cfg_cmd.wstrb   <= (others => '0');
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '1';
        cfg_cmd.reset_p <= '0';
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.wrcmd   <= '0';
        cfg_cmd.rdcmd   <= '0';
    end procedure;

    procedure cfgbus_wait(
        signal cfg_cmd  : in    cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant ERR_OK : boolean := false)
    is
        variable timeout : natural := 16;
    begin
        while (timeout > 0 and cfg_ack.rdack = '0' and cfg_ack.rderr = '0') loop
            timeout := timeout - 1;
            wait until rising_edge(cfg_cmd.clk);
        end loop;
        assert (ERR_OK or cfg_ack.rdack = '1' or cfg_ack.rderr = '1')
            report "ConfigBus read-timeout." severity warning;
        assert (ERR_OK or cfg_ack.rderr = '0')
            report "ConfigBus read-error." severity warning;
    end procedure;

    procedure cfgbus_readwait(
        signal cfg_cmd  : inout cfgbus_cmd;
        signal cfg_ack  : in    cfgbus_ack;
        constant dev    : in    cfgbus_devaddr;
        constant reg    : in    cfgbus_regaddr;
        constant ERR_OK : boolean := false) is
    begin
        cfgbus_read(cfg_cmd, dev, reg);
        cfgbus_wait(cfg_cmd, cfg_ack, ERR_OK);
    end procedure;
end package body;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;

entity cfgbus_clock_source is
    generic (
    CLK_PERIOD  : time := 10.0 ns;
    RESET_DELAY : time := 1.0 us);
    port (
    clk_out : out std_logic;
    reset_p : out std_logic);
end cfgbus_clock_source;

architecture cfgbus_clock_source of cfgbus_clock_source is

signal clk_i : std_logic := '0';
signal rst_i : std_logic := '1';

begin

-- Clock and reset generation.
clk_i <= not clk_i after (CLK_PERIOD / 2);
rst_i <= '0' after RESET_DELAY;

-- Drive output signals.
clk_out <= '1' when (clk_i = '1') else '0';
reset_p <= rst_i;

end cfgbus_clock_source;

---------------------------------------------------------------------

library ieee;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;

entity cfgbus_read_latch is
    generic (
    ERR_OK  : boolean := false);
    port (
    cfg_cmd : in  cfgbus_cmd;
    cfg_ack : in  cfgbus_ack;
    readval : out cfgbus_word;
    readerr : out std_logic);
end cfgbus_read_latch;

architecture cfgbus_read_latch of cfgbus_read_latch is

signal reply_now   : std_logic;
signal reg_readval : cfgbus_word := (others => 'U');
signal reg_readerr : std_logic := 'U';

begin

reply_now <= cfg_ack.rdack or cfg_ack.rderr;
readval <= cfg_ack.rdata when (reply_now = '1') else reg_readval;
readerr <= cfg_ack.rderr when (reply_now = '1') else reg_readerr;

p_reg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Sanity check on status signals.
        assert (ERR_OK or cfg_ack.rderr = '0')
            report "Unexpected ERR strobe." severity error;
        assert (cfg_ack.rdack = '1' or cfg_ack.rdata = x"00000000")
            report "Idle-bus violation." severity error;

        -- Latch the new reply value.
        if (reply_now = '1') then
            reg_readval <= cfg_ack.rdata;
            reg_readerr <= cfg_ack.rderr;
        elsif (cfg_cmd.rdcmd = '1') then
            reg_readval <= (others => 'U');
            reg_readerr <= 'U';
        end if;
    end if;
end process;

end cfgbus_read_latch;
