--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet-over-Serial SPI transceiver port (clock input)
--
-- This module implements a serial-over-Ethernet port with a four-wire SPI
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an SPI follower (i.e., remote device drives chip-select and clock).
--
-- To minimize required FPGA resources, the input clock is treated as a regular
-- signal, oversampled by the global reference clock.  (Typically 50-125 MHz vs.
-- ~10 Mbps max for a typical SPI interface.)  As a result, all inputs are
-- asynchronous and must use metastability buffers for safe operation.
--
-- In both modes, the remote device sets the rate of transmission by providing
-- the serial clock.  If either end of the link does not currently have data to
-- transmit, it should repeatedly send the SLIP inter-frame token (0xC0).
--
-- By default, glitch-filter delay and SPI mode are fixed at build-time.
-- If enabled, an optional ConfigBus interface can be used to set a
-- different configuration at runtime and optionally report status
-- information.  (Connecting the read-reply interface is recommended,
-- but not required for routine operation.)
--
-- If enabled, the ConfigBus interface uses three registers:
--  REGADDR = 0: Port status (read-only)
--      Bits 31-08: Reserved
--      Bits 07-00: Read the 8-bit status word (i.e., rx_data.status)
--  REGADDR = 1: Reference clock rate (read-only)
--      Bits 31-00: Report reference clock rate, in Hz. (i.e., CLFREF_HZ)
--  REGADDR = 2: SPI mode and glitch-filter control (read-write)
--      Bits 31-08: Reserved (zeros)
--      Bits 09-08: SPI mode (0 / 1 / 2 / 3)
--      Bits 07-00: Glitch filter setting (see "io_spi_peripheral")
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
--
-- NOTE: Reference clock must be a few times faster than SCLK.
--       See io_spi_peripheral.vhd for details.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_serial_spi_peripheral is
    generic (
    -- Default settings for this port.
    CLKREF_HZ   : positive;         -- Reference clock rate (Hz)
    SPI_GDLY    : natural := 1;     -- SPI glitch-detection threshold
    SPI_MODE    : natural := 3;     -- SPI clock phase & polarity
    SYNC_MODE   : boolean := false; -- Disable both sync and async process on sclk? 
    TIMEOUT_SEC : positive := 15;   -- Activity timeout, in seconds
    -- ConfigBus device address (optional)
    DEVADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- External SPI interface.
    spi_csb     : in  std_logic;    -- Chip-select bar (input)
    spi_sclk    : in  std_logic;    -- Serial clock in (input)
    spi_sdi     : in  std_logic;    -- Serial data in (user to switch)
    spi_sdo     : out std_logic;    -- Serial data out (switch to user)
    spi_sdt     : out std_logic;    -- Tristate signal for SDO (optional).

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_s2m;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_m2s;  -- Flow control for tx_data

    -- Optional ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock (refclk >> spi_sck*)
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_spi_peripheral;

architecture port_serial_spi_peripheral of port_serial_spi_peripheral is

-- Default configuration parameters:
constant MODE_DEFAULT : byte_t := i2s(SPI_MODE, 8);
constant GDLY_DEFAULT : byte_t := i2s(SPI_GDLY, 8);
constant CFG_DEFAULT  : cfgbus_word :=
    resize(MODE_DEFAULT & GDLY_DEFAULT, CFGBUS_WORD_SIZE);

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 2);
signal cfg_word     : cfgbus_word := CFG_DEFAULT;
signal cfg_mode     : integer range 0 to 3;
signal cfg_gdly     : byte_u;
signal status_word  : cfgbus_word;

-- Byte transfers from raw SPI interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;
signal dec_data     : byte_t;
signal dec_write    : std_logic;

-- Internal reset signals.
signal reset_sync   : std_logic;
signal wdog_rst_p   : std_logic := '1';

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.rate    <= get_rate_word(10);
rx_data.status  <= status_word(7 downto 0);
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= wdog_rst_p;
tx_ctrl.pstart  <= '1';     -- Timestamps discarded
tx_ctrl.tnow    <= TSTAMP_DISABLED;
tx_ctrl.txerr   <= '0';     -- No Tx error states

-- Upstream status reporting.
status_word <= (
    0 => reset_sync,
    others => '0');

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => refclk);

-- Optional ConfigBus interface.
-- If disabled, each setting reduces to the designated constant.
cfg_ack     <= cfgbus_merge(cfg_acks);
cfg_mode    <= u2i(cfg_word(9 downto 8));       -- SPI_MODE
cfg_gdly    <= unsigned(cfg_word(7 downto 0));  -- SPI_GDLY

u_cfg_reg0 : cfgbus_readonly_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 0)   -- Reg0 = Status reporting
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    sync_clk    => refclk,
    sync_val    => status_word);

u_cfg_reg1 : cfgbus_readonly
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 1)   -- Reg1 = Reference clock rate
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(1),
    reg_val     => i2s(CLKREF_HZ, CFGBUS_WORD_SIZE));

u_cfg_reg2 : cfgbus_register_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 2,   -- Reg2 = Mode and glitch-filter control
    WR_ATOMIC   => true,
    WR_MASK     => x"000003FF",
    RSTVAL      => CFG_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => refclk,
    sync_val    => cfg_word);

-- Raw SPI interface
u_spi : entity work.io_spi_peripheral
    generic map(
    IDLE_BYTE   => SLIP_FEND,
    SYNC_MODE   => SYNC_MODE)
    port map(
    spi_csb     => spi_csb,
    spi_sclk    => spi_sclk,
    spi_sdi     => spi_sdi,
    spi_sdo     => spi_sdo,
    spi_sdt     => spi_sdt,
    tx_data     => enc_data,
    tx_valid    => enc_valid,
    tx_ready    => enc_ready,
    rx_data     => dec_data,
    rx_write    => dec_write,
    cfg_mode    => cfg_mode,
    cfg_gdly    => cfg_gdly,
    refclk      => refclk);

-- Detect inactive ports and clear transmit buffer.
-- (Otherwise, broadcast packets will overflow the buffer.)
p_wdog : process(refclk, reset_sync)
    constant TIMEOUT : integer := TIMEOUT_SEC * CLKREF_HZ;
    variable wdog_ctr : integer range 0 to TIMEOUT := TIMEOUT;
begin
    if (reset_sync = '1') then
        wdog_rst_p  <= '1';
        wdog_ctr    := TIMEOUT;
    elsif rising_edge(refclk) then
        wdog_rst_p  <= bool2bit(wdog_ctr = 0);
        if (dec_write = '1') then
            wdog_ctr := TIMEOUT;        -- Activity detect
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;   -- Countdown to zero
        end if;
    end if;
end process;

-- SLIP encoder (for Tx) and decoder (for Rx)
u_enc : entity work.slip_encoder
    port map (
    in_data     => tx_data.data,
    in_last     => tx_data.last,
    in_valid    => tx_data.valid,
    in_ready    => tx_ctrl.ready,
    out_data    => enc_data,
    out_valid   => enc_valid,
    out_ready   => enc_ready,
    refclk      => refclk,
    reset_p     => reset_sync);

u_dec : entity work.slip_decoder
    port map (
    in_data     => dec_data,
    in_write    => dec_write,
    out_data    => rx_data.data,
    out_write   => rx_data.write,
    out_last    => rx_data.last,
    decode_err  => rx_data.rxerr,
    refclk      => refclk,
    reset_p     => reset_sync);

end port_serial_spi_peripheral;
