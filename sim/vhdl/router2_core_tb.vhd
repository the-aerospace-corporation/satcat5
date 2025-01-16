--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Top-level testbench for the IPv4 router.
--
-- This block is the end-to-end unit test of the packet routing pipeline.
-- It instantiates a five-port router with five sources and five sinks;
-- core clock is chosen to ensure full throughput.  Once the routing table
-- is loaded, each source sends randomized traffic at moderate throughput.
-- The test passes if the total number of received packets matches the
-- expected value for each port.
--
-- The complete test takes 11.1 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.router2_common.all;
use     work.router_sim_tools.all;
use     work.switch_types.all;

entity router2_core_tb is
    -- Unit testbench top level, no I/O ports
end router2_core_tb;

architecture tb of router2_core_tb is

constant DEV_ADDR   : integer := 42;
constant PORT_COUNT : integer := 5;
constant ROUTER_MAC : mac_addr_t := x"DEADBEEFCAFE";
constant ROUTER_IP  : ip_addr_t := x"C0A80101";
constant ADDR1      : byte_u := x"01";
constant VERBOSE    : boolean := false;

-- Clock and reset generation.
signal clk_100          : std_logic := '0';
signal clk_125          : std_logic := '0';
signal reset_p          : std_logic := '1';

-- Source traffic generation.
type index_array is array(PORT_COUNT-1 downto 0) of byte_u;
type count_array is array(PORT_COUNT-1 downto 0) of natural;
signal pkt_dst      : index_array := (others => ADDR1);
signal pkt_expect   : count_array := (others => 0);
signal pkt_rcvd     : count_array := (others => 0);
signal pkt_sent     : count_array := (others => 0);

-- Unit under test.
signal prx_data     : array_rx_m2s(PORT_COUNT-1 downto 0);
signal ptx_data     : array_tx_s2m(PORT_COUNT-1 downto 0);
signal ptx_ctrl     : array_tx_m2s(PORT_COUNT-1 downto 0);

-- Overall test control.
signal test_phase   : natural := 0;
signal test_clr     : std_logic := '1';
signal test_run     : std_logic := '0';
signal test_regaddr : cfgbus_regaddr := 0;
signal test_wdata   : cfgbus_word := (others => '0');
signal test_wrcmd   : std_logic := '0';
signal test_rdcmd   : std_logic := '0';
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;

begin

-- Clock and reset generation.
clk_100 <= not clk_100 after 5 ns;
clk_125 <= not clk_125 after 4 ns;
reset_p <= '0' after 1 us;

-- Drive all ConfigBus signals.
-- Due to a bug in Vivado 2019.1, we cannot use "cfgbus_sim_tools"
-- for register addresses larger than 255, which are required here.
-- Workaround is to assign individual signals at the top level only.
cfg_cmd.clk     <= clk_100;
cfg_cmd.sysaddr <= 0;
cfg_cmd.devaddr <= DEV_ADDR;
cfg_cmd.regaddr <= test_regaddr;
cfg_cmd.wdata   <= test_wdata;
cfg_cmd.wstrb   <= (others => test_wrcmd);
cfg_cmd.wrcmd   <= test_wrcmd;
cfg_cmd.rdcmd   <= test_rdcmd;
cfg_cmd.reset_p <= reset_p;


-- Generate source and sink for each port.
gen_ports : for n in PORT_COUNT-1 downto 0 generate
    lbl_ports : block is
        constant IDX_LOCAL : byte_u := to_unsigned(n+1, 8);
    begin
        ptx_ctrl(n).clk     <= clk_100;
        ptx_ctrl(n).ready   <= '1';
        ptx_ctrl(n).pstart  <= '1';
        ptx_ctrl(n).tnow    <= TSTAMP_DISABLED;
        ptx_ctrl(n).tfreq   <= TFREQ_DISABLED;
        ptx_ctrl(n).txerr   <= '0';
        ptx_ctrl(n).reset_p <= reset_p;

        p_port : process(prx_data(n).clk)
            variable temp       : integer := 0;
            variable valid_req  : std_logic := '0';
        begin
            if rising_edge(prx_data(n).clk) then
                -- Randomize the destination address at the end of each packet.
                if (prx_data(n).last = '1') then
                    pkt_dst(n) <= to_unsigned(1 + rand_int(PORT_COUNT), 8);
                end if;

                -- Check for buffer under-run.  (Once a packet starts, new data must
                -- be ready on every clock or RGMII/SGMII interfaces will underflow.)
                if (valid_req = '1' and ptx_data(n).valid = '0') then
                    report "Output buffer underrun" severity error;
                end if;
                valid_req := ptx_data(n).valid and not ptx_data(n).last;

                -- Count packets sent by this port.
                if (test_clr = '1') then
                    pkt_sent(n) <= 0;
                elsif (prx_data(n).write = '1' and prx_data(n).last = '1') then
                    pkt_sent(n) <= pkt_sent(n) + 1;
                    if (VERBOSE) then
                        report "Packet from port " & integer'image(n)
                            & " to address " & integer'image(u2i(pkt_dst(n)));
                    end if;
                end if;

                -- Count packets that we expect to receive on this port.
                if (test_clr = '1') then
                    pkt_expect(n) <= 0;
                else
                    temp := 0;
                    for p in pkt_dst'range loop
                        if (prx_data(p).last = '1' and pkt_dst(p) = IDX_LOCAL) then
                            temp := temp + 1;
                        end if;
                    end loop;
                    pkt_expect(n) <= pkt_expect(n) + temp;
                end if;

                -- Count packets actually received by this port.
                if (test_clr = '1') then
                    pkt_rcvd(n) <= 0;
                elsif (ptx_data(n).valid = '1' and ptx_data(n).last = '1') then
                    pkt_rcvd(n) <= pkt_rcvd(n) + 1;
                    if (VERBOSE) then
                        report "Packet received by port " & integer'image(n);
                    end if;
                end if;
            end if;
        end process;

        u_src : entity work.ip_traffic_sim
            generic map(
            ROUTER_MAC  => ROUTER_MAC,
            CLK_DELAY   => 0.1 ns,
            INIT_SEED1  => (n+1)*12345,
            INIT_SEED2  => (n+1)*54321,
            AUTO_START  => false)
            port map(
            clk         => clk_100,
            reset_p     => reset_p,
            pkt_start   => test_run,
            idx_dst     => pkt_dst(n),
            idx_src     => IDX_LOCAL,
            out_rate    => 0.40,
            out_port    => prx_data(n));
    end block;
end generate;

-- Unit under test
uut : entity work.router2_core
    generic map(
    DEV_ADDR        => DEV_ADDR,
    CORE_CLK_HZ     => 125_000_000,
    DEBUG_VERBOSE   => VERBOSE,
    ALLOW_RUNT      => true,
    PORT_COUNT      => PORT_COUNT,
    DATAPATH_BYTES  => 4,
    IBUF_KBYTES     => 2,
    OBUF_KBYTES     => 16,
    CIDR_TABLE_SIZE => PORT_COUNT)
    port map(
    ports_rx_data   => prx_data,
    ports_tx_data   => ptx_data,
    ports_tx_ctrl   => ptx_ctrl,
    err_ports       => open,    -- Not tested
    err_router      => open,    -- Not tested
    cfg_cmd         => cfg_cmd,
    cfg_ack         => cfg_ack,
    core_clk        => clk_125,
    core_reset_p    => reset_p);

-- High-level test control.
p_test : process
    -- Write to the specified ConfigBus register.
    -- (Cannot use "cfgbus_sim_tools" due to compatibility workaround.)
    procedure cfgbus_write(reg: cfgbus_regaddr; dat: cfgbus_word) is
    begin
        wait until rising_edge(cfg_cmd.clk);
        test_regaddr <= reg;
        test_wdata   <= dat;
        test_wrcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        test_wrcmd   <= '0';
        assert (cfg_cmd.regaddr = reg) severity failure;
    end procedure;

    -- Read from the specified ConfigBus register.
    procedure cfgbus_read(reg: cfgbus_regaddr) is
    begin
        wait until rising_edge(cfg_cmd.clk);
        test_regaddr <= reg;
        test_rdcmd   <= '1';
        wait until rising_edge(cfg_cmd.clk);
        test_rdcmd   <= '0';
        assert (cfg_cmd.regaddr = reg) severity failure;
    end procedure;

    -- Wait for a table update to finish.
    procedure table_wait is
    begin
        -- Wait for operation to complete.
        -- (Note extra pipeline delay in this design.)
        wait until rising_edge(cfg_cmd.clk);
        test_regaddr <= RT_ADDR_CIDR_CTRL;
        test_rdcmd <= '1';
        wait until rising_edge(cfg_cmd.clk);
        wait until rising_edge(cfg_cmd.clk);
        wait for 1 ns;
        assert (cfg_ack.rdack = '1')
            report "Status register timeout." severity error;
        while (cfg_ack.rdata(31) = '1') loop
            wait until rising_edge(cfg_cmd.clk);
            wait for 1 ns;
        end loop;
        test_rdcmd <= '0';
        wait until rising_edge(cfg_cmd.clk);
    end procedure;

    -- Load one entry into the routing table.
    procedure table_route(
        rowidx: natural;        -- Table row
        dstidx: natural;        -- Destination port
        dstip:  ip_addr_t;      -- Destination address (/32)
        dstmac: mac_addr_t)     -- Next-hop address
    is
        constant plen : natural := 32;
        variable cfg1 : cfgbus_word := i2s(plen, 8) & i2s(dstidx, 8) & dstmac(47 downto 32);
        variable cfg2 : cfgbus_word := dstmac(31 downto 0);
        variable cfg3 : cfgbus_word := dstip;
    begin
        if (VERBOSE) then
            report "Loading table row #" & integer'image(rowidx);
        end if;
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg1);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg2);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg3);
        cfgbus_write(RT_ADDR_CIDR_CTRL, x"1000" & i2s(rowidx, 16));
        table_wait;
    end procedure;

    procedure run_trial(nwait : integer) is
    begin
        -- Announce start of traffic generation.
        report "Starting phase " & integer'image(test_phase+1);
        test_clr <= '0';
        test_run <= '1';
        test_phase <= test_phase + 1;

        -- Wait for designated number of sent packets.
        -- (For simplicity, only check the last port is above threshold.)
        wait until rising_edge(clk_100) and (pkt_sent(PORT_COUNT-1) >= nwait);
        test_run <= '0';

        -- Wait a little longer for pipeline to flush, then check counts.
        wait for 100 us;
        for n in pkt_rcvd'range loop
            assert (pkt_rcvd(n) = pkt_expect(n))
                report "Packet-count mismatch on port " & integer'image(n)
                    & ": " & integer'image(pkt_rcvd(n))
                    & " of " & integer'image(pkt_expect(n))
                severity error;
        end loop;
        test_clr <= '1';
        wait until rising_edge(clk_100);
        wait until rising_edge(clk_100);
    end procedure;
begin
    -- Reset plus a brief startup delay.
    test_phase  <= 0;
    test_clr    <= '1';
    test_run    <= '0';
    wait until reset_p = '0';
    wait for 1 us;

    -- Update router configuration with permissive rules.
    cfgbus_write(RT_ADDR_GATEWAY, x"0000" & ROUTER_MAC(47 downto 32));
    cfgbus_write(RT_ADDR_GATEWAY, ROUTER_MAC(31 downto 0));
    cfgbus_write(RT_ADDR_GATEWAY, ROUTER_IP);
    cfgbus_read(RT_ADDR_GATEWAY);   -- Read latches the new setting.

    -- Load the static routing table with pre-cached MAC addresses.
    table_wait;
    table_route(0, 0, x"01010101", x"010101010101");
    table_route(1, 1, x"02020202", x"020202020202");
    table_route(2, 2, x"03030303", x"030303030303");
    table_route(3, 3, x"04040404", x"040404040404");
    table_route(4, 4, x"05050505", x"050505050505");

    -- Run a few trials of increasing length.
    for n in 1 to 5 loop
        run_trial(10*n*n);
    end loop;

    report "All tests completed.";
    wait;
end process;

end tb;
