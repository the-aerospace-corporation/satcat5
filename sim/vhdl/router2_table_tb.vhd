--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the IPv4 routing table
--
-- This unit test for the "router2_table" block confirms that all ConfigBus
-- opcodes operate correctly, and that routing-table search results follow
-- the expected maximum-prefix matching rules, including the default route.
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_sim_tools.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.rand_vec;
use     work.router2_common.all;

entity router2_table_tb is
    generic (
    DEVADDR     : integer := 42;    -- ConfigBus address
    TABLE_SIZE  : positive := 5;    -- Number of table entries
    META_WIDTH  : positive := 4);   -- Metadata word size
end router2_table_tb;

architecture tb of router2_table_tb is

constant REF_WIDTH : integer := META_WIDTH + 32 + 8 + 48;
subtype ref_word is std_logic_vector(REF_WIDTH-1 downto 0);
subtype meta_word is std_logic_vector(META_WIDTH-1 downto 0);

-- Clock and reset generation.
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference FIFO.
signal fifo_vec     : ref_word := (others => '0');
signal ref_vec      : ref_word := (others => '0');
signal ref_meta     : meta_word;
signal ref_dst_ip   : ip_addr_t;
signal ref_dst_idx  : byte_u;
signal ref_dst_mac  : mac_addr_t;
signal ref_found    : std_logic;
signal ref_valid    : std_logic;

-- Unit under test.
signal in_dst_ip   : ip_addr_t := (others => '0');
signal in_next     : std_logic := '0';
signal in_meta     : meta_word := (others => '0');
signal out_dst_ip  : ip_addr_t;
signal out_dst_idx : byte_u;
signal out_dst_mac : mac_addr_t;
signal out_found   : std_logic;
signal out_next    : std_logic;
signal out_meta    : meta_word;

-- High-level test control
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;

begin

-- Clock and reset generation
clk_100 <= not clk_100 after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
cfg_cmd.clk     <= clk_100;
cfg_cmd.reset_p <= reset_p;

-- Reference FIFO
u_fifo_ref : entity work.fifo_smol_sync
    generic map(IO_WIDTH => REF_WIDTH)
    port map(
    in_data     => fifo_vec,
    in_write    => in_next,
    out_data    => ref_vec,
    out_valid   => ref_valid,
    out_read    => out_next,
    clk         => clk_100,
    reset_p     => reset_p);

ref_meta    <= ref_vec(ref_vec'left downto 88);
ref_dst_ip  <= ref_vec(87 downto 56);
ref_dst_idx <= unsigned(ref_vec(55 downto 48));
ref_dst_mac <= ref_vec(47 downto 0);
ref_found   <= or_reduce(ref_dst_mac);

-- Unit under test.
uut : entity work.router2_table
    generic map(
    DEVADDR     => DEVADDR,
    TABLE_SIZE  => TABLE_SIZE,
    META_WIDTH  => META_WIDTH)
    port map(
    in_dst_ip   => in_dst_ip,
    in_next     => in_next,
    in_meta     => in_meta,
    out_dst_ip  => out_dst_ip,
    out_dst_idx => out_dst_idx,
    out_dst_mac => out_dst_mac,
    out_found   => out_found,
    out_next    => out_next,
    out_meta    => out_meta,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk_100,
    reset_p     => reset_p);

-- Compare output against reference.
p_check : process(clk_100)
begin
    if rising_edge(clk_100) then
        if (out_next = '1' and ref_valid = '0') then
            -- Output without a matching reference is an error.
            report "Unexpected output." severity error;
        elsif (out_next = '1' and ref_found = '1') then
            -- Check required fields regardless of "found" flag.
            assert (ref_dst_ip = out_dst_ip)
                report "Output IP mismatch." severity error;
            assert (ref_found = out_found)
                report "Output 'found' mismatch." severity error;
            assert (ref_meta = out_meta)
                report "Output metadata mismatch." severity error;
        end if;

        if (out_next = '1' and ref_valid = '1' and ref_found = '1') then
            -- Check additional fields if there is a matching route.
            assert (ref_dst_idx = out_dst_idx)
                report "Output index mismatch." severity error;
            assert (ref_dst_mac = out_dst_mac)
                report "Output MAC mismatch." severity error;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Define all parameters for a single CIDR route.
    type route_t is record
        subnet  : ip_addr_t;
        mask    : ip_addr_t;
        plen    : natural;
        dst_idx : natural;
        dst_mac : mac_addr_t;
    end record;
    constant ROUTE_NONE : route_t := (IP_NOT_VALID, IP_NOT_VALID, 0, 0, MAC_ADDR_NONE);

    -- Mirror a copy of the routing table contents.
    type mirror_t is array(0 to TABLE_SIZE) of route_t;
    variable route_wridx : natural := 0;
    variable route_table : mirror_t := (others => ROUTE_NONE);

    -- Poll the control register until it reports idle/ready.
    procedure wait_idle is begin
        wait until rising_edge(cfg_cmd.clk);
        cfg_cmd.devaddr <= DEVADDR;
        cfg_cmd.regaddr <= RT_ADDR_CIDR_CTRL;
        cfg_cmd.rdcmd <= '1';
        wait until rising_edge(cfg_cmd.clk);
        while (cfg_ack.rdack = '0' or cfg_ack.rdata(31) = '1') loop
            wait until rising_edge(cfg_cmd.clk);
        end loop;
        cfg_cmd.rdcmd <= '0';
        wait until rising_edge(cfg_cmd.clk);
    end procedure;

    -- Clear the routing table contents.
    procedure load_clear is
    begin
        route_table := (others => ROUTE_NONE);
        route_wridx := 0;               -- Reset write index.
        wait_idle;                      -- Wait until idle/ready.
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_CTRL, x"30000000");
    end procedure;

    -- Set the default route.
    procedure load_default_route(pidx: natural; mac: mac_addr_t) is
        variable cfg1 : cfgbus_word := i2s(pidx, 16) & mac(47 downto 32);
        variable cfg2 : cfgbus_word := mac(31 downto 0);
        variable cfg3 : cfgbus_word := (others => '0');
        variable cfg4 : cfgbus_word := x"20000000";
    begin
        route_table(TABLE_SIZE) := (IP_NOT_VALID, IP_NOT_VALID, 0, pidx, mac);
        wait_idle;                      -- Wait until idle/ready.
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg1);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg2);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg3);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_CTRL, cfg4);
    end procedure;

    procedure load_static_route(pidx: natural; mac: mac_addr_t; subnet: ip_addr_t; plen: natural) is
        variable cfg1 : cfgbus_word := i2s(plen, 8) & i2s(pidx, 8) & mac(47 downto 32);
        variable cfg2 : cfgbus_word := mac(31 downto 0);
        variable cfg3 : cfgbus_word := subnet;
        variable cfg4 : cfgbus_word := x"1000" & i2s(route_wridx, 16);
    begin
        assert (route_wridx < TABLE_SIZE)
            report "Table overflow." severity failure;
        route_table(route_wridx) := (subnet, ip_prefix2mask(plen), plen, pidx, mac);
        route_wridx := route_wridx + 1; -- Increment write index.
        wait_idle;                      -- Wait until idle/ready.
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg1);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg2);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_DATA, cfg3);
        cfgbus_write(cfg_cmd, DEVADDR, RT_ADDR_CIDR_CTRL, cfg4);
    end procedure;

    procedure test_single(dst: ip_addr_t) is
        variable best_idx   : natural := TABLE_SIZE;
        variable tbl_pidx   : byte_t := (others => '0');
        variable tbl_mac    : mac_addr_t := (others => '0');
        variable rand_meta  : meta_word := rand_vec(META_WIDTH);
    begin
        -- Search table for the longest-prefix match...
        for n in route_table'range loop
            if (ip_in_subnet(dst, route_table(n).subnet, route_table(n).mask)) then
                if (route_table(n).plen > route_table(best_idx).plen) then
                    best_idx := n;
                end if;
            end if;
        end loop;
        tbl_mac   := route_table(best_idx).dst_mac;
        tbl_pidx  := i2s(route_table(best_idx).dst_idx, 8);
        -- Load input and reference simultanously.
        test_index  <= test_index + 1;
        in_next     <= '1';
        in_dst_ip   <= dst;
        in_meta     <= rand_meta;
        fifo_vec    <= rand_meta & dst & tbl_pidx & tbl_mac;
        wait until rising_edge(clk_100);
        in_next     <= '0';
    end procedure;
begin
    -- Take control of ConfigBus signals (except clock and reset).
    cfg_cmd.clk     <= 'Z';
    cfg_cmd.sysaddr <= 0;
    cfg_cmd.devaddr <= DEVADDR;
    cfg_cmd.regaddr <= 0;
    cfg_cmd.wdata   <= (others => '0');
    cfg_cmd.wstrb   <= (others => '1');
    cfg_cmd.wrcmd   <= '0';
    cfg_cmd.rdcmd   <= '0';
    cfg_cmd.reset_p <= 'Z';

    -- Load the first routing table.
    wait for 2 us;
    load_default_route(42, x"DEADBEEF0042");
    load_static_route (43, x"DEADBEEF0043", x"40000000", 2);
    load_static_route (44, x"DEADBEEF0044", x"80000000", 2);
    load_static_route (45, x"DEADBEEF0045", x"C0000000", 2);
    wait_idle;
    report "Test configuration 1...";

    -- Test a lot of randomly selected IP addresses...
    wait until rising_edge(clk_100);
    for n in 1 to 32768 loop
        test_single(rand_vec(32));
    end loop;

    -- Load a new routing table configuration.
    wait for 2 us;
    load_clear;
    load_static_route (42, x"DEADBEEF0042", x"40000000", 2);
    load_static_route (43, x"DEADBEEF0043", x"80000000", 1);
    load_static_route (44, x"DEADBEEF0044", x"C0000000", 2);
    load_static_route (45, x"DEADBEEF0045", x"D0000000", 4);
    load_static_route (0,  MAC_ADDR_NONE,   x"E0000000", 4);
    wait_idle;
    report "Test configuration 2...";

    -- Test a lot of randomly selected IP addresses...
    wait until rising_edge(clk_100);
    for n in 1 to 32768 loop
        test_single(rand_vec(32));
    end loop;

    -- End-of-test cleanup.
    wait for 1 us;
    if (ref_valid = '1') then
        report "Unexpected leftovers after end of test." severity error;
    else
        report "All tests completed.";
    end if;
    wait;
end process;

end tb;
