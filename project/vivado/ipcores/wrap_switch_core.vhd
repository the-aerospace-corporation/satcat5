--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "switch_core"
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
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity wrap_switch_core is
    generic (
    CFG_ENABLE      : boolean;  -- Enable switch configuration?
    CFG_DEV_ADDR    : integer;  -- ConfigBus address for switch
    STATS_ENABLE    : boolean;  -- Enable traffic statistics over ConfigBus?
    STATS_DEVADDR   : integer;  -- ConfigBus address for statistics
    CORE_CLK_HZ     : integer;  -- Clock frequency for CORE_CLK
    SUPPORT_PAUSE   : boolean;  -- Support or ignore PAUSE frames?
    SUPPORT_PTP     : boolean;  -- Support precise frame timestamps?
    SUPPORT_VLAN    : boolean;  -- Support or ignore 802.1q VLAN tags?
    MISS_BCAST      : boolean;  -- Broadcast or drop unknown MAC?
    ALLOW_JUMBO     : boolean;  -- Allow jumbo frames? (Size up to 9038 bytes)
    ALLOW_RUNT      : boolean;  -- Allow runt frames? (Size < 64 bytes)
    ALLOW_PRECOMMIT : boolean;  -- Allow output FIFO cut-through?
    PORT_COUNT      : integer;  -- Total standard Ethernet ports
    PORTX_COUNT     : integer;  -- Total 10-gigabit Ethernet ports
    DATAPATH_BYTES  : integer;  -- Width of shared pipeline
    IBUF_KBYTES     : integer;  -- Input buffer size (kilobytes)
    HBUF_KBYTES     : integer;  -- High-priority output buffer (kilobytes)
    OBUF_KBYTES     : integer;  -- Output buffer size (kilobytes)
    PTP_MIXED_STEP  : boolean;  -- Support PTP format conversion?
    MAC_TABLE_EDIT  : boolean;  -- Manual read/write of MAC table?
    MAC_TABLE_SIZE  : integer); -- Max stored MAC addresses
    port (
    -- Up to 32 network ports, enabled/hidden based on PORT_COUNT.
    p00_rx_clk      : in  std_logic;
    p00_rx_data     : in  std_logic_vector(7 downto 0);
    p00_rx_last     : in  std_logic;
    p00_rx_write    : in  std_logic;
    p00_rx_error    : in  std_logic;
    p00_rx_rate     : in  std_logic_vector(15 downto 0);
    p00_rx_status   : in  std_logic_vector(7 downto 0);
    p00_rx_tsof     : in  std_logic_vector(47 downto 0);
    p00_rx_reset    : in  std_logic;
    p00_tx_clk      : in  std_logic;
    p00_tx_data     : out std_logic_vector(7 downto 0);
    p00_tx_last     : out std_logic;
    p00_tx_valid    : out std_logic;
    p00_tx_ready    : in  std_logic;
    p00_tx_error    : in  std_logic;
    p00_tx_pstart   : in  std_logic;
    p00_tx_tnow     : in  std_logic_vector(47 downto 0);
    p00_tx_reset    : in  std_logic;

    p01_rx_clk      : in  std_logic;
    p01_rx_data     : in  std_logic_vector(7 downto 0);
    p01_rx_last     : in  std_logic;
    p01_rx_write    : in  std_logic;
    p01_rx_error    : in  std_logic;
    p01_rx_rate     : in  std_logic_vector(15 downto 0);
    p01_rx_status   : in  std_logic_vector(7 downto 0);
    p01_rx_tsof     : in  std_logic_vector(47 downto 0);
    p01_rx_reset    : in  std_logic;
    p01_tx_clk      : in  std_logic;
    p01_tx_data     : out std_logic_vector(7 downto 0);
    p01_tx_last     : out std_logic;
    p01_tx_valid    : out std_logic;
    p01_tx_ready    : in  std_logic;
    p01_tx_error    : in  std_logic;
    p01_tx_pstart   : in  std_logic;
    p01_tx_tnow     : in  std_logic_vector(47 downto 0);
    p01_tx_reset    : in  std_logic;

    p02_rx_clk      : in  std_logic;
    p02_rx_data     : in  std_logic_vector(7 downto 0);
    p02_rx_last     : in  std_logic;
    p02_rx_write    : in  std_logic;
    p02_rx_error    : in  std_logic;
    p02_rx_rate     : in  std_logic_vector(15 downto 0);
    p02_rx_status   : in  std_logic_vector(7 downto 0);
    p02_rx_tsof     : in  std_logic_vector(47 downto 0);
    p02_rx_reset    : in  std_logic;
    p02_tx_clk      : in  std_logic;
    p02_tx_data     : out std_logic_vector(7 downto 0);
    p02_tx_last     : out std_logic;
    p02_tx_valid    : out std_logic;
    p02_tx_ready    : in  std_logic;
    p02_tx_error    : in  std_logic;
    p02_tx_pstart   : in  std_logic;
    p02_tx_tnow     : in  std_logic_vector(47 downto 0);
    p02_tx_reset    : in  std_logic;

    p03_rx_clk      : in  std_logic;
    p03_rx_data     : in  std_logic_vector(7 downto 0);
    p03_rx_last     : in  std_logic;
    p03_rx_write    : in  std_logic;
    p03_rx_error    : in  std_logic;
    p03_rx_rate     : in  std_logic_vector(15 downto 0);
    p03_rx_status   : in  std_logic_vector(7 downto 0);
    p03_rx_tsof     : in  std_logic_vector(47 downto 0);
    p03_rx_reset    : in  std_logic;
    p03_tx_clk      : in  std_logic;
    p03_tx_data     : out std_logic_vector(7 downto 0);
    p03_tx_last     : out std_logic;
    p03_tx_valid    : out std_logic;
    p03_tx_ready    : in  std_logic;
    p03_tx_error    : in  std_logic;
    p03_tx_pstart   : in  std_logic;
    p03_tx_tnow     : in  std_logic_vector(47 downto 0);
    p03_tx_reset    : in  std_logic;

    p04_rx_clk      : in  std_logic;
    p04_rx_data     : in  std_logic_vector(7 downto 0);
    p04_rx_last     : in  std_logic;
    p04_rx_write    : in  std_logic;
    p04_rx_error    : in  std_logic;
    p04_rx_rate     : in  std_logic_vector(15 downto 0);
    p04_rx_status   : in  std_logic_vector(7 downto 0);
    p04_rx_tsof     : in  std_logic_vector(47 downto 0);
    p04_rx_reset    : in  std_logic;
    p04_tx_clk      : in  std_logic;
    p04_tx_data     : out std_logic_vector(7 downto 0);
    p04_tx_last     : out std_logic;
    p04_tx_valid    : out std_logic;
    p04_tx_ready    : in  std_logic;
    p04_tx_error    : in  std_logic;
    p04_tx_pstart   : in  std_logic;
    p04_tx_tnow     : in  std_logic_vector(47 downto 0);
    p04_tx_reset    : in  std_logic;

    p05_rx_clk      : in  std_logic;
    p05_rx_data     : in  std_logic_vector(7 downto 0);
    p05_rx_last     : in  std_logic;
    p05_rx_write    : in  std_logic;
    p05_rx_error    : in  std_logic;
    p05_rx_rate     : in  std_logic_vector(15 downto 0);
    p05_rx_status   : in  std_logic_vector(7 downto 0);
    p05_rx_tsof     : in  std_logic_vector(47 downto 0);
    p05_rx_reset    : in  std_logic;
    p05_tx_clk      : in  std_logic;
    p05_tx_data     : out std_logic_vector(7 downto 0);
    p05_tx_last     : out std_logic;
    p05_tx_valid    : out std_logic;
    p05_tx_ready    : in  std_logic;
    p05_tx_error    : in  std_logic;
    p05_tx_pstart   : in  std_logic;
    p05_tx_tnow     : in  std_logic_vector(47 downto 0);
    p05_tx_reset    : in  std_logic;

    p06_rx_clk      : in  std_logic;
    p06_rx_data     : in  std_logic_vector(7 downto 0);
    p06_rx_last     : in  std_logic;
    p06_rx_write    : in  std_logic;
    p06_rx_error    : in  std_logic;
    p06_rx_rate     : in  std_logic_vector(15 downto 0);
    p06_rx_status   : in  std_logic_vector(7 downto 0);
    p06_rx_tsof     : in  std_logic_vector(47 downto 0);
    p06_rx_reset    : in  std_logic;
    p06_tx_clk      : in  std_logic;
    p06_tx_data     : out std_logic_vector(7 downto 0);
    p06_tx_last     : out std_logic;
    p06_tx_valid    : out std_logic;
    p06_tx_ready    : in  std_logic;
    p06_tx_error    : in  std_logic;
    p06_tx_pstart   : in  std_logic;
    p06_tx_tnow     : in  std_logic_vector(47 downto 0);
    p06_tx_reset    : in  std_logic;

    p07_rx_clk      : in  std_logic;
    p07_rx_data     : in  std_logic_vector(7 downto 0);
    p07_rx_last     : in  std_logic;
    p07_rx_write    : in  std_logic;
    p07_rx_error    : in  std_logic;
    p07_rx_rate     : in  std_logic_vector(15 downto 0);
    p07_rx_status   : in  std_logic_vector(7 downto 0);
    p07_rx_tsof     : in  std_logic_vector(47 downto 0);
    p07_rx_reset    : in  std_logic;
    p07_tx_clk      : in  std_logic;
    p07_tx_data     : out std_logic_vector(7 downto 0);
    p07_tx_last     : out std_logic;
    p07_tx_valid    : out std_logic;
    p07_tx_ready    : in  std_logic;
    p07_tx_error    : in  std_logic;
    p07_tx_pstart   : in  std_logic;
    p07_tx_tnow     : in  std_logic_vector(47 downto 0);
    p07_tx_reset    : in  std_logic;

    p08_rx_clk      : in  std_logic;
    p08_rx_data     : in  std_logic_vector(7 downto 0);
    p08_rx_last     : in  std_logic;
    p08_rx_write    : in  std_logic;
    p08_rx_error    : in  std_logic;
    p08_rx_rate     : in  std_logic_vector(15 downto 0);
    p08_rx_status   : in  std_logic_vector(7 downto 0);
    p08_rx_tsof     : in  std_logic_vector(47 downto 0);
    p08_rx_reset    : in  std_logic;
    p08_tx_clk      : in  std_logic;
    p08_tx_data     : out std_logic_vector(7 downto 0);
    p08_tx_last     : out std_logic;
    p08_tx_valid    : out std_logic;
    p08_tx_ready    : in  std_logic;
    p08_tx_error    : in  std_logic;
    p08_tx_pstart   : in  std_logic;
    p08_tx_tnow     : in  std_logic_vector(47 downto 0);
    p08_tx_reset    : in  std_logic;

    p09_rx_clk      : in  std_logic;
    p09_rx_data     : in  std_logic_vector(7 downto 0);
    p09_rx_last     : in  std_logic;
    p09_rx_write    : in  std_logic;
    p09_rx_error    : in  std_logic;
    p09_rx_rate     : in  std_logic_vector(15 downto 0);
    p09_rx_status   : in  std_logic_vector(7 downto 0);
    p09_rx_tsof     : in  std_logic_vector(47 downto 0);
    p09_rx_reset    : in  std_logic;
    p09_tx_clk      : in  std_logic;
    p09_tx_data     : out std_logic_vector(7 downto 0);
    p09_tx_last     : out std_logic;
    p09_tx_valid    : out std_logic;
    p09_tx_ready    : in  std_logic;
    p09_tx_error    : in  std_logic;
    p09_tx_pstart   : in  std_logic;
    p09_tx_tnow     : in  std_logic_vector(47 downto 0);
    p09_tx_reset    : in  std_logic;

    p10_rx_clk      : in  std_logic;
    p10_rx_data     : in  std_logic_vector(7 downto 0);
    p10_rx_last     : in  std_logic;
    p10_rx_write    : in  std_logic;
    p10_rx_error    : in  std_logic;
    p10_rx_rate     : in  std_logic_vector(15 downto 0);
    p10_rx_status   : in  std_logic_vector(7 downto 0);
    p10_rx_tsof     : in  std_logic_vector(47 downto 0);
    p10_rx_reset    : in  std_logic;
    p10_tx_clk      : in  std_logic;
    p10_tx_data     : out std_logic_vector(7 downto 0);
    p10_tx_last     : out std_logic;
    p10_tx_valid    : out std_logic;
    p10_tx_ready    : in  std_logic;
    p10_tx_error    : in  std_logic;
    p10_tx_pstart   : in  std_logic;
    p10_tx_tnow     : in  std_logic_vector(47 downto 0);
    p10_tx_reset    : in  std_logic;

    p11_rx_clk      : in  std_logic;
    p11_rx_data     : in  std_logic_vector(7 downto 0);
    p11_rx_last     : in  std_logic;
    p11_rx_write    : in  std_logic;
    p11_rx_error    : in  std_logic;
    p11_rx_rate     : in  std_logic_vector(15 downto 0);
    p11_rx_status   : in  std_logic_vector(7 downto 0);
    p11_rx_tsof     : in  std_logic_vector(47 downto 0);
    p11_rx_reset    : in  std_logic;
    p11_tx_clk      : in  std_logic;
    p11_tx_data     : out std_logic_vector(7 downto 0);
    p11_tx_last     : out std_logic;
    p11_tx_valid    : out std_logic;
    p11_tx_ready    : in  std_logic;
    p11_tx_error    : in  std_logic;
    p11_tx_pstart   : in  std_logic;
    p11_tx_tnow     : in  std_logic_vector(47 downto 0);
    p11_tx_reset    : in  std_logic;

    p12_rx_clk      : in  std_logic;
    p12_rx_data     : in  std_logic_vector(7 downto 0);
    p12_rx_last     : in  std_logic;
    p12_rx_write    : in  std_logic;
    p12_rx_error    : in  std_logic;
    p12_rx_rate     : in  std_logic_vector(15 downto 0);
    p12_rx_status   : in  std_logic_vector(7 downto 0);
    p12_rx_tsof     : in  std_logic_vector(47 downto 0);
    p12_rx_reset    : in  std_logic;
    p12_tx_clk      : in  std_logic;
    p12_tx_data     : out std_logic_vector(7 downto 0);
    p12_tx_last     : out std_logic;
    p12_tx_valid    : out std_logic;
    p12_tx_ready    : in  std_logic;
    p12_tx_error    : in  std_logic;
    p12_tx_pstart   : in  std_logic;
    p12_tx_tnow     : in  std_logic_vector(47 downto 0);
    p12_tx_reset    : in  std_logic;

    p13_rx_clk      : in  std_logic;
    p13_rx_data     : in  std_logic_vector(7 downto 0);
    p13_rx_last     : in  std_logic;
    p13_rx_write    : in  std_logic;
    p13_rx_error    : in  std_logic;
    p13_rx_rate     : in  std_logic_vector(15 downto 0);
    p13_rx_status   : in  std_logic_vector(7 downto 0);
    p13_rx_tsof     : in  std_logic_vector(47 downto 0);
    p13_rx_reset    : in  std_logic;
    p13_tx_clk      : in  std_logic;
    p13_tx_data     : out std_logic_vector(7 downto 0);
    p13_tx_last     : out std_logic;
    p13_tx_valid    : out std_logic;
    p13_tx_ready    : in  std_logic;
    p13_tx_error    : in  std_logic;
    p13_tx_pstart   : in  std_logic;
    p13_tx_tnow     : in  std_logic_vector(47 downto 0);
    p13_tx_reset    : in  std_logic;

    p14_rx_clk      : in  std_logic;
    p14_rx_data     : in  std_logic_vector(7 downto 0);
    p14_rx_last     : in  std_logic;
    p14_rx_write    : in  std_logic;
    p14_rx_error    : in  std_logic;
    p14_rx_rate     : in  std_logic_vector(15 downto 0);
    p14_rx_status   : in  std_logic_vector(7 downto 0);
    p14_rx_tsof     : in  std_logic_vector(47 downto 0);
    p14_rx_reset    : in  std_logic;
    p14_tx_clk      : in  std_logic;
    p14_tx_data     : out std_logic_vector(7 downto 0);
    p14_tx_last     : out std_logic;
    p14_tx_valid    : out std_logic;
    p14_tx_ready    : in  std_logic;
    p14_tx_error    : in  std_logic;
    p14_tx_pstart   : in  std_logic;
    p14_tx_tnow     : in  std_logic_vector(47 downto 0);
    p14_tx_reset    : in  std_logic;

    p15_rx_clk      : in  std_logic;
    p15_rx_data     : in  std_logic_vector(7 downto 0);
    p15_rx_last     : in  std_logic;
    p15_rx_write    : in  std_logic;
    p15_rx_error    : in  std_logic;
    p15_rx_rate     : in  std_logic_vector(15 downto 0);
    p15_rx_status   : in  std_logic_vector(7 downto 0);
    p15_rx_tsof     : in  std_logic_vector(47 downto 0);
    p15_rx_reset    : in  std_logic;
    p15_tx_clk      : in  std_logic;
    p15_tx_data     : out std_logic_vector(7 downto 0);
    p15_tx_last     : out std_logic;
    p15_tx_valid    : out std_logic;
    p15_tx_ready    : in  std_logic;
    p15_tx_error    : in  std_logic;
    p15_tx_pstart   : in  std_logic;
    p15_tx_tnow     : in  std_logic_vector(47 downto 0);
    p15_tx_reset    : in  std_logic;

    p16_rx_clk      : in  std_logic;
    p16_rx_data     : in  std_logic_vector(7 downto 0);
    p16_rx_last     : in  std_logic;
    p16_rx_write    : in  std_logic;
    p16_rx_error    : in  std_logic;
    p16_rx_rate     : in  std_logic_vector(15 downto 0);
    p16_rx_status   : in  std_logic_vector(7 downto 0);
    p16_rx_tsof     : in  std_logic_vector(47 downto 0);
    p16_rx_reset    : in  std_logic;
    p16_tx_clk      : in  std_logic;
    p16_tx_data     : out std_logic_vector(7 downto 0);
    p16_tx_last     : out std_logic;
    p16_tx_valid    : out std_logic;
    p16_tx_ready    : in  std_logic;
    p16_tx_error    : in  std_logic;
    p16_tx_pstart   : in  std_logic;
    p16_tx_tnow     : in  std_logic_vector(47 downto 0);
    p16_tx_reset    : in  std_logic;

    p17_rx_clk      : in  std_logic;
    p17_rx_data     : in  std_logic_vector(7 downto 0);
    p17_rx_last     : in  std_logic;
    p17_rx_write    : in  std_logic;
    p17_rx_error    : in  std_logic;
    p17_rx_rate     : in  std_logic_vector(15 downto 0);
    p17_rx_status   : in  std_logic_vector(7 downto 0);
    p17_rx_tsof     : in  std_logic_vector(47 downto 0);
    p17_rx_reset    : in  std_logic;
    p17_tx_clk      : in  std_logic;
    p17_tx_data     : out std_logic_vector(7 downto 0);
    p17_tx_last     : out std_logic;
    p17_tx_valid    : out std_logic;
    p17_tx_ready    : in  std_logic;
    p17_tx_error    : in  std_logic;
    p17_tx_pstart   : in  std_logic;
    p17_tx_tnow     : in  std_logic_vector(47 downto 0);
    p17_tx_reset    : in  std_logic;

    p18_rx_clk      : in  std_logic;
    p18_rx_data     : in  std_logic_vector(7 downto 0);
    p18_rx_last     : in  std_logic;
    p18_rx_write    : in  std_logic;
    p18_rx_error    : in  std_logic;
    p18_rx_rate     : in  std_logic_vector(15 downto 0);
    p18_rx_status   : in  std_logic_vector(7 downto 0);
    p18_rx_tsof     : in  std_logic_vector(47 downto 0);
    p18_rx_reset    : in  std_logic;
    p18_tx_clk      : in  std_logic;
    p18_tx_data     : out std_logic_vector(7 downto 0);
    p18_tx_last     : out std_logic;
    p18_tx_valid    : out std_logic;
    p18_tx_ready    : in  std_logic;
    p18_tx_error    : in  std_logic;
    p18_tx_pstart   : in  std_logic;
    p18_tx_tnow     : in  std_logic_vector(47 downto 0);
    p18_tx_reset    : in  std_logic;

    p19_rx_clk      : in  std_logic;
    p19_rx_data     : in  std_logic_vector(7 downto 0);
    p19_rx_last     : in  std_logic;
    p19_rx_write    : in  std_logic;
    p19_rx_error    : in  std_logic;
    p19_rx_rate     : in  std_logic_vector(15 downto 0);
    p19_rx_status   : in  std_logic_vector(7 downto 0);
    p19_rx_tsof     : in  std_logic_vector(47 downto 0);
    p19_rx_reset    : in  std_logic;
    p19_tx_clk      : in  std_logic;
    p19_tx_data     : out std_logic_vector(7 downto 0);
    p19_tx_last     : out std_logic;
    p19_tx_valid    : out std_logic;
    p19_tx_ready    : in  std_logic;
    p19_tx_error    : in  std_logic;
    p19_tx_pstart   : in  std_logic;
    p19_tx_tnow     : in  std_logic_vector(47 downto 0);
    p19_tx_reset    : in  std_logic;

    p20_rx_clk      : in  std_logic;
    p20_rx_data     : in  std_logic_vector(7 downto 0);
    p20_rx_last     : in  std_logic;
    p20_rx_write    : in  std_logic;
    p20_rx_error    : in  std_logic;
    p20_rx_rate     : in  std_logic_vector(15 downto 0);
    p20_rx_status   : in  std_logic_vector(7 downto 0);
    p20_rx_tsof     : in  std_logic_vector(47 downto 0);
    p20_rx_reset    : in  std_logic;
    p20_tx_clk      : in  std_logic;
    p20_tx_data     : out std_logic_vector(7 downto 0);
    p20_tx_last     : out std_logic;
    p20_tx_valid    : out std_logic;
    p20_tx_ready    : in  std_logic;
    p20_tx_error    : in  std_logic;
    p20_tx_pstart   : in  std_logic;
    p20_tx_tnow     : in  std_logic_vector(47 downto 0);
    p20_tx_reset    : in  std_logic;

    p21_rx_clk      : in  std_logic;
    p21_rx_data     : in  std_logic_vector(7 downto 0);
    p21_rx_last     : in  std_logic;
    p21_rx_write    : in  std_logic;
    p21_rx_error    : in  std_logic;
    p21_rx_rate     : in  std_logic_vector(15 downto 0);
    p21_rx_status   : in  std_logic_vector(7 downto 0);
    p21_rx_tsof     : in  std_logic_vector(47 downto 0);
    p21_rx_reset    : in  std_logic;
    p21_tx_clk      : in  std_logic;
    p21_tx_data     : out std_logic_vector(7 downto 0);
    p21_tx_last     : out std_logic;
    p21_tx_valid    : out std_logic;
    p21_tx_ready    : in  std_logic;
    p21_tx_error    : in  std_logic;
    p21_tx_pstart   : in  std_logic;
    p21_tx_tnow     : in  std_logic_vector(47 downto 0);
    p21_tx_reset    : in  std_logic;

    p22_rx_clk      : in  std_logic;
    p22_rx_data     : in  std_logic_vector(7 downto 0);
    p22_rx_last     : in  std_logic;
    p22_rx_write    : in  std_logic;
    p22_rx_error    : in  std_logic;
    p22_rx_rate     : in  std_logic_vector(15 downto 0);
    p22_rx_status   : in  std_logic_vector(7 downto 0);
    p22_rx_tsof     : in  std_logic_vector(47 downto 0);
    p22_rx_reset    : in  std_logic;
    p22_tx_clk      : in  std_logic;
    p22_tx_data     : out std_logic_vector(7 downto 0);
    p22_tx_last     : out std_logic;
    p22_tx_valid    : out std_logic;
    p22_tx_ready    : in  std_logic;
    p22_tx_error    : in  std_logic;
    p22_tx_pstart   : in  std_logic;
    p22_tx_tnow     : in  std_logic_vector(47 downto 0);
    p22_tx_reset    : in  std_logic;

    p23_rx_clk      : in  std_logic;
    p23_rx_data     : in  std_logic_vector(7 downto 0);
    p23_rx_last     : in  std_logic;
    p23_rx_write    : in  std_logic;
    p23_rx_error    : in  std_logic;
    p23_rx_rate     : in  std_logic_vector(15 downto 0);
    p23_rx_status   : in  std_logic_vector(7 downto 0);
    p23_rx_tsof     : in  std_logic_vector(47 downto 0);
    p23_rx_reset    : in  std_logic;
    p23_tx_clk      : in  std_logic;
    p23_tx_data     : out std_logic_vector(7 downto 0);
    p23_tx_last     : out std_logic;
    p23_tx_valid    : out std_logic;
    p23_tx_ready    : in  std_logic;
    p23_tx_error    : in  std_logic;
    p23_tx_pstart   : in  std_logic;
    p23_tx_tnow     : in  std_logic_vector(47 downto 0);
    p23_tx_reset    : in  std_logic;

    p24_rx_clk      : in  std_logic;
    p24_rx_data     : in  std_logic_vector(7 downto 0);
    p24_rx_last     : in  std_logic;
    p24_rx_write    : in  std_logic;
    p24_rx_error    : in  std_logic;
    p24_rx_rate     : in  std_logic_vector(15 downto 0);
    p24_rx_status   : in  std_logic_vector(7 downto 0);
    p24_rx_tsof     : in  std_logic_vector(47 downto 0);
    p24_rx_reset    : in  std_logic;
    p24_tx_clk      : in  std_logic;
    p24_tx_data     : out std_logic_vector(7 downto 0);
    p24_tx_last     : out std_logic;
    p24_tx_valid    : out std_logic;
    p24_tx_ready    : in  std_logic;
    p24_tx_error    : in  std_logic;
    p24_tx_pstart   : in  std_logic;
    p24_tx_tnow     : in  std_logic_vector(47 downto 0);
    p24_tx_reset    : in  std_logic;

    p25_rx_clk      : in  std_logic;
    p25_rx_data     : in  std_logic_vector(7 downto 0);
    p25_rx_last     : in  std_logic;
    p25_rx_write    : in  std_logic;
    p25_rx_error    : in  std_logic;
    p25_rx_rate     : in  std_logic_vector(15 downto 0);
    p25_rx_status   : in  std_logic_vector(7 downto 0);
    p25_rx_tsof     : in  std_logic_vector(47 downto 0);
    p25_rx_reset    : in  std_logic;
    p25_tx_clk      : in  std_logic;
    p25_tx_data     : out std_logic_vector(7 downto 0);
    p25_tx_last     : out std_logic;
    p25_tx_valid    : out std_logic;
    p25_tx_ready    : in  std_logic;
    p25_tx_error    : in  std_logic;
    p25_tx_pstart   : in  std_logic;
    p25_tx_tnow     : in  std_logic_vector(47 downto 0);
    p25_tx_reset    : in  std_logic;

    p26_rx_clk      : in  std_logic;
    p26_rx_data     : in  std_logic_vector(7 downto 0);
    p26_rx_last     : in  std_logic;
    p26_rx_write    : in  std_logic;
    p26_rx_error    : in  std_logic;
    p26_rx_rate     : in  std_logic_vector(15 downto 0);
    p26_rx_status   : in  std_logic_vector(7 downto 0);
    p26_rx_tsof     : in  std_logic_vector(47 downto 0);
    p26_rx_reset    : in  std_logic;
    p26_tx_clk      : in  std_logic;
    p26_tx_data     : out std_logic_vector(7 downto 0);
    p26_tx_last     : out std_logic;
    p26_tx_valid    : out std_logic;
    p26_tx_ready    : in  std_logic;
    p26_tx_error    : in  std_logic;
    p26_tx_pstart   : in  std_logic;
    p26_tx_tnow     : in  std_logic_vector(47 downto 0);
    p26_tx_reset    : in  std_logic;

    p27_rx_clk      : in  std_logic;
    p27_rx_data     : in  std_logic_vector(7 downto 0);
    p27_rx_last     : in  std_logic;
    p27_rx_write    : in  std_logic;
    p27_rx_error    : in  std_logic;
    p27_rx_rate     : in  std_logic_vector(15 downto 0);
    p27_rx_status   : in  std_logic_vector(7 downto 0);
    p27_rx_tsof     : in  std_logic_vector(47 downto 0);
    p27_rx_reset    : in  std_logic;
    p27_tx_clk      : in  std_logic;
    p27_tx_data     : out std_logic_vector(7 downto 0);
    p27_tx_last     : out std_logic;
    p27_tx_valid    : out std_logic;
    p27_tx_ready    : in  std_logic;
    p27_tx_error    : in  std_logic;
    p27_tx_pstart   : in  std_logic;
    p27_tx_tnow     : in  std_logic_vector(47 downto 0);
    p27_tx_reset    : in  std_logic;

    p28_rx_clk      : in  std_logic;
    p28_rx_data     : in  std_logic_vector(7 downto 0);
    p28_rx_last     : in  std_logic;
    p28_rx_write    : in  std_logic;
    p28_rx_error    : in  std_logic;
    p28_rx_rate     : in  std_logic_vector(15 downto 0);
    p28_rx_status   : in  std_logic_vector(7 downto 0);
    p28_rx_tsof     : in  std_logic_vector(47 downto 0);
    p28_rx_reset    : in  std_logic;
    p28_tx_clk      : in  std_logic;
    p28_tx_data     : out std_logic_vector(7 downto 0);
    p28_tx_last     : out std_logic;
    p28_tx_valid    : out std_logic;
    p28_tx_ready    : in  std_logic;
    p28_tx_error    : in  std_logic;
    p28_tx_pstart   : in  std_logic;
    p28_tx_tnow     : in  std_logic_vector(47 downto 0);
    p28_tx_reset    : in  std_logic;

    p29_rx_clk      : in  std_logic;
    p29_rx_data     : in  std_logic_vector(7 downto 0);
    p29_rx_last     : in  std_logic;
    p29_rx_write    : in  std_logic;
    p29_rx_error    : in  std_logic;
    p29_rx_rate     : in  std_logic_vector(15 downto 0);
    p29_rx_status   : in  std_logic_vector(7 downto 0);
    p29_rx_tsof     : in  std_logic_vector(47 downto 0);
    p29_rx_reset    : in  std_logic;
    p29_tx_clk      : in  std_logic;
    p29_tx_data     : out std_logic_vector(7 downto 0);
    p29_tx_last     : out std_logic;
    p29_tx_valid    : out std_logic;
    p29_tx_ready    : in  std_logic;
    p29_tx_error    : in  std_logic;
    p29_tx_pstart   : in  std_logic;
    p29_tx_tnow     : in  std_logic_vector(47 downto 0);
    p29_tx_reset    : in  std_logic;

    p30_rx_clk      : in  std_logic;
    p30_rx_data     : in  std_logic_vector(7 downto 0);
    p30_rx_last     : in  std_logic;
    p30_rx_write    : in  std_logic;
    p30_rx_error    : in  std_logic;
    p30_rx_rate     : in  std_logic_vector(15 downto 0);
    p30_rx_status   : in  std_logic_vector(7 downto 0);
    p30_rx_tsof     : in  std_logic_vector(47 downto 0);
    p30_rx_reset    : in  std_logic;
    p30_tx_clk      : in  std_logic;
    p30_tx_data     : out std_logic_vector(7 downto 0);
    p30_tx_last     : out std_logic;
    p30_tx_valid    : out std_logic;
    p30_tx_ready    : in  std_logic;
    p30_tx_error    : in  std_logic;
    p30_tx_pstart   : in  std_logic;
    p30_tx_tnow     : in  std_logic_vector(47 downto 0);
    p30_tx_reset    : in  std_logic;

    p31_rx_clk      : in  std_logic;
    p31_rx_data     : in  std_logic_vector(7 downto 0);
    p31_rx_last     : in  std_logic;
    p31_rx_write    : in  std_logic;
    p31_rx_error    : in  std_logic;
    p31_rx_rate     : in  std_logic_vector(15 downto 0);
    p31_rx_status   : in  std_logic_vector(7 downto 0);
    p31_rx_tsof     : in  std_logic_vector(47 downto 0);
    p31_rx_reset    : in  std_logic;
    p31_tx_clk      : in  std_logic;
    p31_tx_data     : out std_logic_vector(7 downto 0);
    p31_tx_last     : out std_logic;
    p31_tx_valid    : out std_logic;
    p31_tx_ready    : in  std_logic;
    p31_tx_error    : in  std_logic;
    p31_tx_pstart   : in  std_logic;
    p31_tx_tnow     : in  std_logic_vector(47 downto 0);
    p31_tx_reset    : in  std_logic;

    -- Up to 8 high-speed network ports, enabled/hidden based on PORTX_COUNT.
    x00_rx_clk      : in  std_logic;
    x00_rx_data     : in  std_logic_vector(63 downto 0);
    x00_rx_nlast    : in  std_logic_vector(3 downto 0);
    x00_rx_write    : in  std_logic;
    x00_rx_error    : in  std_logic;
    x00_rx_rate     : in  std_logic_vector(15 downto 0);
    x00_rx_status   : in  std_logic_vector(7 downto 0);
    x00_rx_tsof     : in  std_logic_vector(47 downto 0);
    x00_rx_reset    : in  std_logic;
    x00_tx_clk      : in  std_logic;
    x00_tx_data     : out std_logic_vector(63 downto 0);
    x00_tx_nlast    : out std_logic_vector(3 downto 0);
    x00_tx_valid    : out std_logic;
    x00_tx_ready    : in  std_logic;
    x00_tx_error    : in  std_logic;
    x00_tx_pstart   : in  std_logic;
    x00_tx_tnow     : in  std_logic_vector(47 downto 0);
    x00_tx_reset    : in  std_logic;

    x01_rx_clk      : in  std_logic;
    x01_rx_data     : in  std_logic_vector(63 downto 0);
    x01_rx_nlast    : in  std_logic_vector(3 downto 0);
    x01_rx_write    : in  std_logic;
    x01_rx_error    : in  std_logic;
    x01_rx_rate     : in  std_logic_vector(15 downto 0);
    x01_rx_status   : in  std_logic_vector(7 downto 0);
    x01_rx_tsof     : in  std_logic_vector(47 downto 0);
    x01_rx_reset    : in  std_logic;
    x01_tx_clk      : in  std_logic;
    x01_tx_data     : out std_logic_vector(63 downto 0);
    x01_tx_nlast    : out std_logic_vector(3 downto 0);
    x01_tx_valid    : out std_logic;
    x01_tx_ready    : in  std_logic;
    x01_tx_error    : in  std_logic;
    x01_tx_pstart   : in  std_logic;
    x01_tx_tnow     : in  std_logic_vector(47 downto 0);
    x01_tx_reset    : in  std_logic;

    x02_rx_clk      : in  std_logic;
    x02_rx_data     : in  std_logic_vector(63 downto 0);
    x02_rx_nlast    : in  std_logic_vector(3 downto 0);
    x02_rx_write    : in  std_logic;
    x02_rx_error    : in  std_logic;
    x02_rx_rate     : in  std_logic_vector(15 downto 0);
    x02_rx_status   : in  std_logic_vector(7 downto 0);
    x02_rx_tsof     : in  std_logic_vector(47 downto 0);
    x02_rx_reset    : in  std_logic;
    x02_tx_clk      : in  std_logic;
    x02_tx_data     : out std_logic_vector(63 downto 0);
    x02_tx_nlast    : out std_logic_vector(3 downto 0);
    x02_tx_valid    : out std_logic;
    x02_tx_ready    : in  std_logic;
    x02_tx_error    : in  std_logic;
    x02_tx_pstart   : in  std_logic;
    x02_tx_tnow     : in  std_logic_vector(47 downto 0);
    x02_tx_reset    : in  std_logic;

    x03_rx_clk      : in  std_logic;
    x03_rx_data     : in  std_logic_vector(63 downto 0);
    x03_rx_nlast    : in  std_logic_vector(3 downto 0);
    x03_rx_write    : in  std_logic;
    x03_rx_error    : in  std_logic;
    x03_rx_rate     : in  std_logic_vector(15 downto 0);
    x03_rx_status   : in  std_logic_vector(7 downto 0);
    x03_rx_tsof     : in  std_logic_vector(47 downto 0);
    x03_rx_reset    : in  std_logic;
    x03_tx_clk      : in  std_logic;
    x03_tx_data     : out std_logic_vector(63 downto 0);
    x03_tx_nlast    : out std_logic_vector(3 downto 0);
    x03_tx_valid    : out std_logic;
    x03_tx_ready    : in  std_logic;
    x03_tx_error    : in  std_logic;
    x03_tx_pstart   : in  std_logic;
    x03_tx_tnow     : in  std_logic_vector(47 downto 0);
    x03_tx_reset    : in  std_logic;

    x04_rx_clk      : in  std_logic;
    x04_rx_data     : in  std_logic_vector(63 downto 0);
    x04_rx_nlast    : in  std_logic_vector(3 downto 0);
    x04_rx_write    : in  std_logic;
    x04_rx_error    : in  std_logic;
    x04_rx_rate     : in  std_logic_vector(15 downto 0);
    x04_rx_status   : in  std_logic_vector(7 downto 0);
    x04_rx_tsof     : in  std_logic_vector(47 downto 0);
    x04_rx_reset    : in  std_logic;
    x04_tx_clk      : in  std_logic;
    x04_tx_data     : out std_logic_vector(63 downto 0);
    x04_tx_nlast    : out std_logic_vector(3 downto 0);
    x04_tx_valid    : out std_logic;
    x04_tx_ready    : in  std_logic;
    x04_tx_error    : in  std_logic;
    x04_tx_pstart   : in  std_logic;
    x04_tx_tnow     : in  std_logic_vector(47 downto 0);
    x04_tx_reset    : in  std_logic;

    x05_rx_clk      : in  std_logic;
    x05_rx_data     : in  std_logic_vector(63 downto 0);
    x05_rx_nlast    : in  std_logic_vector(3 downto 0);
    x05_rx_write    : in  std_logic;
    x05_rx_error    : in  std_logic;
    x05_rx_rate     : in  std_logic_vector(15 downto 0);
    x05_rx_status   : in  std_logic_vector(7 downto 0);
    x05_rx_tsof     : in  std_logic_vector(47 downto 0);
    x05_rx_reset    : in  std_logic;
    x05_tx_clk      : in  std_logic;
    x05_tx_data     : out std_logic_vector(63 downto 0);
    x05_tx_nlast    : out std_logic_vector(3 downto 0);
    x05_tx_valid    : out std_logic;
    x05_tx_ready    : in  std_logic;
    x05_tx_error    : in  std_logic;
    x05_tx_pstart   : in  std_logic;
    x05_tx_tnow     : in  std_logic_vector(47 downto 0);
    x05_tx_reset    : in  std_logic;

    x06_rx_clk      : in  std_logic;
    x06_rx_data     : in  std_logic_vector(63 downto 0);
    x06_rx_nlast    : in  std_logic_vector(3 downto 0);
    x06_rx_write    : in  std_logic;
    x06_rx_error    : in  std_logic;
    x06_rx_rate     : in  std_logic_vector(15 downto 0);
    x06_rx_status   : in  std_logic_vector(7 downto 0);
    x06_rx_tsof     : in  std_logic_vector(47 downto 0);
    x06_rx_reset    : in  std_logic;
    x06_tx_clk      : in  std_logic;
    x06_tx_data     : out std_logic_vector(63 downto 0);
    x06_tx_nlast    : out std_logic_vector(3 downto 0);
    x06_tx_valid    : out std_logic;
    x06_tx_ready    : in  std_logic;
    x06_tx_error    : in  std_logic;
    x06_tx_pstart   : in  std_logic;
    x06_tx_tnow     : in  std_logic_vector(47 downto 0);
    x06_tx_reset    : in  std_logic;

    x07_rx_clk      : in  std_logic;
    x07_rx_data     : in  std_logic_vector(63 downto 0);
    x07_rx_nlast    : in  std_logic_vector(3 downto 0);
    x07_rx_write    : in  std_logic;
    x07_rx_error    : in  std_logic;
    x07_rx_rate     : in  std_logic_vector(15 downto 0);
    x07_rx_status   : in  std_logic_vector(7 downto 0);
    x07_rx_tsof     : in  std_logic_vector(47 downto 0);
    x07_rx_reset    : in  std_logic;
    x07_tx_clk      : in  std_logic;
    x07_tx_data     : out std_logic_vector(63 downto 0);
    x07_tx_nlast    : out std_logic_vector(3 downto 0);
    x07_tx_valid    : out std_logic;
    x07_tx_ready    : in  std_logic;
    x07_tx_error    : in  std_logic;
    x07_tx_pstart   : in  std_logic;
    x07_tx_tnow     : in  std_logic_vector(47 downto 0);
    x07_tx_reset    : in  std_logic;

    -- Error reporting (see switch_aux).
    errvec_t        : out std_logic_vector(7 downto 0);

    -- Statistics reporting (ConfigBus)
    cfg_clk         : in  std_logic;
    cfg_devaddr     : in  std_logic_vector(7 downto 0);
    cfg_regaddr     : in  std_logic_vector(9 downto 0);
    cfg_wdata       : in  std_logic_vector(31 downto 0);
    cfg_wstrb       : in  std_logic_vector(3 downto 0);
    cfg_wrcmd       : in  std_logic;
    cfg_rdcmd       : in  std_logic;
    cfg_reset_p     : in  std_logic;
    cfg_rdata       : out std_logic_vector(31 downto 0);
    cfg_rdack       : out std_logic;
    cfg_rderr       : out std_logic;
    cfg_irq         : out std_logic;

    -- System interface.
    scrub_req_t     : in  std_logic;    -- Request MAC-lookup scrub
    core_clk        : in  std_logic;    -- Core datapath clock
    reset_p         : in  std_logic);   -- Core async reset
end wrap_switch_core;

architecture wrap_switch_core of wrap_switch_core is

constant PORT_TOTAL : integer := PORT_COUNT + PORTX_COUNT;
signal rx_data      : array_rx_m2s(PORT_COUNT-1 downto 0);
signal tx_data      : array_tx_s2m(PORT_COUNT-1 downto 0);
signal tx_ctrl      : array_tx_m2s(PORT_COUNT-1 downto 0);
signal xrx_data     : array_rx_m2sx(PORTX_COUNT-1 downto 0);
signal xtx_data     : array_tx_s2mx(PORTX_COUNT-1 downto 0);
signal xtx_ctrl     : array_tx_m2sx(PORTX_COUNT-1 downto 0);
signal cfg_cmd      : cfgbus_cmd;
signal cfg_ack      : cfgbus_ack;
signal cfg_acks     : cfgbus_ack_array(0 to 1) := (others => cfgbus_idle);
signal err_ports    : array_port_error(PORT_TOTAL-1 downto 0);
signal err_switch   : switch_error_t;

begin

---------------------------------------------------------------------
-- Convert ConfigBus signals.
---------------------------------------------------------------------
cfg_cmd.clk     <= cfg_clk;
cfg_cmd.sysaddr <= 0;   -- Unused
cfg_cmd.devaddr <= u2i(cfg_devaddr);
cfg_cmd.regaddr <= u2i(cfg_regaddr);
cfg_cmd.wdata   <= cfg_wdata;
cfg_cmd.wstrb   <= cfg_wstrb;
cfg_cmd.wrcmd   <= cfg_wrcmd;
cfg_cmd.rdcmd   <= cfg_rdcmd;
cfg_cmd.reset_p <= cfg_reset_p;
cfg_ack         <= cfgbus_merge(cfg_acks);
cfg_rdata       <= cfg_ack.rdata;
cfg_rdack       <= cfg_ack.rdack;
cfg_rderr       <= cfg_ack.rderr;
cfg_irq         <= cfg_ack.irq;

---------------------------------------------------------------------
-- Convert standard port signals.
---------------------------------------------------------------------
gen_p00 : if (PORT_COUNT > 0) generate
    rx_data(0).clk      <= p00_rx_clk;
    rx_data(0).data     <= p00_rx_data;
    rx_data(0).last     <= p00_rx_last;
    rx_data(0).write    <= p00_rx_write;
    rx_data(0).rxerr    <= p00_rx_error;
    rx_data(0).rate     <= p00_rx_rate;
    rx_data(0).status   <= p00_rx_status;
    rx_data(0).tsof     <= unsigned(p00_rx_tsof);
    rx_data(0).reset_p  <= p00_rx_reset;
    tx_ctrl(0).clk      <= p00_tx_clk;
    tx_ctrl(0).ready    <= p00_tx_ready;
    tx_ctrl(0).pstart   <= p00_tx_pstart;
    tx_ctrl(0).tnow     <= unsigned(p00_tx_tnow);
    tx_ctrl(0).txerr    <= p00_tx_error;
    tx_ctrl(0).reset_p  <= p00_tx_reset;
    p00_tx_data         <= tx_data(0).data;
    p00_tx_last         <= tx_data(0).last;
    p00_tx_valid        <= tx_data(0).valid;
end generate;

gen_n00 : if (PORT_COUNT <= 0) generate
    p00_tx_data         <= (others => '0');
    p00_tx_last         <= '0';
    p00_tx_valid        <= '0';
end generate;

gen_p01 : if (PORT_COUNT > 1) generate
    rx_data(1).clk      <= p01_rx_clk;
    rx_data(1).data     <= p01_rx_data;
    rx_data(1).last     <= p01_rx_last;
    rx_data(1).write    <= p01_rx_write;
    rx_data(1).rxerr    <= p01_rx_error;
    rx_data(1).rate     <= p01_rx_rate;
    rx_data(1).status   <= p01_rx_status;
    rx_data(1).tsof     <= unsigned(p01_rx_tsof);
    rx_data(1).reset_p  <= p01_rx_reset;
    tx_ctrl(1).clk      <= p01_tx_clk;
    tx_ctrl(1).ready    <= p01_tx_ready;
    tx_ctrl(1).pstart   <= p01_tx_pstart;
    tx_ctrl(1).tnow     <= unsigned(p01_tx_tnow);
    tx_ctrl(1).txerr    <= p01_tx_error;
    tx_ctrl(1).reset_p  <= p01_tx_reset;
    p01_tx_data         <= tx_data(1).data;
    p01_tx_last         <= tx_data(1).last;
    p01_tx_valid        <= tx_data(1).valid;
end generate;

gen_n01 : if (PORT_COUNT <= 1) generate
    p01_tx_data         <= (others => '0');
    p01_tx_last         <= '0';
    p01_tx_valid        <= '0';
end generate;

gen_p02 : if (PORT_COUNT > 2) generate
    rx_data(2).clk      <= p02_rx_clk;
    rx_data(2).data     <= p02_rx_data;
    rx_data(2).last     <= p02_rx_last;
    rx_data(2).write    <= p02_rx_write;
    rx_data(2).rxerr    <= p02_rx_error;
    rx_data(2).rate     <= p02_rx_rate;
    rx_data(2).status   <= p02_rx_status;
    rx_data(2).tsof     <= unsigned(p02_rx_tsof);
    rx_data(2).reset_p  <= p02_rx_reset;
    tx_ctrl(2).clk      <= p02_tx_clk;
    tx_ctrl(2).ready    <= p02_tx_ready;
    tx_ctrl(2).pstart   <= p02_tx_pstart;
    tx_ctrl(2).tnow     <= unsigned(p02_tx_tnow);
    tx_ctrl(2).txerr    <= p02_tx_error;
    tx_ctrl(2).reset_p  <= p02_tx_reset;
    p02_tx_data         <= tx_data(2).data;
    p02_tx_last         <= tx_data(2).last;
    p02_tx_valid        <= tx_data(2).valid;
end generate;

gen_n02 : if (PORT_COUNT <= 2) generate
    p02_tx_data         <= (others => '0');
    p02_tx_last         <= '0';
    p02_tx_valid        <= '0';
end generate;

gen_p03 : if (PORT_COUNT > 3) generate
    rx_data(3).clk      <= p03_rx_clk;
    rx_data(3).data     <= p03_rx_data;
    rx_data(3).last     <= p03_rx_last;
    rx_data(3).write    <= p03_rx_write;
    rx_data(3).rxerr    <= p03_rx_error;
    rx_data(3).rate     <= p03_rx_rate;
    rx_data(3).status   <= p03_rx_status;
    rx_data(3).tsof     <= unsigned(p03_rx_tsof);
    rx_data(3).reset_p  <= p03_rx_reset;
    tx_ctrl(3).clk      <= p03_tx_clk;
    tx_ctrl(3).ready    <= p03_tx_ready;
    tx_ctrl(3).pstart   <= p03_tx_pstart;
    tx_ctrl(3).tnow     <= unsigned(p03_tx_tnow);
    tx_ctrl(3).txerr    <= p03_tx_error;
    tx_ctrl(3).reset_p  <= p03_tx_reset;
    p03_tx_data         <= tx_data(3).data;
    p03_tx_last         <= tx_data(3).last;
    p03_tx_valid        <= tx_data(3).valid;
end generate;

gen_n03 : if (PORT_COUNT <= 3) generate
    p03_tx_data         <= (others => '0');
    p03_tx_last         <= '0';
    p03_tx_valid        <= '0';
end generate;

gen_p04 : if (PORT_COUNT > 4) generate
    rx_data(4).clk      <= p04_rx_clk;
    rx_data(4).data     <= p04_rx_data;
    rx_data(4).last     <= p04_rx_last;
    rx_data(4).write    <= p04_rx_write;
    rx_data(4).rxerr    <= p04_rx_error;
    rx_data(4).rate     <= p04_rx_rate;
    rx_data(4).status   <= p04_rx_status;
    rx_data(4).tsof     <= unsigned(p04_rx_tsof);
    rx_data(4).reset_p  <= p04_rx_reset;
    tx_ctrl(4).clk      <= p04_tx_clk;
    tx_ctrl(4).ready    <= p04_tx_ready;
    tx_ctrl(4).pstart   <= p04_tx_pstart;
    tx_ctrl(4).tnow     <= unsigned(p04_tx_tnow);
    tx_ctrl(4).txerr    <= p04_tx_error;
    tx_ctrl(4).reset_p  <= p04_tx_reset;
    p04_tx_data         <= tx_data(4).data;
    p04_tx_last         <= tx_data(4).last;
    p04_tx_valid        <= tx_data(4).valid;
end generate;

gen_n04 : if (PORT_COUNT <= 4) generate
    p04_tx_data         <= (others => '0');
    p04_tx_last         <= '0';
    p04_tx_valid        <= '0';
end generate;

gen_p05 : if (PORT_COUNT > 5) generate
    rx_data(5).clk      <= p05_rx_clk;
    rx_data(5).data     <= p05_rx_data;
    rx_data(5).last     <= p05_rx_last;
    rx_data(5).write    <= p05_rx_write;
    rx_data(5).rxerr    <= p05_rx_error;
    rx_data(5).rate     <= p05_rx_rate;
    rx_data(5).status   <= p05_rx_status;
    rx_data(5).tsof     <= unsigned(p05_rx_tsof);
    rx_data(5).reset_p  <= p05_rx_reset;
    tx_ctrl(5).clk      <= p05_tx_clk;
    tx_ctrl(5).ready    <= p05_tx_ready;
    tx_ctrl(5).pstart   <= p05_tx_pstart;
    tx_ctrl(5).tnow     <= unsigned(p05_tx_tnow);
    tx_ctrl(5).txerr    <= p05_tx_error;
    tx_ctrl(5).reset_p  <= p05_tx_reset;
    p05_tx_data         <= tx_data(5).data;
    p05_tx_last         <= tx_data(5).last;
    p05_tx_valid        <= tx_data(5).valid;
end generate;

gen_n05 : if (PORT_COUNT <= 5) generate
    p05_tx_data         <= (others => '0');
    p05_tx_last         <= '0';
    p05_tx_valid        <= '0';
end generate;

gen_p06 : if (PORT_COUNT > 6) generate
    rx_data(6).clk      <= p06_rx_clk;
    rx_data(6).data     <= p06_rx_data;
    rx_data(6).last     <= p06_rx_last;
    rx_data(6).write    <= p06_rx_write;
    rx_data(6).rxerr    <= p06_rx_error;
    rx_data(6).rate     <= p06_rx_rate;
    rx_data(6).status   <= p06_rx_status;
    rx_data(6).tsof     <= unsigned(p06_rx_tsof);
    rx_data(6).reset_p  <= p06_rx_reset;
    tx_ctrl(6).clk      <= p06_tx_clk;
    tx_ctrl(6).ready    <= p06_tx_ready;
    tx_ctrl(6).pstart   <= p06_tx_pstart;
    tx_ctrl(6).tnow     <= unsigned(p06_tx_tnow);
    tx_ctrl(6).txerr    <= p06_tx_error;
    tx_ctrl(6).reset_p  <= p06_tx_reset;
    p06_tx_data         <= tx_data(6).data;
    p06_tx_last         <= tx_data(6).last;
    p06_tx_valid        <= tx_data(6).valid;
end generate;

gen_n06 : if (PORT_COUNT <= 6) generate
    p06_tx_data         <= (others => '0');
    p06_tx_last         <= '0';
    p06_tx_valid        <= '0';
end generate;

gen_p07 : if (PORT_COUNT > 7) generate
    rx_data(7).clk      <= p07_rx_clk;
    rx_data(7).data     <= p07_rx_data;
    rx_data(7).last     <= p07_rx_last;
    rx_data(7).write    <= p07_rx_write;
    rx_data(7).rxerr    <= p07_rx_error;
    rx_data(7).rate     <= p07_rx_rate;
    rx_data(7).status   <= p07_rx_status;
    rx_data(7).tsof     <= unsigned(p07_rx_tsof);
    rx_data(7).reset_p  <= p07_rx_reset;
    tx_ctrl(7).clk      <= p07_tx_clk;
    tx_ctrl(7).ready    <= p07_tx_ready;
    tx_ctrl(7).pstart   <= p07_tx_pstart;
    tx_ctrl(7).tnow     <= unsigned(p07_tx_tnow);
    tx_ctrl(7).txerr    <= p07_tx_error;
    tx_ctrl(7).reset_p  <= p07_tx_reset;
    p07_tx_data         <= tx_data(7).data;
    p07_tx_last         <= tx_data(7).last;
    p07_tx_valid        <= tx_data(7).valid;
end generate;

gen_n07 : if (PORT_COUNT <= 7) generate
    p07_tx_data         <= (others => '0');
    p07_tx_last         <= '0';
    p07_tx_valid        <= '0';
end generate;

gen_p08 : if (PORT_COUNT > 8) generate
    rx_data(8).clk      <= p08_rx_clk;
    rx_data(8).data     <= p08_rx_data;
    rx_data(8).last     <= p08_rx_last;
    rx_data(8).write    <= p08_rx_write;
    rx_data(8).rxerr    <= p08_rx_error;
    rx_data(8).rate     <= p08_rx_rate;
    rx_data(8).status   <= p08_rx_status;
    rx_data(8).tsof     <= unsigned(p08_rx_tsof);
    rx_data(8).reset_p  <= p08_rx_reset;
    tx_ctrl(8).clk      <= p08_tx_clk;
    tx_ctrl(8).ready    <= p08_tx_ready;
    tx_ctrl(8).pstart   <= p08_tx_pstart;
    tx_ctrl(8).tnow     <= unsigned(p08_tx_tnow);
    tx_ctrl(8).txerr    <= p08_tx_error;
    tx_ctrl(8).reset_p  <= p08_tx_reset;
    p08_tx_data         <= tx_data(8).data;
    p08_tx_last         <= tx_data(8).last;
    p08_tx_valid        <= tx_data(8).valid;
end generate;

gen_n08 : if (PORT_COUNT <= 8) generate
    p08_tx_data         <= (others => '0');
    p08_tx_last         <= '0';
    p08_tx_valid        <= '0';
end generate;

gen_p09 : if (PORT_COUNT > 9) generate
    rx_data(9).clk      <= p09_rx_clk;
    rx_data(9).data     <= p09_rx_data;
    rx_data(9).last     <= p09_rx_last;
    rx_data(9).write    <= p09_rx_write;
    rx_data(9).rxerr    <= p09_rx_error;
    rx_data(9).rate     <= p09_rx_rate;
    rx_data(9).status   <= p09_rx_status;
    rx_data(9).tsof     <= unsigned(p09_rx_tsof);
    rx_data(9).reset_p  <= p09_rx_reset;
    tx_ctrl(9).clk      <= p09_tx_clk;
    tx_ctrl(9).ready    <= p09_tx_ready;
    tx_ctrl(9).pstart   <= p09_tx_pstart;
    tx_ctrl(9).tnow     <= unsigned(p09_tx_tnow);
    tx_ctrl(9).txerr    <= p09_tx_error;
    tx_ctrl(9).reset_p  <= p09_tx_reset;
    p09_tx_data         <= tx_data(9).data;
    p09_tx_last         <= tx_data(9).last;
    p09_tx_valid        <= tx_data(9).valid;
end generate;

gen_n09 : if (PORT_COUNT <= 9) generate
    p09_tx_data         <= (others => '0');
    p09_tx_last         <= '0';
    p09_tx_valid        <= '0';
end generate;

gen_p10 : if (PORT_COUNT > 10) generate
    rx_data(10).clk     <= p10_rx_clk;
    rx_data(10).data    <= p10_rx_data;
    rx_data(10).last    <= p10_rx_last;
    rx_data(10).write   <= p10_rx_write;
    rx_data(10).rxerr   <= p10_rx_error;
    rx_data(10).rate    <= p10_rx_rate;
    rx_data(10).status  <= p10_rx_status;
    rx_data(10).tsof    <= unsigned(p10_rx_tsof);
    rx_data(10).reset_p <= p10_rx_reset;
    tx_ctrl(10).clk     <= p10_tx_clk;
    tx_ctrl(10).ready   <= p10_tx_ready;
    tx_ctrl(10).pstart  <= p10_tx_pstart;
    tx_ctrl(10).tnow    <= unsigned(p10_tx_tnow);
    tx_ctrl(10).txerr   <= p10_tx_error;
    tx_ctrl(10).reset_p <= p10_tx_reset;
    p10_tx_data         <= tx_data(10).data;
    p10_tx_last         <= tx_data(10).last;
    p10_tx_valid        <= tx_data(10).valid;
end generate;

gen_n10 : if (PORT_COUNT <= 10) generate
    p10_tx_data         <= (others => '0');
    p10_tx_last         <= '0';
    p10_tx_valid        <= '0';
end generate;

gen_p11 : if (PORT_COUNT > 11) generate
    rx_data(11).clk     <= p11_rx_clk;
    rx_data(11).data    <= p11_rx_data;
    rx_data(11).last    <= p11_rx_last;
    rx_data(11).write   <= p11_rx_write;
    rx_data(11).rxerr   <= p11_rx_error;
    rx_data(11).rate    <= p11_rx_rate;
    rx_data(11).status  <= p11_rx_status;
    rx_data(11).tsof    <= unsigned(p11_rx_tsof);
    rx_data(11).reset_p <= p11_rx_reset;
    tx_ctrl(11).clk     <= p11_tx_clk;
    tx_ctrl(11).ready   <= p11_tx_ready;
    tx_ctrl(11).pstart  <= p11_tx_pstart;
    tx_ctrl(11).tnow    <= unsigned(p11_tx_tnow);
    tx_ctrl(11).txerr   <= p11_tx_error;
    tx_ctrl(11).reset_p <= p11_tx_reset;
    p11_tx_data         <= tx_data(11).data;
    p11_tx_last         <= tx_data(11).last;
    p11_tx_valid        <= tx_data(11).valid;
end generate;

gen_n11 : if (PORT_COUNT <= 11) generate
    p11_tx_data         <= (others => '0');
    p11_tx_last         <= '0';
    p11_tx_valid        <= '0';
end generate;

gen_p12 : if (PORT_COUNT > 12) generate
    rx_data(12).clk     <= p12_rx_clk;
    rx_data(12).data    <= p12_rx_data;
    rx_data(12).last    <= p12_rx_last;
    rx_data(12).write   <= p12_rx_write;
    rx_data(12).rxerr   <= p12_rx_error;
    rx_data(12).rate    <= p12_rx_rate;
    rx_data(12).status  <= p12_rx_status;
    rx_data(12).tsof    <= unsigned(p12_rx_tsof);
    rx_data(12).reset_p <= p12_rx_reset;
    tx_ctrl(12).clk     <= p12_tx_clk;
    tx_ctrl(12).ready   <= p12_tx_ready;
    tx_ctrl(12).pstart  <= p12_tx_pstart;
    tx_ctrl(12).tnow    <= unsigned(p12_tx_tnow);
    tx_ctrl(12).txerr   <= p12_tx_error;
    tx_ctrl(12).reset_p <= p12_tx_reset;
    p12_tx_data         <= tx_data(12).data;
    p12_tx_last         <= tx_data(12).last;
    p12_tx_valid        <= tx_data(12).valid;
end generate;

gen_n12 : if (PORT_COUNT <= 12) generate
    p12_tx_data         <= (others => '0');
    p12_tx_last         <= '0';
    p12_tx_valid        <= '0';
end generate;

gen_p13 : if (PORT_COUNT > 13) generate
    rx_data(13).clk     <= p13_rx_clk;
    rx_data(13).data    <= p13_rx_data;
    rx_data(13).last    <= p13_rx_last;
    rx_data(13).write   <= p13_rx_write;
    rx_data(13).rxerr   <= p13_rx_error;
    rx_data(13).rate    <= p13_rx_rate;
    rx_data(13).status  <= p13_rx_status;
    rx_data(13).tsof    <= unsigned(p13_rx_tsof);
    rx_data(13).reset_p <= p13_rx_reset;
    tx_ctrl(13).clk     <= p13_tx_clk;
    tx_ctrl(13).ready   <= p13_tx_ready;
    tx_ctrl(13).pstart  <= p13_tx_pstart;
    tx_ctrl(13).tnow    <= unsigned(p13_tx_tnow);
    tx_ctrl(13).txerr   <= p13_tx_error;
    tx_ctrl(13).reset_p <= p13_tx_reset;
    p13_tx_data         <= tx_data(13).data;
    p13_tx_last         <= tx_data(13).last;
    p13_tx_valid        <= tx_data(13).valid;
end generate;

gen_n13 : if (PORT_COUNT <= 13) generate
    p13_tx_data         <= (others => '0');
    p13_tx_last         <= '0';
    p13_tx_valid        <= '0';
end generate;

gen_p14 : if (PORT_COUNT > 14) generate
    rx_data(14).clk     <= p14_rx_clk;
    rx_data(14).data    <= p14_rx_data;
    rx_data(14).last    <= p14_rx_last;
    rx_data(14).write   <= p14_rx_write;
    rx_data(14).rxerr   <= p14_rx_error;
    rx_data(14).rate    <= p14_rx_rate;
    rx_data(14).status  <= p14_rx_status;
    rx_data(14).tsof    <= unsigned(p14_rx_tsof);
    rx_data(14).reset_p <= p14_rx_reset;
    tx_ctrl(14).clk     <= p14_tx_clk;
    tx_ctrl(14).ready   <= p14_tx_ready;
    tx_ctrl(14).pstart  <= p14_tx_pstart;
    tx_ctrl(14).tnow    <= unsigned(p14_tx_tnow);
    tx_ctrl(14).txerr   <= p14_tx_error;
    tx_ctrl(14).reset_p <= p14_tx_reset;
    p14_tx_data         <= tx_data(14).data;
    p14_tx_last         <= tx_data(14).last;
    p14_tx_valid        <= tx_data(14).valid;
end generate;

gen_n14 : if (PORT_COUNT <= 14) generate
    p14_tx_data         <= (others => '0');
    p14_tx_last         <= '0';
    p14_tx_valid        <= '0';
end generate;

gen_p15 : if (PORT_COUNT > 15) generate
    rx_data(15).clk     <= p15_rx_clk;
    rx_data(15).data    <= p15_rx_data;
    rx_data(15).last    <= p15_rx_last;
    rx_data(15).write   <= p15_rx_write;
    rx_data(15).rxerr   <= p15_rx_error;
    rx_data(15).rate    <= p15_rx_rate;
    rx_data(15).status  <= p15_rx_status;
    rx_data(15).tsof    <= unsigned(p15_rx_tsof);
    rx_data(15).reset_p <= p15_rx_reset;
    tx_ctrl(15).clk     <= p15_tx_clk;
    tx_ctrl(15).ready   <= p15_tx_ready;
    tx_ctrl(15).pstart  <= p15_tx_pstart;
    tx_ctrl(15).tnow    <= unsigned(p15_tx_tnow);
    tx_ctrl(15).txerr   <= p15_tx_error;
    tx_ctrl(15).reset_p <= p15_tx_reset;
    p15_tx_data         <= tx_data(15).data;
    p15_tx_last         <= tx_data(15).last;
    p15_tx_valid        <= tx_data(15).valid;
end generate;

gen_n15 : if (PORT_COUNT <= 15) generate
    p15_tx_data         <= (others => '0');
    p15_tx_last         <= '0';
    p15_tx_valid        <= '0';
end generate;

gen_p16 : if (PORT_COUNT > 16) generate
    rx_data(16).clk     <= p16_rx_clk;
    rx_data(16).data    <= p16_rx_data;
    rx_data(16).last    <= p16_rx_last;
    rx_data(16).write   <= p16_rx_write;
    rx_data(16).rxerr   <= p16_rx_error;
    rx_data(16).rate    <= p16_rx_rate;
    rx_data(16).status  <= p16_rx_status;
    rx_data(16).tsof    <= unsigned(p16_rx_tsof);
    rx_data(16).reset_p <= p16_rx_reset;
    tx_ctrl(16).clk     <= p16_tx_clk;
    tx_ctrl(16).ready   <= p16_tx_ready;
    tx_ctrl(16).pstart  <= p16_tx_pstart;
    tx_ctrl(16).tnow    <= unsigned(p16_tx_tnow);
    tx_ctrl(16).txerr   <= p16_tx_error;
    tx_ctrl(16).reset_p <= p16_tx_reset;
    p16_tx_data         <= tx_data(16).data;
    p16_tx_last         <= tx_data(16).last;
    p16_tx_valid        <= tx_data(16).valid;
end generate;

gen_n16 : if (PORT_COUNT <= 16) generate
    p16_tx_data         <= (others => '0');
    p16_tx_last         <= '0';
    p16_tx_valid        <= '0';
end generate;

gen_p17 : if (PORT_COUNT > 17) generate
    rx_data(17).clk     <= p17_rx_clk;
    rx_data(17).data    <= p17_rx_data;
    rx_data(17).last    <= p17_rx_last;
    rx_data(17).write   <= p17_rx_write;
    rx_data(17).rxerr   <= p17_rx_error;
    rx_data(17).rate    <= p17_rx_rate;
    rx_data(17).status  <= p17_rx_status;
    rx_data(17).tsof    <= unsigned(p17_rx_tsof);
    rx_data(17).reset_p <= p17_rx_reset;
    tx_ctrl(17).clk     <= p17_tx_clk;
    tx_ctrl(17).ready   <= p17_tx_ready;
    tx_ctrl(17).pstart  <= p17_tx_pstart;
    tx_ctrl(17).tnow    <= unsigned(p17_tx_tnow);
    tx_ctrl(17).txerr   <= p17_tx_error;
    tx_ctrl(17).reset_p <= p17_tx_reset;
    p17_tx_data         <= tx_data(17).data;
    p17_tx_last         <= tx_data(17).last;
    p17_tx_valid        <= tx_data(17).valid;
end generate;

gen_n17 : if (PORT_COUNT <= 17) generate
    p17_tx_data         <= (others => '0');
    p17_tx_last         <= '0';
    p17_tx_valid        <= '0';
end generate;

gen_p18 : if (PORT_COUNT > 18) generate
    rx_data(18).clk     <= p18_rx_clk;
    rx_data(18).data    <= p18_rx_data;
    rx_data(18).last    <= p18_rx_last;
    rx_data(18).write   <= p18_rx_write;
    rx_data(18).rxerr   <= p18_rx_error;
    rx_data(18).rate    <= p18_rx_rate;
    rx_data(18).status  <= p18_rx_status;
    rx_data(18).tsof    <= unsigned(p18_rx_tsof);
    rx_data(18).reset_p <= p18_rx_reset;
    tx_ctrl(18).clk     <= p18_tx_clk;
    tx_ctrl(18).ready   <= p18_tx_ready;
    tx_ctrl(18).pstart  <= p18_tx_pstart;
    tx_ctrl(18).tnow    <= unsigned(p18_tx_tnow);
    tx_ctrl(18).txerr   <= p18_tx_error;
    tx_ctrl(18).reset_p <= p18_tx_reset;
    p18_tx_data         <= tx_data(18).data;
    p18_tx_last         <= tx_data(18).last;
    p18_tx_valid        <= tx_data(18).valid;
end generate;

gen_n18 : if (PORT_COUNT <= 18) generate
    p18_tx_data         <= (others => '0');
    p18_tx_last         <= '0';
    p18_tx_valid        <= '0';
end generate;

gen_p19 : if (PORT_COUNT > 19) generate
    rx_data(19).clk     <= p19_rx_clk;
    rx_data(19).data    <= p19_rx_data;
    rx_data(19).last    <= p19_rx_last;
    rx_data(19).write   <= p19_rx_write;
    rx_data(19).rxerr   <= p19_rx_error;
    rx_data(19).rate    <= p19_rx_rate;
    rx_data(19).status  <= p19_rx_status;
    rx_data(19).tsof    <= unsigned(p19_rx_tsof);
    rx_data(19).reset_p <= p19_rx_reset;
    tx_ctrl(19).clk     <= p19_tx_clk;
    tx_ctrl(19).ready   <= p19_tx_ready;
    tx_ctrl(19).pstart  <= p19_tx_pstart;
    tx_ctrl(19).tnow    <= unsigned(p19_tx_tnow);
    tx_ctrl(19).txerr   <= p19_tx_error;
    tx_ctrl(19).reset_p <= p19_tx_reset;
    p19_tx_data         <= tx_data(19).data;
    p19_tx_last         <= tx_data(19).last;
    p19_tx_valid        <= tx_data(19).valid;
end generate;

gen_n19 : if (PORT_COUNT <= 19) generate
    p19_tx_data         <= (others => '0');
    p19_tx_last         <= '0';
    p19_tx_valid        <= '0';
end generate;

gen_p20 : if (PORT_COUNT > 20) generate
    rx_data(20).clk     <= p20_rx_clk;
    rx_data(20).data    <= p20_rx_data;
    rx_data(20).last    <= p20_rx_last;
    rx_data(20).write   <= p20_rx_write;
    rx_data(20).rxerr   <= p20_rx_error;
    rx_data(20).rate    <= p20_rx_rate;
    rx_data(20).status  <= p20_rx_status;
    rx_data(20).tsof    <= unsigned(p20_rx_tsof);
    rx_data(20).reset_p <= p20_rx_reset;
    tx_ctrl(20).clk     <= p20_tx_clk;
    tx_ctrl(20).ready   <= p20_tx_ready;
    tx_ctrl(20).pstart  <= p20_tx_pstart;
    tx_ctrl(20).tnow    <= unsigned(p20_tx_tnow);
    tx_ctrl(20).txerr   <= p20_tx_error;
    tx_ctrl(20).reset_p <= p20_tx_reset;
    p20_tx_data         <= tx_data(20).data;
    p20_tx_last         <= tx_data(20).last;
    p20_tx_valid        <= tx_data(20).valid;
end generate;

gen_n20 : if (PORT_COUNT <= 20) generate
    p20_tx_data         <= (others => '0');
    p20_tx_last         <= '0';
    p20_tx_valid        <= '0';
end generate;

gen_p21 : if (PORT_COUNT > 21) generate
    rx_data(21).clk     <= p21_rx_clk;
    rx_data(21).data    <= p21_rx_data;
    rx_data(21).last    <= p21_rx_last;
    rx_data(21).write   <= p21_rx_write;
    rx_data(21).rxerr   <= p21_rx_error;
    rx_data(21).rate    <= p21_rx_rate;
    rx_data(21).status  <= p21_rx_status;
    rx_data(21).tsof    <= unsigned(p21_rx_tsof);
    rx_data(21).reset_p <= p21_rx_reset;
    tx_ctrl(21).clk     <= p21_tx_clk;
    tx_ctrl(21).ready   <= p21_tx_ready;
    tx_ctrl(21).pstart  <= p21_tx_pstart;
    tx_ctrl(21).tnow    <= unsigned(p21_tx_tnow);
    tx_ctrl(21).txerr   <= p21_tx_error;
    tx_ctrl(21).reset_p <= p21_tx_reset;
    p21_tx_data         <= tx_data(21).data;
    p21_tx_last         <= tx_data(21).last;
    p21_tx_valid        <= tx_data(21).valid;
end generate;

gen_n21 : if (PORT_COUNT <= 21) generate
    p21_tx_data         <= (others => '0');
    p21_tx_last         <= '0';
    p21_tx_valid        <= '0';
end generate;

gen_p22 : if (PORT_COUNT > 22) generate
    rx_data(22).clk     <= p22_rx_clk;
    rx_data(22).data    <= p22_rx_data;
    rx_data(22).last    <= p22_rx_last;
    rx_data(22).write   <= p22_rx_write;
    rx_data(22).rxerr   <= p22_rx_error;
    rx_data(22).rate    <= p22_rx_rate;
    rx_data(22).status  <= p22_rx_status;
    rx_data(22).tsof    <= unsigned(p22_rx_tsof);
    rx_data(22).reset_p <= p22_rx_reset;
    tx_ctrl(22).clk     <= p22_tx_clk;
    tx_ctrl(22).ready   <= p22_tx_ready;
    tx_ctrl(22).pstart  <= p22_tx_pstart;
    tx_ctrl(22).tnow    <= unsigned(p22_tx_tnow);
    tx_ctrl(22).txerr   <= p22_tx_error;
    tx_ctrl(22).reset_p <= p22_tx_reset;
    p22_tx_data         <= tx_data(22).data;
    p22_tx_last         <= tx_data(22).last;
    p22_tx_valid        <= tx_data(22).valid;
end generate;

gen_n22 : if (PORT_COUNT <= 22) generate
    p22_tx_data         <= (others => '0');
    p22_tx_last         <= '0';
    p22_tx_valid        <= '0';
end generate;

gen_p23 : if (PORT_COUNT > 23) generate
    rx_data(23).clk     <= p23_rx_clk;
    rx_data(23).data    <= p23_rx_data;
    rx_data(23).last    <= p23_rx_last;
    rx_data(23).write   <= p23_rx_write;
    rx_data(23).rxerr   <= p23_rx_error;
    rx_data(23).rate    <= p23_rx_rate;
    rx_data(23).status  <= p23_rx_status;
    rx_data(23).tsof    <= unsigned(p23_rx_tsof);
    rx_data(23).reset_p <= p23_rx_reset;
    tx_ctrl(23).clk     <= p23_tx_clk;
    tx_ctrl(23).ready   <= p23_tx_ready;
    tx_ctrl(23).pstart  <= p23_tx_pstart;
    tx_ctrl(23).tnow    <= unsigned(p23_tx_tnow);
    tx_ctrl(23).txerr   <= p23_tx_error;
    tx_ctrl(23).reset_p <= p23_tx_reset;
    p23_tx_data         <= tx_data(23).data;
    p23_tx_last         <= tx_data(23).last;
    p23_tx_valid        <= tx_data(23).valid;
end generate;

gen_n23 : if (PORT_COUNT <= 23) generate
    p23_tx_data         <= (others => '0');
    p23_tx_last         <= '0';
    p23_tx_valid        <= '0';
end generate;

gen_p24 : if (PORT_COUNT > 24) generate
    rx_data(24).clk     <= p24_rx_clk;
    rx_data(24).data    <= p24_rx_data;
    rx_data(24).last    <= p24_rx_last;
    rx_data(24).write   <= p24_rx_write;
    rx_data(24).rxerr   <= p24_rx_error;
    rx_data(24).rate    <= p24_rx_rate;
    rx_data(24).status  <= p24_rx_status;
    rx_data(24).tsof    <= unsigned(p24_rx_tsof);
    rx_data(24).reset_p <= p24_rx_reset;
    tx_ctrl(24).clk     <= p24_tx_clk;
    tx_ctrl(24).ready   <= p24_tx_ready;
    tx_ctrl(24).pstart  <= p24_tx_pstart;
    tx_ctrl(24).tnow    <= unsigned(p24_tx_tnow);
    tx_ctrl(24).txerr   <= p24_tx_error;
    tx_ctrl(24).reset_p <= p24_tx_reset;
    p24_tx_data         <= tx_data(24).data;
    p24_tx_last         <= tx_data(24).last;
    p24_tx_valid        <= tx_data(24).valid;
end generate;

gen_n24 : if (PORT_COUNT <= 24) generate
    p24_tx_data         <= (others => '0');
    p24_tx_last         <= '0';
    p24_tx_valid        <= '0';
end generate;

gen_p25 : if (PORT_COUNT > 25) generate
    rx_data(25).clk     <= p25_rx_clk;
    rx_data(25).data    <= p25_rx_data;
    rx_data(25).last    <= p25_rx_last;
    rx_data(25).write   <= p25_rx_write;
    rx_data(25).rxerr   <= p25_rx_error;
    rx_data(25).rate    <= p25_rx_rate;
    rx_data(25).status  <= p25_rx_status;
    rx_data(25).tsof    <= unsigned(p25_rx_tsof);
    rx_data(25).reset_p <= p25_rx_reset;
    tx_ctrl(25).clk     <= p25_tx_clk;
    tx_ctrl(25).ready   <= p25_tx_ready;
    tx_ctrl(25).pstart  <= p25_tx_pstart;
    tx_ctrl(25).tnow    <= unsigned(p25_tx_tnow);
    tx_ctrl(25).txerr   <= p25_tx_error;
    tx_ctrl(25).reset_p <= p25_tx_reset;
    p25_tx_data         <= tx_data(25).data;
    p25_tx_last         <= tx_data(25).last;
    p25_tx_valid        <= tx_data(25).valid;
end generate;

gen_n25 : if (PORT_COUNT <= 25) generate
    p25_tx_data         <= (others => '0');
    p25_tx_last         <= '0';
    p25_tx_valid        <= '0';
end generate;

gen_p26 : if (PORT_COUNT > 26) generate
    rx_data(26).clk     <= p26_rx_clk;
    rx_data(26).data    <= p26_rx_data;
    rx_data(26).last    <= p26_rx_last;
    rx_data(26).write   <= p26_rx_write;
    rx_data(26).rxerr   <= p26_rx_error;
    rx_data(26).rate    <= p26_rx_rate;
    rx_data(26).status  <= p26_rx_status;
    rx_data(26).tsof    <= unsigned(p26_rx_tsof);
    rx_data(26).reset_p <= p26_rx_reset;
    tx_ctrl(26).clk     <= p26_tx_clk;
    tx_ctrl(26).ready   <= p26_tx_ready;
    tx_ctrl(26).pstart  <= p26_tx_pstart;
    tx_ctrl(26).tnow    <= unsigned(p26_tx_tnow);
    tx_ctrl(26).txerr   <= p26_tx_error;
    tx_ctrl(26).reset_p <= p26_tx_reset;
    p26_tx_data         <= tx_data(26).data;
    p26_tx_last         <= tx_data(26).last;
    p26_tx_valid        <= tx_data(26).valid;
end generate;

gen_n26 : if (PORT_COUNT <= 26) generate
    p26_tx_data         <= (others => '0');
    p26_tx_last         <= '0';
    p26_tx_valid        <= '0';
end generate;

gen_p27 : if (PORT_COUNT > 27) generate
    rx_data(27).clk     <= p27_rx_clk;
    rx_data(27).data    <= p27_rx_data;
    rx_data(27).last    <= p27_rx_last;
    rx_data(27).write   <= p27_rx_write;
    rx_data(27).rxerr   <= p27_rx_error;
    rx_data(27).rate    <= p27_rx_rate;
    rx_data(27).status  <= p27_rx_status;
    rx_data(27).tsof    <= unsigned(p27_rx_tsof);
    rx_data(27).reset_p <= p27_rx_reset;
    tx_ctrl(27).clk     <= p27_tx_clk;
    tx_ctrl(27).ready   <= p27_tx_ready;
    tx_ctrl(27).pstart  <= p27_tx_pstart;
    tx_ctrl(27).tnow    <= unsigned(p27_tx_tnow);
    tx_ctrl(27).txerr   <= p27_tx_error;
    tx_ctrl(27).reset_p <= p27_tx_reset;
    p27_tx_data         <= tx_data(27).data;
    p27_tx_last         <= tx_data(27).last;
    p27_tx_valid        <= tx_data(27).valid;
end generate;

gen_n27 : if (PORT_COUNT <= 27) generate
    p27_tx_data         <= (others => '0');
    p27_tx_last         <= '0';
    p27_tx_valid        <= '0';
end generate;

gen_p28 : if (PORT_COUNT > 28) generate
    rx_data(28).clk     <= p28_rx_clk;
    rx_data(28).data    <= p28_rx_data;
    rx_data(28).last    <= p28_rx_last;
    rx_data(28).write   <= p28_rx_write;
    rx_data(28).rxerr   <= p28_rx_error;
    rx_data(28).rate    <= p28_rx_rate;
    rx_data(28).status  <= p28_rx_status;
    rx_data(28).tsof    <= unsigned(p28_rx_tsof);
    rx_data(28).reset_p <= p28_rx_reset;
    tx_ctrl(28).clk     <= p28_tx_clk;
    tx_ctrl(28).ready   <= p28_tx_ready;
    tx_ctrl(28).pstart  <= p28_tx_pstart;
    tx_ctrl(28).tnow    <= unsigned(p28_tx_tnow);
    tx_ctrl(28).txerr   <= p28_tx_error;
    tx_ctrl(28).reset_p <= p28_tx_reset;
    p28_tx_data         <= tx_data(28).data;
    p28_tx_last         <= tx_data(28).last;
    p28_tx_valid        <= tx_data(28).valid;
end generate;

gen_n28 : if (PORT_COUNT <= 28) generate
    p28_tx_data         <= (others => '0');
    p28_tx_last         <= '0';
    p28_tx_valid        <= '0';
end generate;

gen_p29 : if (PORT_COUNT > 29) generate
    rx_data(29).clk     <= p29_rx_clk;
    rx_data(29).data    <= p29_rx_data;
    rx_data(29).last    <= p29_rx_last;
    rx_data(29).write   <= p29_rx_write;
    rx_data(29).rxerr   <= p29_rx_error;
    rx_data(29).rate    <= p29_rx_rate;
    rx_data(29).status  <= p29_rx_status;
    rx_data(29).tsof    <= unsigned(p29_rx_tsof);
    rx_data(29).reset_p <= p29_rx_reset;
    tx_ctrl(29).clk     <= p29_tx_clk;
    tx_ctrl(29).ready   <= p29_tx_ready;
    tx_ctrl(29).pstart  <= p29_tx_pstart;
    tx_ctrl(29).tnow    <= unsigned(p29_tx_tnow);
    tx_ctrl(29).txerr   <= p29_tx_error;
    tx_ctrl(29).reset_p <= p29_tx_reset;
    p29_tx_data         <= tx_data(29).data;
    p29_tx_last         <= tx_data(29).last;
    p29_tx_valid        <= tx_data(29).valid;
end generate;

gen_n29 : if (PORT_COUNT <= 29) generate
    p29_tx_data         <= (others => '0');
    p29_tx_last         <= '0';
    p29_tx_valid        <= '0';
end generate;

gen_p30 : if (PORT_COUNT > 30) generate
    rx_data(30).clk     <= p30_rx_clk;
    rx_data(30).data    <= p30_rx_data;
    rx_data(30).last    <= p30_rx_last;
    rx_data(30).write   <= p30_rx_write;
    rx_data(30).rxerr   <= p30_rx_error;
    rx_data(30).rate    <= p30_rx_rate;
    rx_data(30).status  <= p30_rx_status;
    rx_data(30).tsof    <= unsigned(p30_rx_tsof);
    rx_data(30).reset_p <= p30_rx_reset;
    tx_ctrl(30).clk     <= p30_tx_clk;
    tx_ctrl(30).ready   <= p30_tx_ready;
    tx_ctrl(30).pstart  <= p30_tx_pstart;
    tx_ctrl(30).tnow    <= unsigned(p30_tx_tnow);
    tx_ctrl(30).txerr   <= p30_tx_error;
    tx_ctrl(30).reset_p <= p30_tx_reset;
    p30_tx_data         <= tx_data(30).data;
    p30_tx_last         <= tx_data(30).last;
    p30_tx_valid        <= tx_data(30).valid;
end generate;

gen_n30 : if (PORT_COUNT <= 30) generate
    p30_tx_data         <= (others => '0');
    p30_tx_last         <= '0';
    p30_tx_valid        <= '0';
end generate;

gen_p31 : if (PORT_COUNT > 31) generate
    rx_data(31).clk     <= p31_rx_clk;
    rx_data(31).data    <= p31_rx_data;
    rx_data(31).last    <= p31_rx_last;
    rx_data(31).write   <= p31_rx_write;
    rx_data(31).rxerr   <= p31_rx_error;
    rx_data(31).rate    <= p31_rx_rate;
    rx_data(31).status  <= p31_rx_status;
    rx_data(31).tsof    <= unsigned(p31_rx_tsof);
    rx_data(31).reset_p <= p31_rx_reset;
    tx_ctrl(31).clk     <= p31_tx_clk;
    tx_ctrl(31).ready   <= p31_tx_ready;
    tx_ctrl(31).pstart  <= p31_tx_pstart;
    tx_ctrl(31).tnow    <= unsigned(p31_tx_tnow);
    tx_ctrl(31).txerr   <= p31_tx_error;
    tx_ctrl(31).reset_p <= p31_tx_reset;
    p31_tx_data         <= tx_data(31).data;
    p31_tx_last         <= tx_data(31).last;
    p31_tx_valid        <= tx_data(31).valid;
end generate;

gen_n31 : if (PORT_COUNT <= 31) generate
    p31_tx_data         <= (others => '0');
    p31_tx_last         <= '0';
    p31_tx_valid        <= '0';
end generate;

---------------------------------------------------------------------
-- Convert 10 GbE port signals.
---------------------------------------------------------------------
gen_xp00 : if (PORTX_COUNT > 0) generate
    xrx_data(0).clk     <= x00_rx_clk;
    xrx_data(0).data    <= x00_rx_data;
    xrx_data(0).nlast   <= xlast_v2i(x00_rx_nlast);
    xrx_data(0).write   <= x00_rx_write;
    xrx_data(0).rxerr   <= x00_rx_error;
    xrx_data(0).rate    <= x00_rx_rate;
    xrx_data(0).status  <= x00_rx_status;
    xrx_data(0).tsof    <= unsigned(x00_rx_tsof);
    xrx_data(0).reset_p <= x00_rx_reset;
    xtx_ctrl(0).clk     <= x00_tx_clk;
    xtx_ctrl(0).ready   <= x00_tx_ready;
    xtx_ctrl(0).pstart  <= x00_tx_pstart;
    xtx_ctrl(0).tnow    <= unsigned(x00_tx_tnow);
    xtx_ctrl(0).txerr   <= x00_tx_error;
    xtx_ctrl(0).reset_p <= x00_tx_reset;
    x00_tx_data         <= xtx_data(0).data;
    x00_tx_nlast        <= xlast_i2v(xtx_data(0).nlast);
    x00_tx_valid        <= xtx_data(0).valid;
end generate;

gen_xn00 : if (PORTX_COUNT <= 0) generate
    x00_tx_data         <= (others => '0');
    x00_tx_nlast        <= (others => '0');
    x00_tx_valid        <= '0';
end generate;

gen_xp01 : if (PORTX_COUNT > 1) generate
    xrx_data(1).clk     <= x01_rx_clk;
    xrx_data(1).data    <= x01_rx_data;
    xrx_data(1).nlast   <= xlast_v2i(x01_rx_nlast);
    xrx_data(1).write   <= x01_rx_write;
    xrx_data(1).rxerr   <= x01_rx_error;
    xrx_data(1).rate    <= x01_rx_rate;
    xrx_data(1).status  <= x01_rx_status;
    xrx_data(1).tsof    <= unsigned(x01_rx_tsof);
    xrx_data(1).reset_p <= x01_rx_reset;
    xtx_ctrl(1).clk     <= x01_tx_clk;
    xtx_ctrl(1).ready   <= x01_tx_ready;
    xtx_ctrl(1).pstart  <= x01_tx_pstart;
    xtx_ctrl(1).tnow    <= unsigned(x01_tx_tnow);
    xtx_ctrl(1).txerr   <= x01_tx_error;
    xtx_ctrl(1).reset_p <= x01_tx_reset;
    x01_tx_data         <= xtx_data(1).data;
    x01_tx_nlast        <= xlast_i2v(xtx_data(1).nlast);
    x01_tx_valid        <= xtx_data(1).valid;
end generate;

gen_xn01 : if (PORTX_COUNT <= 1) generate
    x01_tx_data         <= (others => '0');
    x01_tx_nlast        <= (others => '0');
    x01_tx_valid        <= '0';
end generate;

gen_xp02 : if (PORTX_COUNT > 2) generate
    xrx_data(2).clk     <= x02_rx_clk;
    xrx_data(2).data    <= x02_rx_data;
    xrx_data(2).nlast   <= xlast_v2i(x02_rx_nlast);
    xrx_data(2).write   <= x02_rx_write;
    xrx_data(2).rxerr   <= x02_rx_error;
    xrx_data(2).rate    <= x02_rx_rate;
    xrx_data(2).status  <= x02_rx_status;
    xrx_data(2).tsof    <= unsigned(x02_rx_tsof);
    xrx_data(2).reset_p <= x02_rx_reset;
    xtx_ctrl(2).clk     <= x02_tx_clk;
    xtx_ctrl(2).ready   <= x02_tx_ready;
    xtx_ctrl(2).pstart  <= x02_tx_pstart;
    xtx_ctrl(2).tnow    <= unsigned(x02_tx_tnow);
    xtx_ctrl(2).txerr   <= x02_tx_error;
    xtx_ctrl(2).reset_p <= x02_tx_reset;
    x02_tx_data         <= xtx_data(2).data;
    x02_tx_nlast        <= xlast_i2v(xtx_data(2).nlast);
    x02_tx_valid        <= xtx_data(2).valid;
end generate;

gen_xn02 : if (PORTX_COUNT <= 2) generate
    x02_tx_data         <= (others => '0');
    x02_tx_nlast        <= (others => '0');
    x02_tx_valid        <= '0';
end generate;

gen_xp03 : if (PORTX_COUNT > 3) generate
    xrx_data(3).clk     <= x03_rx_clk;
    xrx_data(3).data    <= x03_rx_data;
    xrx_data(3).nlast   <= xlast_v2i(x03_rx_nlast);
    xrx_data(3).write   <= x03_rx_write;
    xrx_data(3).rxerr   <= x03_rx_error;
    xrx_data(3).rate    <= x03_rx_rate;
    xrx_data(3).status  <= x03_rx_status;
    xrx_data(3).tsof    <= unsigned(x03_rx_tsof);
    xrx_data(3).reset_p <= x03_rx_reset;
    xtx_ctrl(3).clk     <= x03_tx_clk;
    xtx_ctrl(3).ready   <= x03_tx_ready;
    xtx_ctrl(3).pstart  <= x03_tx_pstart;
    xtx_ctrl(3).tnow    <= unsigned(x03_tx_tnow);
    xtx_ctrl(3).txerr   <= x03_tx_error;
    xtx_ctrl(3).reset_p <= x03_tx_reset;
    x03_tx_data         <= xtx_data(3).data;
    x03_tx_nlast        <= xlast_i2v(xtx_data(3).nlast);
    x03_tx_valid        <= xtx_data(3).valid;
end generate;

gen_xn03 : if (PORTX_COUNT <= 3) generate
    x03_tx_data         <= (others => '0');
    x03_tx_nlast        <= (others => '0');
    x03_tx_valid        <= '0';
end generate;

gen_xp04 : if (PORTX_COUNT > 4) generate
    xrx_data(4).clk     <= x04_rx_clk;
    xrx_data(4).data    <= x04_rx_data;
    xrx_data(4).nlast   <= xlast_v2i(x04_rx_nlast);
    xrx_data(4).write   <= x04_rx_write;
    xrx_data(4).rxerr   <= x04_rx_error;
    xrx_data(4).rate    <= x04_rx_rate;
    xrx_data(4).status  <= x04_rx_status;
    xrx_data(4).tsof    <= unsigned(x04_rx_tsof);
    xrx_data(4).reset_p <= x04_rx_reset;
    xtx_ctrl(4).clk     <= x04_tx_clk;
    xtx_ctrl(4).ready   <= x04_tx_ready;
    xtx_ctrl(4).pstart  <= x04_tx_pstart;
    xtx_ctrl(4).tnow    <= unsigned(x04_tx_tnow);
    xtx_ctrl(4).txerr   <= x04_tx_error;
    xtx_ctrl(4).reset_p <= x04_tx_reset;
    x04_tx_data         <= xtx_data(4).data;
    x04_tx_nlast        <= xlast_i2v(xtx_data(4).nlast);
    x04_tx_valid        <= xtx_data(4).valid;
end generate;

gen_xn04 : if (PORTX_COUNT <= 4) generate
    x04_tx_data         <= (others => '0');
    x04_tx_nlast        <= (others => '0');
    x04_tx_valid        <= '0';
end generate;

gen_xp05 : if (PORTX_COUNT > 5) generate
    xrx_data(5).clk     <= x05_rx_clk;
    xrx_data(5).data    <= x05_rx_data;
    xrx_data(5).nlast   <= xlast_v2i(x05_rx_nlast);
    xrx_data(5).write   <= x05_rx_write;
    xrx_data(5).rxerr   <= x05_rx_error;
    xrx_data(5).rate    <= x05_rx_rate;
    xrx_data(5).status  <= x05_rx_status;
    xrx_data(5).tsof    <= unsigned(x05_rx_tsof);
    xrx_data(5).reset_p <= x05_rx_reset;
    xtx_ctrl(5).clk     <= x05_tx_clk;
    xtx_ctrl(5).ready   <= x05_tx_ready;
    xtx_ctrl(5).pstart  <= x05_tx_pstart;
    xtx_ctrl(5).tnow    <= unsigned(x05_tx_tnow);
    xtx_ctrl(5).txerr   <= x05_tx_error;
    xtx_ctrl(5).reset_p <= x05_tx_reset;
    x05_tx_data         <= xtx_data(5).data;
    x05_tx_nlast        <= xlast_i2v(xtx_data(5).nlast);
    x05_tx_valid        <= xtx_data(5).valid;
end generate;

gen_xn05 : if (PORTX_COUNT <= 5) generate
    x05_tx_data         <= (others => '0');
    x05_tx_nlast        <= (others => '0');
    x05_tx_valid        <= '0';
end generate;

gen_xp06 : if (PORTX_COUNT > 6) generate
    xrx_data(6).clk     <= x06_rx_clk;
    xrx_data(6).data    <= x06_rx_data;
    xrx_data(6).nlast   <= xlast_v2i(x06_rx_nlast);
    xrx_data(6).write   <= x06_rx_write;
    xrx_data(6).rxerr   <= x06_rx_error;
    xrx_data(6).rate    <= x06_rx_rate;
    xrx_data(6).status  <= x06_rx_status;
    xrx_data(6).tsof    <= unsigned(x06_rx_tsof);
    xrx_data(6).reset_p <= x06_rx_reset;
    xtx_ctrl(6).clk     <= x06_tx_clk;
    xtx_ctrl(6).ready   <= x06_tx_ready;
    xtx_ctrl(6).pstart  <= x06_tx_pstart;
    xtx_ctrl(6).tnow    <= unsigned(x06_tx_tnow);
    xtx_ctrl(6).txerr   <= x06_tx_error;
    xtx_ctrl(6).reset_p <= x06_tx_reset;
    x06_tx_data         <= xtx_data(6).data;
    x06_tx_nlast        <= xlast_i2v(xtx_data(6).nlast);
    x06_tx_valid        <= xtx_data(6).valid;
end generate;

gen_xn06 : if (PORTX_COUNT <= 6) generate
    x06_tx_data         <= (others => '0');
    x06_tx_nlast        <= (others => '0');
    x06_tx_valid        <= '0';
end generate;

gen_xp07 : if (PORTX_COUNT > 7) generate
    xrx_data(7).clk     <= x07_rx_clk;
    xrx_data(7).data    <= x07_rx_data;
    xrx_data(7).nlast   <= xlast_v2i(x07_rx_nlast);
    xrx_data(7).write   <= x07_rx_write;
    xrx_data(7).rxerr   <= x07_rx_error;
    xrx_data(7).rate    <= x07_rx_rate;
    xrx_data(7).status  <= x07_rx_status;
    xrx_data(7).tsof    <= unsigned(x07_rx_tsof);
    xrx_data(7).reset_p <= x07_rx_reset;
    xtx_ctrl(7).clk     <= x07_tx_clk;
    xtx_ctrl(7).ready   <= x07_tx_ready;
    xtx_ctrl(7).pstart  <= x07_tx_pstart;
    xtx_ctrl(7).tnow    <= unsigned(x07_tx_tnow);
    xtx_ctrl(7).txerr   <= x07_tx_error;
    xtx_ctrl(7).reset_p <= x07_tx_reset;
    x07_tx_data         <= xtx_data(7).data;
    x07_tx_nlast        <= xlast_i2v(xtx_data(7).nlast);
    x07_tx_valid        <= xtx_data(7).valid;
end generate;

gen_xn07 : if (PORTX_COUNT <= 7) generate
    x07_tx_data         <= (others => '0');
    x07_tx_nlast        <= (others => '0');
    x07_tx_valid        <= '0';
end generate;

---------------------------------------------------------------------
-- Statistics reporting
---------------------------------------------------------------------

-- Optional statistics reporting (ConfigBus)
gen_stats_en : if STATS_ENABLE generate
    -- Block enabled, instantiate it.
    -- Note: Poll this block at least 1 Hz to prevent overflow.
    --       (Enabling SAFE_COUNT often results in timing problems.)
    u_stats : entity work.cfgbus_port_stats
        generic map(
        PORT_COUNT  => PORT_COUNT,
        PORTX_COUNT => PORTX_COUNT,
        CFG_DEVADDR => STATS_DEVADDR,
        COUNT_WIDTH => 31,
        SAFE_COUNT  => false)
        port map(
        rx_data     => rx_data,
        tx_data     => tx_data,
        tx_ctrl     => tx_ctrl,
        xrx_data    => xrx_data,
        xtx_data    => xtx_data,
        xtx_ctrl    => xtx_ctrl,
        err_ports   => err_ports,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(0));
end generate;

gen_stats_no : if not STATS_ENABLE generate
    -- Tie off unused outputs.
    cfg_acks(0) <= cfgbus_idle;
end generate;

---------------------------------------------------------------------
-- Switch core
---------------------------------------------------------------------

u_wrap : entity work.switch_core
    generic map(
    DEV_ADDR        => cfgbus_devaddr_if(CFG_DEV_ADDR, CFG_ENABLE),
    CORE_CLK_HZ     => CORE_CLK_HZ,
    SUPPORT_PAUSE   => SUPPORT_PAUSE,
    SUPPORT_PTP     => SUPPORT_PTP,
    SUPPORT_VLAN    => SUPPORT_VLAN,
    MISS_BCAST      => MISS_BCAST,
    ALLOW_JUMBO     => ALLOW_JUMBO,
    ALLOW_RUNT      => ALLOW_RUNT,
    ALLOW_PRECOMMIT => ALLOW_PRECOMMIT,
    PORT_COUNT      => PORT_COUNT,
    PORTX_COUNT     => PORTX_COUNT,
    DATAPATH_BYTES  => DATAPATH_BYTES,
    IBUF_KBYTES     => IBUF_KBYTES,
    HBUF_KBYTES     => HBUF_KBYTES,
    OBUF_KBYTES     => OBUF_KBYTES,
    PTP_MIXED_STEP  => PTP_MIXED_STEP,
    MAC_TABLE_EDIT  => MAC_TABLE_EDIT,
    MAC_TABLE_SIZE  => MAC_TABLE_SIZE)
    port map(
    ports_rx_data   => rx_data,
    ports_tx_data   => tx_data,
    ports_tx_ctrl   => tx_ctrl,
    portx_rx_data   => xrx_data,
    portx_tx_data   => xtx_data,
    portx_tx_ctrl   => xtx_ctrl,
    err_ports       => err_ports,
    err_switch      => err_switch,
    errvec_t        => errvec_t,
    cfg_cmd         => cfg_cmd,
    cfg_ack         => cfg_acks(1),
    scrub_req_t     => scrub_req_t,
    core_clk        => core_clk,
    core_reset_p    => reset_p);

end wrap_switch_core;
