--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Testbench for each router configuration helper block
--
-- This testbench simulates each variant of the router configuration block:
--  * router_config_axi (run-time configuration using AXI-Lite)
--  * router_config_static (build-time configuration using constants)
--
-- The complete test takes less than 1.0 milliseconds.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;
use     work.router_sim_tools.all;

entity router_config_tb is
    -- No I/O ports
end router_config_tb;

architecture tb of router_config_tb is

-- Run at 10x acceleration to keep test duration low.
constant CLKREF_HZ      : positive := 10_000_000;

-- Static configuration
constant AXI_ADDR_WIDTH : positive := 16;
constant R_IP_ADDR      : ip_addr_t := x"C0A80101";
constant R_SUB_ADDR     : ip_addr_t := x"C0A80100";
constant R_SUB_MASK     : ip_addr_t := x"FFFFFF00";
constant R_NOIP_DMAC_EG : mac_addr_t := x"DEADBEEFCAFE";
constant R_NOIP_DMAC_IG : mac_addr_t := x"CAFEDEADBEEF";

-- System clock and reset.
signal axi_clk          : std_logic := '0';
signal rtr_clk          : std_logic := '0';
signal reset_p          : std_logic := '1';
signal reset_n          : std_logic;

-- AXI-Lite bus
subtype addr_word is std_logic_vector(AXI_ADDR_WIDTH-1 downto 0);
subtype data_word is std_logic_vector(31 downto 0);
subtype resp_word is std_logic_vector(1 downto 0);
signal axi_awaddr       : addr_word := (others => '0');
signal axi_awvalid      : std_logic := '0';
signal axi_awready      : std_logic;
signal axi_wdata        : data_word := (others => '0');
signal axi_wvalid       : std_logic := '0';
signal axi_wready       : std_logic;
signal axi_bresp        : resp_word;
signal axi_bvalid       : std_logic;
signal axi_bready       : std_logic := '1';
signal axi_araddr       : addr_word := (others => '0');
signal axi_arvalid      : std_logic := '0';
signal axi_arready      : std_logic;
signal axi_rdata        : data_word;
signal axi_rresp        : resp_word;
signal axi_rvalid       : std_logic;
signal axi_rready       : std_logic := '0';

-- Counters for each AXI transaction
signal axi_count_wr     : natural := 0;
signal axi_count_rd     : natural := 0;
signal axi_count_aw     : natural := 0;
signal axi_count_w      : natural := 0;
signal axi_count_b      : natural := 0;
signal axi_count_ar     : natural := 0;
signal axi_count_r      : natural := 0;

-- Output from each unit under test:
signal axi_ip_addr      : ip_addr_t;
signal axi_sub_addr     : ip_addr_t;
signal axi_sub_mask     : ip_addr_t;
signal axi_reset_p      : std_logic;
signal axi_dmac_eg      : mac_addr_t;
signal axi_dmac_ig      : mac_addr_t;
signal axi_time_msec    : timestamp_t;

signal fix_ip_addr      : ip_addr_t;
signal fix_sub_addr     : ip_addr_t;
signal fix_sub_mask     : ip_addr_t;
signal fix_reset_p      : std_logic;
signal fix_dmac_eg      : mac_addr_t;
signal fix_dmac_ig      : mac_addr_t;
signal fix_time_msec    : timestamp_t;

-- Overall test control
signal axi_wr_start     : std_logic := '0';
signal axi_rd_start     : std_logic := '0';
signal axi_rw_addr      : natural := 0;
signal axi_rw_value     : data_word := (others => '0');
signal rtr_drop_count   : bcount_t := (others => '0');

begin

-- Clock and reset generation.
axi_clk <= not axi_clk after 5.7 ns;    -- 1 / (2*5.7ns) = 88 MHz
rtr_clk <= not rtr_clk after 5.0 ns;    -- 1 / (2*5.0ns) = 100 MHz
reset_p <= '0' after 1 us;
reset_n <= not reset_p;

-- AXI-Lite controller
p_axi : process(axi_clk)
    -- Delay countdowns for each pipe (AW, W, B, AR, R)
    variable dly_aw, dly_w, dly_b, dly_ar, dly_r : natural := 0;
begin
    if rising_edge(axi_clk) then
        -- Handle writes
        if (reset_p = '1') then
            axi_awaddr  <= (others => '0');
            axi_awvalid <= '0';
            axi_wdata   <= (others => '0');
            axi_wvalid  <= '0';
            axi_bready  <= '0';
            dly_aw      := 0;
            dly_w       := 0;
            dly_b       := 0;
        elsif (axi_wr_start = '1') then
            -- Latch new address and data.
            axi_awaddr  <= i2s(4*axi_rw_addr, AXI_ADDR_WIDTH);
            axi_wdata   <= axi_rw_value;
            -- Randomize delays for each pipe.
            dly_aw      := rand_int(4);
            dly_w       := rand_int(4);
            dly_b       := rand_int(4);
            -- Update flow-control flags.
            axi_awvalid <= bool2bit(dly_aw = 0);
            axi_wvalid  <= bool2bit(dly_w = 0);
            axi_bready  <= bool2bit(dly_b = 0);
        else
            -- Update flow-control flags.
            if (dly_aw = 1) then
                axi_awvalid <= '1';
            elsif (axi_awready = '1') then
                axi_awvalid <= '0';
            end if;
            if (dly_w = 1) then
                axi_wvalid <= '1';
            elsif (axi_wready = '1') then
                axi_wvalid <= '0';
            end if;
            if (dly_b = 1) then
                axi_bready <= '1';
            end if;
            -- Decrement countdowns.
            if (dly_aw > 0) then
                dly_aw := dly_aw - 1;
            end if;
            if (dly_w > 0) then
                dly_w := dly_w - 1;
            end if;
            if (dly_b > 0) then
                dly_b := dly_b - 1;
            end if;
        end if;

        -- Handle reads.
        if (reset_p = '1') then
            axi_araddr  <= (others => '0');
            axi_arvalid <= '0';
            axi_rready  <= '0';
            dly_aw      := 0;
            dly_w       := 0;
            dly_b       := 0;
        elsif (axi_rd_start = '1') then
            -- Latch new address.
            axi_araddr  <= i2s(4*axi_rw_addr, AXI_ADDR_WIDTH);
            -- Randomize delays for each pipe.
            dly_ar      := rand_int(4);
            dly_r       := rand_int(4);
            -- Update flow-control flags.
            axi_arvalid <= bool2bit(dly_ar = 0);
            axi_rready  <= bool2bit(dly_r = 0);
        else
            -- Check return value.
            if (axi_rvalid = '1' and axi_rready = '1') then
                assert (axi_rdata = axi_rw_value)
                    report "Read data mismatch in register #"
                        & integer'image(axi_rw_addr) & "."
                    severity error;
            end if;
            -- Update flow-control flags.
            if (dly_ar = 1) then
                axi_arvalid <= '1';
            elsif (axi_arready = '1') then
                axi_arvalid <= '0';
            end if;
            if (dly_r = 1) then
                axi_rready <= '1';
            end if;
            -- Decrement countdowns.
            if (dly_ar > 0) then
                dly_ar := dly_ar - 1;
            end if;
            if (dly_r > 0) then
                dly_r := dly_r - 1;
            end if;
        end if;

        -- Count transactions on each pipe.
        axi_count_wr    <= axi_count_wr + u2i(axi_wr_start);
        axi_count_rd    <= axi_count_rd + u2i(axi_rd_start);
        axi_count_aw    <= axi_count_aw + u2i(axi_awvalid and axi_awready);
        axi_count_w     <= axi_count_w  + u2i(axi_wvalid and axi_wready);
        axi_count_b     <= axi_count_b  + u2i(axi_bvalid and axi_bready);
        axi_count_ar    <= axi_count_ar + u2i(axi_arvalid and axi_arready);
        axi_count_r     <= axi_count_r  + u2i(axi_rvalid and axi_rready);
    end if;
end process;

-- Unit under test: AXI variant
uut_axi : entity work.router_config_axi
    generic map(
    CLKREF_HZ       => CLKREF_HZ,
    NOIP_REG_EN     => true,
    R_IP_ADDR       => R_IP_ADDR,
    R_SUB_ADDR      => R_SUB_ADDR,
    R_SUB_MASK      => R_SUB_MASK,
    R_NOIP_DMAC_EG  => R_NOIP_DMAC_EG,
    R_NOIP_DMAC_IG  => R_NOIP_DMAC_IG,
    ADDR_WIDTH      => AXI_ADDR_WIDTH)
    port map(
    cfg_ip_addr     => axi_ip_addr,
    cfg_sub_addr    => axi_sub_addr,
    cfg_sub_mask    => axi_sub_mask,
    cfg_reset_p     => axi_reset_p,
    noip_dmac_eg    => axi_dmac_eg,
    noip_dmac_ig    => axi_dmac_ig,
    rtr_clk         => rtr_clk,
    rtr_drop_count  => rtr_drop_count,
    rtr_time_msec   => axi_time_msec,
    axi_clk         => axi_clk,
    axi_aresetn     => reset_n,
    axi_awaddr      => axi_awaddr,
    axi_awvalid     => axi_awvalid,
    axi_awready     => axi_awready,
    axi_wdata       => axi_wdata,
    axi_wvalid      => axi_wvalid,
    axi_wready      => axi_wready,
    axi_bresp       => axi_bresp,
    axi_bvalid      => axi_bvalid,
    axi_bready      => axi_bready,
    axi_araddr      => axi_araddr,
    axi_arvalid     => axi_arvalid,
    axi_arready     => axi_arready,
    axi_rdata       => axi_rdata,
    axi_rresp       => axi_rresp,
    axi_rvalid      => axi_rvalid,
    axi_rready      => axi_rready);

-- Unit under test: Static variant
uut_fix : entity work.router_config_static
    generic map(
    CLKREF_HZ       => CLKREF_HZ,
    R_IP_ADDR       => R_IP_ADDR,
    R_SUB_ADDR      => R_SUB_ADDR,
    R_SUB_MASK      => R_SUB_MASK,
    R_NOIP_DMAC_EG  => R_NOIP_DMAC_EG,
    R_NOIP_DMAC_IG  => R_NOIP_DMAC_IG)
    port map(
    cfg_ip_addr     => fix_ip_addr,
    cfg_sub_addr    => fix_sub_addr,
    cfg_sub_mask    => fix_sub_mask,
    cfg_reset_p     => fix_reset_p,
    noip_dmac_eg    => fix_dmac_eg,
    noip_dmac_ig    => fix_dmac_ig,
    rtr_clk         => rtr_clk,
    rtr_time_msec   => fix_time_msec,
    ext_reset_p     => reset_p);

-- Overall test control
p_test : process
    -- Request a single write transaction.
    procedure axi_write(addr: natural; data: data_word) is
    begin
        -- Issue write command.
        wait until rising_edge(axi_clk);
        axi_wr_start <= '1';
        axi_rw_addr  <= addr;
        axi_rw_value <= data;
        wait until rising_edge(axi_clk);
        axi_wr_start <= '0';

        -- Wait a few clocks, then check counters.
        for n in 1 to 6 loop
            wait until rising_edge(axi_clk);
        end loop;
        assert (axi_count_aw = axi_count_wr
            and axi_count_w = axi_count_wr
            and axi_count_b = axi_count_wr)
            report "Write-count mismatch." severity error;
    end procedure;

    -- Request a single read transcation and check reply.
    procedure axi_read(addr: natural; ref: data_word) is
    begin
        -- Issue read command.
        wait until rising_edge(axi_clk);
        axi_rd_start <= '1';
        axi_rw_addr  <= addr;
        axi_rw_value <= ref;
        wait until rising_edge(axi_clk);
        axi_rd_start <= '0';

        -- Wait a few clocks, then check counters.
        for n in 1 to 6 loop
            wait until rising_edge(axi_clk);
        end loop;
        assert (axi_count_ar = axi_count_rd
            and axi_count_r = axi_count_rd)
            report "Read-count mismatch." severity error;
    end procedure;

    variable drop_incr : data_word := (others => '0');
begin
    -- Wait for reset to finish.
    wait until falling_edge(reset_p);
    wait for 1 us;

    -- Confirm default and static outputs.
    report "Checking initial state...";
    assert (axi_ip_addr = R_IP_ADDR
        and axi_sub_addr = R_SUB_ADDR
        and axi_sub_mask = R_SUB_MASK
        and axi_reset_p = '1'
        and axi_dmac_eg = R_NOIP_DMAC_EG
        and axi_dmac_ig = R_NOIP_DMAC_IG
        and axi_time_msec = x"80000000")
        report "UUT_AXI initial state mismatch." severity error;

    assert (fix_ip_addr = R_IP_ADDR
        and fix_sub_addr = R_SUB_ADDR
        and fix_sub_mask = R_SUB_MASK
        and fix_reset_p = '0'
        and fix_dmac_eg = R_NOIP_DMAC_EG
        and fix_dmac_ig = R_NOIP_DMAC_IG
        and fix_time_msec = x"80000000")
        report "UUT_FIX initial state mismatch." severity error;

    -- Wait a moment and check timers again.
    report "Checking timers...";
    wait for 140 us;    -- 10x acceleration
    assert (axi_time_msec = x"80000001")
        report "UUT_AXI time mismatch." severity error;
    assert (fix_time_msec = x"80000001")
        report "UUT_FIX time mismatch." severity error;
    wait for 100 us;    -- 10x acceleration
    assert (axi_time_msec = x"80000002")
        report "UUT_AXI time mismatch." severity error;
    assert (fix_time_msec = x"80000002")
        report "UUT_FIX time mismatch." severity error;
    wait for 10 us;

    -- Reconfigure the AXI block.
    report "Checking configuration registers...";
    axi_write(0, x"00000001");              -- Release from reset
    axi_read(0, x"00000001");               -- Readback
    assert (axi_reset_p = '0')
        report "UUT_AXI Reg0 mismatch." severity error;

    axi_write(1, rand_vec(32));             -- Router IP-address
    axi_read(1, axi_rw_value);              -- Readback
    assert (axi_ip_addr = axi_rw_value)
        report "UUT_AXI Reg1 mismatch." severity error;

    axi_write(2, rand_vec(32));             -- Subnet address
    axi_read(2, axi_rw_value);              -- Readback
    assert (axi_sub_addr = axi_rw_value)
        report "UUT_AXI Reg2 mismatch." severity error;

    axi_write(3, rand_vec(32));             -- Subnet mask
    axi_read(3, axi_rw_value);              -- Readback
    assert (axi_sub_mask = axi_rw_value)
        report "UUT_AXI Reg3 mismatch." severity error;

    axi_write(4, x"01234567");              -- Current time
    axi_read(4, axi_rw_value);              -- Readback
    assert (axi_time_msec = unsigned(axi_rw_value))
        report "UUT_AXI Reg4 mismatch." severity error;

    axi_write(6, rand_vec(32));             -- Egress DMAC
    axi_read(6, axi_rw_value);              -- Readback
    assert (axi_dmac_eg(31 downto 0) = axi_rw_value)
        report "UUT_AXI Reg6 mismatch." severity error;

    axi_write(7, x"0000" & rand_vec(16));   -- (continued)
    axi_read(7, axi_rw_value);              -- Readback
    assert (axi_dmac_eg(47 downto 32) = axi_rw_value(15 downto 0))
        report "UUT_AXI Reg7 mismatch." severity error;

    axi_write(8, rand_vec(32));             -- Ingress DMAC
    axi_read(8, axi_rw_value);              -- Readback
    assert (axi_dmac_ig(31 downto 0) = axi_rw_value)
        report "UUT_AXI Reg8 mismatch." severity error;

    axi_write(9, x"0000" & rand_vec(16));   -- (continued)
    axi_read(9, axi_rw_value);              -- Readback
    assert (axi_dmac_ig(47 downto 32) = axi_rw_value(15 downto 0))
        report "UUT_AXI Reg9 mismatch." severity error;

    -- Poke the dropped-packets counter a few times.
    -- Note: Counter rtr_drop_count accumulates with wraparound.
    --       Read value is the difference since the last read.
    report "Checking dropped-packet counter...";
    for n in 1 to 5 loop
        drop_incr := x"0000" & rand_vec(16);
        rtr_drop_count <= rtr_drop_count + u2i(drop_incr);
        axi_write(5, x"00000000");
        axi_read(5, drop_incr);
    end loop;

    -- Check that both timers are still incrementing.
    report "Checking timers again...";
    for n in 1 to 4 loop
        wait for 100 us;    -- 10x acceleration
        axi_read(4, std_logic_vector(axi_time_msec));
        assert (axi_time_msec = x"01234567" + n)
            report "UUT_AXI time mismatch." severity error;
        assert (fix_time_msec = x"80000002" + n)
            report "UUT_FIX time mismatch." severity error;
    end loop;

    -- Done.
    report "All tests completed!";
    wait;
end process;

end tb;
