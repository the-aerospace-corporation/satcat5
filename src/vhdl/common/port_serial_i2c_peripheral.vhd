--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet-over-Serial I2C transceiver port (peripheral)
--
-- This module implements a serial-over-Ethernet port with a two-wire I2C
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an I2C peripheral (i.e., the sink for the I2C clock).  It is always
-- ready to accept data and will never request clock-stretching.  This
-- is the preferred mode of operation for I2C ports on a SatCat5 switch.
--
-- To send data, the remote device executes an I2C write, i.e.:
--  START, address with write flag, any number of data bytes, STOP
--
-- To receive data, the remote device exeuctes an I2C read, i.e.:
--  START, address with read flag, any number of data bytes, STOP
--
-- Both streams are SLIP-encoded.  Frame boundaries are not aligned to
-- the start or end of each I2C transaction. If either end of the link
-- does not currently have data to transmit, it should repeatedly send
-- the SLIP inter-frame token (0xC0).
--
-- A "ready-to-send" flag is provided so that the remote device knows to
-- execute a read.  (This can be tied to a microcontroller interrupt, etc.)
-- If this flag is not available, the remote device should poll regularly
-- and look for two consecutive 0xC0 tokens, which is an unambiguous
-- indicator that no additional data is currently available.
--
-- By default, the expected I2C address is fixed at build-time.  If the
-- expected address is set to the special "general call" address (0000000),
-- then it accepts all commands.  Otherwise, it only accepts commands sent
-- to the designated address.
--
-- Generally, the top-level should instantiate a bidirectional buffer, to
-- connect SCL and SDA to their respective I/O pads.  For more details,
-- refer to "io_i2c_controller.vhd".
--
-- If enabled, an optional ConfigBus interface can be used to set a
-- different configuration at runtime and optionally report status
-- information.  (Connecting the read-reply interface is recommended,
-- but not required for routine operation.)
--
-- If enabled, the ConfigBus interface uses two registers:
--  REGADDR = 0: Port status (read-only)
--      Bits 31-08: Reserved
--      Bits 07-00: Read the 8-bit status word (i.e., rx_data.status)
--  REGADDR = 1: Reference clock rate (read-only)
--      Bits 31-00: Report reference clock rate, in Hz. (i.e., CLFREF_HZ)
--  REGADDR = 2: I2C address control (read-write)
--      Bits 31-24: Reserved (zeros)
--      Bits 23-17: I2C device address
--      Bits 16-00: Reserved (zeros)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.eth_frame_common.all;
use     work.i2c_constants.all;     -- io_i2c_controller.vhd
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_serial_i2c_peripheral is
    generic (
    -- Default settings for this port.
    I2C_ADDR    : i2c_addr_t;       -- Local I2C device address
    CLKREF_HZ   : positive;         -- Reference clock rate (Hz)
    TIMEOUT_SEC : positive := 15;   -- Activity timeout, in seconds
    -- ConfigBus device address (optional)
    DEVADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- External I2C interface.
    -- Note: Top level should instantiate tri-state buffer for SDATA.
    sclk_i      : in  std_logic;
    sdata_o     : out std_logic;
    sdata_i     : in  std_logic;
    rts_out     : out std_logic;

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_s2m;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_m2s;  -- Flow control for tx_data

    -- Optional ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;

    -- Clock and reset
    ref_clk     : in  std_logic;    -- Reference clock (ref_clk >> sclk)
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_i2c_peripheral;

architecture port_serial_i2c_peripheral of port_serial_i2c_peripheral is

-- Default configuration parameters:
constant CFG_DEFAULT : cfgbus_word :=
    resize(I2C_ADDR & "00000000000000000", CFGBUS_WORD_SIZE);

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 2);
signal cfg_word     : cfgbus_word := CFG_DEFAULT;
signal cfg_addr     : i2c_addr_t;
signal status_word  : cfgbus_word;

-- Control signals for the I2C interface.
signal i2c_rxdata   : i2c_data_t;
signal i2c_rxwrite  : std_logic;
signal i2c_rxstart  : std_logic;
signal i2c_rxrdreq  : std_logic;
signal i2c_rxstop   : std_logic;
signal i2c_txdata   : i2c_data_t := (others => '0');
signal i2c_txvalid  : std_logic := '0';
signal i2c_txready  : std_logic;

-- Byte transfers from SLIP interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

-- Synchronous reset signals.
signal reset_sync   : std_logic;
signal wdog_rst_p   : std_logic := '1';

begin

-- Forward clock and reset signals.
rx_data.clk     <= ref_clk;
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= status_word(7 downto 0);
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= ref_clk;
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
    out_clk     => ref_clk);

-- Optional ConfigBus interface.
-- If disabled, each setting reduces to the designated constant.
cfg_ack     <= cfgbus_merge(cfg_acks);
cfg_addr    <= cfg_word(23 downto 17);          -- I2C_ADDR

u_cfg_reg0 : cfgbus_readonly_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 0)   -- Reg0 = Status reporting
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(0),
    sync_clk    => ref_clk,
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
    REGADDR     => 2,   -- Reg2 = Address control
    WR_ATOMIC   => true,
    WR_MASK     => x"00FE0000",
    RSTVAL      => CFG_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => ref_clk,
    sync_val    => cfg_word);

-- Raw I2C interface, including address filtering.
u_i2c : entity work.io_i2c_peripheral
    port map(
    sclk_i      => sclk_i,
    sdata_o     => sdata_o,
    sdata_i     => sdata_i,
    i2c_addr    => cfg_addr,
    rx_data     => i2c_rxdata,
    rx_write    => i2c_rxwrite,
    rx_start    => i2c_rxstart,
    rx_rdreq    => i2c_rxrdreq,
    rx_stop     => i2c_rxstop,
    tx_data     => i2c_txdata,
    tx_valid    => i2c_txvalid,
    tx_ready    => i2c_txready,
    ref_clk     => ref_clk,
    reset_p     => reset_sync);

-- Detect inactive ports and clear transmit buffer.
-- (Otherwise, broadcast packets will overflow the buffer.)
p_wdog : process(ref_clk, reset_sync)
    constant TIMEOUT : integer := TIMEOUT_SEC * CLKREF_HZ;
    variable wdog_ctr : integer range 0 to TIMEOUT := TIMEOUT;
begin
    if (reset_sync = '1') then
        wdog_rst_p  <= '1';
        wdog_ctr    := TIMEOUT;
    elsif rising_edge(ref_clk) then
        wdog_rst_p  <= bool2bit(wdog_ctr = 0);
        if (i2c_rxwrite = '1' or i2c_rxrdreq = '1') then
            wdog_ctr := TIMEOUT;        -- Activity detect
        elsif (wdog_ctr > 0) then
            wdog_ctr := wdog_ctr - 1;   -- Countdown to zero
        end if;
    end if;
end process;

-- Idle token insertion and upstream flow-control.
enc_ready <= i2c_rxrdreq and not i2c_txvalid;

p_enc : process(ref_clk)
begin
    if rising_edge(ref_clk) then
        -- Update the Tx-VALID strobe (AXI flow control).
        if (reset_sync = '1') then
            i2c_txvalid <= '0';         -- Port reset
        elsif (i2c_rxrdreq = '1') then
            i2c_txvalid <= '1';         -- Request next byte
        elsif (i2c_txready = '1') then
            i2c_txvalid <= '0';         -- Byte consumed
        end if;

        -- Update the Tx-DATA byte (AXI flow control).
        if (enc_ready = '1' and enc_valid = '1') then
            i2c_txdata <= enc_data;     -- Normal byte
        elsif (enc_ready = '1' and enc_valid = '0') then
            i2c_txdata <= SLIP_FEND;    -- Filler byte
        end if;

        -- Output buffer for the ready-to-send flag.
        rts_out <= enc_valid;
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
    refclk      => ref_clk,
    reset_p     => reset_sync);

u_dec : entity work.slip_decoder
    port map (
    in_data     => i2c_rxdata,
    in_write    => i2c_rxwrite,
    out_data    => rx_data.data,
    out_write   => rx_data.write,
    out_last    => rx_data.last,
    decode_err  => rx_data.rxerr,
    refclk      => ref_clk,
    reset_p     => reset_sync);


end port_serial_i2c_peripheral;
