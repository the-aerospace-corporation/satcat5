--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "port_serial_i2c_controller"
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity wrap_port_serial_i2c_controller is
    generic (
    CFG_ENABLE      : boolean;      -- Enable switch configuration?
    CFG_DEV_ADDR    : integer;      -- ConfigBus device address
    I2C_ADDR        : std_logic_vector(7 downto 1); -- Remote I2C device address
    CLKREF_HZ       : positive;     -- Reference clock rate (Hz)
    BAUD_HZ         : positive);    -- I2C baud rate
    port (
    -- External 2-wire interface.
    i2c_sclk    : inout std_logic;
    i2c_sdata   : inout std_logic;

    -- Network port
    sw_rx_clk   : out std_logic;
    sw_rx_data  : out std_logic_vector(7 downto 0);
    sw_rx_last  : out std_logic;
    sw_rx_write : out std_logic;
    sw_rx_error : out std_logic;
    sw_rx_rate  : out std_logic_vector(15 downto 0);
    sw_rx_status: out std_logic_vector(7 downto 0);
    sw_rx_tsof  : out std_logic_vector(47 downto 0);
    sw_rx_reset : out std_logic;
    sw_tx_clk   : out std_logic;
    sw_tx_data  : in  std_logic_vector(7 downto 0);
    sw_tx_last  : in  std_logic;
    sw_tx_valid : in  std_logic;
    sw_tx_ready : out std_logic;
    sw_tx_error : out std_logic;
    sw_tx_pstart: out std_logic;
    sw_tx_tnow  : out std_logic_vector(47 downto 0);
    sw_tx_reset : out std_logic;

    -- Runtime configuration (optional)
    cfg_clk     : in  std_logic;
    cfg_devaddr : in  std_logic_vector(7 downto 0);
    cfg_regaddr : in  std_logic_vector(9 downto 0);
    cfg_wdata   : in  std_logic_vector(31 downto 0);
    cfg_wstrb   : in  std_logic_vector(3 downto 0);
    cfg_wrcmd   : in  std_logic;
    cfg_rdcmd   : in  std_logic;
    cfg_reset_p : in  std_logic;
    cfg_rdata   : out std_logic_vector(31 downto 0);
    cfg_rdack   : out std_logic;
    cfg_rderr   : out std_logic;
    cfg_irq     : out std_logic;

    -- Clock and reset
    ref_clk     : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end wrap_port_serial_i2c_controller;

architecture wrap_port_serial_i2c_controller of wrap_port_serial_i2c_controller is

signal rx_data  : port_rx_m2s;
signal tx_data  : port_tx_s2m;
signal tx_ctrl  : port_tx_m2s;
signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;
signal sclk_i, sclk_o, sdata_i, sdata_o : std_logic;

begin

-- Convert ConfigBus signals.
cfg_cmd.clk     <= cfg_clk;
cfg_cmd.sysaddr <= 0;   -- Unused
cfg_cmd.devaddr <= u2i(cfg_devaddr);
cfg_cmd.regaddr <= u2i(cfg_regaddr);
cfg_cmd.wdata   <= cfg_wdata;
cfg_cmd.wstrb   <= cfg_wstrb;
cfg_cmd.wrcmd   <= cfg_wrcmd;
cfg_cmd.rdcmd   <= cfg_rdcmd;
cfg_cmd.reset_p <= cfg_reset_p;
cfg_rdata       <= cfg_ack.rdata;
cfg_rdack       <= cfg_ack.rdack;
cfg_rderr       <= cfg_ack.rderr;
cfg_irq         <= cfg_ack.irq;

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

-- Convert external interface.
u_sclk : entity work.bidir_io
    port map(
    io_pin  => i2c_sclk,
    d_in    => sclk_i,
    d_out   => sclk_o,
    t_en    => sclk_o);
u_sdata : entity work.bidir_io
    port map(
    io_pin  => i2c_sdata,
    d_in    => sdata_i,
    d_out   => sdata_o,
    t_en    => sdata_o);

-- Unit being wrapped.
u_wrap : entity work.port_serial_i2c_controller
    generic map(
    DEVADDR     => cfgbus_devaddr_if(CFG_DEV_ADDR, CFG_ENABLE),
    I2C_ADDR    => I2C_ADDR,
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => BAUD_HZ)
    port map(
    sclk_o      => sclk_o,
    sclk_i      => sclk_i,
    sdata_o     => sdata_o,
    sdata_i     => sdata_i,
    rx_data     => rx_data,
    tx_data     => tx_data,
    tx_ctrl     => tx_ctrl,
    ext_pause   => '0',
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    ref_clk     => ref_clk,
    reset_p     => reset_p);

end wrap_port_serial_i2c_controller;
