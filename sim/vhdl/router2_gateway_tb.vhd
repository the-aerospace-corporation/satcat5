--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for the router's IPv4 gateway
--
-- The "gateway" is block that performs next-hop routing and enforces
-- various rules required by RFC1812, inspecting various fields of the
-- IPv4 packet headers.  This block tests many of those rules, under
-- a variety of flow-control conditions.
--
-- The complete test takes 2.4 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.router_sim_tools.all;
use     work.router2_common.all;
use     work.switch_types.all;

entity router2_gateway_tb_helper is
    generic (
    IO_BYTES    : positive;     -- Width of datapath
    VERBOSITY   : natural);     -- Simulation log level (0/1/2)
end router2_gateway_tb_helper;

architecture helper of router2_gateway_tb_helper is

-- Test parameters.
constant DEVADDR    : integer := 42;
constant PORT_COUNT : integer := 3;
constant TABLE_SIZE : integer := 6;
subtype dmask_t is std_logic_vector(PORT_COUNT downto 0);
subtype rules_t is std_logic_vector(15 downto 0);

-- Commonly used port masks.
constant MASK_NONE      : dmask_t := (others => '0');
constant MASK_BCAST     : dmask_t := (others => '1');
constant MASK_OFFLOAD   : dmask_t := (PORT_COUNT => '1', others => '0');
constant MASK_PORT0     : dmask_t := (0 => '1', others => '0');
constant MASK_PORT1     : dmask_t := (1 => '1', others => '0');
constant MASK_PORT2     : dmask_t := (2 => '1', others => '0');

-- Address parameters for the test network:
--  The Cloud <--- P0 -> Test router  <- P1 ---> LAN with Local1a, Local1b
--  *.*.*.*              192.168.0.0             192.168.1.* (DEADBEEF1111-2222)
--  FACADE123456         DEADBEEF0000 <- P2 ---> LAN with Local2a, Local2b
--                                               192.168.2.* (DEADBEEF3333-5555)
constant IP_ROUTER      : ip_addr_t := x"C0A80000";         -- 192.168.0.0
constant IP_SUBNET1     : ip_addr_t := x"C0A80100";         -- 192.168.1.* (Port 1)
constant IP_SUBNET2     : ip_addr_t := x"C0A80200";         -- 192.168.2.* (Port 2)
constant IP_REMOTE1     : ip_addr_t := x"C0A80801";         -- 192.168.8.1 (Port 0)
constant IP_REMOTE2     : ip_addr_t := x"C0A80802";         -- 192.168.8.2 (Port 0)
constant IP_LOCAL1A     : ip_addr_t := x"C0A80101";         -- LAN Endpoint (port 1)
constant IP_LOCAL1B     : ip_addr_t := x"C0A80102";         -- LAN Endpoint (port 1)
constant IP_LOCAL2A     : ip_addr_t := x"C0A80201";         -- LAN Endpoint (port 2)
constant IP_LOCAL2B     : ip_addr_t := x"C0A80202";         -- LAN Endpoint (port 2)
constant IP_LOCAL2C     : ip_addr_t := x"C0A80203";         -- LAN Endpoint (port 2)
constant MAC_UPLINK     : mac_addr_t := x"FACADE123456";    -- Uplink to cloud (Port 0)
constant MAC_ROUTER     : mac_addr_t := x"DEADBEEF0000";    -- Router under test
constant MAC_LOCAL1A    : mac_addr_t := x"DEADBEEF1111";    -- LAN Endpoint (port 1)
constant MAC_LOCAL1B    : mac_addr_t := x"DEADBEEF2222";    -- LAN Endpoint (port 1)
constant MAC_LOCAL2A    : mac_addr_t := x"DEADBEEF3333";    -- LAN Endpoint (port 2)
constant MAC_LOCAL2B    : mac_addr_t := x"DEADBEEF4444";    -- LAN Endpoint (port 2)
constant MAC_LOCAL2C    : mac_addr_t := x"DEADBEEF5555";    -- LAN Endpoint (port 2)
-- Note: All MAC addresses are cached except for MAC_LOCAL2C.

-- Clock and reset generation.
signal pre_clk      : std_logic := '0';
signal clk_100      : std_logic := '0';
signal reset_p      : std_logic := '1';

-- Reference stream.
constant LOAD_BYTES : positive := 8;
constant META_WIDTH : positive := PORT_COUNT+1 + 48 + 8;
signal fifo_mvec    : std_logic_vector(META_WIDTH-1 downto 0);
signal in_mvec      : std_logic_vector(META_WIDTH-1 downto 0);
signal ref_mvec     : std_logic_vector(META_WIDTH-1 downto 0);

signal fifo_data    : std_logic_vector(8*LOAD_BYTES-1 downto 0) := (others => '0');
signal fifo_nlast   : integer range 0 to LOAD_BYTES := 0;
signal fifo_write   : std_logic := '0';
signal fifo_dstmac  : mac_addr_t := (others => '0');
signal fifo_pdst    : dmask_t := (others => '0');
signal fifo_psrc    : integer range 0 to PORT_COUNT-1 := 0;

signal ref_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal ref_nlast    : integer range 0 to IO_BYTES;
signal ref_dstmac   : mac_addr_t;
signal ref_pdst     : dmask_t;
signal ref_psrc     : integer range 0 to PORT_COUNT-1;
signal ref_empty    : std_logic;

-- Unit under test.
signal in_data      : std_logic_vector(8*IO_BYTES-1 downto 0);
signal in_nlast     : integer range 0 to IO_BYTES;
signal in_valid     : std_logic;
signal in_ready     : std_logic;
signal in_empty     : std_logic;
signal in_psrc      : integer range 0 to PORT_COUNT-1;
signal out_data     : std_logic_vector(8*IO_BYTES-1 downto 0);
signal out_nlast    : integer range 0 to IO_BYTES;
signal out_valid    : std_logic;
signal out_ready    : std_logic;
signal out_dstmac   : mac_addr_t;
signal out_srcmac   : mac_addr_t;
signal out_pdst     : dmask_t;
signal out_psrc     : integer range 0 to PORT_COUNT-1;

-- High-level test control
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal test_index   : natural := 0;
signal test_rate_i  : real := 0.0;
signal test_rate_o  : real := 0.0;
signal test_rules   : rules_t := (others => '1');
signal test_regaddr : cfgbus_regaddr := 0;
signal test_wdata   : cfgbus_word := (others => '0');
signal test_wrcmd   : std_logic := '0';
signal test_rdcmd   : std_logic := '0';
signal test_bmask   : dmask_t;
signal block_bad_dmac   : std_logic;
signal block_ipv4_bcast : std_logic;
signal block_ipv4_mcast : std_logic;
signal block_noip_bcast : std_logic;
signal block_noip_all   : std_logic;
signal block_lcl_bcast  : std_logic;

begin

-- Clock and reset generation
-- (Taking care to avoid simulation artifacts from single-tick delays.)
pre_clk <= not pre_clk after 5 ns;  -- 1 / (2*5ns) = 100 MHz
reset_p <= '0' after 1 us;
clk_100         <= pre_clk;         -- Matched delay
cfg_cmd.clk     <= pre_clk;         -- Matched delay

-- Drive all other ConfigBus signals.
-- Due to a bug in Vivado 2019.1, we cannot use "cfgbus_sim_tools"
-- for register addresses larger than 255, which are required here.
-- Workaround is to assign individual signals at the top level only.
cfg_cmd.sysaddr <= 0;
cfg_cmd.devaddr <= DEVADDR;
cfg_cmd.regaddr <= test_regaddr;
cfg_cmd.wdata   <= test_wdata;
cfg_cmd.wstrb   <= (others => test_wrcmd);
cfg_cmd.wrcmd   <= test_wrcmd;
cfg_cmd.rdcmd   <= test_rdcmd;
cfg_cmd.reset_p <= reset_p;

-- Input and reference FIFOs.
u_fifo_in : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => META_WIDTH)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_data,
    in_meta         => fifo_mvec,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk_100,
    out_data        => in_data,
    out_meta        => in_mvec,
    out_nlast       => in_nlast,
    out_valid       => in_valid,
    out_ready       => in_ready,
    out_empty       => in_empty,
    out_rate        => test_rate_i,
    reset_p         => reset_p);

u_fifo_ref : entity work.fifo_sim_throttle
    generic map(
    INPUT_BYTES     => LOAD_BYTES,
    OUTPUT_BYTES    => IO_BYTES,
    META_WIDTH      => META_WIDTH)
    port map(
    in_clk          => clk_100,
    in_data         => fifo_data,
    in_meta         => fifo_mvec,
    in_nlast        => fifo_nlast,
    in_write        => fifo_write,
    out_clk         => clk_100,
    out_data        => ref_data,
    out_meta        => ref_mvec,
    out_nlast       => ref_nlast,
    out_valid       => out_ready,
    out_ready       => out_valid,
    out_empty       => ref_empty,
    out_rate        => test_rate_o,
    reset_p         => reset_p);

-- Metadata conversion for the input and reference FIFOs.
fifo_mvec   <= fifo_pdst & fifo_dstmac & i2s(fifo_psrc, 8);
in_psrc     <= u2i(in_mvec(7 downto 0));
ref_psrc    <= u2i(ref_mvec(7 downto 0));
ref_dstmac  <= ref_mvec(55 downto 8);
ref_pdst    <= ref_mvec(ref_mvec'left downto 56);

-- Break out each named rule.
block_lcl_bcast     <= test_rules(5);
block_noip_all      <= test_rules(4);
block_noip_bcast    <= test_rules(3);
block_ipv4_mcast    <= test_rules(2);
block_ipv4_bcast    <= test_rules(1);
block_bad_dmac      <= test_rules(0);
test_bmask <= (not MASK_OFFLOAD) when (block_lcl_bcast = '1') else MASK_BCAST;

-- Unit under test.
uut : entity work.router2_gateway
    generic map(
    DEVADDR     => DEVADDR,
    IO_BYTES    => IO_BYTES,
    PORT_COUNT  => PORT_COUNT,
    TABLE_SIZE  => TABLE_SIZE,
    DEFAULT_MAC => MAC_ROUTER,
    DEFAULT_IP  => IP_ROUTER,
    DEFAULT_BLK => x"FFFF",
    VERBOSE     => VERBOSITY > 0)
    port map(
    in_data     => in_data,
    in_nlast    => in_nlast,
    in_valid    => in_valid,
    in_ready    => in_ready,
    in_psrc     => in_psrc,
    in_meta     => SWITCH_META_NULL,
    out_data    => out_data,
    out_nlast   => out_nlast,
    out_valid   => out_valid,
    out_ready   => out_ready,
    out_dstmac  => out_dstmac,
    out_srcmac  => out_srcmac,
    out_pdst    => out_pdst,
    out_psrc    => out_psrc,
    out_meta    => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk_100,
    reset_p     => reset_p);

-- Check the output stream.
p_check : process(clk_100)
    variable print_msg : boolean := true;
    procedure assert_once(ok: boolean; msg: string) is
    begin
        if print_msg and not ok then
            report msg severity error;
            print_msg := false; -- Suppress later errors
        end if;
    end procedure;
begin
    if rising_edge(clk_100) then
        if (out_valid = '1' and out_ready = '1') then
            assert_once(out_data   = ref_data,      "DATA mismatch");
            assert_once(out_nlast  = ref_nlast,     "NLAST mismatch");
            assert_once(out_dstmac = ref_dstmac,    "DSTMAC mismatch");
            assert_once(out_srcmac = MAC_ROUTER,    "SRCMAC mismatch");
            assert_once(out_pdst   = ref_pdst,      "PDST mismatch");
            assert_once(out_psrc   = ref_psrc,      "PSRC mismatch");
            if (out_nlast > 0) then
                test_index <= test_index + 1;
                print_msg := true; -- Reset once-per-packet flag.
            end if;
        end if;
    end if;
end process;

-- High-level test control.
p_test : process
    -- Define all parameters for a single CIDR route.
    type route_t is record
        subnet  : ip_addr_t;    -- Subnet base address
        mask    : ip_addr_t;    -- Subnet mask (from plen)
        plen    : natural;      -- Prefix length
        pidx    : natural;      -- Source or destination port
        dstmac  : mac_addr_t;   -- Next-hop MAC address, if known
    end record;
    constant ROUTE_NONE : route_t := (IP_NOT_VALID, IP_NOT_VALID, 0, 0, MAC_ADDR_NONE);

    -- Mirror a copy of the routing table contents.
    type mirror_t is array(0 to TABLE_SIZE) of route_t;
    variable route_table : mirror_t := (others => ROUTE_NONE);

    -- Write to a single ConfigBus register.
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

    -- Update router configuration using the RT_ADDR_GATEWAY register.
    procedure rules_update(rules: rules_t) is
        variable cfg1 : cfgbus_word := rules & MAC_ROUTER(47 downto 32);
        variable cfg2 : cfgbus_word := MAC_ROUTER(31 downto 0);
        variable cfg3 : cfgbus_word := IP_ROUTER(31 downto 0);
    begin
        cfgbus_write(RT_ADDR_GATEWAY, cfg1);
        cfgbus_write(RT_ADDR_GATEWAY, cfg2);
        cfgbus_write(RT_ADDR_GATEWAY, cfg3);
        test_rdcmd <= '1';
        test_rules <= rules;
        wait until rising_edge(cfg_cmd.clk);
        test_rdcmd <= '0';
    end procedure;

    -- Wait for a table update to finish.
    procedure table_wait is
    begin
        -- Wait for operation to complete.
        test_regaddr <= RT_ADDR_CIDR_CTRL;
        test_rdcmd <= '1';
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

    -- Clear the routing table.
    procedure table_clear is
    begin
        route_table := (others => ROUTE_NONE);
        cfgbus_write(RT_ADDR_CIDR_DATA, x"30000000");
        table_wait;
    end procedure;

    -- Load the default route.
    procedure table_default(
        dstidx: natural;        -- Destination port
        dstmac: mac_addr_t)     -- Next-hop address
    is
        variable cfg1 : cfgbus_word := i2s(dstidx, 16) & dstmac(47 downto 32);
        variable cfg2 : cfgbus_word := dstmac(31 downto 0);
        variable cfg3 : cfgbus_word := (others => '0');
    begin
        route_table(TABLE_SIZE) := (IP_NOT_VALID, IP_NOT_VALID, 0, dstidx, dstmac);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg1);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg2);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg3);
        cfgbus_write(RT_ADDR_CIDR_CTRL, x"20000000");
        table_wait;
    end procedure;

    -- Load one entry into the routing table.
    procedure table_route(
        rowidx: natural;        -- Table row
        ipaddr: ip_addr_t;      -- Subnet start
        plen:   natural;        -- Prefix length (0-32)
        dstidx: natural;        -- Destination port
        dstmac: mac_addr_t)     -- Next-hop address
    is
        variable cfg1 : cfgbus_word := i2s(plen, 8) & i2s(dstidx, 8) & dstmac(47 downto 32);
        variable cfg2 : cfgbus_word := dstmac(31 downto 0);
        variable cfg3 : cfgbus_word := ipaddr;
    begin
        route_table(rowidx) := (ipaddr, ip_prefix2mask(plen), plen, dstidx, dstmac);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg1);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg2);
        cfgbus_write(RT_ADDR_CIDR_DATA, cfg3);
        cfgbus_write(RT_ADDR_CIDR_CTRL, x"1000" & i2s(rowidx, 16));
        table_wait;
    end procedure;

    -- Routing table CIDR lookup by destination IP address.
    impure function table_lookup(dst : ip_addr_t) return route_t is
        variable best_idx : natural := TABLE_SIZE;  -- Default route
    begin
        for n in route_table'range loop
            if (work.router_sim_tools.ip_in_subnet(dst, route_table(n).subnet, route_table(n).mask)) then
                if (route_table(n).plen > route_table(best_idx).plen) then
                    best_idx := n;
                end if;
            end if;
        end loop;
        if VERBOSITY > 1 then
            report "table_lookup: " & format(dst) & " -> " & integer'image(best_idx);
        end if;
        return route_table(best_idx);
    end function;

    -- Load the designated packet data into the reference FIFOs.
    -- (Includes metadata for expected destination parameters.)
    procedure packet_load_eth(
        pkt : std_logic_vector;     -- Packet contents
        src : natural;              -- Source port index
        dst : dmask_t;              -- Destination mask
        mac : mac_addr_t)           -- Next-hop MAC address
    is
        variable nbytes : natural := (pkt'length) / 8;
        variable rdpos  : natural := 0;
        variable tmp    : byte_t := (others => '0');
    begin
        wait until rising_edge(clk_100);
        fifo_dstmac <= mac;
        fifo_pdst   <= dst;
        fifo_psrc   <= src;
        fifo_write  <= '1';
        while (rdpos < nbytes) loop
            if (rdpos + LOAD_BYTES >= nbytes) then
                fifo_nlast <= nbytes - rdpos;
            else
                fifo_nlast <= 0;
            end if;
            for n in 0 to LOAD_BYTES-1 loop
                tmp := strm_byte_zpad(rdpos, pkt);
                fifo_data(8*LOAD_BYTES-8*n-1 downto 8*LOAD_BYTES-8*n-8) <= tmp;
                rdpos := rdpos + 1;
            end loop;
            wait until rising_edge(clk_100);
        end loop;
        fifo_write <= '0';
    end procedure;

    -- Helper function for loading an IPv4 packet.
    procedure packet_load_ipv4(
        ip_pkt  : std_logic_vector;
        src_mac : mac_addr_t)
    is
        -- Parse specific packet fields.
        variable ipttl : byte_u := unsigned(ip_pkt(ip_pkt'left-64 downto ip_pkt'left-71));
        variable ipsrc : ip_addr_t := ip_pkt(ip_pkt'left-96  downto ip_pkt'left-127);
        variable ipdst : ip_addr_t := ip_pkt(ip_pkt'left-128 downto ip_pkt'left-159);
        variable psrc  : natural := table_lookup(ipsrc).pidx;
        variable route : route_t := table_lookup(ipdst);
        variable pdst  : dmask_t := (others => '0');
        -- Safe broadcast blocks the loopback port.
        variable self  : dmask_t := one_hot_encode(psrc, PORT_COUNT+1);
        variable bcast : dmask_t := test_bmask and not self;
        -- Construct the outer Ethernet packet.
        variable eth   : eth_packet := make_eth_pkt(MAC_ROUTER, src_mac, ETYPE_IPV4, ip_pkt);
    begin
        -- Determine the expected destination port(s).
        if (ip_is_reserved(ipdst) or ip_is_reserved(ipsrc)) then
            pdst := MASK_NONE;          -- Drop (reserved address)
            route.dstmac := MAC_ADDR_NONE;
        elsif (ipsrc = IP_ROUTER or ip_is_multicast(ipsrc) or ip_is_broadcast(ipsrc)) then
            pdst := MASK_NONE;          -- Drop (illegal source)
            route.dstmac := MAC_ADDR_NONE;
        elsif (ipttl = 0 or ipdst = IP_ROUTER) then
            pdst := MASK_OFFLOAD;       -- Offload to router
            route.dstmac := MAC_ROUTER;
        elsif (ip_is_multicast(ipdst) and block_ipv4_mcast = '1') then
            pdst := MASK_NONE;          -- Drop (multicast + rule)
            route.dstmac := MAC_ADDR_NONE;
        elsif (ip_is_broadcast(ipdst) and block_ipv4_bcast = '1') then
            pdst := MASK_NONE;          -- Drop (broadcast + rule)
            route.dstmac := MAC_ADDR_NONE;
        elsif (ip_is_multicast(ipdst) or ip_is_broadcast(ipdst)) then
            pdst := bcast;              -- Broadcast packet
            route.dstmac := MAC_ADDR_BROADCAST;
        elsif (route.dstmac = MAC_ADDR_NONE) then
            pdst := MASK_OFFLOAD;       -- Unicast w/ unknown MAC.
            route.dstmac := MAC_ROUTER;
        else                            -- Unicast w/ known MAC.
            pdst := shift_left(MASK_PORT0, route.pidx);
            if (route.pidx = psrc) then -- With ICMP redirect?
                pdst := pdst or MASK_OFFLOAD;
            end if;
        end if;
        -- Load packet contents.
        packet_load_eth(eth.all, psrc, pdst, route.dstmac);
    end procedure;

    -- Wait for all transmissions to finish.
    -- (i.e., N consecutive cycles without an expected data transfer.)
    procedure packet_wait(ri, ro: real) is
        variable count_done, count_idle : integer := 0;
    begin
        test_rate_i <= ri;
        test_rate_o <= ro;
        wait for 1 us;
        while (count_done < 100) loop
            assert (count_idle < 10000)
                report "Test timeout." severity failure;
            if (in_empty = '1' and ref_empty = '1') then
                count_done := count_done + 1;
                count_idle := 0;
            elsif (in_valid = '1' and in_ready = '1') then
                count_done := 0;
                count_idle := 0;
            else
                count_done := 0;
                count_idle := count_idle + 1;
            end if;
            wait until rising_edge(clk_100);
        end loop;
        test_rate_i <= 0.0;
        test_rate_o <= 0.0;
    end procedure;

    -- Run a series of carefully chosen packets.
    procedure run_series(ri, ro: real) is
        -- Ref1, Ref2: Captured TCP-over-Ethernet frames from a Windows desktop.
        -- (This is mainly used to confirm checksums are calculated correctly.)
        constant ETH_CAPTURE1 : std_logic_vector(479 downto 0) :=
            x"18_60_24_7e_35_79_00_25_b4_cf_32_c0_08_00" &          -- Eth header
            x"45_00_00_2e_78_10_40_00_7c_06_6f_94_ac_11_28_a9" &    -- Start IP header
            x"0a_03_38_68_eb_97_0d_3d_90_f3_b9_dc_eb_32_de_14" &    -- Dst + User data
            x"50_10_01_00_8a_c2_00_00_5d_b5_87_4d_00_00";           -- More user data
        constant ETH_CAPTURE2 : std_logic_vector(431 downto 0) :=
            x"00_25_b4_cf_32_c0_18_60_24_7e_35_79_08_00" &          -- Eth header
            x"45_00_00_28_12_01_40_00_80_06_d1_a9_0a_03_38_68" &    -- Start IP header
            x"ac_11_28_a9_0d_3d_eb_97_eb_32_ed_19_90_f3_ba_32" &    -- Dst + User data
            x"50_10_f9_4d_17_40_00_00";                             -- More user data
        -- Packet with various header errors (modified from above).
        -- (Using raw-Ethernet mode to simplify creation of invalid header fields.)
        constant ETH_BADCHK : std_logic_vector(431 downto 0) :=
            x"00_25_b4_cf_32_c0_18_60_24_7e_35_79_08_00" &          -- Eth header
            x"45_00_00_28_12_01_40_00_80_06_ff_ff_0a_03_38_68" &    -- Start IP header
            x"ac_11_28_a9_0d_3d_eb_97_eb_32_ed_19_90_f3_ba_32" &    -- Dst + User data
            x"50_10_f9_4d_17_40_00_00";                             -- More user data
        constant ETH_BADLEN : std_logic_vector(431 downto 0) :=
            x"00_25_b4_cf_32_c0_18_60_24_7e_35_79_08_00" &          -- Eth header
            x"45_00_00_08_12_01_40_00_80_06_d1_c9_0a_03_38_68" &    -- Start IP header
            x"ac_11_28_a9_0d_3d_eb_97_eb_32_ed_19_90_f3_ba_32" &    -- Dst + User data
            x"50_10_f9_4d_17_40_00_00";                             -- More user data
        -- Non-Ipv4 packet types.
        variable ETH_ARP1 : eth_packet := make_eth_pkt(
            MAC_ADDR_BROADCAST, MAC_UPLINK, ETYPE_ARP, rand_bytes(32));
        variable ETH_PTP1 : eth_packet := make_eth_pkt(
            MAC_ROUTER, MAC_UPLINK, ETYPE_PTP, rand_bytes(64));
        -- ICMP echo request (aka ping) to the router and to a remote server.
        variable ECHO_ROUTER : ip_packet := make_icmp_request(
            IP_ROUTER, IP_LOCAL1A, ICMP_TC_ECHORQ, x"ab01", rand_bytes(8));
        variable ECHO_REMOTE : ip_packet := make_icmp_request(
            IP_REMOTE1, IP_LOCAL2A, ICMP_TC_ECHORQ, x"ab02", rand_bytes(8));
        -- Basic UDP packets.
        variable UDP_BASIC1 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1A, IP_LOCAL1B, x"ab11", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BASIC2 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1B, IP_LOCAL2A, x"ab12", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BASIC3 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL2A, IP_LOCAL1B, x"ab13", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BASIC4 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL2B, IP_LOCAL1A, x"ab14", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BASIC5 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1A, IP_REMOTE1, x"ab15", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BASIC6 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_REMOTE2, IP_LOCAL2B, x"ab16", IPPROTO_UDP), rand_bytes(16));
        -- UDP packets with TTL=1 and TTL=0, respectively.
        variable UDP_TTL1 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1A, IP_LOCAL2A, x"ab21", IPPROTO_UDP, IPFLAG_NORMAL, 1), rand_bytes(16));
        variable UDP_TTL0 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL2A, IP_LOCAL1A, x"ab22", IPPROTO_UDP, IPFLAG_NORMAL, 0), rand_bytes(16));
        -- Packets with illegal source addresses.
        variable UDP_BADSRC1 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1A, IP_BROADCAST, x"ab31", IPPROTO_UDP), rand_bytes(16));
        variable UDP_BADSRC2 : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL1B, IP_ROUTER, x"ab32", IPPROTO_UDP), rand_bytes(16));
        -- UDP broadcast packets.
        variable UDP_BCAST : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_BROADCAST, IP_LOCAL2A, x"ab41", IPPROTO_UDP), rand_bytes(16));
        -- UDP with deferred forwarding (i.e., next-hop MAC hasn't been cached).
        variable UDP_DEFER : ip_packet := make_ipv4_pkt(
            make_ipv4_header(IP_LOCAL2C, IP_LOCAL1B, x"ab51", IPPROTO_UDP), rand_bytes(16));
    begin
        -- Load and process each batch of packets.
        if (block_bad_dmac = '1') then
            packet_load_eth(ETH_CAPTURE1, 1, MASK_NONE, MAC_ADDR_NONE);
            packet_load_eth(ETH_CAPTURE2, 2, MASK_NONE, MAC_ADDR_NONE);
            packet_load_eth(ETH_BADCHK, 1, MASK_NONE, MAC_ADDR_NONE);
            packet_load_eth(ETH_BADLEN, 2, MASK_NONE, MAC_ADDR_NONE);
        else
            packet_load_eth(ETH_CAPTURE1, 1, MASK_PORT0, MAC_UPLINK);
            packet_load_eth(ETH_CAPTURE2, 2, MASK_PORT0, MAC_UPLINK);
            packet_load_eth(ETH_BADCHK, 1, MASK_NONE, MAC_ADDR_NONE);
            packet_load_eth(ETH_BADLEN, 2, MASK_NONE, MAC_ADDR_NONE);
        end if;
        packet_load_eth(ETH_ARP1.all, 0, MASK_OFFLOAD, MAC_ROUTER);
        if (block_noip_all = '1') then
            packet_load_eth(ETH_PTP1.all, 0, MASK_NONE, MAC_ADDR_NONE);
        else
            packet_load_eth(ETH_PTP1.all, 0, MASK_OFFLOAD, MAC_ROUTER);
        end if;
        packet_wait(ri, ro);

        packet_load_ipv4(ECHO_ROUTER.all,   MAC_LOCAL1A);
        packet_load_ipv4(ECHO_REMOTE.all,   MAC_LOCAL2A);
        packet_load_ipv4(UDP_BASIC1.all,    MAC_LOCAL1B);
        packet_load_ipv4(UDP_BASIC2.all,    MAC_LOCAL2A);
        packet_load_ipv4(UDP_BASIC3.all,    MAC_LOCAL1B);
        packet_load_ipv4(UDP_BASIC4.all,    MAC_LOCAL1A);
        packet_load_ipv4(UDP_BASIC5.all,    MAC_UPLINK);
        packet_load_ipv4(UDP_BASIC6.all,    MAC_LOCAL2B);
        packet_wait(ri, ro);

        packet_load_ipv4(UDP_TTL1.all,      MAC_LOCAL2A);
        packet_load_ipv4(UDP_TTL0.all,      MAC_LOCAL1A);
        packet_load_ipv4(UDP_BADSRC1.all,   MAC_LOCAL2C);
        packet_load_ipv4(UDP_BADSRC2.all,   MAC_LOCAL2C);
        packet_load_ipv4(UDP_BCAST.all,     MAC_LOCAL2A);
        packet_load_ipv4(UDP_DEFER.all,     MAC_LOCAL1B);
        packet_wait(ri, ro);
    end procedure;
begin
    -- Take control of ConfigBus signals.
    test_regaddr    <= 0;
    test_wdata      <= (others => '0');
    test_wrcmd      <= '0';
    test_rdcmd      <= '0';

    -- Configure the test network.
    wait for 2 us;
    table_wait;
    table_default(0, MAC_UPLINK);                       -- CIDR routes
    table_route(0, IP_SUBNET1, 24, 1, MAC_ADDR_NONE);
    table_route(1, IP_SUBNET2, 24, 2, MAC_ADDR_NONE);
    table_route(2, IP_LOCAL1A, 32, 1, MAC_LOCAL1A);     -- ARP cache
    table_route(3, IP_LOCAL1B, 32, 1, MAC_LOCAL1B);
    table_route(4, IP_LOCAL2A, 32, 2, MAC_LOCAL2A);
    table_route(5, IP_LOCAL2B, 32, 2, MAC_LOCAL2B);

    -- Basic test series with restrictive rules.
    rules_update(x"FFFF");  -- Shut down everything
    run_series(1.0, 1.0);

    -- Run tests under various flow-control conditions.
    rules_update(x"0000");  -- Allow everything
    for n in 1 to 10 loop
        run_series(1.0, 1.0);
        run_series(0.1, 0.9);
        run_series(0.9, 0.1);
    end loop;
    report "All tests completed!";
    wait;
end process;

end helper;

---------------------------------------------------------------------

entity router2_gateway_tb is
    -- Unit testbench top level, no I/O ports
end router2_gateway_tb;

architecture tb of router2_gateway_tb is
begin

uut0 : entity work.router2_gateway_tb_helper
    generic map(
    IO_BYTES    => 1,
    VERBOSITY   => 0);

uut1 : entity work.router2_gateway_tb_helper
    generic map(
    IO_BYTES    => 8,
    VERBOSITY   => 0);

end tb;
