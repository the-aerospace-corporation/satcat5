--------------------------------------------------------------------------
-- Copyright 2020-2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Configuration helper for use with router_inline_top
--
-- This block is a simple static configuration, where all addresses are set
-- at build-time and timestamps use the arbitrary-reference mode.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router_common.all;

entity router_config_static is
    generic (
    CLKREF_HZ       : positive := 125_000_000;      -- Frequency of rtr_clk
    R_IP_ADDR       : ip_addr_t := x"C0A80101";     -- Default = 192.168.1.1
    R_SUB_ADDR      : ip_addr_t := x"C0A80100";     -- Default = 192.168.0.0
    R_SUB_MASK      : ip_addr_t := x"FFFFFF00";     -- Default = 255.255.255.0
    R_IPV4_DMAC_EG  : mac_addr_t := x"DEADBEEFCAFE";
    R_IPV4_DMAC_IG  : mac_addr_t := x"DEADBEEFCAFE";
    R_NOIP_DMAC_EG  : mac_addr_t := MAC_ADDR_BROADCAST;
    R_NOIP_DMAC_IG  : mac_addr_t := MAC_ADDR_BROADCAST);
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
    rtr_time_msec   : out timestamp_t;
    ext_reset_p     : in  std_logic := '0');
end router_config_static;

architecture router_config_static of router_config_static is

signal reg_time_msec : unsigned(30 downto 0) := (others => '0');

begin

-- Drive top-level outputs:
-- Note: Clock is always in arbitrary-refernece mode (MSB = '1').
cfg_reset_p     <= ext_reset_p;
cfg_ip_addr     <= R_IP_ADDR;
cfg_sub_addr    <= R_SUB_ADDR;
cfg_sub_mask    <= R_SUB_MASK;
ipv4_dmac_eg    <= R_IPV4_DMAC_EG;
ipv4_dmac_ig    <= R_IPV4_DMAC_IG;
noip_dmac_eg    <= R_NOIP_DMAC_EG;
noip_dmac_ig    <= R_NOIP_DMAC_IG;
rtr_time_msec   <= '1' & reg_time_msec;

-- Millisecond timestamps from an arbitrary reference time.
p_timer : process(rtr_clk) is
    constant ONE_MSEC : positive := clocks_per_baud(CLKREF_HZ, 1000);
    variable clk_ctr  : integer range 0 to ONE_MSEC-1 := (ONE_MSEC-1);
begin
    if rising_edge(rtr_clk) then
        if (ext_reset_p = '1') then
            reg_time_msec   <= (others => '0');
            clk_ctr         := ONE_MSEC - 1;
        elsif (clk_ctr = 0) then
            reg_time_msec   <= reg_time_msec + 1;
            clk_ctr         := ONE_MSEC - 1;
        else
            clk_ctr         := clk_ctr - 1;
        end if;
    end if;
end process;

end router_config_static;
