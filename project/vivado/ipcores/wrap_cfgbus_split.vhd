--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Wrapper for splitting and combining ConfigBus ports
--
-- Xilinx IP-cores can only use simple std_logic and std_logic_vector types.
-- This shim provides that conversion.
--
-- IMPORTANT NOTE: This script takes a LONG time to run in GUI mode, and can
-- even run out of memory.  It should always be run from the TCL console.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

entity wrap_cfgbus_split is
    generic (
    PORT_COUNT  : integer;  -- Number of downstream ports
    DLY_BUFFER  : boolean); -- Delay inputs and outputs by one clock?
    port (
    -- Upstream port
    cfg_clk     : in  std_logic;
    cfg_sysaddr : in  std_logic_vector(11 downto 0);
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

    -- Up to 16 downstream ports, enabled/hidden based on PORT_COUNT.
    p00_clk     : out std_logic;
    p00_sysaddr : out std_logic_vector(11 downto 0);
    p00_devaddr : out std_logic_vector(7 downto 0);
    p00_regaddr : out std_logic_vector(9 downto 0);
    p00_wdata   : out std_logic_vector(31 downto 0);
    p00_wstrb   : out std_logic_vector(3 downto 0);
    p00_wrcmd   : out std_logic;
    p00_rdcmd   : out std_logic;
    p00_reset_p : out std_logic;
    p00_rdata   : in  std_logic_vector(31 downto 0);
    p00_rdack   : in  std_logic;
    p00_rderr   : in  std_logic;
    p00_irq     : in  std_logic;

    p01_clk     : out std_logic;
    p01_sysaddr : out std_logic_vector(11 downto 0);
    p01_devaddr : out std_logic_vector(7 downto 0);
    p01_regaddr : out std_logic_vector(9 downto 0);
    p01_wdata   : out std_logic_vector(31 downto 0);
    p01_wstrb   : out std_logic_vector(3 downto 0);
    p01_wrcmd   : out std_logic;
    p01_rdcmd   : out std_logic;
    p01_reset_p : out std_logic;
    p01_rdata   : in  std_logic_vector(31 downto 0);
    p01_rdack   : in  std_logic;
    p01_rderr   : in  std_logic;
    p01_irq     : in  std_logic;

    p02_clk     : out std_logic;
    p02_sysaddr : out std_logic_vector(11 downto 0);
    p02_devaddr : out std_logic_vector(7 downto 0);
    p02_regaddr : out std_logic_vector(9 downto 0);
    p02_wdata   : out std_logic_vector(31 downto 0);
    p02_wstrb   : out std_logic_vector(3 downto 0);
    p02_wrcmd   : out std_logic;
    p02_rdcmd   : out std_logic;
    p02_reset_p : out std_logic;
    p02_rdata   : in  std_logic_vector(31 downto 0);
    p02_rdack   : in  std_logic;
    p02_rderr   : in  std_logic;
    p02_irq     : in  std_logic;

    p03_clk     : out std_logic;
    p03_sysaddr : out std_logic_vector(11 downto 0);
    p03_devaddr : out std_logic_vector(7 downto 0);
    p03_regaddr : out std_logic_vector(9 downto 0);
    p03_wdata   : out std_logic_vector(31 downto 0);
    p03_wstrb   : out std_logic_vector(3 downto 0);
    p03_wrcmd   : out std_logic;
    p03_rdcmd   : out std_logic;
    p03_reset_p : out std_logic;
    p03_rdata   : in  std_logic_vector(31 downto 0);
    p03_rdack   : in  std_logic;
    p03_rderr   : in  std_logic;
    p03_irq     : in  std_logic;

    p04_clk     : out std_logic;
    p04_sysaddr : out std_logic_vector(11 downto 0);
    p04_devaddr : out std_logic_vector(7 downto 0);
    p04_regaddr : out std_logic_vector(9 downto 0);
    p04_wdata   : out std_logic_vector(31 downto 0);
    p04_wstrb   : out std_logic_vector(3 downto 0);
    p04_wrcmd   : out std_logic;
    p04_rdcmd   : out std_logic;
    p04_reset_p : out std_logic;
    p04_rdata   : in  std_logic_vector(31 downto 0);
    p04_rdack   : in  std_logic;
    p04_rderr   : in  std_logic;
    p04_irq     : in  std_logic;

    p05_clk     : out std_logic;
    p05_sysaddr : out std_logic_vector(11 downto 0);
    p05_devaddr : out std_logic_vector(7 downto 0);
    p05_regaddr : out std_logic_vector(9 downto 0);
    p05_wdata   : out std_logic_vector(31 downto 0);
    p05_wstrb   : out std_logic_vector(3 downto 0);
    p05_wrcmd   : out std_logic;
    p05_rdcmd   : out std_logic;
    p05_reset_p : out std_logic;
    p05_rdata   : in  std_logic_vector(31 downto 0);
    p05_rdack   : in  std_logic;
    p05_rderr   : in  std_logic;
    p05_irq     : in  std_logic;

    p06_clk     : out std_logic;
    p06_sysaddr : out std_logic_vector(11 downto 0);
    p06_devaddr : out std_logic_vector(7 downto 0);
    p06_regaddr : out std_logic_vector(9 downto 0);
    p06_wdata   : out std_logic_vector(31 downto 0);
    p06_wstrb   : out std_logic_vector(3 downto 0);
    p06_wrcmd   : out std_logic;
    p06_rdcmd   : out std_logic;
    p06_reset_p : out std_logic;
    p06_rdata   : in  std_logic_vector(31 downto 0);
    p06_rdack   : in  std_logic;
    p06_rderr   : in  std_logic;
    p06_irq     : in  std_logic;

    p07_clk     : out std_logic;
    p07_sysaddr : out std_logic_vector(11 downto 0);
    p07_devaddr : out std_logic_vector(7 downto 0);
    p07_regaddr : out std_logic_vector(9 downto 0);
    p07_wdata   : out std_logic_vector(31 downto 0);
    p07_wstrb   : out std_logic_vector(3 downto 0);
    p07_wrcmd   : out std_logic;
    p07_rdcmd   : out std_logic;
    p07_reset_p : out std_logic;
    p07_rdata   : in  std_logic_vector(31 downto 0);
    p07_rdack   : in  std_logic;
    p07_rderr   : in  std_logic;
    p07_irq     : in  std_logic;

    p08_clk     : out std_logic;
    p08_sysaddr : out std_logic_vector(11 downto 0);
    p08_devaddr : out std_logic_vector(7 downto 0);
    p08_regaddr : out std_logic_vector(9 downto 0);
    p08_wdata   : out std_logic_vector(31 downto 0);
    p08_wstrb   : out std_logic_vector(3 downto 0);
    p08_wrcmd   : out std_logic;
    p08_rdcmd   : out std_logic;
    p08_reset_p : out std_logic;
    p08_rdata   : in  std_logic_vector(31 downto 0);
    p08_rdack   : in  std_logic;
    p08_rderr   : in  std_logic;
    p08_irq     : in  std_logic;

    p09_clk     : out std_logic;
    p09_sysaddr : out std_logic_vector(11 downto 0);
    p09_devaddr : out std_logic_vector(7 downto 0);
    p09_regaddr : out std_logic_vector(9 downto 0);
    p09_wdata   : out std_logic_vector(31 downto 0);
    p09_wstrb   : out std_logic_vector(3 downto 0);
    p09_wrcmd   : out std_logic;
    p09_rdcmd   : out std_logic;
    p09_reset_p : out std_logic;
    p09_rdata   : in  std_logic_vector(31 downto 0);
    p09_rdack   : in  std_logic;
    p09_rderr   : in  std_logic;
    p09_irq     : in  std_logic;

    p10_clk     : out std_logic;
    p10_sysaddr : out std_logic_vector(11 downto 0);
    p10_devaddr : out std_logic_vector(7 downto 0);
    p10_regaddr : out std_logic_vector(9 downto 0);
    p10_wdata   : out std_logic_vector(31 downto 0);
    p10_wstrb   : out std_logic_vector(3 downto 0);
    p10_wrcmd   : out std_logic;
    p10_rdcmd   : out std_logic;
    p10_reset_p : out std_logic;
    p10_rdata   : in  std_logic_vector(31 downto 0);
    p10_rdack   : in  std_logic;
    p10_rderr   : in  std_logic;
    p10_irq     : in  std_logic;

    p11_clk     : out std_logic;
    p11_sysaddr : out std_logic_vector(11 downto 0);
    p11_devaddr : out std_logic_vector(7 downto 0);
    p11_regaddr : out std_logic_vector(9 downto 0);
    p11_wdata   : out std_logic_vector(31 downto 0);
    p11_wstrb   : out std_logic_vector(3 downto 0);
    p11_wrcmd   : out std_logic;
    p11_rdcmd   : out std_logic;
    p11_reset_p : out std_logic;
    p11_rdata   : in  std_logic_vector(31 downto 0);
    p11_rdack   : in  std_logic;
    p11_rderr   : in  std_logic;
    p11_irq     : in  std_logic;

    p12_clk     : out std_logic;
    p12_sysaddr : out std_logic_vector(11 downto 0);
    p12_devaddr : out std_logic_vector(7 downto 0);
    p12_regaddr : out std_logic_vector(9 downto 0);
    p12_wdata   : out std_logic_vector(31 downto 0);
    p12_wstrb   : out std_logic_vector(3 downto 0);
    p12_wrcmd   : out std_logic;
    p12_rdcmd   : out std_logic;
    p12_reset_p : out std_logic;
    p12_rdata   : in  std_logic_vector(31 downto 0);
    p12_rdack   : in  std_logic;
    p12_rderr   : in  std_logic;
    p12_irq     : in  std_logic;

    p13_clk     : out std_logic;
    p13_sysaddr : out std_logic_vector(11 downto 0);
    p13_devaddr : out std_logic_vector(7 downto 0);
    p13_regaddr : out std_logic_vector(9 downto 0);
    p13_wdata   : out std_logic_vector(31 downto 0);
    p13_wstrb   : out std_logic_vector(3 downto 0);
    p13_wrcmd   : out std_logic;
    p13_rdcmd   : out std_logic;
    p13_reset_p : out std_logic;
    p13_rdata   : in  std_logic_vector(31 downto 0);
    p13_rdack   : in  std_logic;
    p13_rderr   : in  std_logic;
    p13_irq     : in  std_logic;

    p14_clk     : out std_logic;
    p14_sysaddr : out std_logic_vector(11 downto 0);
    p14_devaddr : out std_logic_vector(7 downto 0);
    p14_regaddr : out std_logic_vector(9 downto 0);
    p14_wdata   : out std_logic_vector(31 downto 0);
    p14_wstrb   : out std_logic_vector(3 downto 0);
    p14_wrcmd   : out std_logic;
    p14_rdcmd   : out std_logic;
    p14_reset_p : out std_logic;
    p14_rdata   : in  std_logic_vector(31 downto 0);
    p14_rdack   : in  std_logic;
    p14_rderr   : in  std_logic;
    p14_irq     : in  std_logic;

    p15_clk     : out std_logic;
    p15_sysaddr : out std_logic_vector(11 downto 0);
    p15_devaddr : out std_logic_vector(7 downto 0);
    p15_regaddr : out std_logic_vector(9 downto 0);
    p15_wdata   : out std_logic_vector(31 downto 0);
    p15_wstrb   : out std_logic_vector(3 downto 0);
    p15_wrcmd   : out std_logic;
    p15_rdcmd   : out std_logic;
    p15_reset_p : out std_logic;
    p15_rdata   : in  std_logic_vector(31 downto 0);
    p15_rdack   : in  std_logic;
    p15_rderr   : in  std_logic;
    p15_irq     : in  std_logic);
end wrap_cfgbus_split;

architecture wrap_cfgbus_split of wrap_cfgbus_split is

signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;
signal buf_cmd  : cfgbus_cmd;
signal buf_ack  : cfgbus_ack;
signal raw_ack  : cfgbus_ack_array(15 downto 0);

begin

-- Map signals for the upstream port.
cfg_cmd.clk     <= cfg_clk;
cfg_cmd.sysaddr <= u2i(cfg_sysaddr);
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

-- Optionally insert buffer stage.
gen_buff : if DLY_BUFFER generate
    u_buff : cfgbus_buffer
        port map(
        host_cmd    => cfg_cmd,
        host_ack    => cfg_ack,
        buff_cmd    => buf_cmd,
        buff_ack    => buf_ack);
end generate;

gen_nobuff : if not DLY_BUFFER generate
    buf_cmd <= cfg_cmd;
    cfg_ack <= buf_ack;
end generate;

-- Conslidate inputs.
buf_ack <= cfgbus_merge(raw_ack);

-- Copy buffered command signals to every output, enabled or not.
p00_clk     <= buf_cmd.clk;
p01_clk     <= buf_cmd.clk;
p02_clk     <= buf_cmd.clk;
p03_clk     <= buf_cmd.clk;
p04_clk     <= buf_cmd.clk;
p05_clk     <= buf_cmd.clk;
p06_clk     <= buf_cmd.clk;
p07_clk     <= buf_cmd.clk;
p08_clk     <= buf_cmd.clk;
p09_clk     <= buf_cmd.clk;
p10_clk     <= buf_cmd.clk;
p11_clk     <= buf_cmd.clk;
p12_clk     <= buf_cmd.clk;
p13_clk     <= buf_cmd.clk;
p14_clk     <= buf_cmd.clk;
p15_clk     <= buf_cmd.clk;

p00_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p01_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p02_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p03_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p04_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p05_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p06_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p07_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p08_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p09_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p10_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p11_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p12_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p13_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p14_sysaddr <= i2s(buf_cmd.sysaddr, 12);
p15_sysaddr <= i2s(buf_cmd.sysaddr, 12);

p00_devaddr <= i2s(buf_cmd.devaddr, 8);
p01_devaddr <= i2s(buf_cmd.devaddr, 8);
p02_devaddr <= i2s(buf_cmd.devaddr, 8);
p03_devaddr <= i2s(buf_cmd.devaddr, 8);
p04_devaddr <= i2s(buf_cmd.devaddr, 8);
p05_devaddr <= i2s(buf_cmd.devaddr, 8);
p06_devaddr <= i2s(buf_cmd.devaddr, 8);
p07_devaddr <= i2s(buf_cmd.devaddr, 8);
p08_devaddr <= i2s(buf_cmd.devaddr, 8);
p09_devaddr <= i2s(buf_cmd.devaddr, 8);
p10_devaddr <= i2s(buf_cmd.devaddr, 8);
p11_devaddr <= i2s(buf_cmd.devaddr, 8);
p12_devaddr <= i2s(buf_cmd.devaddr, 8);
p13_devaddr <= i2s(buf_cmd.devaddr, 8);
p14_devaddr <= i2s(buf_cmd.devaddr, 8);
p15_devaddr <= i2s(buf_cmd.devaddr, 8);

p00_regaddr <= i2s(buf_cmd.regaddr, 10);
p01_regaddr <= i2s(buf_cmd.regaddr, 10);
p02_regaddr <= i2s(buf_cmd.regaddr, 10);
p03_regaddr <= i2s(buf_cmd.regaddr, 10);
p04_regaddr <= i2s(buf_cmd.regaddr, 10);
p05_regaddr <= i2s(buf_cmd.regaddr, 10);
p06_regaddr <= i2s(buf_cmd.regaddr, 10);
p07_regaddr <= i2s(buf_cmd.regaddr, 10);
p08_regaddr <= i2s(buf_cmd.regaddr, 10);
p09_regaddr <= i2s(buf_cmd.regaddr, 10);
p10_regaddr <= i2s(buf_cmd.regaddr, 10);
p11_regaddr <= i2s(buf_cmd.regaddr, 10);
p12_regaddr <= i2s(buf_cmd.regaddr, 10);
p13_regaddr <= i2s(buf_cmd.regaddr, 10);
p14_regaddr <= i2s(buf_cmd.regaddr, 10);
p15_regaddr <= i2s(buf_cmd.regaddr, 10);

p00_wdata   <= buf_cmd.wdata;
p01_wdata   <= buf_cmd.wdata;
p02_wdata   <= buf_cmd.wdata;
p03_wdata   <= buf_cmd.wdata;
p04_wdata   <= buf_cmd.wdata;
p05_wdata   <= buf_cmd.wdata;
p06_wdata   <= buf_cmd.wdata;
p07_wdata   <= buf_cmd.wdata;
p08_wdata   <= buf_cmd.wdata;
p09_wdata   <= buf_cmd.wdata;
p10_wdata   <= buf_cmd.wdata;
p11_wdata   <= buf_cmd.wdata;
p12_wdata   <= buf_cmd.wdata;
p13_wdata   <= buf_cmd.wdata;
p14_wdata   <= buf_cmd.wdata;
p15_wdata   <= buf_cmd.wdata;

p00_wstrb   <= buf_cmd.wstrb;
p01_wstrb   <= buf_cmd.wstrb;
p02_wstrb   <= buf_cmd.wstrb;
p03_wstrb   <= buf_cmd.wstrb;
p04_wstrb   <= buf_cmd.wstrb;
p05_wstrb   <= buf_cmd.wstrb;
p06_wstrb   <= buf_cmd.wstrb;
p07_wstrb   <= buf_cmd.wstrb;
p08_wstrb   <= buf_cmd.wstrb;
p09_wstrb   <= buf_cmd.wstrb;
p10_wstrb   <= buf_cmd.wstrb;
p11_wstrb   <= buf_cmd.wstrb;
p12_wstrb   <= buf_cmd.wstrb;
p13_wstrb   <= buf_cmd.wstrb;
p14_wstrb   <= buf_cmd.wstrb;
p15_wstrb   <= buf_cmd.wstrb;

p00_wrcmd   <= buf_cmd.wrcmd;
p01_wrcmd   <= buf_cmd.wrcmd;
p02_wrcmd   <= buf_cmd.wrcmd;
p03_wrcmd   <= buf_cmd.wrcmd;
p04_wrcmd   <= buf_cmd.wrcmd;
p05_wrcmd   <= buf_cmd.wrcmd;
p06_wrcmd   <= buf_cmd.wrcmd;
p07_wrcmd   <= buf_cmd.wrcmd;
p08_wrcmd   <= buf_cmd.wrcmd;
p09_wrcmd   <= buf_cmd.wrcmd;
p10_wrcmd   <= buf_cmd.wrcmd;
p11_wrcmd   <= buf_cmd.wrcmd;
p12_wrcmd   <= buf_cmd.wrcmd;
p13_wrcmd   <= buf_cmd.wrcmd;
p14_wrcmd   <= buf_cmd.wrcmd;
p15_wrcmd   <= buf_cmd.wrcmd;

p00_rdcmd   <= buf_cmd.rdcmd;
p01_rdcmd   <= buf_cmd.rdcmd;
p02_rdcmd   <= buf_cmd.rdcmd;
p03_rdcmd   <= buf_cmd.rdcmd;
p04_rdcmd   <= buf_cmd.rdcmd;
p05_rdcmd   <= buf_cmd.rdcmd;
p06_rdcmd   <= buf_cmd.rdcmd;
p07_rdcmd   <= buf_cmd.rdcmd;
p08_rdcmd   <= buf_cmd.rdcmd;
p09_rdcmd   <= buf_cmd.rdcmd;
p10_rdcmd   <= buf_cmd.rdcmd;
p11_rdcmd   <= buf_cmd.rdcmd;
p12_rdcmd   <= buf_cmd.rdcmd;
p13_rdcmd   <= buf_cmd.rdcmd;
p14_rdcmd   <= buf_cmd.rdcmd;
p15_rdcmd   <= buf_cmd.rdcmd;

p00_reset_p <= buf_cmd.reset_p;
p01_reset_p <= buf_cmd.reset_p;
p02_reset_p <= buf_cmd.reset_p;
p03_reset_p <= buf_cmd.reset_p;
p04_reset_p <= buf_cmd.reset_p;
p05_reset_p <= buf_cmd.reset_p;
p06_reset_p <= buf_cmd.reset_p;
p07_reset_p <= buf_cmd.reset_p;
p08_reset_p <= buf_cmd.reset_p;
p09_reset_p <= buf_cmd.reset_p;
p10_reset_p <= buf_cmd.reset_p;
p11_reset_p <= buf_cmd.reset_p;
p12_reset_p <= buf_cmd.reset_p;
p13_reset_p <= buf_cmd.reset_p;
p14_reset_p <= buf_cmd.reset_p;
p15_reset_p <= buf_cmd.reset_p;

-- Accept or ignore inputs based on PORT_COUNT.
gen_p00 : if (PORT_COUNT > 0) generate
    raw_ack(0).rdata <= p00_rdata;
    raw_ack(0).rdack <= p00_rdack;
    raw_ack(0).rderr <= p00_rderr;
    raw_ack(0).irq   <= p00_irq;
end generate;

gen_n00 : if (PORT_COUNT < 1) generate
    raw_ack(0) <= cfgbus_idle;
end generate;

gen_p01 : if (PORT_COUNT > 1) generate
    raw_ack(1).rdata <= p01_rdata;
    raw_ack(1).rdack <= p01_rdack;
    raw_ack(1).rderr <= p01_rderr;
    raw_ack(1).irq   <= p01_irq;
end generate;

gen_n01 : if (PORT_COUNT < 2) generate
    raw_ack(1) <= cfgbus_idle;
end generate;

gen_p02 : if (PORT_COUNT > 2) generate
    raw_ack(2).rdata <= p02_rdata;
    raw_ack(2).rdack <= p02_rdack;
    raw_ack(2).rderr <= p02_rderr;
    raw_ack(2).irq   <= p02_irq;
end generate;

gen_n02 : if (PORT_COUNT < 3) generate
    raw_ack(2) <= cfgbus_idle;
end generate;

gen_p03 : if (PORT_COUNT > 3) generate
    raw_ack(3).rdata <= p03_rdata;
    raw_ack(3).rdack <= p03_rdack;
    raw_ack(3).rderr <= p03_rderr;
    raw_ack(3).irq   <= p03_irq;
end generate;

gen_n03 : if (PORT_COUNT < 4) generate
    raw_ack(3) <= cfgbus_idle;
end generate;

gen_p04 : if (PORT_COUNT > 4) generate
    raw_ack(4).rdata <= p04_rdata;
    raw_ack(4).rdack <= p04_rdack;
    raw_ack(4).rderr <= p04_rderr;
    raw_ack(4).irq   <= p04_irq;
end generate;

gen_n04 : if (PORT_COUNT < 5) generate
    raw_ack(4) <= cfgbus_idle;
end generate;

gen_p05 : if (PORT_COUNT > 5) generate
    raw_ack(5).rdata <= p05_rdata;
    raw_ack(5).rdack <= p05_rdack;
    raw_ack(5).rderr <= p05_rderr;
    raw_ack(5).irq   <= p05_irq;
end generate;

gen_n05 : if (PORT_COUNT < 6) generate
    raw_ack(5) <= cfgbus_idle;
end generate;

gen_p06 : if (PORT_COUNT > 6) generate
    raw_ack(6).rdata <= p06_rdata;
    raw_ack(6).rdack <= p06_rdack;
    raw_ack(6).rderr <= p06_rderr;
    raw_ack(6).irq   <= p06_irq;
end generate;

gen_n06 : if (PORT_COUNT < 7) generate
    raw_ack(6) <= cfgbus_idle;
end generate;

gen_p07 : if (PORT_COUNT > 7) generate
    raw_ack(7).rdata <= p07_rdata;
    raw_ack(7).rdack <= p07_rdack;
    raw_ack(7).rderr <= p07_rderr;
    raw_ack(7).irq   <= p07_irq;
end generate;

gen_n07 : if (PORT_COUNT < 8) generate
    raw_ack(7) <= cfgbus_idle;
end generate;

gen_p08 : if (PORT_COUNT > 8) generate
    raw_ack(8).rdata <= p08_rdata;
    raw_ack(8).rdack <= p08_rdack;
    raw_ack(8).rderr <= p08_rderr;
    raw_ack(8).irq   <= p08_irq;
end generate;

gen_n08 : if (PORT_COUNT < 9) generate
    raw_ack(8) <= cfgbus_idle;
end generate;

gen_p09 : if (PORT_COUNT > 9) generate
    raw_ack(9).rdata <= p09_rdata;
    raw_ack(9).rdack <= p09_rdack;
    raw_ack(9).rderr <= p09_rderr;
    raw_ack(9).irq   <= p09_irq;
end generate;

gen_n09 : if (PORT_COUNT < 10) generate
    raw_ack(9) <= cfgbus_idle;
end generate;

gen_p10 : if (PORT_COUNT > 10) generate
    raw_ack(10).rdata <= p10_rdata;
    raw_ack(10).rdack <= p10_rdack;
    raw_ack(10).rderr <= p10_rderr;
    raw_ack(10).irq   <= p10_irq;
end generate;

gen_n10 : if (PORT_COUNT < 11) generate
    raw_ack(10) <= cfgbus_idle;
end generate;

gen_p11 : if (PORT_COUNT > 11) generate
    raw_ack(11).rdata <= p11_rdata;
    raw_ack(11).rdack <= p11_rdack;
    raw_ack(11).rderr <= p11_rderr;
    raw_ack(11).irq   <= p11_irq;
end generate;

gen_n11 : if (PORT_COUNT < 12) generate
    raw_ack(11) <= cfgbus_idle;
end generate;

gen_p12 : if (PORT_COUNT > 12) generate
    raw_ack(12).rdata <= p12_rdata;
    raw_ack(12).rdack <= p12_rdack;
    raw_ack(12).rderr <= p12_rderr;
    raw_ack(12).irq   <= p12_irq;
end generate;

gen_n12 : if (PORT_COUNT < 13) generate
    raw_ack(12) <= cfgbus_idle;
end generate;

gen_p13 : if (PORT_COUNT > 13) generate
    raw_ack(13).rdata <= p13_rdata;
    raw_ack(13).rdack <= p13_rdack;
    raw_ack(13).rderr <= p13_rderr;
    raw_ack(13).irq   <= p13_irq;
end generate;

gen_n13 : if (PORT_COUNT < 14) generate
    raw_ack(13) <= cfgbus_idle;
end generate;

gen_p14 : if (PORT_COUNT > 14) generate
    raw_ack(14).rdata <= p14_rdata;
    raw_ack(14).rdack <= p14_rdack;
    raw_ack(14).rderr <= p14_rderr;
    raw_ack(14).irq   <= p14_irq;
end generate;

gen_n14 : if (PORT_COUNT < 15) generate
    raw_ack(14) <= cfgbus_idle;
end generate;

gen_p15 : if (PORT_COUNT > 15) generate
    raw_ack(15).rdata <= p15_rdata;
    raw_ack(15).rdack <= p15_rdack;
    raw_ack(15).rderr <= p15_rderr;
    raw_ack(15).irq   <= p15_irq;
end generate;

gen_n15 : if (PORT_COUNT < 16) generate
    raw_ack(15) <= cfgbus_idle;
end generate;

end wrap_cfgbus_split;
