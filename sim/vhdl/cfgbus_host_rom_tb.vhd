--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus host with ROM input
--
-- This unit test loads a short read/write sequence with included
-- delays, and confirms the commands match expectations.
--
-- The complete test takes less than 20 microseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.cfgbus_common.all;
use     work.cfgbus_host_rom_creation.all;
use     work.common_functions.all;

entity cfgbus_host_rom_tb is
    generic (
    RD_TIMEOUT  : positive := 6);
    -- Unit testbench top level, no I/O ports
end cfgbus_host_rom_tb;

architecture tb of cfgbus_host_rom_tb is

-- Generate the command sequence:
constant ROM_READS  : positive := 15;
constant ROM_WRITES : positive := 15;
constant ROM_WORDS  : positive := ROM_READS + 2*ROM_WRITES;
constant ROM_VECTOR : std_logic_vector(32*ROM_WORDS-1 downto 0) :=
    cfgbus_rom_read(0, 0) &
    cfgbus_rom_read(0, 1) &
    cfgbus_rom_read(0, 2, 1) &
    cfgbus_rom_read(0, 3) &
    cfgbus_rom_read(0, 4) &
    cfgbus_rom_read(0, 5) &
    cfgbus_rom_read(0, 6, 2) &
    cfgbus_rom_read(0, 7) &
    cfgbus_rom_read(0, 8) &
    cfgbus_rom_read(0, 9, 3) &
    cfgbus_rom_write(0, 0, i2s(0, 32)) &
    cfgbus_rom_write(0, 1, i2s(1, 32)) &
    cfgbus_rom_write(0, 2, i2s(2, 32), 1) &
    cfgbus_rom_write(0, 3, i2s(3, 32)) &
    cfgbus_rom_write(0, 4, i2s(4, 32)) &
    cfgbus_rom_write(0, 5, i2s(5, 32)) &
    cfgbus_rom_write(0, 6, i2s(6, 32), 2) &
    cfgbus_rom_write(0, 7, i2s(7, 32)) &
    cfgbus_rom_write(0, 8, i2s(8, 32)) &
    cfgbus_rom_write(0, 9, i2s(9, 32), 3) &
    cfgbus_rom_read(0, 10) &
    cfgbus_rom_write(0, 10, i2s(10, 32)) &
    cfgbus_rom_read(0, 11) &
    cfgbus_rom_write(0, 11, i2s(11, 32)) &
    cfgbus_rom_read(0, 12) &
    cfgbus_rom_write(0, 12, i2s(12, 32)) &
    cfgbus_rom_read(0, 13) &
    cfgbus_rom_write(0, 13, i2s(13, 32)) &
    cfgbus_rom_read(0, 14) &
    cfgbus_rom_write(0, 14, i2s(14, 32));

-- Clock and reset generation.
signal ref_clk      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Unit under test.
signal status_done  : std_logic;
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack := cfgbus_idle;

-- ConfigBus peripheral.
signal cfg_ack_now  : std_logic;
signal cfg_count    : natural := 0; -- Counter since last read command
signal cfg_rdelay   : natural;
signal cfg_sumaddr  : natural;
signal cfg_rdcount  : natural := 0;
signal cfg_wrcount  : natural := 0;

begin

-- Clock and reset generation.
ref_clk <= not ref_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Unit under test.
uut : entity work.cfgbus_host_rom
    generic map(
    REF_CLK_HZ  => 100_000,         -- Accelerated testing (1 step = 1 usec)
    ROM_VECTOR  => ROM_VECTOR,
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    status_done => status_done,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

-- Expected read-response delay varies by address.
cfg_rdelay  <= cfg_rdcount mod (RD_TIMEOUT+2);

-- Respond to read and write commands.
cfg_sumaddr <= 1024 * cfg_cmd.devaddr + cfg_cmd.regaddr;
cfg_ack_now <= bool2bit(cfg_rdelay = 0 and cfg_cmd.rdcmd = '1')
            or bool2bit(cfg_rdelay > 0 and cfg_rdelay = cfg_count);
cfg_ack <= cfgbus_reply(i2s(cfg_rdcount, 32))
    when (cfg_ack_now = '1') else cfgbus_idle;

p_cfgbus : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- No simultaneous read+write operations.
        assert (cfg_cmd.wrcmd = '0' or cfg_cmd.rdcmd = '0')
            report "Concurrent read+write." severity error;

        -- Confirm write-address and write-data.
        if (cfg_cmd.wrcmd = '1') then
            report "Write command #" & integer'image(cfg_wrcount);
            assert (cfg_sumaddr = cfg_wrcount)
                report "Write address mismatch." severity error;
            assert (cfg_cmd.wdata = i2s(cfg_wrcount, 32))
                report "Write data mismatch." severity error;
            cfg_wrcount <= cfg_wrcount + 1;
        end if;

        -- Confirm read-address and increment read-count.
        if (cfg_cmd.rdcmd = '1') then
            report "Read command #" & integer'image(cfg_rdcount);
            assert (cfg_sumaddr = cfg_rdcount)
                report "Read address mismatch." severity error;
        end if;

        if (cfg_ack.rdack = '1') then
            cfg_rdcount <= cfg_rdcount + 1;
        end if;

        -- Count cycles since last read command.
        if (cfg_ack.rdack = '1') then
            cfg_count <= 0;
        elsif (cfg_cmd.rdcmd = '1') then
            cfg_count <= 1;
        elsif (cfg_count > 0) then
            cfg_count <= cfg_count + 1;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
begin
    wait until cfg_rdcount = ROM_READS;
    wait until cfg_wrcount = ROM_WRITES;
    report "All tests completed!";
    wait;
end process;

end tb;
