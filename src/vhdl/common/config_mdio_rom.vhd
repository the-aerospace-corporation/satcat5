--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- MDIO controller using fixed configuration tables
--
-- The "Management Data Input/Output" (MDIO) is an interface defined in
-- IEEE 802.3, Part 3.  It is commonly used to configure Ethernet PHY
-- transceivers.  This block implements a bus writer that issues a
-- fixed series of MDIO commands as soon as it is released from reset,
-- with an optional delay period before each command.
--
-- Each command is defined by a 32-bit word:
--     Bit 31-26: Delay before sending this command, in milliseconds
--     Bit 25-21: PHY address
--     Bit 20-16: Register address
--     Bit 15-00: Register data
--
-- A package is provided to enable easier ROM generation.
--
-- The command sequence is set at build time (i.e., during synthesis),
-- specified as a single std_logic_vector of concatenated command words.
-- Concatenation can be in either order, but MSW-first (big-endian on
-- 32-bit boundaries) is the default. Vectors can be hard-coded, or
-- loaded from a file using the utility functions in config_file2rom.
--
-- The preamble, start, write, and turnaround tokens are inserted
-- automatically and should not be included in the command vector.
-- Indirect registers (e.g., MMD3, MMD7, etc.) can be accessed by
-- using multiple consecutive regular MDIO commands.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;

package config_mdio_rom_creation is
    subtype config_mdio_rom_word is std_logic_vector(31 downto 0);

    function config_mdio_rom_cmd(dly, phy, reg, dat : natural)
        return config_mdio_rom_word;
end package;

package body config_mdio_rom_creation is
    function config_mdio_rom_cmd(dly, phy, reg, dat : natural)
        return config_mdio_rom_word
    is
        variable cmd : config_mdio_rom_word :=
            i2s(dly, 6) & i2s(phy, 5) & i2s(reg, 5) & i2s(dat, 16);
    begin
        return cmd;
    end function;
end package body;

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.byte_t;

entity config_mdio_rom is
    generic (
    CLKREF_HZ   : positive;         -- Main clock rate (Hz)
    MDIO_BAUD   : positive;         -- MDIO baud rate (bps)
    ROM_VECTOR  : std_logic_vector; -- Concatenated command words
    MSW_FIRST   : boolean := true); -- Word order for ROM_VECTOR
    port (
    -- MDIO interface
    mdio_clk    : out std_logic;
    mdio_data   : out std_logic;
    mdio_oe     : out std_logic;

    -- Status information.
    status_done : out std_logic;

    -- System interface
    ref_clk     : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Active-high reset
end config_mdio_rom;

architecture rtl of config_mdio_rom is

-- Useful constants:
constant ROM_WORDS  : integer := ROM_VECTOR'length / 32;    -- Round down
constant ONE_MSEC   : integer := div_ceil(CLKREF_HZ, 1000); -- Round up

-- Read data from ROM, one word at a time.
signal rom_addr     : integer range 0 to ROM_WORDS-1 := 0;
signal rom_data     : std_logic_vector(31 downto 0) := (others => '0');

-- Interpreter state machine.
type cmd_state_t is (ST_READ, ST_WAIT, ST_DATA, ST_DONE);
signal cmd_state    : cmd_state_t := ST_READ;
signal cmd_bcount   : integer range 0 to 7 := 0;
signal delay_req    : unsigned(5 downto 0);
signal delay_start  : std_logic := '1';
signal delay_wait   : std_logic := '1';

-- Low-level MDIO interface.
signal cmd_data     : byte_t := (others => '0');
signal cmd_last     : std_logic := '0';
signal cmd_valid    : std_logic := '0';
signal cmd_ready    : std_logic;

begin

-- Sanity check on input vector.
assert (ROM_VECTOR'length = 32*ROM_WORDS)
    report "ROM_VECTOR length should be a multiple of 32 bits." severity error;

-- Top-level outputs.
status_done <= bool2bit(cmd_state = ST_DONE);

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

-- Delay countdown state machine latches new values during ST_READ.
delay_req <= unsigned(rom_data(31 downto 26));
p_dly : process(ref_clk)
    variable ct_inner : integer range 0 to ONE_MSEC-1 := 0;
    variable ct_outer : integer range 0 to 63 := 0;
begin
    if rising_edge(ref_clk) then
        -- Overall state.
        if (reset_p = '1' or cmd_state = ST_READ) then
            -- ROM address change, wait for new data.
            delay_start <= '1';
            delay_wait  <= '1';
        elsif (delay_start = '1') then
            -- Start of new delay countdown.
            delay_start <= '0';
            delay_wait  <= bool2bit(delay_req > 0);
        elsif (ct_inner > 0 or ct_outer > 0) then
            -- Countdown in progress.
            delay_start <= '0';
            delay_wait  <= '1';
        else
            -- Done / idle until next read phase.
            delay_start <= '0';
            delay_wait  <= '0';
        end if;

        -- Two nested counters for delay countdown.
        if (delay_start = '1') then
            -- Start new countdown based on ROM contents.
            ct_inner := 0;
            ct_outer := to_integer(delay_req);
        elsif (ct_inner > 0) then
            -- Inner countdown loop (each clock)
            ct_inner := ct_inner - 1;
        elsif (ct_outer > 0) then
            -- Outer countdown loop (each millisecond)
            ct_inner := ONE_MSEC-1;
            ct_outer := ct_outer - 1;
        end if;
    end if;
end process;

-- Interpreter state machine.
p_cmd : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        if (reset_p = '1') then
            -- Interface reset.
            rom_addr    <= 0;
            cmd_bcount  <= 0;
            cmd_state   <= ST_READ;
        elsif (cmd_state = ST_READ) then
            -- Single-cycle while we read the next ROM word.
            cmd_bcount  <= 0;
            cmd_state   <= ST_WAIT;
        elsif (cmd_state = ST_WAIT and delay_wait = '0') then
            -- Delay completed, start next MDIO frame.
            cmd_bcount  <= 0;
            cmd_state   <= ST_DATA;
        elsif (cmd_state = ST_DATA and cmd_ready = '1') then
            -- Wait for each preamble or data byte to be accepted.
            -- After the last byte, start next command if applicable.
            if (cmd_bcount < 7) then
                cmd_bcount <= cmd_bcount + 1;
            elsif (rom_addr + 1 < ROM_WORDS) then
                rom_addr   <= rom_addr + 1;
                cmd_bcount <= 0;
                cmd_state  <= ST_READ;  -- Start next command
            else
                rom_addr   <= 0;
                cmd_bcount <= 0;
                cmd_state  <= ST_DONE;  -- Done, idle forever
            end if;
        end if;
    end if;
end process;

-- Combinational logic for the command signals.
-- Insert preamble/start/write/turnaround tokens and assert valid/last flags.
cmd_data <= ("0101" & rom_data(25 downto 22)) when (cmd_bcount = 4)
       else (rom_data(21 downto 16) & "10") when (cmd_bcount = 5)
       else (rom_data(15 downto 8)) when (cmd_bcount = 6)
       else (rom_data(7 downto 0)) when (cmd_bcount = 7)
       else (others => '1');   -- Preamble
cmd_valid <= bool2bit(cmd_state = ST_DATA);
cmd_last  <= bool2bit(cmd_state = ST_DATA and cmd_bcount = 7);

-- Low-level MDIO interface.
u_mdio : entity work.io_mdio_writer
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    MDIO_BAUD   => MDIO_BAUD)
    port map(
    cmd_data    => cmd_data,
    cmd_last    => cmd_last,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    mdio_oe     => mdio_oe,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

end rtl;
