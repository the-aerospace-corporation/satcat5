--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "port_axi_mailbox"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity wrap_port_axi_mailbox is
    generic (
    ADDR_WIDTH  : integer := 32;        -- AXI-Lite address width
    MIN_FRAME   : integer := 0;         -- Minimum output frame size
    APPEND_FCS  : boolean := true;      -- Append FCS to each sent frame??
    STRIP_FCS   : boolean := true;      -- Remove FCS from received frames?
    PTP_ENABLE  : boolean := false;     -- Enable PTP timestamps?
    PTP_REF_HZ  : integer := 0;         -- Vernier reference frequency
    PTP_TAU_MS  : integer := 50;        -- Tracking time constant (msec)
    PTP_AUX_EN  : boolean := true);     -- Enable extra tracking filter?
    port (
    -- Internal Ethernet port.
    sw_rx_clk       : out std_logic;
    sw_rx_data      : out std_logic_vector(7 downto 0);
    sw_rx_last      : out std_logic;
    sw_rx_write     : out std_logic;
    sw_rx_error     : out std_logic;
    sw_rx_rate      : out std_logic_vector(15 downto 0);
    sw_rx_status    : out std_logic_vector(7 downto 0);
    sw_rx_tsof      : out std_logic_vector(47 downto 0);
    sw_rx_reset     : out std_logic;
    sw_tx_clk       : out std_logic;
    sw_tx_data      : in  std_logic_vector(7 downto 0);
    sw_tx_last      : in  std_logic;
    sw_tx_valid     : in  std_logic;
    sw_tx_ready     : out std_logic;
    sw_tx_error     : out std_logic;
    sw_tx_pstart    : out std_logic;
    sw_tx_tnow      : out std_logic_vector(47 downto 0);
    sw_tx_reset     : out std_logic;

    -- Vernier reference time (optional)
    tref_vclka  : in  std_logic;
    tref_vclkb  : in  std_logic;
    tref_tnext  : in  std_logic;
    tref_tstamp : in  std_logic_vector(47 downto 0);

    -- Interrupt signal (optional)
    irq_out         : out std_logic;

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
end wrap_port_axi_mailbox;

architecture wrap_port_axi_mailbox of wrap_port_axi_mailbox is

constant VCONFIG : vernier_config := create_vernier_config(
    value_else_zero(PTP_REF_HZ, PTP_ENABLE), real(PTP_TAU_MS), PTP_AUX_EN);

signal ref_time : port_timeref;
signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_s2m;
signal tx_ctrl  : port_tx_m2s;
signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert port signals.
sw_rx_clk       <= rx_data.clk;
sw_rx_data      <= rx_data.data;
sw_rx_last      <= rx_data.last;
sw_rx_write     <= rx_data.write;
sw_rx_error     <= rx_data.rxerr;
sw_rx_rate      <= rx_data.rate;
sw_rx_tsof      <= std_logic_vector(rx_data.tsof);
sw_rx_status    <= rx_data.status;
sw_rx_reset     <= rx_data.reset_p;
sw_tx_clk       <= tx_ctrl.clk;
sw_tx_ready     <= tx_ctrl.ready;
sw_tx_pstart    <= tx_ctrl.pstart;
sw_tx_tnow      <= std_logic_vector(tx_ctrl.tnow);
sw_tx_error     <= tx_ctrl.txerr;
sw_tx_reset     <= tx_ctrl.reset_p;
tx_data.data    <= sw_tx_data;
tx_data.last    <= sw_tx_last;
tx_data.valid   <= sw_tx_valid;

-- Convert Vernier signals.
ref_time.vclka  <= tref_vclka;
ref_time.vclkb  <= tref_vclkb;
ref_time.tnext  <= tref_tnext;
ref_time.tstamp <= unsigned(tref_tstamp);

-- ConfigBus adapter.
u_cfgbus : entity work.cfgbus_host_axi
    generic map(
    ADDR_WIDTH  => ADDR_WIDTH)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    axi_irq     => irq_out,
    axi_clk     => axi_clk,
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

-- Mailbox port.
u_wrap : entity work.port_mailbox
    generic map(
    DEV_ADDR    => CFGBUS_ADDR_ANY,
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => STRIP_FCS,
    VCONFIG     => VCONFIG)
    port map(
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    ref_time    => ref_time,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

end wrap_port_axi_mailbox;
