--------------------------------------------------------------------------
-- Copyright 2020-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Configuration helper for use with router_inline_top
--
-- This block presents an AXI-Lite memory-mapped interface for configuring
-- the inline IPv4-router.  Parameters such as subnet configuration and
-- current time are written to a series of memory-mapped registers, which
-- can then be read and written by a soft-core microcontroller.
--
-- For more information on AXI-Lite, refer to the "AMBA AXI and ACE
-- Protocol Specification" (ARM IHI 0022E), version 4, Section B.
--
-- All registers must be read/written as atomic 32-bit words, with
-- word-aligned addresses.  Arbitrary byte-masked I/O is not supported.
--
-- The register list and address map is as follows:
--      Base +  0 = Router enable (default = hold in reset)
--                  Write 1 to run, 0 to hold in reset.
--      Base +  4 = Router IP-address (default 192.168.1.1)
--      Base +  8 = Subnet address (default 192.168.1.0)
--      Base + 12 = Subnet mask (default 255.255.255.0)
--      Base + 16 = Current time, in milliseconds.
--                  MSB = '0' for milliseconds since UTC midnight.
--                  MSB = '1' for any other time reference.
--      Base + 20 = Number of dropped packets since last query.
--                  Write anything to update, then read after a short delay.
--      Base + 24 = LSBs of non-IPv4 egress DMAC (31:00)
--      Base + 28 = 16-bit reserved + MSBs of non-IPv4 egress DMAC (47:32)
--      Base + 32 = LSBs of non-IPv4 ingress DMAC (31:00)
--      Base + 36 = 16-bit reserved + MSBs of non-IPv4 ingress DMAC (47:32)
--      Base + 40 = LSBs of IPv4 egress DMAC (31:00)
--      Base + 44 = 16-bit reserved + MSBs of IPv4 egress DMAC (47:32)
--      Base + 48 = LSBs of IPv4 ingress DMAC (31:00)
--      Base + 52 = 16-bit reserved + MSBs of IPv4 ingress DMAC (47:32)
--      All other addresses reserved.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.sync_toggle2pulse;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_config_axi is
    generic (
    CLKREF_HZ       : positive := 125_000_000;      -- Frequency of rtr_clk
    IPV4_REG_EN     : boolean := true;              -- Enable IPV4_* registers?
    NOIP_REG_EN     : boolean := true;              -- Enable NOIP_* registers?
    R_IP_ADDR       : ip_addr_t := x"C0A80101";     -- Default = 192.168.1.1
    R_SUB_ADDR      : ip_addr_t := x"C0A80100";     -- Default = 192.168.0.0
    R_SUB_MASK      : ip_addr_t := x"FFFFFF00";     -- Default = 255.255.255.0
    R_IPV4_DMAC_EG  : mac_addr_t := x"DEADBEEFCAFE";
    R_IPV4_DMAC_IG  : mac_addr_t := x"DEADBEEFCAFE";
    R_NOIP_DMAC_EG  : mac_addr_t := MAC_ADDR_BROADCAST;
    R_NOIP_DMAC_IG  : mac_addr_t := MAC_ADDR_BROADCAST;
    ADDR_WIDTH      : positive := 32;               -- AXI-Lite address width
    BASE_ADDR       : natural := 0);                -- Base address (see above)
    port (
    -- Quasi-static configuration parameters.
    cfg_ip_addr     : out ip_addr_t;
    cfg_sub_addr    : out ip_addr_t;
    cfg_sub_mask    : out ip_addr_t;
    cfg_reset_p     : out std_logic;
    ipv4_dmac_eg    : out mac_addr_t;
    ipv4_dmac_ig    : out mac_addr_t;
    noip_dmac_eg    : out mac_addr_t;
    noip_dmac_ig    : out mac_addr_t;

    -- Configuration in the router clock domain.
    rtr_clk         : in  std_logic;
    rtr_drop_count  : in  bcount_t;
    rtr_time_msec   : out timestamp_t;

    -- AXI-Lite interface
    axi_clk         : in  std_logic;
    axi_aresetn     : in  std_logic;
    axi_awaddr      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_awvalid     : in  std_logic;
    axi_awready     : out std_logic;
    axi_wdata       : in  std_logic_vector(31 downto 0);
    axi_wstrb       : in  std_logic_vector(3 downto 0) := "1111";
    axi_wvalid      : in  std_logic;
    axi_wready      : out std_logic;
    axi_bresp       : out std_logic_vector(1 downto 0);
    axi_bvalid      : out std_logic;
    axi_bready      : in  std_logic;
    axi_araddr      : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_arvalid     : in  std_logic;
    axi_arready     : out std_logic;
    axi_rdata       : out std_logic_vector(31 downto 0);
    axi_rresp       : out std_logic_vector(1 downto 0);
    axi_rvalid      : out std_logic;
    axi_rready      : in  std_logic);
end router_config_axi;

architecture router_config_axi of router_config_axi is

constant SUB_ADDR_WIDTH : positive := 4;
subtype sub_addr_t is unsigned(SUB_ADDR_WIDTH-1 downto 0);

-- Clock-domain transition for the timestamp counter.
signal reg_time_utc_n   : std_logic := '1';             -- Default = Arb ref
signal reg_time_msec    : unsigned(30 downto 0) := (others => '0');
signal reg_time_cpu     : ip_addr_t := (others => '0');
signal time_update_t    : std_logic := '0';             -- Toggle in axi_clk
signal time_update_i    : std_logic;                    -- Strobe in rtr_clk
signal time_incr_t      : std_logic := '0';             -- Toggle in rtr_clk
signal time_incr_i      : std_logic;                    -- Strobe in axi_clk

-- Clock-domain transition for the dropped-packet counter.
signal reg_drop_ref     : bcount_t := (others => '0');
signal reg_drop_diff    : bcount_t := (others => '0');
signal drop_update_t    : std_logic := '0';             -- Toggle in axi_clk
signal drop_update_i    : std_logic;                    -- Strobe in rtr_clk

-- Quasi-static configuration registers.
signal reg_running      : std_logic := '0';
signal reg_ip_addr      : ip_addr_t := R_IP_ADDR;
signal reg_sub_addr     : ip_addr_t := R_SUB_ADDR;
signal reg_sub_mask     : ip_addr_t := R_SUB_MASK;
signal reg_ipv4_dmac_eg : mac_addr_t := R_IPV4_DMAC_EG;
signal reg_ipv4_dmac_ig : mac_addr_t := R_IPV4_DMAC_IG;
signal reg_noip_dmac_eg : mac_addr_t := R_NOIP_DMAC_EG;
signal reg_noip_dmac_ig : mac_addr_t := R_NOIP_DMAC_IG;

-- AXI-Lite write interface logic.
signal wr_gotaddr       : std_logic := '0';
signal wr_gotdata       : std_logic := '0';
signal wr_preexec       : std_logic;
signal wr_rpend         : std_logic := '0';
signal wr_exec          : std_logic := '0';
signal wr_addr          : sub_addr_t := (others => '0');
signal wr_data          : ip_addr_t := (others => '0');

-- AXI-Lite read interface logic.
signal rd_data          : ip_addr_t := (others => '0');
signal rd_pending       : std_logic := '0';

begin

-- Drive top-level outputs:
cfg_reset_p     <= not reg_running;
cfg_ip_addr     <= reg_ip_addr;
cfg_sub_addr    <= reg_sub_addr;
cfg_sub_mask    <= reg_sub_mask;
ipv4_dmac_eg    <= reg_ipv4_dmac_eg;
ipv4_dmac_ig    <= reg_ipv4_dmac_ig;
noip_dmac_eg    <= reg_noip_dmac_eg;
noip_dmac_ig    <= reg_noip_dmac_ig;

rtr_time_msec   <= reg_time_utc_n & reg_time_msec;

-- AXI command responses are always "OK" ('00').
axi_rresp   <= "00";
axi_bresp   <= "00";
axi_bvalid  <= wr_rpend and axi_aresetn;

-- Clock-domain transition for the timestamp counter.
u_time_sync : sync_toggle2pulse
    port map(
    in_toggle   => time_update_t,
    out_strobe  => time_update_i,
    out_clk     => rtr_clk);

u_time_incr : sync_toggle2pulse
    port map(
    in_toggle   => time_incr_t,
    out_strobe  => time_incr_i,
    out_clk     => axi_clk);

p_timer : process(rtr_clk) is
    constant ONE_MSEC : positive := clocks_per_baud(CLKREF_HZ, 1000);
    variable clk_ctr  : integer range 0 to ONE_MSEC-1 := (ONE_MSEC-1);
begin
    if rising_edge(rtr_clk) then
        if (time_update_i = '1') then
            reg_time_utc_n  <= reg_time_cpu(31);
            reg_time_msec   <= unsigned(reg_time_cpu(30 downto 0));
            clk_ctr         := ONE_MSEC - 1;
        elsif (clk_ctr = 0) then
            time_incr_t     <= not time_incr_t;
            reg_time_msec   <= reg_time_msec + 1;
            clk_ctr         := ONE_MSEC - 1;
        else
            clk_ctr         := clk_ctr - 1;
        end if;
    end if;
end process;

-- Clock-domain transition for the dropped-packet counter.
u_drop_sync : sync_toggle2pulse
    port map(
    in_toggle   => drop_update_t,
    out_strobe  => drop_update_i,
    out_clk     => rtr_clk);

p_drop_count : process(rtr_clk) is
begin
    if rising_edge(rtr_clk) then
        if (axi_aresetn = '0') then
            -- Global reset.
            reg_drop_diff   <= (others => '0');
            reg_drop_ref    <= (others => '0');
        elsif (drop_update_i = '1') then
            -- Calculate errors since the last query.
            reg_drop_diff   <= rtr_drop_count - reg_drop_ref;
            reg_drop_ref    <= rtr_drop_count;
        end if;
    end if;
end process;

-- Handle AXI write commands.
p_cfg_reg : process(axi_clk) is
    constant TIME_SYNC_COOLDOWN : integer := 15;
    variable time_update_cd : integer range 0 to TIME_SYNC_COOLDOWN := 0;
begin
    if rising_edge(axi_clk) then
        -- Quasi-static configuration registers.
        if (axi_aresetn = '0') then
            reg_running         <= '0';
            reg_ip_addr         <= R_IP_ADDR;
            reg_sub_addr        <= R_SUB_ADDR;
            reg_sub_mask        <= R_SUB_MASK;
            reg_ipv4_dmac_eg    <= R_IPV4_DMAC_EG;
            reg_ipv4_dmac_ig    <= R_IPV4_DMAC_IG;
            reg_noip_dmac_eg    <= R_NOIP_DMAC_EG;
            reg_noip_dmac_ig    <= R_NOIP_DMAC_IG;
        elsif (wr_exec = '0') then
            null;   -- No command this cycle
        elsif (wr_addr = 0) then
            reg_running <= wr_data(0);
        elsif (wr_addr = 1) then
            reg_ip_addr <= wr_data;
        elsif (wr_addr = 2) then
            reg_sub_addr <= wr_data;
        elsif (wr_addr = 3) then
            reg_sub_mask <= wr_data;
        -- Note: Registers 4 and 5 handled below
        elsif (wr_addr = 6 and NOIP_REG_EN) then
            reg_noip_dmac_eg(31 downto 0) <= wr_data;
        elsif (wr_addr = 7 and NOIP_REG_EN) then
            reg_noip_dmac_eg(47 downto 32) <= wr_data(15 downto 0);
        elsif (wr_addr = 8 and NOIP_REG_EN) then
            reg_noip_dmac_ig(31 downto 0) <= wr_data;
        elsif (wr_addr = 9 and NOIP_REG_EN) then
            reg_noip_dmac_ig(47 downto 32) <= wr_data(15 downto 0);
        elsif (wr_addr = 10 and IPV4_REG_EN) then
            reg_ipv4_dmac_eg(31 downto 0) <= wr_data;
        elsif (wr_addr = 11 and IPV4_REG_EN) then
            reg_ipv4_dmac_eg(47 downto 32) <= wr_data(15 downto 0);
        elsif (wr_addr = 12 and IPV4_REG_EN) then
            reg_ipv4_dmac_ig(31 downto 0) <= wr_data;
        elsif (wr_addr = 13 and IPV4_REG_EN) then
            reg_ipv4_dmac_ig(47 downto 32) <= wr_data(15 downto 0);
        end if;

        -- Clock-domain transition for the timestamp counter.
        -- On write: Signal main counter that it should latch new value,
        --           and ignore routine updates for a few clock cycles.
        -- Otherwise: Latch the updated value from the rtc_clk domain.
        --            (Infrequent updates, already quasi-stable.
        if (wr_exec = '1' and wr_addr = 4) then
            reg_time_cpu    <= wr_data;
            time_update_t   <= not time_update_t;
            time_update_cd  := TIME_SYNC_COOLDOWN;
        elsif (time_update_cd > 0) then
            time_update_cd  := time_update_cd - 1;
        elsif (time_incr_i = '1') then
            reg_time_cpu    <= std_logic_vector(reg_time_utc_n & reg_time_msec);
        end if;

        -- Clock-domain transition for the dropped-packet counter.
        if (wr_exec = '1' and wr_addr = 5) then
            drop_update_t   <= not drop_update_t;
        end if;
    end if;
end process;

-- AXI-Lite write interface logic.
axi_awready <= not wr_gotaddr;
axi_wready  <= not wr_gotdata;
wr_preexec  <= (axi_bready or not wr_rpend)
           and (wr_gotaddr or axi_awvalid)
           and (wr_gotdata or axi_wvalid);

p_axi_wr : process(axi_clk)
begin
    if rising_edge(axi_clk) then
        if (axi_awvalid = '1' and wr_gotaddr = '0') then
            -- Latch new address when ready.
            wr_addr <= convert_address(axi_awaddr, BASE_ADDR, SUB_ADDR_WIDTH);
        end if;

        if (axi_wvalid = '1' and wr_gotdata = '0') then
            -- Latch new data when ready.
            wr_data <= axi_wdata;
            -- Note: Ignore WSTRB, except for warnings in simulation.
            assert (axi_wstrb = "1111")
                report "Register writes must be atomic." severity warning;
        end if;

        -- Update the response-pending flag.
        if (axi_aresetn = '0') then
            wr_rpend <= '0';    -- Global reset
        elsif (wr_preexec = '1') then
            wr_rpend <= '1';    -- New data received
        elsif (axi_bready = '1') then
            wr_rpend <= '0';    -- Response accepted
        end if;

        -- Update the pending / hold flags for address and data.
        wr_exec <= wr_preexec and axi_aresetn;
        if (axi_aresetn = '0' or wr_preexec = '1') then
            -- Clear pending flags on execution or reset.
            wr_gotaddr <= '0';
            wr_gotdata <= '0';
        else
            -- Otherwise, set and hold flags as we receive each item.
            wr_gotaddr <= wr_gotaddr or axi_awvalid;
            wr_gotdata <= wr_gotdata or axi_wvalid;
        end if;
    end if;
end process;

-- AXI-Lite read interface logic.
axi_arready <= axi_rready or not rd_pending;
axi_rdata   <= rd_data;
axi_rvalid  <= rd_pending and axi_aresetn;

p_axi_rd : process(axi_clk)
    variable addr_temp : sub_addr_t := (others => '0');
begin
    if rising_edge(axi_clk) then
        -- Latch the read value as we accept the address.
        if (axi_arvalid = '1' and (axi_rready = '1' or rd_pending = '0')) then
            addr_temp := convert_address(axi_araddr, BASE_ADDR, SUB_ADDR_WIDTH);
            if (addr_temp = 0) then
                rd_data <= (0 => reg_running, others => '0');
            elsif (addr_temp = 1) then
                rd_data <= reg_ip_addr;
            elsif (addr_temp = 2) then
                rd_data <= reg_sub_addr;
            elsif (addr_temp = 3) then
                rd_data <= reg_sub_mask;
            elsif (addr_temp = 4) then
                rd_data <= reg_time_cpu;
            elsif (addr_temp = 5) then
                rd_data <= std_logic_vector(x"0000" & reg_drop_diff);
            elsif (addr_temp = 6 and NOIP_REG_EN) then
                rd_data <= reg_noip_dmac_eg(31 downto 0);
            elsif (addr_temp = 7 and NOIP_REG_EN) then
                rd_data <= x"0000" & reg_noip_dmac_eg(47 downto 32);
            elsif (addr_temp = 8 and NOIP_REG_EN) then
                rd_data <= reg_noip_dmac_ig(31 downto 0);
            elsif (addr_temp = 9 and NOIP_REG_EN) then
                rd_data <= x"0000" & reg_noip_dmac_ig(47 downto 32);
            elsif (addr_temp = 10 and IPV4_REG_EN) then
                rd_data <= reg_ipv4_dmac_eg(31 downto 0);
            elsif (addr_temp = 11 and IPV4_REG_EN) then
                rd_data <= x"0000" & reg_ipv4_dmac_eg(47 downto 32);
            elsif (addr_temp = 12 and IPV4_REG_EN) then
                rd_data <= reg_ipv4_dmac_ig(31 downto 0);
            elsif (addr_temp = 13 and IPV4_REG_EN) then
                rd_data <= x"0000" & reg_ipv4_dmac_ig(47 downto 32);
            else
                rd_data <= (others => '0');
            end if;
        end if;

        -- Buffer read transaction until the reply is consumed.
        if (axi_aresetn = '0') then
            rd_pending <= '0';  -- Interface reset
        elsif (rd_pending = '1' and axi_rready = '0') then
            rd_pending <= '1';  -- Hold until reply is consumed
        elsif (axi_arvalid = '1') then
            rd_pending <= '1';  -- Start of new read transaction
        else
            rd_pending <= '0';  -- Idle
        end if;
    end if;
end process;

end router_config_axi;
