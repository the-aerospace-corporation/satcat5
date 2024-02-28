--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for ConfigBus interface to the MAC table
--
-- This is a unit test for the adapter that connects the MAC-table's
-- auxiliary read/write functions to a ConfigBus interface.
--
-- The complete test takes less than 0.1 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.cfgbus_sim_tools.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity mac_query_tb is
    generic (
    DEV_ADDR    : integer := 42;
    PORT_COUNT  : positive := 8;
    TABLE_SIZE  : positive := 24);
    -- Unit testbench top level, no I/O ports
end mac_query_tb;

architecture tb of mac_query_tb is

-- Unit under test
signal mac_clk      : std_logic := '0';
signal mac_clear    : std_logic;
signal mac_learn    : std_logic;
signal read_index   : integer range 0 to TABLE_SIZE-1;
signal read_valid   : std_logic;
signal read_ready   : std_logic := '0';
signal read_addr    : mac_addr_t := (others => '0');
signal read_psrc    : integer range 0 to PORT_COUNT-1;
signal write_addr   : mac_addr_t;
signal write_psrc   : integer range 0 to PORT_COUNT-1;
signal write_valid  : std_logic;
signal write_ready  : std_logic := '0';

-- Test data
signal last_clear   : std_logic := '0';
signal last_rd_idx  : integer range 0 to TABLE_SIZE-1 := 0;
signal last_wr_addr : mac_addr_t := (others => '0');
signal last_wr_psrc : integer range 0 to PORT_COUNT-1 := 0;

-- Command interface.
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_rdval    : cfgbus_word;

begin

-- Clock and reset generation.
mac_clk <= not mac_clk after 4.0 ns;    -- 1 / (2*4ns) = 125 MHz
u_clk : cfgbus_clock_source
    port map(clk_out => cfg_cmd.clk);

-- Helper object for ConfigBus reads
u_read_latch : cfgbus_read_latch
    port map(
    cfg_cmd => cfg_cmd,
    cfg_ack => cfg_ack,
    readval => cfg_rdval);

-- Unit under test.
uut : entity work.mac_query
    generic map(
    DEV_ADDR    => DEV_ADDR,
    PORT_COUNT  => PORT_COUNT,
    TABLE_SIZE  => TABLE_SIZE)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    mac_clk     => mac_clk,
    mac_clear   => mac_clear,
    mac_learn   => mac_learn,
    read_index  => read_index,
    read_valid  => read_valid,
    read_ready  => read_ready,
    read_addr   => read_addr,
    read_psrc   => read_psrc,
    write_addr  => write_addr,
    write_psrc  => write_psrc,
    write_valid => write_valid,
    write_ready => write_ready);

-- Detect "clear" events since the last register write.
p_clear : process(mac_clk, cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) and (cfg_cmd.wrcmd = '1') then
        last_clear <= '0';
    end if;
    if rising_edge(mac_clk) and (mac_clear = '1') then
        last_clear <= '1';
    end if;
end process;

-- Test data and flow control randomization.
p_mac : process(mac_clk)
    variable pre_read, pre_write : std_logic := '0';
begin
    if rising_edge(mac_clk) then
        -- Flow-control randomization.
        pre_read    := rand_bit(0.1);
        pre_write   := rand_bit(0.1);
        read_ready  <= pre_read;
        write_ready <= pre_write;

        -- Read command: Randomize response just before read_ready.
        if (read_valid = '1' and pre_read = '1') then
            read_addr <= rand_vec(read_addr'length);
            read_psrc <= rand_int(PORT_COUNT);
        end if;

        -- Write and read commands: Latch parameters.
        if (read_valid = '1' and read_ready = '1') then
            last_rd_idx <= read_index;
        end if;

        if (write_valid = '1' and write_ready = '1') then
            last_wr_addr <= write_addr;
            last_wr_psrc <= write_psrc;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    constant OPCODE_IDLE    : byte_t := x"00";
    constant OPCODE_READ    : byte_t := x"01";
    constant OPCODE_WRITE   : byte_t := x"02";
    constant OPCODE_CLEAR   : byte_t := x"03";
    constant OPCODE_LEARN   : byte_t := x"04";

    procedure mactbl_wait_idle is
    begin
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REGADDR_QUERY_CTRL);
        while (cfg_rdval(31 downto 24) /= OPCODE_IDLE) loop
            cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REGADDR_QUERY_CTRL);
        end loop;
    end procedure;

    procedure mactbl_read(tbl_idx : natural) is
        variable opcode : cfgbus_word := OPCODE_READ & i2s(tbl_idx, 24);
    begin
        -- Issue the command and wait for it to complete.
        mactbl_wait_idle;
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL, opcode);
        mactbl_wait_idle;
        -- Confirm results match expectations.
        assert (last_rd_idx = tbl_idx)
            report "Read index mismatch" severity error;
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REGADDR_QUERY_CTRL);
        assert (u2i(cfg_rdval(15 downto 0)) = read_psrc)
            report "Read PSRC mismatch" severity error;
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REGADDR_QUERY_MAC_LSB);
        assert (cfg_rdval(31 downto 0) = read_addr(31 downto 0))
            report "Read MAC-LSB mismatch" severity error;
        cfgbus_readwait(cfg_cmd, cfg_ack, DEV_ADDR, REGADDR_QUERY_MAC_MSB);
        assert (cfg_rdval(15 downto 0) = read_addr(47 downto 32))
            report "Read MAC-MSB mismatch" severity error;
    end procedure;

    procedure mactbl_write(port_idx : natural; mac_addr : mac_addr_t) is
        variable opcode : cfgbus_word := OPCODE_WRITE & i2s(port_idx, 24);
    begin
        -- Issue the command and wait for it to complete.
        mactbl_wait_idle;
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_LSB, mac_addr(31 downto 0));
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_MAC_MSB, x"0000" & mac_addr(47 downto 32));
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL, opcode);
        mactbl_wait_idle;
        -- Confirm results match expectations.
        assert (last_wr_addr = mac_addr)
            report "Write address mismatch" severity error;
        assert (last_wr_psrc = port_idx)
            report "Write index mismatch" severity error;
    end procedure;

    procedure mactbl_clear is
        variable opnone : cfgbus_word := OPCODE_IDLE & i2s(0, 24);
        variable opcode : cfgbus_word := OPCODE_CLEAR & i2s(0, 24);
    begin
        -- Issue a no-op to clear the test flag.
        mactbl_wait_idle;
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL, opcode);
        mactbl_wait_idle;
        assert (last_clear = '1')
            report "Missing CLEAR strobe" severity error;
        -- Issue a clear command and confirm test flag.
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL, opcode);
        mactbl_wait_idle;
        assert (last_clear = '1')
            report "Missing CLEAR strobe" severity error;
    end procedure;

    procedure mactbl_learn(enable : std_logic) is
        variable opcode : cfgbus_word := OPCODE_LEARN & i2s(u2i(enable), 24);
    begin
        -- Issue the command and wait for it to complete.
        mactbl_wait_idle;
        cfgbus_write(cfg_cmd, DEV_ADDR, REGADDR_QUERY_CTRL, opcode);
        mactbl_wait_idle;
        -- Confirm results match expectations.
        assert (mac_learn = enable)
            report "Learning-enable mismatch" severity error;
    end procedure;
begin
    -- Initial reset.
    cfgbus_reset(cfg_cmd);
    wait for 1 us;

    -- Issue each command a few times with random arguments.
    for n in 1 to 10 loop
        mactbl_read(rand_int(TABLE_SIZE));
    end loop;
    for n in 1 to 10 loop
        mactbl_write(rand_int(PORT_COUNT), rand_vec(48));
    end loop;
    for n in 1 to 10 loop
        mactbl_clear;
    end loop;
    for n in 1 to 10 loop
        mactbl_learn(rand_bit);
    end loop;

    report "All tests completed!";
    wait;
end process;

end tb;
