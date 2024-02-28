--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Port-type wrapper for "clkgen_vernier" and "ptp_counter_gen"
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

entity wrap_ptp_reference is
    generic (
    CFG_ENABLE      : boolean;      -- Enable switch configuration?
    CFG_DEV_ADDR    : integer;      -- ConfigBus device address
    PTP_REF_HZ      : integer);     -- Vernier reference frequency
    port (
    -- Global Vernier reference time
    tref_vclka  : out std_logic;
    tref_vclkb  : out std_logic;
    tref_tnext  : out std_logic;
    tref_tstamp : out std_logic_vector(47 downto 0);

    -- Reference clock and reset.
    ref_clk     : in  std_logic;
    reset_p     : in  std_logic;

    -- ConfigBus interface (optional)
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
    cfg_irq     : out std_logic);
end wrap_ptp_reference;

architecture wrap_ptp_reference of wrap_ptp_reference is

constant VCONFIG : vernier_config := create_vernier_config(PTP_REF_HZ);

signal vclka    : std_logic;
signal vclkb    : std_logic;
signal vreset_p : std_logic;
signal ref_time : port_timeref;
signal cfg_cmd  : cfgbus_cmd;
signal cfg_ack  : cfgbus_ack;

begin

-- Convert Vernier signals.
tref_vclka      <= ref_time.vclka;
tref_vclkb      <= ref_time.vclkb;
tref_tnext      <= ref_time.tnext;
tref_tstamp     <= std_logic_vector(ref_time.tstamp);

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

-- Synthesize the Vernier clock pair.
u_clk : entity work.clkgen_vernier
    generic map(VCONFIG => VCONFIG)
    port map(
    rstin_p     => reset_p,
    refclk      => ref_clk,
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p);

-- Group clocks with a free-running counter.
u_wrap : entity work.ptp_counter_gen
    generic map(
    DEVADDR     => cfgbus_devaddr_if(CFG_DEV_ADDR, CFG_ENABLE),
    REGADDR     => CFGBUS_ADDR_ANY,
    VCONFIG     => VCONFIG)
    port map(
    vclka       => vclka,
    vclkb       => vclkb,
    vreset_p    => vreset_p,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    ref_time    => ref_time);

end wrap_ptp_reference;
