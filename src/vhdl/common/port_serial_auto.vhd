--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Ethernet-over-Serial, auto-sensing SPI/UART port
--
-- This module implements a 4-wire serial port that automatically
-- changes between three possible modes:
--   * SPI, normal pinout
--   * UART, Tx/Rx normal
--   * UART, Tx/Rx swapped
--
-- The block does do not attempt to auto-sense the SPI mode (CPOL, CPHA)
-- or the UART baud rate.  These parameters are fixed at build time.
--
-- On reset, or after an idle period of a few seconds, it reverts to
-- the auto-detecting mode.  Once any of the interfaces receives a
-- SLIP idle character (0xC0), that mode is selected and locked-in.
-- The mode can also be set by external command, if desired.
--
-- I/O is assigned as follows in each mode:
--
--     Idx  Name         Pin 0       Pin 1       Pin 2       Pin 3
--     N/A  Shutdown     Pullup*     Pullup*     Pullup*     Pullup*
--     (0)  Auto         Pullup      Pullup      Pullup      Pullup
--     (1)  SPI          CSb (E2S)   MOSI (E2S)  MISO (S2E)  SCK (E2S)
--     (2)  UART (norm)  RTSb (E2S)  RxD (S2E)   TxD (E2S)   CTSb (S2E)
--     (3)  UART (swap)  CTSb (S2E)  TxD (E2S)   RxD (S2E)   RTSb (E2S)
--
-- Note: Weak pullup resistors are required in auto-detect mode.  Default
--       configuration enables the FPGA's built-in pullups (PULLUP_EN), but
--       this can be bypassed safely if external pullups are provided.
--       While in shutdown, all pins can remain in pullup mode (default),
--       or they can be forcibly driven to logic zero (FORCE_ZERO) to
--       prevent parasitic power leaching.
-- Note: "E2S" = Endpoint to switch (i.e., FPGA input)
--       "S2E" = Switch to endpoint (i.e., FPGA output)
-- Note: In the table above, input/output labels refer to the switch FPGA.
--       However, naming conventions for UART signals treat the FPGA as DCE,
--       per RS-232 convention, so they are named with respect to the remote
--       endpoint (DTE).  See discussion under port_serial_uart_4wire.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;  -- For byte_t
use     work.switch_types.all;
use     work.synchronization.all;

entity port_serial_auto is
    generic (
    CLKREF_HZ   : integer;              -- Reference clock rate (Hz)
    SPI_MODE    : integer := 3;         -- SPI clock phase & polarity
    UART_BAUD   : integer := 921600;    -- UART baud rate
    PULLUP_EN   : boolean := true;      -- Enable FPGA pullups on ext_pads?
    FORCE_SHDN  : boolean := false;     -- In shutdown, drive ext_pads to zero?
    START_TYPE  : integer := 0);        -- Port type on startup (0 = auto)
    port (
    -- External 4-wire interface.
    ext_pads    : inout std_logic_vector(3 downto 0);

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_m2s;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_s2m;  -- Flow control for tx_data

    -- Manual configuration interface (optional)
    cfg_mode    : in  integer range 0 to 3 := 0;
    cfg_write   : in  std_logic := '0';

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_auto;

architecture port_serial_auto of port_serial_auto is

-- Define mode configuration codes.
subtype mode_t is integer range 0 to 3;
constant MODE_AUTO  : mode_t := 0;
constant MODE_SPI   : mode_t := 1;
constant MODE_UART1 : mode_t := 2;
constant MODE_UART2 : mode_t := 3;

-- Top-level bidirectional pins.
signal ext_din      : std_logic_vector(3 downto 0);
signal ext_dout     : std_logic_vector(3 downto 0);
signal ext_tris     : std_logic_vector(3 downto 0);

-- Raw interfaces (one SPI, one Tx UART, two Rx UART)
signal spi_csb      : std_logic;
signal spi_sclk     : std_logic;
signal spi_sdi      : std_logic;
signal spi_sdo      : std_logic;
signal spi_sdt      : std_logic;
signal uart0_txd    : std_logic;
signal uart1_rxd    : std_logic;
signal uart2_rxd    : std_logic;
signal uart0_rtsb   : std_logic;
signal uart1_ctsb   : std_logic;
signal uart2_ctsb   : std_logic;

-- Data interfaces for each of the above.
signal spi_tx_valid : std_logic;
signal spi_tx_ready : std_logic;
signal spi_rx_data  : byte_t;
signal spi_rx_write : std_logic;
signal uart0_valid  : std_logic;
signal uart0_ready  : std_logic;
signal uart1_data   : byte_t;
signal uart1_write  : std_logic;
signal uart2_data   : byte_t;
signal uart2_write  : std_logic;

-- Mode detection state machine.
signal det_mode     : mode_t := START_TYPE;
signal lock_any     : std_logic := '0';
signal lock_spi     : std_logic := '0';
signal lock_uart1   : std_logic := '0';
signal lock_uart2   : std_logic := '0';
signal wdog_rst_p   : std_logic := '1';

-- SLIP encoder and decoder.
signal reset_sync   : std_logic;
signal codec_reset  : std_logic := '1';
signal dec_data     : byte_t := SLIP_FEND;
signal dec_write    : std_logic := '0';
signal enc_data     : byte_t;
signal enc_valid    : std_logic;
signal enc_ready    : std_logic;

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.reset_p <= codec_reset;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= codec_reset;
tx_ctrl.txerr   <= '0';     -- No error states

-- Synchronize the external reset signal.
u_rsync : sync_reset
    port map(
    in_reset_p  => reset_p,
    out_reset_p => reset_sync,
    out_clk     => refclk);

-- Instantiate each top-level bidirectional pin.
gen_pads : for n in ext_pads'range generate
    u_bidir : entity work.bidir_io
        generic map (EN_PULLUP => PULLUP_EN)
        port map(
        io_pin  => ext_pads(n),
        d_in    => ext_din(n),
        d_out   => ext_dout(n),
        t_en    => ext_tris(n));
end generate;

-- Map logical signals to output signals.
-- If FORCE_SHDN is enabled, drive all pins to zero while in reset.
-- Otherwise, assign control of each pin according to detected state.
ext_dout(0) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else uart0_rtsb;
ext_dout(1) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else spi_sdo when (det_mode = MODE_SPI) else uart0_txd;
ext_dout(2) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else spi_sdo when (det_mode = MODE_SPI) else uart0_txd;
ext_dout(3) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else uart0_rtsb;

ext_tris(0) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else bool2bit(det_mode /= MODE_UART2);
ext_tris(1) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else bool2bit(det_mode /= MODE_UART1);
ext_tris(2) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else spi_sdt when (det_mode = MODE_SPI)
          else bool2bit(det_mode /= MODE_UART2);
ext_tris(3) <= '0' when (FORCE_SHDN and reset_sync = '1')
          else bool2bit(det_mode /= MODE_UART1);

-- Map input pins to logical signals.
spi_csb      <= ext_din(0);
spi_sclk     <= ext_din(3);
spi_sdi      <= ext_din(1);
uart1_rxd    <= ext_din(2);
uart2_rxd    <= ext_din(1);

uart0_rtsb <= not enc_valid;

u_ctsb1 : sync_buffer
    port map(
    in_flag  => ext_din(0),
    out_flag => uart1_ctsb,
    out_clk  => refclk);

u_ctsb2 : sync_buffer
    port map(
    in_flag  => ext_din(3),
    out_flag => uart2_ctsb,
    out_clk  => refclk);

-- Raw interfaces (one SPI, one Tx UART, two Rx UART)
u_spi : entity work.io_spi_clkin
    generic map (
    IDLE_BYTE   => SLIP_FEND,
    SPI_MODE    => SPI_MODE)
    port map (
    spi_csb     => spi_csb,
    spi_sclk    => spi_sclk,
    spi_sdi     => spi_sdi,
    spi_sdo     => spi_sdo,
    spi_sdt     => spi_sdt,
    tx_data     => enc_data,
    tx_valid    => spi_tx_valid,
    tx_ready    => spi_tx_ready,
    rx_data     => spi_rx_data,
    rx_write    => spi_rx_write,
    refclk      => refclk);

u_uart0 : entity work.io_uart_tx
    generic map (
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => UART_BAUD)
    port map (
    uart_txd    => uart0_txd,
    tx_data     => enc_data,
    tx_valid    => uart0_valid,
    tx_ready    => uart0_ready,
    refclk      => refclk,
    reset_p     => reset_sync);

u_uart1 : entity work.io_uart_rx
    generic map (
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => UART_BAUD,
    DEBUG_WARN  => false)
    port map (
    uart_rxd    => uart1_rxd,
    rx_data     => uart1_data,
    rx_write    => uart1_write,
    refclk      => refclk,
    reset_p     => reset_sync);

u_uart2 : entity work.io_uart_rx
    generic map (
    CLKREF_HZ   => CLKREF_HZ,
    BAUD_HZ     => UART_BAUD,
    DEBUG_WARN  => false)
    port map (
    uart_rxd    => uart2_rxd,
    rx_data     => uart2_data,
    rx_write    => uart2_write,
    refclk      => refclk,
    reset_p     => reset_sync);

-- Mode detection state machine.
lock_any    <= lock_spi or lock_uart1 or lock_uart2;
lock_spi    <= bool2bit(spi_rx_write = '1' and spi_rx_data = SLIP_FEND);
lock_uart1  <= bool2bit(uart1_write = '1' and uart1_data = SLIP_FEND);
lock_uart2  <= bool2bit(uart2_write = '1' and uart2_data = SLIP_FEND);

p_detect : process(refclk)
begin
    if rising_edge(refclk) then
        -- Update the active mode.
        if (cfg_write = '1') then
            -- Direct command (overrides watchdog)
            det_mode <= cfg_mode;
        elsif (reset_sync = '1' or wdog_rst_p = '1') then
            -- Global or watchdog reset
            det_mode <= START_TYPE;
        elsif (det_mode = MODE_AUTO) then
            -- Autodetect mode: Accept the first SLIP frame token.
            if (lock_spi = '1') then
                det_mode <= MODE_SPI;
            elsif (lock_uart1 = '1') then
                det_mode <= MODE_UART1;
            elsif (lock_uart2 = '1') then
                det_mode <= MODE_UART2;
            end if;
        end if;

        -- Reset SLIP encoder and decoder while in AUTO mode.
        if (reset_sync = '1' or wdog_rst_p = '1') then
            codec_reset <= '1';
        elsif (lock_any = '1') then
            codec_reset <= '0';
        end if;

        -- Drive the SLIP decoder stream.
        if (det_mode = MODE_SPI) then
            dec_data  <= spi_rx_data;
            dec_write <= spi_rx_write;
        elsif (det_mode = MODE_UART1) then
            dec_data  <= uart1_data;
            dec_write <= uart1_write;
        elsif (det_mode = MODE_UART2) then
            dec_data  <= uart2_data;
            dec_write <= uart2_write;
        else
            dec_data  <= SLIP_FEND;
            dec_write <= lock_any;
        end if;
    end if;
end process;

-- Map SLIP encoder stream to the active device.
-- (Block any outgoing data until we determine port type,
--  and respect flow-control flags for outgoing UART data.)
spi_tx_valid <= enc_valid and bool2bit(det_mode = MODE_SPI);
uart0_valid  <= (enc_valid and not uart1_ctsb) when (det_mode = MODE_UART1)
           else (enc_valid and not uart2_ctsb) when (det_mode = MODE_UART2) else '0';
enc_ready    <= (uart0_ready and not uart1_ctsb) when (det_mode = MODE_UART1)
           else (uart0_ready and not uart2_ctsb) when (det_mode = MODE_UART2)
           else spi_tx_ready when (det_mode = MODE_SPI) else '1';

-- Detect inactive ports and clear transmit buffer.
-- (Otherwise, broadcast packets will overflow the buffer.)
p_wdog : process(refclk)
    constant TIMEOUT : integer := 2*CLKREF_HZ;
    variable wdog_ctr : integer range 0 to TIMEOUT := TIMEOUT;
begin
    if rising_edge(refclk) then
        wdog_rst_p  <= bool2bit(wdog_ctr = 0);
        if (reset_sync = '1') then
            wdog_ctr := TIMEOUT;        -- Port reset/shutdown
        elsif ((det_mode = MODE_AUTO) or (dec_write = '1')) then
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
    out_valid   => enc_valid,
    out_data    => enc_data,
    out_ready   => enc_ready,
    refclk      => refclk,
    reset_p     => codec_reset);

u_dec : entity work.slip_decoder
    port map (
    in_data     => dec_data,
    in_write    => dec_write,
    out_data    => rx_data.data,
    out_write   => rx_data.write,
    out_last    => rx_data.last,
    decode_err  => rx_data.rxerr,
    refclk      => refclk,
    reset_p     => codec_reset);

end port_serial_auto;
