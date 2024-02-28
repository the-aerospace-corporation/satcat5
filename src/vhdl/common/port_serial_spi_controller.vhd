--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet-over-Serial SPI transceiver port (clock output)
--
-- This module implements a serial-over-Ethernet port with a four-wire SPI
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an SPI clock source (i.e., this block drives chip-select and clock).
--
-- Use of this block is not recommended for normal devices, but it may
-- be required for switch-to-switch links.
--
-- The only provided flow-control is through an optional "pause" flag.
-- Unless this flag is asserted, the SPI clock is always running.
--
-- By default, SPI clock-divider and mode are fixed at build-time.
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
--  REGADDR = 2: SPI mode and clock-rate control (read-write)
--      Bits 31-08: Reserved (zeros)
--      Bits 09-08: SPI mode (0 / 1 / 2 / 3)
--      Bits 07-00: Clock divider ratio = round(0.5 * CLKREF_HZ / baud_hz)
--
-- See also: https://en.wikipedia.org/wiki/Serial_Peripheral_Interface_Bus
-- See also: https://en.wikipedia.org/wiki/Serial_Line_Internet_Protocol
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

entity port_serial_spi_controller is
    generic (
    -- Default settings for this port.
    CLKREF_HZ   : positive;         -- Reference clock rate (Hz)
    SPI_BAUD    : positive;         -- SPI baud rate (bps)
    SPI_MODE    : natural := 3;     -- SPI clock phase & polarity
    -- ConfigBus device address (optional)
    DEVADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- External SPI interface.
    spi_csb     : out std_logic;    -- Chip-select bar (output)
    spi_sclk    : out std_logic;    -- Serial clock out (output)
    spi_sdi     : in  std_logic;    -- Serial data in
    spi_sdo     : out std_logic;    -- Serial data out

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_s2m;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_m2s;  -- Flow control for tx_data

    -- Pause flag (optional)
    ext_pause   : in  std_logic := '0';

    -- Optional ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_spi_controller;

architecture port_serial_spi_controller of port_serial_spi_controller is

-- Default configuration parameters:
constant MODE_DEFAULT : byte_t := i2s(SPI_MODE, 8);
constant RATE_DEFAULT : byte_t :=
    i2s(clocks_per_baud(CLKREF_HZ, 2 * SPI_BAUD), 8);
constant CFG_DEFAULT  : cfgbus_word :=
    resize(MODE_DEFAULT & RATE_DEFAULT, CFGBUS_WORD_SIZE);

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 2);
signal cfg_word     : cfgbus_word := CFG_DEFAULT;
signal cfg_mode     : integer range 0 to 3;
signal cfg_rate     : byte_u;
signal status_word  : cfgbus_word;

-- Flow control and idle token insertion.
signal flow_data    : byte_t := SLIP_FEND;
signal flow_last    : std_logic := '0';
signal flow_valid   : std_logic := '0';
signal flow_ready   : std_logic;

-- Byte transfers from raw SPI interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic := '0';
signal dec_data     : byte_t;
signal dec_write    : std_logic;

-- Synchronous reset signal.
signal reset_sync   : std_logic;

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.rate    <= get_rate_word(clocks_per_baud(SPI_BAUD, 1_000_000));
rx_data.status  <= status_word(7 downto 0);
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= reset_sync;
tx_ctrl.pstart  <= '1';     -- Timestamps discarded
tx_ctrl.tnow    <= TSTAMP_DISABLED;
tx_ctrl.txerr   <= '0';     -- No Tx error states

-- Upstream status reporting.
status_word <= (
    0 => reset_sync,
    1 => ext_pause,
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
cfg_rate    <= unsigned(cfg_word(7 downto 0));  -- RATE_DEFAULT

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
    REGADDR     => 2,   -- Reg2 = Mode and rate control
    WR_ATOMIC   => true,
    WR_MASK     => x"000003FF",
    RSTVAL      => CFG_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => refclk,
    sync_val    => cfg_word);

-- Raw SPI interface
u_spi : entity work.io_spi_controller
    port map(
    cmd_data    => flow_data,
    cmd_last    => flow_last,
    cmd_valid   => flow_valid,
    cmd_ready   => flow_ready,
    rcvd_data   => dec_data,
    rcvd_write  => dec_write,
    spi_csb     => spi_csb,
    spi_sck     => spi_sclk,
    spi_sdo     => spi_sdo,
    spi_sdi     => spi_sdi,
    cfg_mode    => cfg_mode,
    cfg_rate    => cfg_rate,
    ref_clk     => refclk,
    reset_p     => reset_sync);

-- Flow control and idle token insertion:
-- Arbitrarily break each SPI transaction into fixed-length chunks, so
-- that the chip-select line is exercised frequently. (This minimizes
-- lost data on startup or after an error.)  Before starting each chunk,
-- check the pause flag to allow some degree of flow control.
-- If there's no data available, insert a SLIP idle token instead.
p_flow : process(refclk)
    -- Counter wraparound every 2^6 = 64 bytes.
    subtype flow_count_t is unsigned(5 downto 0);
    constant BYTE_LAST  : flow_count_t := (others => '1');
    variable byte_ctr   : flow_count_t := (others => '0');
begin
    if rising_edge(refclk) then
        enc_ready <= '0';   -- Set default
        if (reset_sync = '1') then
            -- Global reset
            flow_data   <= SLIP_FEND;
            flow_last   <= '0';
            flow_valid  <= '0';
            enc_ready   <= '0';
            byte_ctr    := (others => '0');
        elsif (flow_valid = '0' or flow_ready = '1') then
            -- Ready to present the next byte.
            if (enc_valid = '1') then
                flow_data <= enc_data;      -- Normal data
            else
                flow_data <= SLIP_FEND;     -- Idle filler
            end if;
            -- End of each chunk briefly deasserts chip-select.
            flow_last <= bool2bit(byte_ctr = BYTE_LAST);
            -- Optional pause at the start of each chunk.
            -- Note: Single-cycle delay in enc_ready is safe because
            --       SPI will always take many clock cycles per byte.
            if (byte_ctr = 0 and ext_pause = '1') then
                flow_valid <= '0';          -- Paused
            else
                flow_valid <= '1';          -- Continue
                enc_ready  <= enc_valid;    -- Byte consumed?
                byte_ctr   := byte_ctr + 1; -- Increment with wraparound
            end if;
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

end port_serial_spi_controller;
