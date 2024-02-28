--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Common I/O peripherals, controlled by ConfigBus
--
-- This block is a wrapper for a 32-bit register and any number of MDIO
-- blocks, all controlled by any ConfigBus host.  It is used in several
-- of the example designs.
--
-- This block has a fixed register mapping:
--  RegAddr 0x10 = Writeable register
--  RegAddr 0x20 = MDIO port 0
--  RegAddr 0x21 = MDIO port 1
--  RegAddr 0x22 = MDIO port 2, etc.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

entity config_peripherals is
    generic (
    DEVADDR     : integer;          -- ConfigBus device address
    CLKREF_HZ   : positive;         -- ConfigBus clock rate (Hz)
    MDIO_BAUD   : positive;         -- MDIO baud rate (bps)
    MDIO_COUNT  : natural;          -- Number of MDIO ports
    REG_RSTVAL  : cfgbus_word);     -- Register initial state
    port (
    -- MDIO interface for each port
    mdio_clk    :   out std_logic_vector(MDIO_COUNT-1 downto 0);
    mdio_data   : inout std_logic_vector(MDIO_COUNT-1 downto 0);

    -- Writeable register
    reg_out     :   out std_logic_vector(31 downto 0);

    -- ConfigBus device interface.
    cfg_cmd     : in    cfgbus_cmd;
    cfg_ack     :   out cfgbus_ack);
end config_peripherals;

architecture config_peripherals of config_peripherals is

signal cfg_acks : cfgbus_ack_array(MDIO_COUNT downto 0);

begin

-- Simple read/writeable ConfigBus register.
u_reg : cfgbus_register
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 16#10#,
    RSTVAL      => REG_RSTVAL)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    reg_val     => reg_out);

-- Instantiate each MDIO port.
gen_mdio : for n in 0 to MDIO_COUNT-1 generate
    u_mdio : entity work.cfgbus_mdio
        generic map(
        DEVADDR     => DEVADDR,
        REGADDR     => 16#20# + n,
        CLKREF_HZ   => CLKREF_HZ,
        MDIO_BAUD   => MDIO_BAUD)
        port map(
        mdio_clk    => mdio_clk(n),
        mdio_data   => mdio_data(n),
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(1+n));
end generate;

-- Consolidate ConfigBus replies.
cfg_ack <= cfgbus_merge(cfg_acks);

end config_peripherals;
