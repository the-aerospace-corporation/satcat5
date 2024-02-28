--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus to AXI-Lite converter
--
-- This is a unit test for the "cfgbus_to_axilite" block.  It exercises
-- a series of valid and invalid read/write commands and confirms outputs
-- match expectations in all edge-cases.
--
-- The complete test takes less than 0.1 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.router_sim_tools.all;

entity cfgbus_to_axilite_tb is
    -- Unit testbench top level, no I/O ports
end cfgbus_to_axilite_tb;

architecture tb of cfgbus_to_axilite_tb is

-- Control register addresses.
constant ADDR_WIDTH : integer := 16;
constant DEV_ADDR   : integer := 42;
constant REG_ADDR   : integer := 0;
constant REG_WRITE  : integer := 1;
constant REG_READ   : integer := 2;
constant REG_IRQ    : integer := 3;

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal clk_125      : std_logic := '0';
signal reset_n      : std_logic := '0';

-- Simulated AXI peripheral.
signal cmd_addr     : cfgbus_word := (others => '0');
signal cmd_data     : cfgbus_word := (others => '0');
signal count_aw     : natural := 0;
signal count_w      : natural := 0;
signal count_b      : natural := 0;
signal count_ar     : natural := 0;
signal count_r      : natural := 0;

-- AXI bus.
signal axi_awaddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_awvalid  : std_logic;
signal axi_awready  : std_logic := '0';
signal axi_wdata    : std_logic_vector(31 downto 0);
signal axi_wstrb    : std_logic_vector(3 downto 0);
signal axi_wvalid   : std_logic;
signal axi_wready   : std_logic := '0';
signal axi_bresp    : std_logic_vector(1 downto 0) := (others => '0');
signal axi_bvalid   : std_logic := '0';
signal axi_bready   : std_logic;
signal axi_araddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_arvalid  : std_logic;
signal axi_arready  : std_logic := '0';
signal axi_rdata    : std_logic_vector(31 downto 0) := (others => '0');
signal axi_rresp    : std_logic_vector(1 downto 0) := (others => '0');
signal axi_rvalid   : std_logic := '0';
signal axi_rready   : std_logic;

-- Test control.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_rdval    : cfgbus_word;
signal cfg_rderr    : std_logic;
signal err_request  : std_logic := '0';

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5.0 ns;
clk_125 <= not clk_125 after 4.0 ns;
reset_n <= '1' after 1.0 us;
cfg_cmd.clk <= clk_100;

-- Model a very simple AXI peripheral.
p_axi : process(clk_125)
begin
    if rising_edge(clk_125) then
        -- Reads echo the most recent write value.
        if (axi_wvalid = '1' and axi_wready = '1') then
            cmd_data <= axi_wdata;
        end if;

        -- Count transactions on each pipe.
        -- (And make a note of read/write addresses.)
        if (axi_awvalid = '1' and axi_awready = '1') then
            count_aw <= count_aw + 1;
            cmd_addr <= resize(axi_awaddr, 32);
        end if;
        if (axi_wvalid = '1' and axi_wready = '1') then
            count_w <= count_w + 1;
            assert (axi_wstrb = "1111") report "Invalid write-strobe.";
        end if;
        if (axi_bvalid = '1' and axi_bready = '1') then
            count_b <= count_b + 1;
        end if;
        if (axi_arvalid = '1' and axi_arready = '1') then
            count_ar <= count_ar + 1;
            cmd_addr <= resize(axi_araddr, 32);
        end if;
        if (axi_rvalid = '1' and axi_rready = '1') then
            count_r <= count_r + 1;
        end if;
    end if;
end process;

-- Simple loopback for all AXI flow-control signals.
axi_awready <= axi_awvalid;
axi_wready  <= axi_wvalid;
axi_bvalid  <= axi_awvalid;
axi_arready <= axi_arvalid;
axi_rvalid  <= axi_arvalid;
axi_rdata   <= cmd_data;

-- On request, set error flags on BRESP and RRESP.
axi_bresp <= "11" when (err_request = '1') else "00";
axi_rresp <= "11" when (err_request = '1') else "00";

-- Unit under test.
uut : entity work.cfgbus_to_axilite
    generic map(
    DEVADDR     => DEV_ADDR,
    ADDR_WIDTH  => ADDR_WIDTH,
    IRQ_ENABLE  => false)   -- Not tested
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    axi_aclk    => clk_125,
    axi_aresetn => reset_n,
    axi_awaddr  => axi_awaddr,
    axi_awvalid => axi_awvalid,
    axi_awready => axi_awready,
    axi_wdata   => axi_wdata,
    axi_wstrb   => axi_wstrb,
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

-- Helper object for ConfigBus reads
u_read_latch : cfgbus_read_latch
    generic map(ERR_OK => true)
    port map(
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_ack,
    readval => cfg_rdval,
    readerr => cfg_rderr);

-- Test control.
p_test : process
    procedure axi_write(addr, data : natural) is
        variable addr_w : cfgbus_word := i2s(addr, 32);
        variable data_w : cfgbus_word := i2s(data, 32);
    begin
        -- Execute the write command.
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_ADDR, addr_w);
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_WRITE, data_w);

        -- Wait a moment, then check result.
        wait for 50 ns;
        assert (cmd_addr = addr_w) report "Write address mismatch: "
            & integer'image(u2i(cmd_addr)) & " vs. " & integer'image(u2i(addr_w));
        assert (cmd_data = data_w) report "Write data mismatch: "
            & integer'image(u2i(cmd_data)) & " vs. " & integer'image(u2i(data_w));
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REG_WRITE);
        assert (cfg_rdval(0) = not err_request) report "Write error mismatch.";
    end procedure;

    procedure axi_read(addr : natural) is
        variable addr_w : cfgbus_word := i2s(addr, 32);
    begin
        -- Execute the read command.
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_ADDR, addr_w);
        cfgbus_write(cfg_cmd, DEV_ADDR, REG_READ, CFGBUS_WORD_ZERO);

        -- Wait a moment, then check result.
        wait for 100 ns;
        assert (cmd_addr = addr_w) report "Read address mismatch: "
            & integer'image(u2i(cmd_addr)) & " vs. " & integer'image(u2i(addr_w));
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REG_READ, true);
        if (err_request = '1') then
            assert (cfg_rderr = '1') report "Missing read error.";
        else
            assert (cfg_rderr = '0') report "Unexpected read error.";
            assert (cfg_rdval = cmd_data) report "Read data mismatch: "
                & integer'image(u2i(cfg_rdval)) & " vs. " & integer'image(u2i(cmd_data));
        end if;
    end procedure;
begin
    -- Initial setup.
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Fixed reads and writes.
    for n in 1 to 10 loop
        axi_write(n, n);
    end loop;

    for n in 1 to 10 loop
        axi_read(n);
    end loop;

    -- Reading status while idle should cause an error.
    cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REG_READ, true);
    assert (cfg_rderr = '1') report "Missing error on empty.";

    -- Random reads and writes with error flags.
    for n in 1 to 200 loop
        err_request <= rand_bit;
        if (rand_bit = '1') then
            axi_write(rand_int(256), rand_int(256));
        else
            axi_read(rand_int(256));
        end if;
    end loop;

    -- Sanity check on total command counts.
    assert (count_aw = count_w and count_w = count_b)
        report "Command counter mismatch (AW/W/B).";
    assert (count_ar = count_r)
        report "Command counter mismatch (AR/R).";

    report "All tests completed!";
    wait;
end process;

end tb;
