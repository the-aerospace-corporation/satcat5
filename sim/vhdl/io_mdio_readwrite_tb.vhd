--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the read/write MDIO controller
--
-- This testbench connects the read/write MDIO controller to a simple MDIO
-- device, and confirms that commands are received with the expected
-- format and timing.
--
-- A full test takes less than 2.6 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;

entity io_mdio_readwrite_tb is
    -- Unit testbench top level, no I/O ports
end io_mdio_readwrite_tb;

architecture tb of io_mdio_readwrite_tb is

constant CLKREF_HZ      : integer := 100000000;
constant MDIO_BAUD      : integer := 2500000;
constant TIME_HALF_BIT  : integer := CLKREF_HZ / (2*MDIO_BAUD); -- Round down

-- Clock and reset generation
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference timer.
subtype time_word is unsigned(31 downto 0);
signal time_now     : time_word := (others => '0');

-- Unit under test
signal cmd_ctrl     : std_logic_vector(11 downto 0);
signal cmd_data     : std_logic_vector(15 downto 0);
signal cmd_valid    : std_logic := '0';
signal cmd_ready    : std_logic;
signal rd_data      : std_logic_vector(15 downto 0);
signal rd_rdy       : std_logic;

-- MDIO physical interface
signal mdio_clk     : std_logic;
signal mdio_data    : std_logic;

-- MDIO receiver
signal rcvr_phy     : std_logic_vector(4 downto 0) := (others => '0');
signal rcvr_reg     : std_logic_vector(4 downto 0) := (others => '0');
signal rcvr_dat     : std_logic_vector(15 downto 0) := (others => '0');
signal rcvr_rdy     : std_logic := '0';

-- Check output against reference.
signal ref_idx      : integer := 0;
signal ref_rcount   : integer := 0;
signal ref_wren     : std_logic := '0';
signal ref_phy      : std_logic_vector(4 downto 0) := (others => '0');
signal ref_reg      : std_logic_vector(4 downto 0) := (others => '0');
signal ref_dat      : std_logic_vector(15 downto 0) := (others => '0');
signal rd_count     : integer := 0;

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
cmd_ctrl <= ("01" & ref_phy & ref_reg) when (ref_wren = '1')
       else ("10" & ref_phy & ref_reg);
cmd_data <= (ref_dat) when (ref_wren = '1')
       else (others => '0');

uut : entity work.io_mdio_readwrite
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    MDIO_BAUD   => MDIO_BAUD)
    port map(
    cmd_ctrl    => cmd_ctrl,
    cmd_data    => cmd_data,
    cmd_valid   => cmd_valid,
    cmd_ready   => cmd_ready,
    rd_data     => rd_data,
    rd_rdy      => rd_rdy,
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    ref_clk     => clk_100,
    reset_p     => reset_p);

-- Simple MDIO receiver.
p_mdio : process(clk_100)
    variable time_elapsed   : time_word := (others => '0');
    variable time_rising    : time_word := (others => '0');
    variable tx_bcount      : integer := 0;
    variable mdio_sreg      : std_logic_vector(63 downto 0) := (others => '0');
    variable mdio_clk_d     : std_logic := '0';
begin
    if rising_edge(clk_100) then
        -- Measure elapsed time since last clock rising edge.
        time_elapsed := time_now - time_rising;

        -- Update shift-register on each rising edge.
        if (mdio_clk = '1' and mdio_clk_d = '0') then
            mdio_sreg := mdio_sreg(62 downto 0) & mdio_data;
        end if;

        -- Transmit state machine.
        if (reset_p = '1') then
            mdio_data <= 'H';
        elsif (mdio_clk = '1' and mdio_clk_d = '0') then
            -- If we get a read preamble, start transmitting.
            if (mdio_sreg(46 downto 11) = x"FFFFFFFF6") then
                tx_bcount := 16;
                mdio_data <= '0';                   -- Transition bit
            elsif (tx_bcount > 0) then
                tx_bcount := tx_bcount - 1;
                mdio_data <= ref_dat(tx_bcount);    -- Next data bit
            else
                mdio_data <= 'H';                   -- Idle
            end if;
        end if;

        -- Receive state machine.
        rcvr_rdy <= '0';    -- Set default
        if (mdio_clk = '1' and mdio_clk_d = '0') then
            -- Rising edge, confirm baud rate is OK.
            assert (11*time_elapsed >= 20*TIME_HALF_BIT)
                report "Baud rate violation (rising)" severity error;
            time_rising := time_now;
            -- If we get a valid preamble, latch data and assert ready strobe.
            if (mdio_sreg(63 downto 28) = x"FFFFFFFF5") then
                assert (mdio_sreg(17 downto 16) = "10")
                    report "Transition token error" severity error;
                rcvr_phy <= mdio_sreg(27 downto 23);
                rcvr_reg <= mdio_sreg(22 downto 18);
                rcvr_dat <= mdio_sreg(15 downto 0);
                rcvr_rdy <= '1';
            end if;
        elsif (mdio_clk = '0' and mdio_clk_d = '1') then
            -- Falling edge, confirm baud rate is OK.
            assert (11*time_elapsed >= 10*TIME_HALF_BIT)
                report "Baud rate violation (falling)" severity error;
        end if;

        -- Delayed copy of clock signal.
        mdio_clk_d := mdio_clk;
    end if;
end process;

-- Check received data against reference.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (rcvr_rdy = '1') then
            assert (rcvr_phy = ref_phy)
                report "PHY address mismatch" severity error;
            assert (rcvr_reg = ref_reg)
                report "REG address mismatch" severity error;
            assert (ref_wren = '0' or rcvr_dat = ref_dat)
                report "REG data mismatch" severity error;
        end if;

        if (rd_rdy = '1') then
            assert (ref_wren = '0' and rd_data = ref_dat)
                report "RD data mismatch" severity error;
            rd_count <= rd_count + 1;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    variable seed1 : positive := 1871025;
    variable seed2 : positive := 6871041;
    variable delay : unsigned(3 downto 0) := (others => '0');

    impure function rand_bit return std_logic is
        variable rand : real := 0.0;
    begin
        uniform(seed1, seed2, rand);
        return bool2bit(rand < 0.5);
    end function;

    impure function rand_vec(w : positive) return std_logic_vector is
        variable temp : std_logic_vector(w-1 downto 0);
    begin
        for n in temp'range loop
            temp(n) := rand_bit;
        end loop;
        return temp;
    end function;

begin
    -- Hold until end of reset.
    cmd_valid   <= '0';
    ref_idx     <= 0;
    ref_rcount  <= 0;
    ref_wren    <= '0';
    ref_phy     <= (others => '0');
    ref_reg     <= (others => '0');
    ref_dat     <= (others => '0');
    wait until (reset_p = '0');
    wait for 1 us;

    -- Run a series of randomized tests.
    while (ref_idx < 100) loop
        -- Start test with randomized parameters.
        report "Starting test #" & integer'image(ref_idx + 1);
        ref_idx     <= ref_idx + 1;
        ref_wren    <= rand_bit;
        ref_phy     <= rand_vec(5);
        ref_reg     <= rand_vec(5);
        ref_dat     <= rand_vec(16);
        -- Optional delay before starting test.
        delay := unsigned(rand_vec(4));
        while (delay > 0) loop
            wait until rising_edge(clk_100);
            delay := delay - 1;
        end loop;
        -- Initiate command.
        cmd_valid <= '1';
        wait until rising_edge(clk_100);
        cmd_valid <= '0';
        wait until rising_edge(clk_100);
        -- Was this a read? Increment reference counter.
        if (ref_wren = '0') then
            ref_rcount <= ref_rcount + 1;
        end if;
        -- Wait for end of command.
        while (cmd_ready = '0') loop
            wait until rising_edge(clk_100);
        end loop;
        -- Confirm expected read-count.
        assert (ref_rcount = rd_count)
            report "Missing read strobe" severity error;
    end loop;

    -- Done!
    report "All tests completed!";
    wait;
end process;

end tb;
