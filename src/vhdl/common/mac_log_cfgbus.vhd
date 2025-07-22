--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus wrapper for "mac_log_core"
--
-- This block is a thin wrapper for "mac_log_core" that can be read using
-- a ConfigBus interface.  The interface uses a single read-only register:
--  * Bit 31    = Data valid (i.e., FIFO is non-empty)
--  * Bit 30    = Last word in packet descriptor
--  * Bit 29-24 = Reserved
--  * Bit 23-00 = Read 24 bits at a time, starting from the timestamp
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity mac_log_cfgbus is
    generic (
    DEV_ADDR    : integer;          -- ConfigBus address
    REG_ADDR    : integer := CFGBUS_ADDR_ANY;
    CORE_CLK_HZ : positive;         -- Core clock frequency (Hz)
    PORT_COUNT  : positive);        -- Number of ingress ports
    port (
    -- Packet logs from the shared pipeline.
    mac_data    : in  log_meta_t;
    mac_psrc    : in  integer range 0 to PORT_COUNT-1;
    mac_dmask   : in  std_logic_vector(PORT_COUNT-1 downto 0);
    mac_write   : in  std_logic;

    -- Packet logs from each ingress port.
    port_data   : in  log_meta_array(PORT_COUNT-1 downto 0);
    port_write  : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- Clock and synchronous reset.
    core_clk    : in  std_logic;
    reset_p     : in  std_logic);
end mac_log_cfgbus;

architecture mac_log_cfgbus of mac_log_cfgbus is

signal log_data     : std_logic_vector(23 downto 0);
signal log_last     : std_logic;
signal log_valid    : std_logic;
signal log_ready    : std_logic;
signal cpu_data     : cfgbus_word;

begin

-- Generate log-data stream as 24-bit words.
u_log : entity work.mac_log_core
    generic map(
    CORE_CLK_HZ => CORE_CLK_HZ,
    OUT_BYTES   => 3,
    PORT_COUNT  => PORT_COUNT)
    port map(
    mac_data    => mac_data,
    mac_psrc    => mac_psrc,
    mac_dmask   => mac_dmask,
    mac_write   => mac_write,
    port_data   => port_data,
    port_write  => port_write,
    out_clk     => cfg_cmd.clk,
    out_data    => log_data,
    out_last    => log_last,
    out_valid   => log_valid,
    out_ready   => log_ready,
    core_clk    => core_clk,
    reset_p     => reset_p);

-- ConfigBus interface.
log_ready <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_ADDR));
cpu_data  <= log_valid & log_last & "000000" & log_data;

p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (log_ready = '1') then
            cfg_ack <= cfgbus_reply(cpu_data);
        else
            cfg_ack <= cfgbus_idle;
        end if;
    end if;
end process;

end mac_log_cfgbus;
