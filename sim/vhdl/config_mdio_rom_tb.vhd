--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the fixed configuration MDIO controller
--
-- This testbench connects the ROM-based MDIO controller to a simple MDIO
-- receiver, and confirms that commands are received with the expected
-- format and timing.  Since config_mdio_rom uses the io_mdio_writer block
-- internally, this test also indirectly covers that block.
--
-- A full test takes less than 30 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.config_mdio_rom_creation.all;
use     work.switch_types.all;

entity config_mdio_rom_tb is
    -- Unit testbench top level, no I/O ports
end config_mdio_rom_tb;

architecture tb of config_mdio_rom_tb is

constant CLKREF_HZ      : integer := 100000000;
constant MDIO_BAUD      : integer := 100000;
constant TIME_HALF_BIT  : integer := CLKREF_HZ / (2*MDIO_BAUD); -- Round down
constant TIME_MSEC      : integer := CLKREF_HZ / 1000;          -- Round down

-- Hard-coded test sequence:
constant CMD_COUNT  : integer := 12;
constant ROM_VECTOR : std_logic_vector(32*CMD_COUNT-1 downto 0) :=
    config_mdio_rom_cmd( 5,  1, 12, 52764) &
    config_mdio_rom_cmd( 0,  2, 11, 55499) &
    config_mdio_rom_cmd( 0,  3, 10, 44684) &
    config_mdio_rom_cmd( 3,  4,  9, 49267) &
    config_mdio_rom_cmd( 0,  5,  8, 55148) &
    config_mdio_rom_cmd( 0,  6,  7, 10316) &
    config_mdio_rom_cmd( 0,  7,  6, 39596) &
    config_mdio_rom_cmd( 0,  8,  5, 46969) &
    config_mdio_rom_cmd( 0,  9,  4, 48849) &
    config_mdio_rom_cmd( 2, 10,  3, 22884) &
    config_mdio_rom_cmd( 0, 11,  2, 21071) &
    config_mdio_rom_cmd( 0, 12,  1, 49815);

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference timer.
subtype time_word is unsigned(31 downto 0);
signal time_now     : time_word := (others => '0');

-- MDIO physical interface
signal mdio_clk     : std_logic;
signal mdio_data    : std_logic;
signal mdio_oe      : std_logic;
signal status_done  : std_logic;

-- MDIO receiver
signal rcvr_phy     : std_logic_vector(4 downto 0) := (others => '0');
signal rcvr_reg     : std_logic_vector(4 downto 0) := (others => '0');
signal rcvr_dat     : std_logic_vector(15 downto 0) := (others => '0');
signal rcvr_rdy     : std_logic := '0';

-- Check output against reference.
signal ref_idx      : integer := 0;
signal ref_cmd      : config_mdio_rom_word := (others => '0');
signal ref_dly      : integer := 0;
signal ref_phy      : std_logic_vector(4 downto 0) := (others => '0');
signal ref_reg      : std_logic_vector(4 downto 0) := (others => '0');
signal ref_dat      : std_logic_vector(15 downto 0) := (others => '0');

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Reference timer.
p_time : process(clk_100)
begin
    if rising_edge(clk_100) then
        time_now <= time_now + 1;
    end if;
end process;

-- Unit under test
uut : entity work.config_mdio_rom
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    MDIO_BAUD   => MDIO_BAUD,
    ROM_VECTOR  => ROM_VECTOR)
    port map(
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    mdio_oe     => mdio_oe,
    status_done => status_done,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- Simple MDIO receiver.
p_mdio : process(clk_100)
    variable time_elapsed   : time_word := (others => '0');
    variable time_rising    : time_word := (others => '0');
    variable mdio_sreg      : std_logic_vector(63 downto 0) := (others => '0');
    variable mdio_clk_d     : std_logic := '0';
    variable mdio_data_d    : std_logic := '1';
begin
    if rising_edge(clk_100) then
        -- Measure elapsed time since last clock rising edge.
        time_elapsed := time_now - time_rising;

        -- Main receiver state machine.
        rcvr_rdy <= '0';    -- Set default
        if (mdio_clk = '1' and mdio_clk_d = '0') then
            -- Rising edge, confirm baud rate is OK.
            assert (11*time_elapsed >= 20*TIME_HALF_BIT)
                report "Baud rate violation (rising)" severity error;
            assert (mdio_oe = '1')
                report "Missing output enable (rising)" severity error;
            time_rising := time_now;
            -- Push new data onto the shift register, MSB-first.
            mdio_sreg := mdio_sreg(62 downto 0) & mdio_data;
            -- If we get a valid preamble, latch data and assert ready strobe.
            if (mdio_sreg(63 downto 28) = x"FFFFFFFF5") then
                assert (mdio_sreg(17 downto 16) = "10")
                    report "Transition token error" severity error;
                rcvr_phy <= mdio_sreg(27 downto 23);
                rcvr_reg <= mdio_sreg(22 downto 18);
                rcvr_dat <= mdio_sreg(15 downto 0);
                rcvr_rdy <= '1';
            end if;
        elsif (mdio_clk = '1') then
            -- While clock is high, confirm data is held constant.
            assert (mdio_data = mdio_sreg(0))
                report "Data change before falling edge" severity error;
            assert (9*time_elapsed < 10*TIME_HALF_BIT)
                report "Baud rate violation (stuck clock)" severity warning;
            assert (mdio_oe = '1')
                report "Missing output enable (clk-high)" severity error;
        elsif (mdio_clk = '0' and mdio_clk_d = '1') then
            -- Falling edge, confirm baud rate is OK.
            assert (11*time_elapsed >= 10*TIME_HALF_BIT)
                report "Baud rate violation (falling)" severity error;
            assert (mdio_oe = '1')
                report "Missing output enable (falling)" severity error;
        end if;

        -- Delayed copies of clk and data signals.
        mdio_clk_d  := mdio_clk;
        mdio_data_d := mdio_data;
    end if;
end process;

-- Check received data directly against the ROM.
ref_cmd <= (others => '0') when (ref_idx >= CMD_COUNT) else
    ROM_VECTOR(32*(CMD_COUNT-ref_idx)-1 downto 32*(CMD_COUNT-ref_idx)-32);
ref_dly <= TIME_MSEC * u2i(ref_cmd(31 downto 26));
ref_phy <= ref_cmd(25 downto 21);
ref_reg <= ref_cmd(20 downto 16);
ref_dat <= ref_cmd(15 downto 0);

p_check : process(clk_100)
    variable time_elapsed   : time_word := (others => '0');
    variable time_prevcmd   : time_word := (others => '0');
begin
    if rising_edge(clk_100) then
        -- Update elapsed time since last command.
        time_elapsed := time_now - time_prevcmd;

        -- Once we've been idle for a while, check if we finished.
        if (time_elapsed = 10*TIME_MSEC) then
            assert (ref_idx = CMD_COUNT)
                report "Command count mismatch." severity error;
            assert (status_done = '1')
                report "Missing DONE flag." severity error;
            report "All tests completed.";
        end if;

        -- Check received commands against reference.
        if (rcvr_rdy = '1' and ref_idx >= CMD_COUNT) then
            ref_idx <= ref_idx + 1;     -- Count all commands
            report "Unexpected command (past end)" severity error;
        elsif (rcvr_rdy = '1') then
            report "Received command #" & integer'image(ref_idx);
            ref_idx <= ref_idx + 1;     -- Count all commands
            time_prevcmd := time_now;   -- Valid commands ONLY
            assert (time_elapsed >= ref_dly)
                report "Delay time violation" severity error;
            assert (rcvr_phy = ref_phy)
                report "PHY address mismatch" severity error;
            assert (rcvr_reg = ref_reg)
                report "REG address mismatch" severity error;
            assert (rcvr_dat = ref_dat)
                report "REG data mismatch" severity error;
        end if;
    end if;
end process;

end tb;
