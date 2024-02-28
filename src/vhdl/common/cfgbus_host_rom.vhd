--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with ROM input
--
-- This module acts as a ConfigBus host, accepting read, write, and delay
-- commands from a read-only memory defined at build-time.
--
-- The ROM contents are a series of concatenated 32-bit words, each command
-- occupying either 1 or 2 words.  A package is included to define the ROM
-- contents, or they can be read from a file (config_file2rom.vhd).
--
-- Command definition:
--  * Bits 31:    Opcode (Read = 0, Write = 1)
--  * Bits 30-18: Delay before command, in milliseconds
--  * Bits 17-10: ConfigBus device address
--  * Bits 09-00: ConfigBus register address
--  * Writes append a second word with the ConfigBus write value.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

package cfgbus_host_rom_creation is
    subtype cfgbus_rom_rdcmd is std_logic_vector(31 downto 0);
    subtype cfgbus_rom_wrcmd is std_logic_vector(63 downto 0);

    -- Note: Optional delay is applied *before* the designated command.
    function cfgbus_rom_read(
        dev : cfgbus_devaddr;
        reg : cfgbus_regaddr;
        dly : natural := 0)
        return cfgbus_rom_rdcmd;

    function cfgbus_rom_write(
        dev : cfgbus_devaddr;
        reg : cfgbus_regaddr;
        dat : cfgbus_word;
        dly : natural := 0)
        return cfgbus_rom_wrcmd;
end package;

package body cfgbus_host_rom_creation is
    function cfgbus_rom_read(
        dev : cfgbus_devaddr;
        reg : cfgbus_regaddr;
        dly : natural := 0)
        return cfgbus_rom_rdcmd
    is
        variable cmd : cfgbus_rom_rdcmd :=
            "0" & i2s(dly, 13) & i2s(dev, 8) & i2s(reg, 10);
    begin
        return cmd;
    end function;

    function cfgbus_rom_write(
        dev : cfgbus_devaddr;
        reg : cfgbus_regaddr;
        dat : cfgbus_word;
        dly : natural := 0)
        return cfgbus_rom_wrcmd
    is
        variable cmd : cfgbus_rom_wrcmd :=
            "1" & i2s(dly, 13) & i2s(dev, 8) & i2s(reg, 10) & dat;
    begin
        return cmd;
    end function;
end package body;

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_rom is
    generic (
    REF_CLK_HZ  : positive;         -- Main clock rate (Hz)
    ROM_VECTOR  : std_logic_vector; -- Concatenated command words
    RD_TIMEOUT  : positive := 16;   -- ConfigBus read timeout (clocks)
    MSW_FIRST   : boolean := true); -- Word order for ROM_VECTOR
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- Status information.
    status_done : out std_logic;

    -- System clock and reset
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic);
end cfgbus_host_rom;

architecture cfgbus_host_rom of cfgbus_host_rom is

-- Useful constants:
constant ROM_WORDS  : integer := ROM_VECTOR'length / 32;
constant ONE_MSEC   : integer := div_ceil(REF_CLK_HZ, 1000);
subtype rom_delay_t is unsigned(12 downto 0);
subtype rom_addr_t is integer range 0 to ROM_WORDS-1;
subtype one_msec_t is integer range 0 to ONE_MSEC-1;

-- Internal ConfigBus signals.
signal int_cmd      : cfgbus_cmd;
signal int_ack      : cfgbus_ack;

-- Read data from ROM, one word at a time.
signal rom_addr     : rom_addr_t := 0;
signal rom_data     : cfgbus_word := (others => '0');
signal rom_delay    : rom_delay_t;

-- Interpreter state machine.
type cmd_state_t is (ST_READ, ST_WAIT, ST_EXEC, ST_DONE);
signal cmd_state    : cmd_state_t := ST_READ;
signal cmd_write    : std_logic := '0';
signal delay_msec   : rom_delay_t := (others => '0');
signal delay_count  : one_msec_t := ONE_MSEC-1;
signal cfg_devaddr  : cfgbus_devaddr := 0;
signal cfg_regaddr  : cfgbus_regaddr := 0;
signal cfg_wrcmd    : std_logic := '0';
signal cfg_rdcmd    : std_logic := '0';

begin

-- Top-level outputs.
status_done <= bool2bit(cmd_state = ST_DONE);

-- Handle timeouts (each RDCMD will produce exactly one RDACK or ERR).
u_timeout : cfgbus_timeout
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    host_cmd    => int_cmd,
    host_ack    => int_ack,
    host_wait   => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Drive internal ConfigBus signals.
int_cmd.clk     <= ref_clk;
int_cmd.sysaddr <= 0;
int_cmd.devaddr <= cfg_devaddr;
int_cmd.regaddr <= cfg_regaddr;
int_cmd.wdata   <= rom_data;
int_cmd.wstrb   <= (others => '1');
int_cmd.wrcmd   <= cfg_wrcmd;
int_cmd.rdcmd   <= cfg_rdcmd;
int_cmd.reset_p <= reset_p;

-- Read data from ROM, one word at a time.
-- (Keep this as a separate process, no reset, to allow BRAM inferrence.)
p_rom : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        if (MSW_FIRST) then
            rom_data <= ROM_VECTOR(32*(ROM_WORDS-rom_addr)-1
                            downto 32*(ROM_WORDS-rom_addr)-32);
        else
            rom_data <= ROM_VECTOR(32*rom_addr+31 downto 32*rom_addr);
        end if;
    end if;
end process;

rom_delay <= unsigned(rom_data(30 downto 18));

-- Controller state machine.
p_cmd : process(ref_clk)
    function incr(addr : rom_addr_t) return rom_addr_t is
    begin
        if (addr + 1 < ROM_WORDS) then
            return addr + 1;
        else
            return 0;
        end if;
    end function;
begin
    if rising_edge(ref_clk) then
        -- Set defaults, override as needed.
        cfg_wrcmd <= '0';
        cfg_rdcmd <= '0';

        -- Command sequencing and address state machine.
        if (reset_p = '1') then
            -- Global reset returns to start of ROM.
            cmd_state   <= ST_READ;
            rom_addr    <= 0;
        elsif (cmd_state = ST_READ) then
            -- Start of each command.
            cmd_state   <= ST_WAIT;
            rom_addr    <= incr(rom_addr);
        elsif (cmd_state = ST_WAIT) then
            -- Wait for the delay countdown, then execute.
            if (delay_msec = 0) then
                cmd_state <= ST_EXEC;
                cfg_wrcmd <= cmd_write;
                cfg_rdcmd <= not cmd_write;
                if (cmd_write = '1') then
                    rom_addr <= incr(rom_addr);
                end if;
            end if;
        elsif (cmd_state = ST_EXEC) then
            -- Command executed, wait for reply if applicable, then
            -- start the next command or move to the idle state.
            if (cmd_write = '1' or int_ack.rdack = '1' or int_ack.rderr = '1') then
                if (rom_addr = 0) then
                    cmd_state <= ST_DONE;
                else
                    cmd_state <= ST_READ;
                end if;
            end if;
        end if;

        -- Update delay countdowns.
        if (cmd_state = ST_READ) then
            -- Reset countdown for each new command.
            delay_msec  <= rom_delay;
            if (rom_delay > 0) then
                delay_count <= ONE_MSEC - 1;
            else
                delay_count <= 0;
            end if;
        elsif (delay_count > 0) then
            -- Countdown each millisecond.
            delay_count <= delay_count - 1;
        elsif (delay_msec > 0) then
            -- Countdown remaining milliseconds.
            delay_msec  <= delay_msec - 1;
            delay_count <= ONE_MSEC - 1;
        end if;

        -- Latch other parameters at the start of each command.
        if (cmd_state = ST_READ) then
            cmd_write   <= rom_data(31);
            cfg_devaddr <= u2i(rom_data(17 downto 10));
            cfg_regaddr <= u2i(rom_data(9 downto 0));
        end if;
    end if;
end process;

end cfgbus_host_rom;
