--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with Wishbone interface
--
-- This module acts as a ConfigBus host, accepting read and write commands
-- from a Wishbone bus and bridging those commands to the ConfigBus interface.
-- It is compatible with Rev B.4 of the Wishbone specification:
--  https://cdn.opencores.org/downloads/wbspec_b4.pdf
--
-- Standardized Wishbone datasheet:
--  Description:            Bridge for connecting Wishbone to ConfigBus
--  Supported cycles:       Slave, single read/write.
--                          Slave, block read/write.
--  Data port size:         32-bit
--  ...granularity:         32-bit
--  ...maximum operand:     32-bit
--  ...transfer order:      Big/little-endian
--  ...transfer sequence:   Undefined
--  Clock freq constraints: None
--  Supported signal list:  Standard Wishbone names with "wb_" prefix:
--                          CLK_I, RST_I, ADR_I, CYC_I, DAT_I, STB_I, WE_I,
--                          ACK_O, DAT_O, ERR_O --> wb_clk_i, wb_rst_i, ...
--                          Reads from an invalid address may assert ERR_O.
--
-- Reads and writes are passed through the bridge on a one-to-one basis,
-- mapping the bits of the Wishbone address space (1 MiB) as follows:
--  * Bits 01..00:  Not connected (32-bit granularity)
--  * Bits 11..02:  ConfigBus register address (0-1023)
--  * Bits 19..12:  ConfigBus device address (0-255)
--
-- For simplicity, only 32-bit granularity is supported.
-- Support for 8-bit granularity may be added in a future update.
--
-- The "ERR_O" strobe is triggered under any of the following conditions:
--  * Read operations return multiple replies (address conflict).
--  * Read operations return no reply (no response / timeout).
-- Failed reads will also assert ACK_O, so the bus will not stall even
-- if the Wishbone master ignores ERR_O or the signal is disconnected.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;

entity cfgbus_host_wishbone is
    generic (
    -- ConfigBus read timeout (clocks)
    RD_TIMEOUT  : positive := 16);
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- Interrupt flag.
    interrupt   : out std_logic;

    -- Wishbone interface.
    wb_clk_i    : in  std_logic;
    wb_rst_i    : in  std_logic;
    wb_adr_i    : in  std_logic_vector(19 downto 2);
    wb_cyc_i    : in  std_logic;
    wb_dat_i    : in  std_logic_vector(31 downto 0);
    wb_stb_i    : in  std_logic;
    wb_we_i     : in  std_logic;
    wb_ack_o    : out std_logic;
    wb_dat_o    : out std_logic_vector(31 downto 0);
    wb_err_o    : out std_logic);
end cfgbus_host_wishbone;

architecture cfgbus_host_wishbone of cfgbus_host_wishbone is

-- Timeouts and error detection.
signal int_cmd      : cfgbus_cmd;
signal int_ack      : cfgbus_ack;

-- Command state machine.
signal cmd_start    : std_logic;
signal wr_start     : std_logic;
signal rd_start     : std_logic;
signal rd_pending   : std_logic := '0';
signal rd_done      : std_logic;

begin

-- Drive top-level Wishbone slave outputs:
wb_ack_o    <= wr_start or rd_done;
wb_dat_o    <= int_ack.rdata;
wb_err_o    <= int_ack.rderr;
interrupt   <= int_ack.irq;

-- Drive internal ConfigBus signals:
int_cmd.clk     <= wb_clk_i;
int_cmd.sysaddr <= 0;
int_cmd.devaddr <= u2i(wb_adr_i(19 downto 12));
int_cmd.regaddr <= u2i(wb_adr_i(11 downto 2));
int_cmd.wdata   <= wb_dat_i;
int_cmd.wstrb   <= (others => '1');
int_cmd.wrcmd   <= wr_start;
int_cmd.rdcmd   <= rd_start;
int_cmd.reset_p <= wb_rst_i;

-- Timeouts and error detection.
u_timeout : cfgbus_timeout
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    host_cmd    => int_cmd,
    host_ack    => int_ack,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Command state machine.
-- Note: Writes have no "pending" flag because they complete immediately.
cmd_start   <= wb_cyc_i and wb_stb_i and not rd_pending;
wr_start    <= cmd_start and wb_we_i;
rd_start    <= cmd_start and not wb_we_i;
rd_done     <= int_ack.rdack or int_ack.rderr;

p_write : process(wb_clk_i)
begin
    if rising_edge(wb_clk_i) then
        -- Update the read pending flag.
        if (wb_rst_i = '1' or rd_done = '1') then
            rd_pending <= '0';
        elsif (rd_start = '1') then
            rd_pending <= '1';
        end if;
    end if;
end process;

end cfgbus_host_wishbone;
