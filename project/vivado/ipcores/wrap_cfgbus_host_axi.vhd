--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "cfgbus_host_axi"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

entity wrap_cfgbus_host_axi is
    generic (
    ADDR_WIDTH  : positive := 32;   -- AXI-Lite address width
    RD_TIMEOUT  : positive := 15);  -- ConfigBus read timeout (clocks)
    port (
    -- ConfigBus host interface.
    cfg_clk     : out std_logic;
    cfg_sysaddr : out std_logic_vector(11 downto 0);
    cfg_devaddr : out std_logic_vector(7 downto 0);
    cfg_regaddr : out std_logic_vector(9 downto 0);
    cfg_wdata   : out std_logic_vector(31 downto 0);
    cfg_wstrb   : out std_logic_vector(3 downto 0);
    cfg_wrcmd   : out std_logic;
    cfg_rdcmd   : out std_logic;
    cfg_reset_p : out std_logic;
    cfg_rdata   : in  std_logic_vector(31 downto 0);
    cfg_rdack   : in  std_logic;
    cfg_rderr   : in  std_logic;
    cfg_irq     : in  std_logic;

    -- Interrupt (optional)
    irq_out     : out std_logic;

    -- AXI-Lite interface
    axi_clk     : in  std_logic;
    axi_aresetn : in  std_logic;
    axi_awaddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_awvalid : in  std_logic;
    axi_awready : out std_logic;
    axi_wdata   : in  std_logic_vector(31 downto 0);
    axi_wstrb   : in  std_logic_vector(3 downto 0);
    axi_wvalid  : in  std_logic;
    axi_wready  : out std_logic;
    axi_bresp   : out std_logic_vector(1 downto 0);
    axi_bvalid  : out std_logic;
    axi_bready  : in  std_logic;
    axi_araddr  : in  std_logic_vector(ADDR_WIDTH-1 downto 0);
    axi_arvalid : in  std_logic;
    axi_arready : out std_logic;
    axi_rdata   : out std_logic_vector(31 downto 0);
    axi_rresp   : out std_logic_vector(1 downto 0);
    axi_rvalid  : out std_logic;
    axi_rready  : in  std_logic);
end wrap_cfgbus_host_axi;

architecture wrap_cfgbus_host_axi of wrap_cfgbus_host_axi is

signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert ConfigBus signals.
cfg_clk         <= cfg_cmd.clk;
cfg_sysaddr     <= i2s(cfg_cmd.sysaddr, 12);
cfg_devaddr     <= i2s(cfg_cmd.devaddr, 8);
cfg_regaddr     <= i2s(cfg_cmd.regaddr, 10);
cfg_wdata       <= cfg_cmd.wdata;
cfg_wstrb       <= cfg_cmd.wstrb;
cfg_wrcmd       <= cfg_cmd.wrcmd;
cfg_rdcmd       <= cfg_cmd.rdcmd;
cfg_reset_p     <= cfg_cmd.reset_p;
cfg_ack.rdata   <= cfg_rdata;
cfg_ack.rdack   <= cfg_rdack;
cfg_ack.rderr   <= cfg_rderr;
cfg_ack.irq     <= cfg_irq;

-- Wrapped unit
u_wrap : entity work.cfgbus_host_axi
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT,
    ADDR_WIDTH  => ADDR_WIDTH)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    axi_clk     => axi_clk,
    axi_aresetn => axi_aresetn,
    axi_irq     => irq_out,
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

end wrap_cfgbus_host_axi;
