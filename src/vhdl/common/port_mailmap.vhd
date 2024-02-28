--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- "MailMap" port for use with ConfigBus
--
-- This block acts as a virtual internal port, connecting an Ethernet
-- switch core to a memory-mapped interface suitable for integrating
-- a soft-core microcontroller. (e.g., LEON, Microblaze, etc.) or
-- any other ConfigBus host.
--
-- It is similar to "port_mailbox" but makes the entire frame available
-- as a memory-mapped array, rather than reading and writing a byte at
-- at a time through a single register.  This requires additional BRAM
-- but offers substantially improved performance.
--
-- On the software side, the memory-mapped array can be treated as any
-- regular C/C++ data structure.  Byte-enable strobes are followed.
-- The array can be configured for big-endian or little-endian mode.
--
-- Jumbo frames are not supported.  If received, they are discarded.
--
-- After sending each frame, that buffer is "busy" as it is tranferred
-- to the underlying Ethernet port.  This occurs at a fixed rate of
-- 1 byte per clock cycle; for a 100 MHz clock, a max-length frame
-- is transferred in just 15 microseconds.  During this phase, any
-- writes to the transmit buffer are ignored.
--
-- The transmit buffer can be configured as read-write (default) or
-- write-only.  The latter may save resources on some FPGA platforms,
-- depending on whether dual-port block-RAM can simultaneously read
-- or write on a single port.
--
-- Enabling PTP (i.e., CFG_CLK_HZ and VCONFIG configured), also enables
-- the real-time clock (RTC) output and several ConfigBus registers:
--  * Control for the RTC (see "ptp_realtime.vhd")
--  * Precise Tx and Rx timestamps (see "ptp_realsof.vhd")
--  * Freezing the current time for one-step SYNC messages.
--
-- To send a one-step PTP SYNC message:
--  * Write Reg 1022 = 0x01 to freeze the current time (RTC and TSOF).
--  * Read Reg 1012 through 1015 and copy that timestamp into the SYNC
--    message.  (Note: RTC-subns sets initial value of correctionField.)
--  * Write the message contents normally (copy data, then Reg 1023).
-- By freezing the TSOF reported to the SatCat5 switch, the unknown delay from
-- the freeze until the message is sent is added to the PTP "correctionField".
--
-- Memory is mapped as follows:
--  * Reg 0-399:    Received frame contents (read-only)
--  * Reg 400-505:  Reserved
--  * Reg 506-509:  Timestamp of most recent received frame (PTP, read-only)
--  * Reg 510:      Interrupt control (see cfgbus_common::cfgbus_interrupt)
--  * Reg 511:      Received frame control (read-write):
--                  Read = Current frame length, in bytes. (0 = Empty)
--                  Write = Discard buffer and begin reading next frame.
--  * Reg 512-911:  Transmit frame buffer (read-write or write-only)
--  * Reg 912-1011: Reserved
--  * Reg 1012-17:  Real-time clock control (PTP, read-write)
--  * Reg 1018-21:  Timestamp of most recent sent frame (PTP, read-only)
--  * Reg 1022:     Read: PTP status register
--                      Bit 31: PTP enabled?
--                      Bit 30: Vernier locked?
--                      Bit 00: One-step frozen?
--                  Write: One-step freeze (1 to freeze, 0 for normal operation)
--  * Reg 1023:     Transmit frame control (read-write)
--                  Write = Set frame length to be sent, in bytes.
--                  Read = Busy (1) or idle (0).
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.common_primitives.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.all;

entity port_mailmap is
    generic (
    DEV_ADDR    : integer;              -- Peripheral address (-1 = any)
    BIG_ENDIAN  : boolean := false;     -- Big-endian byte order?
    TX_READBACK : boolean := true;      -- Enable readback of Tx buffer?
    MIN_FRAME   : natural := 64;        -- Minimum output frame size
    APPEND_FCS  : boolean := true;      -- Append FCS to each sent frame?
    CHECK_FCS   : boolean := false;     -- Always check FCS for each frame?
    STRIP_FCS   : boolean := true;      -- Remove FCS from received frames?
    CFG_CLK_HZ  : natural := 0;         -- ConfigBus clock rate (for PTP)
    VCONFIG     : vernier_config := VERNIER_DISABLED);
    port (
    -- Internal Ethernet port.
    rx_data     : out port_rx_m2s;
    tx_data     : in  port_tx_s2m;
    tx_ctrl     : out port_tx_m2s;

    -- Global reference for PTP timestamps, if enabled.
    ref_time    : in  port_timeref := PORT_TIMEREF_NULL;
    rtc_time    : out ptp_time_t;

    -- ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack);
end port_mailmap;

architecture port_mailmap of port_mailmap is

-- Each BRAM is 512 words x 32 bits = 2 kiB.
constant RAM_WORDS : integer := 512;
constant RAM_BYTES : integer := 4;
constant RAM_ADDRW : integer := log2_ceil(RAM_WORDS);
subtype ram_addr is unsigned(RAM_ADDRW-1 downto 0);
subtype ram_bidx is integer range 0 to RAM_BYTES-1;
subtype len_word is unsigned(10 downto 0);

-- Convert sequential byte-index to word-address and lane-index.
function get_addr(len : len_word) return ram_addr is
    constant idx : natural := to_integer(len) / RAM_BYTES;
begin
    return to_unsigned(idx mod RAM_WORDS, RAM_ADDRW);
end function;

function get_lane(len : len_word) return ram_bidx is
    constant idx : natural := to_integer(len);
begin
    if (BIG_ENDIAN) then
        return (RAM_BYTES-1) - (idx mod RAM_BYTES);
    else
        return (idx mod RAM_BYTES);
    end if;
end function;

-- Internal reset signal
signal port_areset  : std_logic;
signal port_reset_p : std_logic;

-- Precision timestamps
constant PTP_ENABLE : boolean := (CFG_CLK_HZ > 0 and VCONFIG.input_hz > 0);
constant CRC_ENABLE : boolean := CHECK_FCS or PTP_ENABLE;
signal lcl_tsof     : tstamp_t := TSTAMP_DISABLED;
signal lcl_tnow     : tstamp_t := TSTAMP_DISABLED;
signal lcl_tvalid   : std_logic := '0';
signal rtc_tnow     : ptp_time_t := PTP_TIME_ZERO;
signal rtc_freeze   : std_logic := '0';     -- Strobe
signal rtc_frozen   : std_logic := '0';     -- Persistent flag
signal rtc_status   : cfgbus_word := (others => '0');

-- Receive datapath and control.
signal rx_raw_data  : byte_t;
signal rx_raw_last  : std_logic;
signal rx_raw_valid : std_logic;
signal rx_raw_ready : std_logic;
signal rx_raw_write : std_logic;
signal rx_crc_data  : byte_t;
signal rx_crc_last  : std_logic;
signal rx_crc_error : std_logic;
signal rx_crc_valid : std_logic;
signal rx_crc_ready : std_logic;
signal rx_adj_data  : byte_t;
signal rx_adj_last  : std_logic;
signal rx_adj_error : std_logic;
signal rx_adj_valid : std_logic;
signal rx_adj_ready : std_logic;
signal rx_adj_write : std_logic;
signal rx_ctrl_wren : cfgbus_wstrb := (others => '0');
signal rx_ctrl_len  : len_word := (others => '0');
signal rx_ctrl_rcvd : std_logic := '0';
signal rx_wr_addr   : ram_addr;

-- Transmit datapath and control.
signal tx_ctrl_len  : len_word := (others => '0');
signal tx_ctrl_busy : std_logic := '0';
signal tx_rd_data   : cfgbus_word := (others => '0');
signal tx_rd_addr   : ram_addr := (others => '0');
signal tx_rd_bidx   : ram_bidx := 0;
signal tx_rd_last   : std_logic := '0';
signal tx_rd_next   : std_logic := '0';
signal tx_fifo_data : byte_t := (others => '0');
signal tx_fifo_last : std_logic := '0';
signal tx_fifo_wr   : std_logic := '0';
signal tx_fifo_ok   : std_logic;
signal tx_raw_data  : byte_t := (others => '0');
signal tx_raw_last  : std_logic := '0';
signal tx_raw_valid : std_logic := '0';
signal tx_raw_ready : std_logic;
signal tx_adj_data  : byte_t;
signal tx_adj_last  : std_logic;
signal tx_adj_valid : std_logic;
signal tx_adj_ready : std_logic;
signal tx_adj_write : std_logic;

-- ConfigBus interface.
signal cfg_addr     : ram_addr;
signal cfg_wren     : std_logic;
signal cfg_wstrb    : cfgbus_wstrb;
signal cfg_txdata   : cfgbus_word := (others => '0');
signal cfg_rxdata   : cfgbus_word := (others => '0');
signal cfg_status   : cfgbus_word := (others => '0');
signal cfg_txread   : std_logic := '0';
signal cfg_rxread   : std_logic := '0';
signal cfg_regread  : std_logic := '0';
signal cfg_clr_rx   : std_logic := '0';
signal cfg_send_tx  : std_logic := '0';
signal cfg_send_len : len_word := (others => '0');
signal irq_toggle   : std_logic := '0';
signal cfg_acks     : cfgbus_ack_array(0 to 4) := (others => cfgbus_idle);

begin

-- Data coming from the Ethernet switch. (Note Tx/Rx swap)
rx_raw_data     <= tx_data.data;
rx_raw_last     <= tx_data.last;
rx_raw_valid    <= tx_data.valid;
rx_raw_write    <= rx_raw_valid and rx_raw_ready;
tx_ctrl.ready   <= rx_raw_ready;
tx_ctrl.clk     <= cfg_cmd.clk;
tx_ctrl.pstart  <= rx_adj_ready and not rx_adj_valid;
tx_ctrl.tnow    <= lcl_tnow;
tx_ctrl.txerr   <= '0';
tx_ctrl.reset_p <= port_reset_p;

-- Hold port reset at least N clock cycles.
u_rst : sync_reset
    port map(
    in_reset_p  => cfg_cmd.reset_p,
    out_reset_p => port_reset_p,
    out_clk     => cfg_cmd.clk);

-- If PTP is enabled...
gen_ptp : if PTP_ENABLE generate
    --  Generate switch-local timestamps with a Vernier synchronizer.
    u_tstamp : entity work.ptp_counter_sync
        generic map(
        VCONFIG     => VCONFIG,
        USER_CLK_HZ => CFG_CLK_HZ)
        port map(
        ref_time    => ref_time,
        user_clk    => cfg_cmd.clk,
        user_ctr    => lcl_tnow,
        user_lock   => lcl_tvalid,
        user_rst_p  => port_reset_p);

    -- Freeze or unfreeze TSOF field.
    p_sof : process(cfg_cmd.clk)
        constant ONE_CYCLE : tstamp_t := get_tstamp_incr(CFG_CLK_HZ);
    begin
        if rising_edge(cfg_cmd.clk) then
            -- Update the "freeze" strobe and "frozen" flag.
            rtc_freeze <= '0';
            if (port_reset_p = '1') then
                rtc_frozen  <= '0';     -- Global reset
            elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, 1022)) then
                rtc_freeze  <= cfg_cmd.wdata(0);
                rtc_frozen  <= cfg_cmd.wdata(0);
            elsif (tx_adj_write = '1') then
                rtc_frozen  <= '0';     -- Auto-clear on send
            end if;

            -- Clock-enable for the start-of-frame timestamp.
            if (rtc_freeze = '1' or rtc_frozen = '0') then
                lcl_tsof <= lcl_tnow + ONE_CYCLE;
            end if;
        end if;
    end process;

    -- Instantiate a real-time clock for global timestamps.
    u_rtc : entity work.ptp_realtime
        generic map(
        CFG_CLK_HZ  => CFG_CLK_HZ,
        DEV_ADDR    => DEV_ADDR,
        REG_BASE    => 1012)    -- Six consecutive registers
        port map(
        time_now    => rtc_tnow,
        time_read   => rtc_freeze,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(0));

    -- Read-only Tx and Rx timestamps.
    u_rx : entity work.ptp_realsof
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_BASE    => 506)     -- Four consecutive registers
        port map(
        in_tnow     => rtc_tnow,
        in_last     => rx_adj_last,
        in_write    => rx_adj_write,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(1));

    u_tx : entity work.ptp_realsof
        generic map(
        DEV_ADDR    => DEV_ADDR,
        REG_BASE    => 1018)    -- Four consecutive registers
        port map(
        in_tnow     => rtc_tnow,
        in_last     => tx_adj_last,
        in_write    => tx_adj_write,
        cfg_cmd     => cfg_cmd,
        cfg_ack     => cfg_acks(2));

    -- ConfigBus status reporting.
    rtc_status <= (31 => '1', 30 => lcl_tvalid, 0 => rtc_frozen, others => '0');
end generate;

-- Optionally check FCS of each incoming packet.
-- In most cases, this logic is redundant because the upstream switch has
-- already checked the CRC. However, PTP and other modes may intentionally
-- inject bad CRCs to indicate when a packet should be dropped.
gen_rxcrc1 : if CRC_ENABLE generate
    blk_crc : block is
        signal rx_raw_nlast : integer range 0 to 1;
        signal tmp_residue  : crc_word_t;
        signal tmp_data     : byte_t;
        signal tmp_nlast    : integer range 0 to 1;
        signal tmp_last     : std_logic;
        signal tmp_error    : std_logic;
        signal tmp_write    : std_logic;
    begin
        -- Byte-at-a-time CRC check.
        -- Note: Pipeline delay is exactly one clock-cycle.
        rx_raw_nlast <= u2i(rx_raw_last);
        u_crc_check : entity work.eth_frame_parcrc2
            port map(
            in_data     => rx_raw_data,
            in_nlast    => rx_raw_nlast,
            in_write    => rx_raw_write,
            out_res     => tmp_residue,
            out_data    => tmp_data,
            out_nlast   => tmp_nlast,
            out_write   => tmp_write,
            clk         => cfg_cmd.clk,
            reset_p     => port_reset_p);

        -- Check CRC residue at the end of each frame.
        tmp_last    <= bool2bit(tmp_nlast > 0);
        tmp_error   <= tmp_last and bool2bit(tmp_residue /= CRC_RESIDUE);

        -- Skid-buffer for upstream flow-control.
        u_crc_fifo : entity work.fifo_smol_sync
            generic map(
            IO_WIDTH    => 8,
            META_WIDTH  => 1)
            port map(
            in_data     => tmp_data,
            in_meta(0)  => tmp_error,
            in_last     => tmp_last,
            in_write    => tmp_write,
            out_data    => rx_crc_data,
            out_meta(0) => rx_crc_error,
            out_last    => rx_crc_last,
            out_valid   => rx_crc_valid,
            out_read    => rx_crc_ready,
            fifo_hempty => rx_raw_ready,
            clk         => cfg_cmd.clk,
            reset_p     => port_reset_p);
    end block;
end generate;

gen_rxcrc0 : if not CRC_ENABLE generate
    rx_crc_data     <= rx_raw_data;
    rx_crc_error    <= '0';
    rx_crc_last     <= rx_raw_last;
    rx_crc_valid    <= rx_raw_valid;
    rx_raw_ready    <= rx_crc_ready;
end generate;

-- Optionally strip FCS from incoming packets.
-- Note: Pipeline delay is 1-2 cycles depending on configuration.
u_rx_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => 0,
    APPEND_FCS  => false,
    STRIP_FCS   => STRIP_FCS)
    port map(
    in_data     => rx_crc_data,
    in_last     => rx_crc_last,
    in_error    => rx_crc_error,
    in_valid    => rx_crc_valid,
    in_ready    => rx_crc_ready,
    out_data    => rx_adj_data,
    out_last    => rx_adj_last,
    out_error   => rx_adj_error,
    out_valid   => rx_adj_valid,
    out_ready   => rx_adj_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Accept data whenever we're between packets.
rx_adj_ready <= not rx_ctrl_rcvd;
rx_adj_write <= rx_adj_valid and rx_adj_ready;

-- Controller for writing received data to the working buffer.
p_rx_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (port_reset_p = '1' or cfg_clr_rx = '1') then
            -- Reset buffer contents and begin storing new data.
            rx_ctrl_len  <= (others => '0');
            rx_ctrl_rcvd <= '0';
        elsif (rx_adj_write = '1') then
            -- Accept new data and update state.
            if (rx_adj_last = '0') then
                -- Receive next byte.
                rx_ctrl_len  <= rx_ctrl_len + 1;
                rx_ctrl_rcvd <= '0';
            elsif (rx_adj_error = '0' and rx_ctrl_len < MAX_FRAME_BYTES) then
                -- Receive final byte.
                rx_ctrl_len  <= rx_ctrl_len + 1;
                rx_ctrl_rcvd <= '1';
                irq_toggle   <= not irq_toggle;
            else
                -- Packet too long or bad FCS; discard.
                rx_ctrl_len  <= (others => '0');
                rx_ctrl_rcvd <= '0';
            end if;
        end if;
    end if;
end process;

-- Convert Tx/Rx/ConfigBus state to RAM addresses and write-enables.
cfg_addr    <= to_unsigned(cfg_cmd.regaddr mod RAM_WORDS, RAM_ADDRW);
cfg_wren    <= bool2bit(cfgbus_wrcmd(cfg_cmd, DEV_ADDR)) and not tx_ctrl_busy;
rx_wr_addr  <= get_addr(rx_ctrl_len);
tx_rd_addr  <= get_addr(tx_ctrl_len);
gen_lane : for n in 0 to RAM_BYTES-1 generate
    cfg_wstrb(n)    <= cfg_wren and cfg_cmd.wstrb(n);
    rx_ctrl_wren(n) <= rx_adj_write and bool2bit(n = get_lane(rx_ctrl_len));
end generate;

-- Platform-specific dual-port block RAM.
gen_dpram : for n in 0 to 3 generate
    u_rxbuff : dpram
        generic map(
        AWIDTH  => RAM_ADDRW,
        DWIDTH  => 8,
        TRIPORT => false)
        port map(
        wr_clk  => cfg_cmd.clk,
        wr_addr => rx_wr_addr,
        wr_en   => rx_ctrl_wren(n),
        wr_val  => rx_adj_data,
        wr_rval => open,
        rd_clk  => cfg_cmd.clk,
        rd_addr => cfg_addr,
        rd_val  => cfg_rxdata(8*n+7 downto 8*n));

    u_txbuff : dpram
        generic map(
        AWIDTH  => RAM_ADDRW,
        DWIDTH  => 8,
        TRIPORT => TX_READBACK)
        port map(
        wr_clk  => cfg_cmd.clk,
        wr_addr => cfg_addr,
        wr_en   => cfg_wstrb(n),
        wr_val  => cfg_cmd.wdata(8*n+7 downto 8*n),
        wr_rval => cfg_txdata(8*n+7 downto 8*n),
        rd_clk  => cfg_cmd.clk,
        rd_addr => tx_rd_addr,
        rd_val  => tx_rd_data(8*n+7 downto 8*n));
end generate;

-- Transmit controller reads buffer on demand.
p_tx_ctrl : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- On demand, scan read address from 0 to N-1.
        if (port_reset_p = '1') then
            -- Global reset.
            tx_ctrl_len  <= (others => '0');
            tx_ctrl_busy <= '0';
        elsif (cfg_send_tx = '1' and cfg_send_len > 0) then
            -- Begin readout.
            tx_ctrl_len  <= (others => '0');
            tx_ctrl_busy <= '1';
        elsif (tx_ctrl_busy = '1' and tx_fifo_ok = '1') then
            -- Continue readout.
            tx_ctrl_len  <= tx_ctrl_len + 1;
            tx_ctrl_busy <= bool2bit(tx_ctrl_len + 1 < cfg_send_len);
        end if;

        -- One-cycle delay for reading the BRAM.
        tx_rd_next <= tx_ctrl_busy and tx_fifo_ok;
        tx_rd_bidx <= get_lane(tx_ctrl_len);
        tx_rd_last <= bool2bit(tx_ctrl_len + 1 = cfg_send_len);

        -- Extract the appropriate byte from the readout.
        tx_fifo_data  <= tx_rd_data(8*tx_rd_bidx+7 downto 8*tx_rd_bidx);
        tx_fifo_last  <= tx_rd_last;
        tx_fifo_wr    <= tx_rd_next;
    end if;
end process;

-- Small FIFO for flow-control.
u_tx_fifo : entity work.fifo_smol_sync
    generic map(IO_WIDTH => 8)
    port map(
    in_data     => tx_fifo_data,
    in_last     => tx_fifo_last,
    in_write    => tx_fifo_wr,
    out_data    => tx_raw_data,
    out_last    => tx_raw_last,
    out_valid   => tx_raw_valid,
    out_read    => tx_raw_ready,
    fifo_hempty => tx_fifo_ok,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Optionally append and zero-pad data before sending.
u_tx_adj : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => false)
    port map(
    in_data     => tx_raw_data,
    in_last     => tx_raw_last,
    in_valid    => tx_raw_valid,
    in_ready    => tx_raw_ready,
    out_data    => tx_adj_data,
    out_last    => tx_adj_last,
    out_valid   => tx_adj_valid,
    out_ready   => tx_adj_ready,
    clk         => cfg_cmd.clk,
    reset_p     => port_reset_p);

-- Data going to the Ethernet switch. (Note Tx/Rx swap)
rtc_time        <= rtc_tnow;
tx_adj_ready    <= '1';
tx_adj_write    <= tx_adj_valid and tx_adj_ready;
rx_data.clk     <= cfg_cmd.clk;
rx_data.data    <= tx_adj_data;
rx_data.last    <= tx_adj_last;
rx_data.write   <= tx_adj_write;
rx_data.rxerr   <= '0';
rx_data.rate    <= get_rate_word(1);
rx_data.status  <= (0 => port_reset_p, 1 => lcl_tvalid, others => '0');
rx_data.tsof    <= lcl_tsof;
rx_data.reset_p <= port_reset_p;

-- Interrupt control uses the standard ConfigBus primitive.
u_irq : cfgbus_interrupt
    generic map(
    DEVADDR     => DEV_ADDR,
    REGADDR     => 510)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_acks(3),
    ext_toggle  => irq_toggle);

-- Combine ConfigBus replies from each source.
cfg_acks(4) <= cfgbus_reply(cfg_status) when (cfg_regread = '1')
          else cfgbus_reply(cfg_txdata) when (cfg_txread = '1')
          else cfgbus_reply(cfg_rxdata) when (cfg_rxread = '1')
          else cfgbus_idle;

cfg_ack <= cfgbus_merge(cfg_acks);

-- ConfigBus interface.
p_cfgbus : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Set defaults for various strobes.
        cfg_txread  <= '0';
        cfg_rxread  <= '0';
        cfg_regread <= '0';
        cfg_status  <= (others => '0');
        cfg_clr_rx  <= '0';
        cfg_send_tx <= '0';

        -- Handle writes to the conrol registers.
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, 511)) then
            cfg_clr_rx   <= '1';
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, 1023) and tx_ctrl_busy = '0') then
            cfg_send_tx  <= '1';
            cfg_send_len <= unsigned(cfg_cmd.wdata(cfg_send_len'range));
        end if;

        -- Handle reads from any register.
        if (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, 511)) then
            if (rx_ctrl_rcvd = '1') then
                cfg_status <= std_logic_vector(resize(rx_ctrl_len, 32));
            else
                cfg_status <= (others => '0');
            end if;
            cfg_regread <= '1';
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, 1022)) then
            cfg_status  <= rtc_status;
            cfg_regread <= '1';
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR, 1023)) then
            cfg_status  <= (0 => tx_ctrl_busy, others => '0');
            cfg_regread <= '1';
        elsif (cfgbus_rdcmd(cfg_cmd, DEV_ADDR)) then
            cfg_rxread <= bool2bit(cfg_cmd.regaddr <= 399);
            cfg_txread <= bool2bit(512 <= cfg_cmd.regaddr and cfg_cmd.regaddr <= 911);
        end if;
    end if;
end process;

end port_mailmap;
