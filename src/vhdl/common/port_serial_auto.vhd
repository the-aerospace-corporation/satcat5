--------------------------------------------------------------------------
-- Copyright 2019-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
--
-- By default, UART baud-rate and SPI mode are fixed at build-time.
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
--  REGADDR = 2: UART baud-rate control (read-write)
--      Bit     31: Ignore external flow-control (CTS)
--      Bits 30-16: Reserved (zeros)
--      Bits 15-00: Clock divider ratio = round(CLKREF_HZ / baud_hz)
--  REGADDR = 3: SPI mode and glitch-filter control (read-write)
--      Bits 31-08: Reserved (zeros)
--      Bits 09-08: SPI mode (0 / 1 / 2 / 3)
--      Bits 07-00: Glitch filter setting (see "io_spi_peripheral")
--  REGADDR = 4: SPI/UART autodetect (read-write)
--      Bits 31-02: Reserved (zeros)
--      Bits 01-00: Interface mode
--          0x0 = Autodetect (default)
--          0x1 = SPI
--          0x2 = UART (normal)
--          0x3 = UART (swapped)
--
-- I/O is assigned as follows in each mode:
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
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_serial_auto is
    generic (
    -- Default SPI and UART parameters
    CLKREF_HZ   : positive;             -- Reference clock rate (Hz)
    SPI_GDLY    : natural := 1;         -- SPI glitch-detection threshold
    SPI_MODE    : natural := 3;         -- SPI clock phase & polarity
    UART_BAUD   : positive := 921600;   -- Default UART baud rate
    TIMEOUT_SEC : positive := 15;       -- Activity timeout, in seconds
    -- Other I/O parameters
    PULLUP_EN   : boolean := true;      -- Enable FPGA pullups on ext_pads?
    FORCE_SHDN  : boolean := false;     -- In shutdown, drive ext_pads to zero?
    -- ConfigBus device address (optional)
    DEVADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- External 4-wire interface.
    ext_pads    : inout std_logic_vector(3 downto 0);

    -- Generic internal port interface.
    rx_data     : out port_rx_m2s;  -- Data from end user to switch core
    tx_data     : in  port_tx_s2m;  -- Data from switch core to end user
    tx_ctrl     : out port_tx_m2s;  -- Flow control for tx_data

    -- Optional ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;

    -- Clock and reset
    refclk      : in  std_logic;    -- Reference clock
    reset_p     : in  std_logic);   -- Reset / shutdown
end port_serial_auto;

architecture port_serial_auto of port_serial_auto is

-- Define internal mode-detection states.
subtype mode_t is std_logic_vector(1 downto 0);
constant MODE_AUTO  : mode_t := "00";
constant MODE_SPI   : mode_t := "01";
constant MODE_UART1 : mode_t := "10";
constant MODE_UART2 : mode_t := "11";

-- Default clock-divider ratios and other settings:
constant UART_RATE_DEFAULT  : cfgbus_word :=
    i2s(clocks_per_baud_uart(CLKREF_HZ, UART_BAUD), CFGBUS_WORD_SIZE);
constant SPI_MODE_DEFAULT   : byte_t := i2s(SPI_MODE, 8);
constant SPI_GDLY_DEFAULT   : byte_t := i2s(SPI_GDLY, 8);
constant SPI_CFG_DEFAULT    : cfgbus_word :=
    resize(SPI_MODE_DEFAULT & SPI_GDLY_DEFAULT, CFGBUS_WORD_SIZE);

-- ConfigBus interface.
signal cfg_acks     : cfgbus_ack_array(0 to 4);
signal cfg_u_word   : cfgbus_word := UART_RATE_DEFAULT;
signal cfg_u_ovr    : std_logic;
signal cfg_u_rate   : unsigned(15 downto 0);
signal cfg_s_word   : cfgbus_word := SPI_CFG_DEFAULT;
signal cfg_s_mode   : integer range 0 to 3;
signal cfg_s_gdly   : byte_u;
signal status_word  : cfgbus_word;
signal detect_wrval : mode_t := MODE_AUTO;
signal detect_rdval : mode_t;
signal detect_wr_t  : std_logic := '0'; -- Toggle in CfgBus domain
signal detect_wr_s  : std_logic;        -- Strobe in RefClk domain

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
signal uart0_ctsb   : std_logic;
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
signal det_mode     : mode_t := MODE_AUTO;
signal est_rate     : port_rate_t := (others => '0');
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

-- Clock-crossing constraints.
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of detect_wrval : signal is (DEVADDR >= 0);

begin

-- Forward clock and reset signals.
rx_data.clk     <= refclk;
rx_data.rate    <= est_rate;
rx_data.status  <= status_word(7 downto 0);
rx_data.tsof    <= TSTAMP_DISABLED;
rx_data.reset_p <= codec_reset;
tx_ctrl.clk     <= refclk;
tx_ctrl.reset_p <= codec_reset;
tx_ctrl.pstart  <= '1';     -- Timestamps discarded
tx_ctrl.tnow    <= TSTAMP_DISABLED;
tx_ctrl.txerr   <= '0';     -- No error states

-- Upstream status reporting.
status_word <= (
    0 => reset_sync,
    1 => lock_spi,
    2 => lock_uart1,
    3 => lock_uart2,
    4 => uart0_ctsb,
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
cfg_u_ovr   <= cfg_u_word(31);                      -- Ignore CTS?
cfg_u_rate  <= unsigned(cfg_u_word(15 downto 0));   -- UART_RATE_DEFAULT
cfg_s_mode  <= u2i(cfg_s_word(9 downto 8));         -- SPI_MODE
cfg_s_gdly  <= unsigned(cfg_s_word(7 downto 0));    -- SPI_GDLY

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
    REGADDR     => 2,   -- Reg2 = UART control
    WR_ATOMIC   => true,
    WR_MASK     => x"8000FFFF",
    RSTVAL      => UART_RATE_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(2),
    sync_clk    => refclk,
    sync_val    => cfg_u_word);

u_cfg_reg3 : cfgbus_register_sync
    generic map(
    DEVADDR     => DEVADDR,
    REGADDR     => 3,   -- Reg3 = SPI control
    WR_ATOMIC   => true,
    WR_MASK     => cfgbus_mask_lsb(10),
    RSTVAL      => SPI_CFG_DEFAULT)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(3),
    sync_clk    => refclk,
    sync_val    => cfg_s_word);

p_cfg_reg4 : process(cfg_cmd.clk)
    -- Reg4 = SPI/UART autodetect (read/write).
    constant REGADDR : natural := 4;
begin
    if rising_edge(cfg_cmd.clk) then
        -- Respond to ConfigBus writes.
        if (cfg_cmd.reset_p = '1') then
            -- ConfigBus reset reverts setting to autodetect mode.
            -- Otherwise, the setting persists across port reset.
            detect_wrval <= MODE_AUTO;
        elsif cfgbus_wrcmd(cfg_cmd, DEVADDR, REGADDR) then
            -- Mode change triggered by ConfigBus command.
            detect_wrval <= cfg_cmd.wdata(1 downto 0);
            detect_wr_t  <= not detect_wr_t;
        end if;

        -- Respond to ConfigBus reads:
        if cfgbus_rdcmd(cfg_cmd, DEVADDR, REGADDR) then
            cfg_acks(4) <= cfgbus_reply(resize(detect_rdval, 32));
        else
            cfg_acks(4) <= cfgbus_idle;
        end if;
    end if;
end process;

-- Clock-domain transitions relating to the ConfigBus interface.
u_detect_wr : sync_toggle2pulse
    port map(
    in_toggle   => detect_wr_t,
    out_strobe  => detect_wr_s,
    out_clk     => refclk);

u_detect_rd : sync_buffer_slv
    generic map(IO_WIDTH => det_mode'length)
    port map(
    in_flag     => det_mode,
    out_flag    => detect_rdval,
    out_clk     => cfg_cmd.clk);

-- Instantiate each top-level bidirectional pin.
gen_pads : for n in ext_pads'range generate
    u_bidir : bidir_io
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
u_spi : entity work.io_spi_peripheral
    generic map (
    IDLE_BYTE   => SLIP_FEND)
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
    cfg_mode    => cfg_s_mode,
    cfg_gdly    => cfg_s_gdly,
    refclk      => refclk);

u_uart0 : entity work.io_uart_tx
    port map (
    uart_txd    => uart0_txd,
    tx_data     => enc_data,
    tx_valid    => uart0_valid,
    tx_ready    => uart0_ready,
    rate_div    => cfg_u_rate,
    refclk      => refclk,
    reset_p     => reset_sync);

u_uart1 : entity work.io_uart_rx
    generic map (
    DEBUG_WARN  => false)
    port map (
    uart_rxd    => uart1_rxd,
    rx_data     => uart1_data,
    rx_write    => uart1_write,
    rate_div    => cfg_u_rate,
    refclk      => refclk,
    reset_p     => reset_sync);

u_uart2 : entity work.io_uart_rx
    generic map (
    DEBUG_WARN  => false)
    port map (
    uart_rxd    => uart2_rxd,
    rx_data     => uart2_data,
    rx_write    => uart2_write,
    rate_div    => cfg_u_rate,
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
        -- Update the active mode?
        if (reset_sync = '1' or wdog_rst_p = '1' or detect_wr_s = '1') then
            -- Reset or ConfigBus command, revert to specified mode.
            -- (The commanded mode persists across a port reset.)
            det_mode <= detect_wrval;
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

        -- Reset SLIP encoder and decoder?
        if (reset_sync = '1' or detect_wr_s = '1') then
            -- Global reset or command -> SLIP reset.
            codec_reset <= '1';
        elsif (wdog_rst_p = '1') then
            -- Activity timeout -> Reset only in AUTO mode.
            codec_reset <= bool2bit(detect_wrval = MODE_AUTO);
        elsif (lock_any = '1') then
            -- Exiting AUTO mode -> Release from reset.
            codec_reset <= '0';
        end if;

        -- Drive the SLIP decoder stream and choose estimated rate.
        if (det_mode = MODE_SPI) then
            est_rate  <= get_rate_word(10);
            dec_data  <= spi_rx_data;
            dec_write <= spi_rx_write;
        elsif (det_mode = MODE_UART1) then
            est_rate  <= get_rate_word(1);
            dec_data  <= uart1_data;
            dec_write <= uart1_write;
        elsif (det_mode = MODE_UART2) then
            est_rate  <= get_rate_word(1);
            dec_data  <= uart2_data;
            dec_write <= uart2_write;
        else
            est_rate  <= (others => '0');
            dec_data  <= SLIP_FEND;
            dec_write <= lock_any;
        end if;
    end if;
end process;

-- Map SLIP encoder stream to the active device.
-- (Block any outgoing data until we determine port type,
--  and respect flow-control flags for outgoing UART data.)
spi_tx_valid <= enc_valid and bool2bit(det_mode = MODE_SPI);
uart0_ctsb   <= '0' when (cfg_u_ovr = '1')
           else uart1_ctsb when (det_mode = MODE_UART1)
           else uart2_ctsb when (det_mode = MODE_UART2) else '1';
uart0_valid  <= enc_valid and not uart0_ctsb;
enc_ready    <= spi_tx_ready when (det_mode = MODE_SPI)
           else (uart0_ready and not uart0_ctsb);

-- Detect inactive ports and clear transmit buffer.
-- (Otherwise, broadcast packets will overflow the buffer.)
p_wdog : process(refclk)
    constant TIMEOUT : integer := TIMEOUT_SEC * CLKREF_HZ;
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
