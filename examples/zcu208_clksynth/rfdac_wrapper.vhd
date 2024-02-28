--------------------------------------------------------------------------
-- Copyright 2023 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
-- VHDL wrapper for the RF Data Converter IP-core
--
-- This block is a thin wrapper for the "usp_rf_data_converter_0" IP core,
-- which instantiates four RF-DAC channels and shared control logic.
--
-- Each data stream has sixteen samples per clock, formed from concatenated
-- 16-bit words, LSW-first.  Each pair of channels has its own clock.
--
-- TODO: Confirm it is actually LSW-first.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
library unisim;
use     unisim.vcomponents.all;
use     work.cfgbus_common.all;
use     work.common_primitives.all;

entity rfdac_wrapper is
    generic (
    DEVADDR     : cfgbus_devaddr);
    port (
    -- Analog I/O.
    refclk_in_p : in  std_logic;
    refclk_in_n : in  std_logic;
    sysref_in_p : in  std_logic;
    sysref_in_n : in  std_logic;
    dac_out_p   : out std_logic_vector(3 downto 0);
    dac_out_n   : out std_logic_vector(3 downto 0);

    -- Tile 2 clock and data.
    tile2_clk   : out std_logic;
    tile2_strm0 : in  signed(255 downto 0);
    tile2_strm1 : in  signed(255 downto 0);

    -- Tile 3 clock and data.
    tile3_clk   : out std_logic;
    tile3_strm2 : in  signed(255 downto 0);
    tile3_strm3 : in  signed(255 downto 0);

    -- Control interface
    clk_100     : in  std_logic;
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end rfdac_wrapper;

architecture rfdac_wrapper of rfdac_wrapper is

-- Component definition for the Verilog wrapper.
component usp_rf_data_converter_0 is
    port (
    s_axi_aclk      : in  std_logic;
    s_axi_aresetn   : in  std_logic;
    s_axi_awaddr    : in  std_logic_vector(17 downto 0);
    s_axi_awvalid   : in  std_logic;
    s_axi_awready   : out std_logic;
    s_axi_wdata     : in  std_logic_vector(31 downto 0);
    s_axi_wstrb     : in  std_logic_vector(3 downto 0);
    s_axi_wvalid    : in  std_logic;
    s_axi_wready    : out std_logic;
    s_axi_bresp     : out std_logic_vector(1 downto 0);
    s_axi_bvalid    : out std_logic;
    s_axi_bready    : in  std_logic;
    s_axi_araddr    : in  std_logic_vector(17 downto 0);
    s_axi_arvalid   : in  std_logic;
    s_axi_arready   : out std_logic;
    s_axi_rdata     : out std_logic_vector(31 downto 0);
    s_axi_rresp     : out std_logic_vector(1 downto 0);
    s_axi_rvalid    : out std_logic;
    s_axi_rready    : in  std_logic;
    sysref_in_p     : in  std_logic;
    sysref_in_n     : in  std_logic;
    dac2_clk_p      : in  std_logic;
    dac2_clk_n      : in  std_logic;
    clk_dac2        : out std_logic;
    s2_axis_aclk    : in  std_logic;
    s2_axis_aresetn : in  std_logic;
    clk_dac3        : out std_logic;
    s3_axis_aclk    : in  std_logic;
    s3_axis_aresetn : in  std_logic;
    vout20_p        : out std_logic;
    vout20_n        : out std_logic;
    vout22_p        : out std_logic;
    vout22_n        : out std_logic;
    vout30_p        : out std_logic;
    vout30_n        : out std_logic;
    vout32_p        : out std_logic;
    vout32_n        : out std_logic;
    s20_axis_tdata  : in  std_logic_vector(255 downto 0);
    s20_axis_tvalid : in  std_logic;
    s20_axis_tready : out std_logic;
    s22_axis_tdata  : in  std_logic_vector(255 downto 0);
    s22_axis_tvalid : in  std_logic;
    s22_axis_tready : out std_logic;
    s30_axis_tdata  : in  std_logic_vector(255 downto 0);
    s30_axis_tvalid : in  std_logic;
    s30_axis_tready : out std_logic;
    s32_axis_tdata  : in  std_logic_vector(255 downto 0);
    s32_axis_tvalid : in  std_logic;
    s32_axis_tready : out std_logic;
    irq             : out std_logic);
end component;

-- AXI-Lite configuration bus.
constant ADDR_WIDTH : integer := 18;
signal interrupt    : std_logic;
signal axi_aresetp  : std_logic;
signal axi_aresetn  : std_logic;
signal axi_awaddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_awvalid  : std_logic;
signal axi_awready  : std_logic;
signal axi_wdata    : std_logic_vector(31 downto 0);
signal axi_wstrb    : std_logic_vector(3 downto 0);
signal axi_wvalid   : std_logic;
signal axi_wready   : std_logic;
signal axi_bresp    : std_logic_vector(1 downto 0);
signal axi_bvalid   : std_logic;
signal axi_bready   : std_logic;
signal axi_araddr   : std_logic_vector(ADDR_WIDTH-1 downto 0);
signal axi_arvalid  : std_logic;
signal axi_arready  : std_logic;
signal axi_rdata    : std_logic_vector(31 downto 0);
signal axi_rresp    : std_logic_vector(1 downto 0);
signal axi_rvalid   : std_logic;
signal axi_rready   : std_logic;

-- Clock buffers.
signal clk2_raw     : std_logic;
signal clk2_buf     : std_logic;
signal clk3_raw     : std_logic;
signal clk3_buf     : std_logic;

begin

-- Hold reset for a moment on startup.
u_rst : sync_reset
    generic map(HOLD_MIN => 100_000)
    port map(
    in_reset_p  => cfg_cmd.reset_p,
    out_reset_p => axi_aresetp,
    out_clk     => clk_100);

axi_aresetn <= not axi_aresetp;

-- Convert ConfigBus to AXI-Lite.
u_axi : entity work.cfgbus_to_axilite
    generic map(
    DEVADDR     => DEVADDR,
    ADDR_WIDTH  => ADDR_WIDTH)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    interrupt   => interrupt,
    axi_aclk    => clk_100,
    axi_aresetn => axi_aresetn,
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

-- Instantiate the Xilinx IP-core.
u_dac : usp_rf_data_converter_0
    port map(
    s_axi_aclk      => clk_100,
    s_axi_aresetn   => axi_aresetn,
    s_axi_awaddr    => axi_awaddr,
    s_axi_awvalid   => axi_awvalid,
    s_axi_awready   => axi_awready,
    s_axi_wdata     => axi_wdata,
    s_axi_wstrb     => axi_wstrb,
    s_axi_wvalid    => axi_wvalid,
    s_axi_wready    => axi_wready,
    s_axi_bresp     => axi_bresp,
    s_axi_bvalid    => axi_bvalid,
    s_axi_bready    => axi_bready,
    s_axi_araddr    => axi_araddr,
    s_axi_arvalid   => axi_arvalid,
    s_axi_arready   => axi_arready,
    s_axi_rdata     => axi_rdata,
    s_axi_rresp     => axi_rresp,
    s_axi_rvalid    => axi_rvalid,
    s_axi_rready    => axi_rready,
    sysref_in_p     => sysref_in_p,
    sysref_in_n     => sysref_in_n,
    dac2_clk_p      => refclk_in_p,
    dac2_clk_n      => refclk_in_n,
    clk_dac2        => clk2_raw,
    s2_axis_aclk    => clk2_buf,
    s2_axis_aresetn => axi_aresetn,
    clk_dac3        => clk3_raw,
    s3_axis_aclk    => clk3_buf,
    s3_axis_aresetn => axi_aresetn,
    vout20_p        => dac_out_p(0),
    vout20_n        => dac_out_n(0),
    vout22_p        => dac_out_p(1),
    vout22_n        => dac_out_n(1),
    vout30_p        => dac_out_p(2),
    vout30_n        => dac_out_n(2),
    vout32_p        => dac_out_p(3),
    vout32_n        => dac_out_n(3),
    s20_axis_tdata  => std_logic_vector(tile2_strm0),
    s20_axis_tvalid => '1',
    s20_axis_tready => open,
    s22_axis_tdata  => std_logic_vector(tile2_strm1),
    s22_axis_tvalid => '1',
    s22_axis_tready => open,
    s30_axis_tdata  => std_logic_vector(tile3_strm2),
    s30_axis_tvalid => '1',
    s30_axis_tready => open,
    s32_axis_tdata  => std_logic_vector(tile3_strm3),
    s32_axis_tvalid => '1',
    s32_axis_tready => open,
    irq             => interrupt);

-- Clock buffers.
u_clk2 : BUFG port map(I => clk2_raw, O => clk2_buf);
u_clk3 : BUFG port map(I => clk3_raw, O => clk3_buf);

tile2_clk <= clk2_buf;
tile3_clk <= clk3_buf;

end rfdac_wrapper;
