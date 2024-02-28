--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus host with APB interface
--
-- This is a unit test for the APB-to-ConfigBus bridge.  It executes a
-- series of read and write transactions under various flow-control
-- conditions, and verifies that the resulting commands and replies
-- match expectations.
--
-- The complete test takes less than one millisecond.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_apb_tb is
    generic (
    ADDR_WIDTH  : positive := 32;
    RD_TIMEOUT  : positive := 6);
    -- Unit testbench top level, no I/O ports
end cfgbus_host_apb_tb;

architecture tb of cfgbus_host_apb_tb is

-- Clock and reset generation.
signal apb_clk      : std_logic := '0';
signal reset_n      : std_logic := '0';

-- APB interface.
signal apb_paddr    : std_logic_vector(ADDR_WIDTH-1 downto 0) := (others => 'X');
signal apb_psel     : std_logic := '0';
signal apb_penable  : std_logic := '0';
signal apb_pwrite   : std_logic := '0';
signal apb_pwdata   : std_logic_vector(31 downto 0) := (others => 'X');
signal apb_pready   : std_logic;
signal apb_prdata   : std_logic_vector(31 downto 0);
signal apb_pslverr  : std_logic;

-- ConfigBus interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack := cfgbus_idle;
signal cfg_ack_now  : std_logic;
signal cfg_count    : natural := 0; -- Counter since last read command
signal cfg_sumaddr  : natural;

-- Reference counters.
signal apb_rdelay   : natural;
signal apb_wrcount  : natural := 0;
signal apb_rdcount  : natural := 0;
signal cfg_rdelay   : natural;
signal cfg_wrcount  : natural := 0;
signal cfg_rdcount  : natural := 0;

-- Test control.
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;

begin

-- Clock and reset generation.
apb_clk <= not apb_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_n <= '1' after 1 us;

-- Initiate APB commands and check responses.
p_apb : process(apb_clk)
    variable seed1 : positive := 1287107;
    variable seed2 : positive := 5871890;
    variable rand1, rand2 : real := 0.0;
begin
    if rising_edge(apb_clk) then
        -- Generate APB commands at random intervals.
        if (apb_psel = '0' or apb_pready = '1') then
            -- Previous command completed. Start a new one?
            uniform(seed1, seed2, rand1);
            uniform(seed1, seed2, rand2);
            if (rand1 >= test_rate) then
                apb_psel    <= '0'; -- Idle
                apb_penable <= '0';
                apb_pwrite  <= 'X';
                apb_paddr   <= (others => 'X');
                apb_pwdata  <= (others => 'X');
            elsif (rand2 < 0.5) then
                apb_psel    <= '1'; -- Read
                apb_penable <= '0';
                apb_pwrite  <= '0';
                apb_paddr   <= i2s(4 * apb_rdcount, ADDR_WIDTH);
                apb_pwdata  <= (others => 'X');
                apb_rdcount <= apb_rdcount + 1;
            else
                apb_psel    <= '1'; -- Write
                apb_penable <= '0';
                apb_pwrite  <= '1';
                apb_paddr   <= i2s(4 * apb_wrcount, ADDR_WIDTH);
                apb_pwdata  <= i2s(apb_wrcount, ADDR_WIDTH);
                apb_wrcount <= apb_wrcount + 1;
            end if;
        else
            -- Raise PENABLE and wait for response...
            apb_penable <= '1';
        end if;

        -- Inspect read and write responses.
        if (apb_pready = '1') then
            assert (apb_penable = '1')
                report "Response too early." severity error;
            if (apb_pwrite = '1') then
                assert (apb_pslverr = '0')  -- Normal write
                    report "Unexpected write error." severity error;
            elsif (apb_rdelay <= RD_TIMEOUT) then
                assert (apb_pslverr = '0')  -- Normal read
                    report "Unexpected read error." severity error;
                assert (apb_prdata = i2s(apb_rdcount-1, 32))
                    report "Read data mismatch." severity error;
            else
                assert (apb_pslverr = '1')  -- Read timeout
                    report "Missing read error." severity error;
            end if;
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.cfgbus_host_apb
    generic map(
    ADDR_WIDTH  => ADDR_WIDTH,
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    interrupt   => open,
    apb_pclk    => apb_clk,
    apb_presetn => reset_n,
    apb_paddr   => apb_paddr,
    apb_psel    => apb_psel,
    apb_penable => apb_penable,
    apb_pwrite  => apb_pwrite,
    apb_pwdata  => apb_pwdata,
    apb_pready  => apb_pready,
    apb_prdata  => apb_prdata,
    apb_pslverr => apb_pslverr);

-- Expected read-response delay varies by address.
apb_rdelay  <= (apb_rdcount-1) mod (RD_TIMEOUT+2);
cfg_rdelay  <= (cfg_rdcount)   mod (RD_TIMEOUT+2);

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
            assert (cfg_sumaddr = cfg_wrcount)
                report "Write address mismatch." severity error;
            assert (cfg_cmd.wdata = i2s(cfg_wrcount, 32))
                report "Write data mismatch." severity error;
            cfg_wrcount <= cfg_wrcount + 1;
        end if;

        -- Confirm read-address and increment read-count.
        if (cfg_cmd.rdcmd = '1') then
            assert (cfg_sumaddr = cfg_rdcount)
                report "Read address mismatch." severity error;
        end if;

        if (cfg_cmd.reset_p = '0' and cfg_ack.rdack = '1') then
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
    procedure run_one(rate : real) is
    begin
        test_index  <= test_index + 1;
        test_rate   <= rate;
        wait for 100 us;
        assert (cfg_rdcount > 100 and cfg_wrcount > 100)
            report "Low throughput." severity error;
    end procedure;
begin
    wait until rising_edge(reset_n);
    wait for 1 us;

    -- Run tests at different rates.
    run_one(0.1);
    run_one(0.5);
    run_one(0.9);
    run_one(1.0);

    report "All tests completed!";
    wait;
end process;

end tb;
