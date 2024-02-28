--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus-controlled MDIO port
--
-- This module controls an MDIO port using a single ConfigBus register.
-- Writing to the register queues an MDIO transaction in a small FIFO.
-- Each transaction can be a read or a write.
--
-- The register format is as follows:
--  * Bits 31-28: Reserved / zeros
--  * Bits 27-26: Operator ("01" = write, "10" = read)
--  * Bits 25-21: PHY address
--  * Bits 20-16: REG address
--  * Bits 15-00: Write-data (Ignored by reads)
--
-- Reading from the register reports the results:
--  * Bit  31:    Command FIFO full
--  * Bit  30:    Read-data valid
--  * Bits 29-16: Reserved
--  * Bits 15-00: Read-data
--
-- To execute an MDIO write:
--  * Write the desired address and data parameters to the register.
--
-- To execute an MDIO read:
--  * Write the desired address to the register (data = 0).
--  * Poll or wait until all queued operations are completed.
--  * Read the status register to obtain the last read value.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;

entity cfgbus_mdio is
    generic (
    DEVADDR     : integer;          -- ConfigBus device address
    REGADDR     : integer;          -- ConfigBus register address
    CLKREF_HZ   : positive;         -- ConfigBus clock rate (Hz)
    MDIO_BAUD   : positive);        -- MDIO baud rate (bps)
    port (
    -- MDIO port
    mdio_clk    :   out std_logic;
    mdio_data   : inout std_logic;
    -- ConfigBus device interface.
    cfg_cmd     : in    cfgbus_cmd;
    cfg_ack     :   out cfgbus_ack);
end cfgbus_mdio;

architecture cfgbus_mdio of cfgbus_mdio is

-- MDIO controller
signal wr_ctrl      : std_logic_vector(11 downto 0) := (others => '0');
signal wr_data      : std_logic_vector(15 downto 0) := (others => '0');
signal wr_valid     : std_logic := '0';
signal wr_ready     : std_logic;
signal rd_data      : std_logic_vector(15 downto 0);
signal rd_rdy       : std_logic;

-- ConfigBus state machine.
signal fifo_wr      : std_logic;
signal fifo_full    : std_logic;
signal rfifo_data   : std_logic_vector(15 downto 0);
signal rfifo_valid  : std_logic;
signal rfifo_read   : std_logic;
signal rd_status    : cfgbus_word;
signal ack          : cfgbus_ack := cfgbus_idle;

begin

-- Drive top-level outputs.
cfg_ack <= ack;

-- MDIO controller
u_mdio : entity work.io_mdio_readwrite
    generic map(
    CLKREF_HZ   => CLKREF_HZ,
    MDIO_BAUD   => MDIO_BAUD)
    port map(
    cmd_ctrl    => wr_ctrl,
    cmd_data    => wr_data,
    cmd_valid   => wr_valid,
    cmd_ready   => wr_ready,
    rd_data     => rd_data,
    rd_rdy      => rd_rdy,
    mdio_clk    => mdio_clk,
    mdio_data   => mdio_data,
    ref_clk     => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

-- Small FIFO for read replies.
rfifo_read <= bool2bit(cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR));

u_rfifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 16)
    port map(
    in_data     => rd_data,
    in_write    => rd_rdy,
    out_data    => rfifo_data,
    out_valid   => rfifo_valid,
    out_read    => rfifo_read,
    clk         => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

-- Command FIFO handles ConfigBus writes.
fifo_wr <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR));

u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => 16,
    META_WIDTH  => 12)
    port map(
    in_data     => cfg_cmd.wdata(15 downto 0),
    in_meta     => cfg_cmd.wdata(27 downto 16),
    in_write    => fifo_wr,
    out_data    => wr_data,
    out_meta    => wr_ctrl,
    out_valid   => wr_valid,
    out_read    => wr_ready,
    fifo_full   => fifo_full,
    clk         => cfg_cmd.clk,
    reset_p     => cfg_cmd.reset_p);

-- Handle ConfigBus reads.
rd_status <= fifo_full & rfifo_valid & "00000000000000" & rfifo_data;

p_read : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (rfifo_read = '1') then
            ack <= cfgbus_reply(rd_status);
        else
            ack <= cfgbus_idle;
        end if;
    end if;
end process;

end cfgbus_mdio;
