--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet-over-Serial I2C transceiver port (controller)
--
-- This module implements a serial-over-Ethernet port with a two-wire I2C
-- interface, including SLIP encoding and decoding.  This variant acts as
-- an I2C controller (i.e., the nominal source of the I2C clock.)
--
-- Use of this block is not recommended for normal SatCat5 switches, but
-- it may be required for switch-to-switch links.
--
-- The I2C clock runs more-or-less contiguously.  The block will always
-- attempt to transmit (multi-byte write command with address then data)
-- when frame data is available to send; otherwise it will poll for
-- received data (multi-byte read command with address).  An optional
-- "pause" flag will stop transactions at the next convenient boundary.
--
-- By default, I2C clock-divider and address are fixed at build-time.
-- If enabled, an optional ConfigBus interface can be used to set a
-- different configuration at runtime and optionally report status
-- information.  (Connecting the read-reply interface is recommended,
-- but not required for routine operation.)
--
-- Generally, the top-level should instantiate a bidirectional buffer, to
-- connect SCL and SDA to their respective I/O pads.  For more details,
-- refer to "io_i2c_controller.vhd".
--
-- If enabled, the ConfigBus interface uses three registers:
--  REGADDR = 0: Port status (read-only)
--      Bits 31-08: Reserved
--      Bits 07-00: Read the 8-bit status word (i.e., rx_data.status)
--  REGADDR = 1: Reference clock rate (read-only)
--      Bits 31-00: Report reference clock rate, in Hz. (i.e., CLFREF_HZ)
--  REGADDR = 2: I2C address and clock-rate control (read-write)
--      Bits 31-24: Reserved (zeros)
--      Bits 23-17: Remote I2C device address
--      Bits 16-08: Reserved (zeros)
--      Bits 11-00: Clock divider ratio = round(0.25 * CLKREF_HZ / baud_hz) - 1
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_reset;
use     work.eth_frame_common.all;
use     work.i2c_constants.all;         -- io_i2c_controller.vhd
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_serial_i2c_controller is
    generic (
    -- Default settings for this port.
    I2C_ADDR    : i2c_addr_t;           -- Remote I2C device address
    CLKREF_HZ   : positive;             -- Reference clock rate (Hz)
    BAUD_HZ     : positive := 400_000;  -- I2C baud rate
    -- ConfigBus device address (optional)
    DEVADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- External I2C interface.
    -- Note: Top level should instantiate tri-state buffer.
    -- Note: sclk_i is required for clock-stretching, otherwise optional.
    sclk_o      : out std_logic;
    sclk_i      : in  std_logic := '1';
    sdata_o     : out std_logic;
    sdata_i     : in  std_logic;

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
    ref_clk     : in  std_logic;    -- Reference clock (ref_clk >> sclk)
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_i2c_controller;

architecture port_serial_i2c_controller of port_serial_i2c_controller is

-- Default configuration parameters:
constant REF_CLKDIV : i2c_clkdiv_t :=
    i2c_get_clkdiv(CLKREF_HZ, BAUD_HZ);
constant PAD_CLKDIV : std_logic_vector(16 downto 0) :=
    std_logic_vector(resize(REF_CLKDIV, 17));
constant CFG_DEFAULT : cfgbus_word :=
    resize(I2C_ADDR & PAD_CLKDIV, CFGBUS_WORD_SIZE);

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 2);
signal cfg_word     : cfgbus_word := CFG_DEFAULT;
signal cfg_addr     : i2c_addr_t;
signal cfg_clkdiv   : i2c_clkdiv_t;
signal status_word  : cfgbus_word;

-- Control signals for the I2C interface.
signal i2c_opcode   : i2c_cmd_t := CMD_START;
signal i2c_txdata   : i2c_data_t := (others => '0');
signal i2c_txvalid  : std_logic := '0';
signal i2c_txready  : std_logic;
signal i2c_txwren   : std_logic := '0';
signal i2c_rxdata   : i2c_data_t;
signal i2c_rxwrite  : std_logic;
signal i2c_noack    : std_logic;
signal read_idle    : std_logic := '0';
signal read_fend    : std_logic := '0';
signal write_next   : std_logic := '0';
signal reset_sync   : std_logic;

-- Byte transfers from raw I2C interface.
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

begin

-- Forward clock and reset signals.
rx_data.clk     <= ref_clk;
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= status_word(7 downto 0);
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= reset_sync;
tx_ctrl.clk     <= ref_clk;
tx_ctrl.reset_p <= reset_sync;
tx_ctrl.pstart  <= '1';     -- Timestamps discarded
tx_ctrl.tnow    <= TSTAMP_DISABLED;
tx_ctrl.txerr   <= '0';     -- No Tx error states

-- Upstream status reporting.
status_word <= (
    0 => reset_sync,
    1 => i2c_noack,
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
cfg_clkdiv  <= unsigned(cfg_word(11 downto 0)); -- REF_CLKDIV

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
    REGADDR     => 2,   -- Reg2 = Rate and address control
    WR_ATOMIC   => true,
    WR_MASK     => x"00FE0FFF",
    RSTVAL      => CFG_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => ref_clk,
    sync_val    => cfg_word);

-- Raw I2C interface
u_i2c : entity work.io_i2c_controller
    port map(
    sclk_o      => sclk_o,
    sclk_i      => sclk_i,
    sdata_o     => sdata_o,
    sdata_i     => sdata_i,
    cfg_clkdiv  => cfg_clkdiv,
    tx_opcode   => i2c_opcode,
    tx_data     => i2c_txdata,
    tx_valid    => i2c_txvalid,
    tx_ready    => i2c_txready,
    rx_data     => i2c_rxdata,
    rx_write    => i2c_rxwrite,
    bus_noack   => i2c_noack,
    ref_clk     => ref_clk,
    reset_p     => reset_sync);

-- State machine for generating I2C command sequence:
--  * Each write burst consists of START + address/W + up to NMAX written bytes.
--  * Each read burst consists of START + address/R + up to NMAX read bytes.
--  * If the PAUSE flag is asserted, stop the current burst and revert to idle.
--  * If there is data waiting to be sent, alternate write/read bursts.
--  * Otherwise, continue to issue read bursts.
p_ctrl : process(ref_clk)
    constant NMAX : positive := 32; -- Max transaction size (mostly arbitrary)
    type ctrl_state_t is (STATE_IDLE, STATE_START, STATE_WRITE, STATE_READ, STATE_STOP);
    variable ctrl_state : ctrl_state_t := STATE_IDLE;
    variable ctrl_count : integer range 0 to NMAX-1 := 0;
begin
    if rising_edge(ref_clk) then
        -- Upstream flow-control:
        i2c_txwren <= bool2bit(ctrl_state = STATE_WRITE) and not ext_pause;

        -- Simplified logic for the next data byte:
        if (i2c_txvalid = '0' or i2c_txready = '1') then
            if (ctrl_state /= STATE_START) then
                i2c_txdata <= enc_data;         -- Normal data
            elsif (enc_valid = '1' and write_next = '1') then
                i2c_txdata <= cfg_addr & '0';   -- Address + WRITE
            else
                i2c_txdata <= cfg_addr & '1';   -- Address + READ
            end if;
        end if;

        -- Detect an idle read (two consecutive SLIP_FEND tokens).
        if (reset_sync = '1') then
            read_idle   <= '0';
            read_fend   <= '0';
        elsif (i2c_rxwrite = '1') then
            read_idle   <= bool2bit(i2c_rxdata = SLIP_FEND) and read_fend;
            read_fend   <= bool2bit(i2c_rxdata = SLIP_FEND);
        end if;

        -- Decide the next opcode and update control state:
        if (reset_sync = '1') then
            i2c_opcode  <= CMD_START;
            i2c_txvalid <= '0';
            write_next  <= '0';
            ctrl_state  := STATE_IDLE;
            ctrl_count  := 0;
        elsif (i2c_txvalid = '0' or i2c_txready = '1') then
            if (ctrl_state = STATE_IDLE) then
                -- When ready, open new transaction with START token.
                i2c_opcode  <= CMD_START;
                ctrl_count  := 0;
                if (ext_pause = '1') then
                    i2c_txvalid <= '0';
                else
                    i2c_txvalid <= '1';
                    ctrl_state  := STATE_START;
                end if;
            elsif (ctrl_state = STATE_READ and (ext_pause = '1' or read_idle = '1' or ctrl_count = NMAX-1)) then
                -- Special case for clean termination of READ burst.
                -- (Must issue RXFINAL opcode before sending STOP token.)
                i2c_opcode  <= CMD_RXFINAL;
                i2c_txvalid <= '1';
                ctrl_state  := STATE_STOP;
                ctrl_count  := 0;
            elsif (ctrl_state = STATE_STOP or ext_pause = '1') then
                -- End of burst, send STOP token and revert to idle.
                i2c_opcode  <= CMD_STOP;
                i2c_txvalid <= '1';
                ctrl_state  := STATE_IDLE;
                ctrl_count  := 0;
            elsif (ctrl_state = STATE_START) then
                -- Send the address with READ or WRITE flag.
                i2c_opcode  <= CMD_TXBYTE;
                i2c_txvalid <= '1';
                ctrl_count  := 0;
                if (enc_valid = '1' and write_next = '1') then
                    ctrl_state := STATE_WRITE;
                    write_next <= '0';
                else
                    ctrl_state := STATE_READ;
                    write_next <= '1';
                end if;
            elsif (ctrl_state = STATE_WRITE) then
                -- Send the next Tx-byte.
                i2c_opcode  <= CMD_TXBYTE;
                i2c_txvalid <= '1';
                -- End of transaction?
                if (enc_data = SLIP_FEND or ctrl_count = NMAX-1) then
                    ctrl_state := STATE_STOP;
                    ctrl_count := 0;
                else
                    ctrl_count := ctrl_count + 1;
                end if;
            elsif (ctrl_state = STATE_READ) then
                -- Request the next Rx-byte.
                i2c_txvalid <= '1';
                i2c_opcode <= CMD_RXBYTE;
                ctrl_count := ctrl_count + 1;
            end if;
        end if;
    end if;
end process;

-- SLIP encoder (for Tx) and decoder (for Rx)
enc_ready <= i2c_txready and i2c_txwren;

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

end port_serial_i2c_controller;
