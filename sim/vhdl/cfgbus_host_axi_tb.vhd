--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus host with AXI4-Lite interface
--
-- This is a unit test for the AXI-to-ConfigBus bridge.  It executes a
-- series of read and write transactions under various flow-control
-- conditions, and verifies that the resulting commands and replies
-- match expectations.
--
-- The complete test takes less than 1.2 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_axi_tb is
    generic (
    ADDR_WIDTH  : positive := 32);      -- AXI-Lite address width
    -- Unit testbench top level, no I/O ports
end cfgbus_host_axi_tb;

architecture tb of cfgbus_host_axi_tb is

-- Clock and reset generation.
signal axi_clk      : std_logic := '0';
signal reset_n      : std_logic := '0';

-- AXI-Lite interface.
subtype addr_word is std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_awaddr   : addr_word := (others => '0');
signal axi_awvalid  : std_logic := '0';
signal axi_awready  : std_logic;
signal axi_wdata    : cfgbus_word := (others => '0');
signal axi_wvalid   : std_logic := '0';
signal axi_wready   : std_logic;
signal axi_bresp    : std_logic_vector(1 downto 0);
signal axi_bvalid   : std_logic;
signal axi_bready   : std_logic := '0';
signal axi_araddr   : addr_word := (others => '0');
signal axi_arvalid  : std_logic := '0';
signal axi_arready  : std_logic;
signal axi_rdata    : cfgbus_word;
signal axi_rresp    : std_logic_vector(1 downto 0);
signal axi_rvalid   : std_logic;
signal axi_rready   : std_logic := '0';

-- ConfigBus interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack := cfgbus_idle;
signal cfg_sumaddr  : natural;

-- Reference counters.
signal axi_awcount  : natural := 0;
signal axi_wcount   : natural := 0;
signal axi_bcount   : natural := 0;
signal axi_arcount  : natural := 0;
signal axi_rcount   : natural := 0;
signal cfg_wrcount  : natural := 0;
signal cfg_rdcount  : natural := 0;

-- Test control.
signal test_index   : natural := 0;
signal rate_aw      : real := 0.0;
signal rate_w       : real := 0.0;
signal rate_b       : real := 0.0;
signal rate_ar      : real := 0.0;
signal rate_r       : real := 0.0;

begin

-- Clock and reset generation.
axi_clk <= not axi_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_n <= '1' after 1 us;

-- Generate data and flow control for each AXI pipe.
p_axi : process(axi_clk)
    variable seed1 : positive := 1287107;
    variable seed2 : positive := 5871890;
    variable rand  : real := 0.0;
begin
    if rising_edge(axi_clk) then
        -- Generate data for the "AW", "W", and "AR" pipes.
        if (axi_awvalid = '0' or axi_awready = '1') then
            -- Generate a new write command?
            uniform(seed1, seed2, rand);
            if (rand < rate_aw) then
                axi_awaddr  <= i2s(4 * axi_awcount, ADDR_WIDTH);
                axi_awvalid <= '1';
                axi_awcount <= axi_awcount + 1;
            else
                axi_awaddr  <= (others => '0');
                axi_awvalid <= '0';
            end if;
        end if;

        if (axi_wvalid = '0' or axi_wready = '1') then
            -- Generate a new write word?
            uniform(seed1, seed2, rand);
            if (rand < rate_w) then
                axi_wdata   <= i2s(axi_wcount, 32);
                axi_wvalid  <= '1';
                axi_wcount  <= axi_wcount + 1;
            else
                axi_wdata   <= (others => '0');
                axi_wvalid  <= '0';
            end if;
        end if;

        if (axi_arvalid = '0' or axi_arready = '1') then
            -- Generate a new read command?
            uniform(seed1, seed2, rand);
            if (rand < rate_ar) then
                axi_araddr  <= i2s(4 * axi_arcount, ADDR_WIDTH);
                axi_arvalid <= '1';
                axi_arcount <= axi_arcount + 1;
            else
                axi_araddr  <= (others => '0');
                axi_arvalid <= '0';
            end if;
        end if;

        -- Check outputs from the "B" and "R" pipes.
        if (axi_bvalid = '1' and axi_bready = '1') then
            assert (axi_bresp = "00")
                report "Unexpected write-error." severity error;
            assert (axi_bcount < axi_awcount and axi_bcount < axi_wcount)
                report "Premature write-reply." severity error;
            axi_bcount <= axi_bcount + 1;
        end if;

        if (axi_rvalid = '1' and axi_rready = '1') then
            assert (axi_rdata = i2s(axi_rcount, 32))
                report "Read-data mismatch." severity error;
            assert (axi_rresp = "00")
                report "Unexpected read error." severity error;
            assert (axi_rcount < axi_arcount)
                report "Premature read-data." severity error;
            axi_rcount <= axi_rcount + 1;
        end if;

        -- Flow-control randomization for "B" and "R" pipes.
        uniform(seed1, seed2, rand);
        axi_bready <= bool2bit(rand < rate_b);
        uniform(seed1, seed2, rand);
        axi_rready <= bool2bit(rand < rate_r);
    end if;
end process;

-- Unit under test.
uut : entity work.cfgbus_host_axi
    generic map(ADDR_WIDTH => ADDR_WIDTH)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    axi_clk     => axi_clk,
    axi_aresetn => reset_n,
    axi_irq     => open,
    axi_awaddr  => axi_awaddr,
    axi_awvalid => axi_awvalid,
    axi_awready => axi_awready,
    axi_wdata   => axi_wdata,
    axi_wvalid  => axi_wvalid,
    axi_wready  => axi_wready,
    axi_bresp   => axi_bresp,
    axi_bvalid  => axi_bvalid,
    axi_bready  => axi_bready,
    axi_araddr  => axi_araddr,
    axi_arvalid => axi_arvalid,
    axi_arready => axi_arready,
    axi_rdata   => axi_rdata,
    axi_rresp   => axi_rresp,
    axi_rvalid  => axi_rvalid,
    axi_rready  => axi_rready);

-- Respond to read and write commands.
cfg_sumaddr <= 1024 * cfg_cmd.devaddr + cfg_cmd.regaddr;

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

        -- Confirm read-address and respond.
        if (cfg_cmd.rdcmd = '1') then
            assert (cfg_sumaddr = cfg_rdcount)
                report "Read address mismatch." severity error;
            cfg_rdcount <= cfg_rdcount + 1;
            cfg_ack <= cfgbus_reply(i2s(cfg_rdcount, 32));
        else
            cfg_ack <= cfgbus_idle;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    procedure run_one(aw, w, b, ar, r : real) is
    begin
        test_index  <= test_index + 1;
        rate_aw     <= aw;
        rate_w      <= w;
        rate_b      <= b;
        rate_ar     <= ar;
        rate_r      <= r;
        wait for 100 us;
    end procedure;
begin
    wait until rising_edge(reset_n);
    wait for 1 us;

    -- General low-rate test.
    run_one(0.1, 0.1, 0.1, 0.1, 0.1);

    -- Try making each pipe the fastest.
    run_one(0.9, 0.1, 0.1, 0.1, 0.1);
    run_one(0.1, 0.9, 0.1, 0.1, 0.1);
    run_one(0.1, 0.1, 0.9, 0.1, 0.1);
    run_one(0.1, 0.1, 0.1, 0.9, 0.1);
    run_one(0.1, 0.1, 0.1, 0.1, 0.9);

    -- Try making each pipe the slowest.
    run_one(0.1, 0.9, 0.9, 0.9, 0.9);
    run_one(0.9, 0.1, 0.9, 0.9, 0.9);
    run_one(0.9, 0.9, 0.1, 0.9, 0.9);
    run_one(0.9, 0.9, 0.9, 0.1, 0.9);
    run_one(0.9, 0.9, 0.9, 0.9, 0.1);

    report "All tests completed.";
    wait;
end process;

end tb;
