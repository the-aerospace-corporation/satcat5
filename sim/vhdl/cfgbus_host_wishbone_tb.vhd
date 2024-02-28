--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus host with Wishbone interface
--
-- This is a unit test for the Wishbone-to-ConfigBus bridge.  It executes
-- a series of read and write transactions under various flow-control
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

entity cfgbus_host_wishbone_tb is
    generic (RD_TIMEOUT : positive := 6);
    -- Unit testbench top level, no I/O ports
end cfgbus_host_wishbone_tb;

architecture tb of cfgbus_host_wishbone_tb is

-- Clock and reset generation.
signal wb_clk       : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Wishbone interface.
signal wb_adr_i     : std_logic_vector(19 downto 2) := (others => 'X');
signal wb_cyc_i     : std_logic := '0';
signal wb_dat_i     : std_logic_vector(31 downto 0) := (others => 'X');
signal wb_stb_i     : std_logic := '0';
signal wb_we_i      : std_logic := '0';
signal wb_ack_o     : std_logic;
signal wb_dat_o     : std_logic_vector(31 downto 0);
signal wb_err_o     : std_logic;

-- ConfigBus interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack := cfgbus_idle;
signal cfg_ack_now  : std_logic;
signal cfg_count    : natural := 0; -- Counter since last read command
signal cfg_sumaddr  : natural;

-- Reference counters.
signal wb_rdelay    : natural;
signal wb_wrcount   : natural := 0;
signal wb_rdcount1  : natural := 0;
signal wb_rdcount2  : natural := 0;
signal cfg_rdelay   : natural;
signal cfg_wrcount  : natural := 0;
signal cfg_rdcount  : natural := 0;

-- Test control.
signal test_index   : natural := 0;
signal test_rate    : real := 0.0;

begin

-- Clock and reset generation.
wb_clk  <= not wb_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;

-- Initiate Wishbone commands and check responses.
p_wishbone : process(wb_clk)
    variable seed1 : positive := 1287107;
    variable seed2 : positive := 5871890;
    variable rand1, rand2 : real := 0.0;
    variable burst : natural := 0;
begin
    if rising_edge(wb_clk) then
        -- Generate Wishbone commands at random intervals.
        if (wb_cyc_i = '0') then
            -- Ready to start a new burst?
            uniform(seed1, seed2, rand1);
            uniform(seed1, seed2, rand2);
            if (rand1 < test_rate) then
                burst := 1 + integer(floor(rand2 * 8.0));
            end if;
        elsif (wb_ack_o = '1') then
            -- Count down until end of burst.
            burst := burst - 1;
        end if;

        -- Generate each command in the burst.
        if (burst = 0) then
            -- Idle between bursts.
            wb_cyc_i    <= '0';
            wb_stb_i    <= '0';
            wb_we_i     <= 'X';
            wb_adr_i    <= (others => 'X');
            wb_dat_i    <= (others => 'X');
        elsif (wb_stb_i = '0' or wb_ack_o = '1') then
            -- Randomized delay (except start of burst).
            uniform(seed1, seed2, rand1);
            uniform(seed1, seed2, rand2);
            if (wb_cyc_i = '1' and rand1 >= test_rate) then
                wb_cyc_i    <= '1';     -- Wait state
                wb_stb_i    <= '0';
                wb_we_i     <= 'X';
                wb_adr_i    <= (others => 'X');
                wb_dat_i    <= (others => 'X');
            elsif (rand2 < 0.5) then
                wb_cyc_i    <= '1';     -- Read command
                wb_stb_i    <= '1';
                wb_we_i     <= '0';
                wb_adr_i    <= i2s(wb_rdcount1, 18);
                wb_dat_i    <= (others => 'X');
                wb_rdcount1 <= wb_rdcount1 + 1;
            else
                wb_cyc_i    <= '1';     -- Write command
                wb_stb_i    <= '1';
                wb_we_i     <= '1';
                wb_adr_i    <= i2s(wb_wrcount, 18);
                wb_dat_i    <= i2s(wb_wrcount, 32);
                wb_wrcount  <= wb_wrcount + 1;
            end if;
        end if;

        -- Inspect read and write responses.
        if (wb_ack_o = '1') then
            assert (wb_cyc_i = '1' and wb_stb_i = '1')
                report "Unexpected ACK." severity error;
            if (wb_we_i = '1') then
                assert (wb_err_o = '0')     -- Normal write
                    report "Unexpected write error." severity error;
            elsif (wb_rdelay <= RD_TIMEOUT) then
                assert (wb_err_o = '0')     -- Normal read
                    report "Unexpected read error." severity error;
                assert (wb_dat_o = i2s(wb_rdcount2, 32))
                    report "Read data mismatch." severity error;
            else
                assert (wb_err_o = '1')     -- Read timeout
                    report "Missing read error." severity error;
            end if;
        end if;

        if (wb_ack_o = '1' and wb_we_i = '0') then
            wb_rdcount2 <= wb_rdcount2 + 1;
        end if;
    end if;
end process;

-- Unit under test.
uut : entity work.cfgbus_host_wishbone
    generic map(RD_TIMEOUT => RD_TIMEOUT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    interrupt   => open,
    wb_clk_i    => wb_clk,
    wb_rst_i    => reset_p,
    wb_adr_i    => wb_adr_i,
    wb_cyc_i    => wb_cyc_i,
    wb_dat_i    => wb_dat_i,
    wb_stb_i    => wb_stb_i,
    wb_we_i     => wb_we_i,
    wb_ack_o    => wb_ack_o,
    wb_dat_o    => wb_dat_o,
    wb_err_o    => wb_err_o);

-- Expected read-response delay varies by address.
wb_rdelay   <= wb_rdcount2 mod (RD_TIMEOUT+2);
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
    procedure run_one(rate : real) is
    begin
        test_index  <= test_index + 1;
        test_rate   <= rate;
        wait for 100 us;
        assert (cfg_rdcount > 100 and cfg_wrcount > 100)
            report "Low throughput." severity error;
    end procedure;
begin
    wait until falling_edge(reset_p);
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
