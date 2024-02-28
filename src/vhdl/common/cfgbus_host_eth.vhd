--------------------------------------------------------------------------
-- Copyright 2021-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- ConfigBus host with Ethernet packet interface
--
-- This module acts as a ConfigBus host, accepting read and write commands
-- over a generic Ethernet byte stream.  This makes it suitable for use
-- with internal switch ports, configuration UARTs, and other interfaces.
-- Including the FCS in this input stream is optional.
--
-- The "length" argument M sets the number of read or write operations to
-- be performed.  Single-register operations set M=0.  Multi-word operations
-- set M = L-1, where L is the total number of reads or writes. Opcodes are
-- available for no-increment mode (repeatedly read/write same register) or
-- for auto-increment mode (each read/write increments register address).
--
-- Write opcodes use the four LSBs as a write-enable mask.  Multi-write
-- commands apply the same mask to each operation.  Use 0x1F and 0x2F
-- (i.e., Write each byte-lane) for general-purpose writes.
--
-- The command packet format is as follows:
--  6 bytes     Destination MAC
--              Must match broadcast address or CFG_MACADDR.
--  6 bytes     Source MAC
--              Response will be sent to this address.
--  2 bytes     EtherType = CFG_ETYPE
--              Frames not matching CFG_ETYPE are ignored.
--  1 byte      Opcode
--              0x00 = No-op
--              0x2x = Write no-increment (LSBs = Write-enable mask)
--                     See description above. Use 0x2F for general writes.
--              0x3x = Write auto-increment (LSBs = Write-enable mask)
--                     See description above. Use 0x3F for general writes.
--              0x40 = Read no-increment
--              0x50 = Read auto-increment
--              All others reserved
--  1 byte      Length parameter M = N-1 (see above)
--  1 byte      Sequence count (increment after each command)
--  1 byte      Reserved (zero)
--  4 bytes     Combined address (DevAddr * 1024 + RegAddr)
--  (4N bytes)  Write value(s), if applicable
--  (All subsequent bytes are ignored.)
--
-- The reply format is as follows:
--  6 bytes     Destination MAC (echo source)
--  6 bytes     Source MAC = CFG_MACADDR.
--  2 bytes     EtherType = CFG_ETYPE + 1
--  1 byte      Opcode (echo)
--  1 byte      Length parameter (echo)
--  1 byte      Sequence count (echo)
--  1 byte      Reserved (zero)
--  4 bytes     Combined address (echo)
--  (4N bytes)  Read value(s), if applicable
--  (1 byte)    Read-error flag, if applicable
--              (0x00 = Success, 0xFF = At least one error)
--  (All subsequent bytes should be ignored)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.cfgbus_common.all;
use     work.eth_frame_common.all;

entity cfgbus_host_eth is
    generic (
    CFG_ETYPE   : mac_type_t := x"5C01";
    CFG_MACADDR : mac_addr_t := x"5A5ADEADBEEF";
    APPEND_FCS  : boolean := true;      -- Include FCS in output?
    MIN_FRAME   : natural := 64;        -- Pad reply to minimum size? (bytes)
    RD_TIMEOUT  : positive := 16);      -- ConfigBus read timeout (clocks)
    port (
    -- ConfigBus host interface.
    cfg_cmd     : out cfgbus_cmd;
    cfg_ack     : in  cfgbus_ack;

    -- Input stream (AXI flow-control)
    rx_data     : in  byte_t;
    rx_last     : in  std_logic;
    rx_valid    : in  std_logic;
    rx_ready    : out std_logic;

    -- Output stream (AXI flow-control)
    tx_data     : out byte_t;
    tx_last     : out std_logic;
    tx_valid    : out std_logic;
    tx_ready    : in  std_logic;

    -- Interrupt signal (optional)
    irq_out     : out std_logic;

    -- Clock and reset
    txrx_clk    : in  std_logic;
    reset_p     : in  std_logic);
end cfgbus_host_eth;

architecture cfgbus_host_eth of cfgbus_host_eth is

-- Reply uses a different EtherType to prevent loops.
constant REPLY_ETYPE : mac_type_t :=
    std_logic_vector(unsigned(CFG_ETYPE) + 1);

-- Define various opcodes.
subtype opcode_t is std_logic_vector(3 downto 0);
constant OPCODE_WRITE_RPT   : opcode_t := x"2";
constant OPCODE_WRITE_INC   : opcode_t := x"3";
constant OPCODE_READ_RPT    : opcode_t := x"4";
constant OPCODE_READ_INC    : opcode_t := x"5";

-- Define byte-offsets for command and reply packets.
constant PKTIDX_MAC_DST     : integer := 6;     -- Bytes  0- 5 = DST
constant PKTIDX_MAC_SRC     : integer := 12;    -- Bytes  6-11 = SRC
constant PKTIDX_ETYPE       : integer := 14;    -- Bytes 12-13 = EtherType
constant PKTIDX_OPCODE      : integer := 15;    -- Byte  14-14 = Opcode
constant PKTIDX_LENGTH      : integer := 16;    -- Byte  15-15 = Word count - 1
constant PKTIDX_SEQUENCE    : integer := 17;    -- Byte  16-16 = Sequence count
constant PKTIDX_RESERVED    : integer := 18;    -- Byte  17-17 = Reserved
constant PKTIDX_ADDR        : integer := 22;    -- Byte  18-21 = Combined address
constant PKTIDX_HEADER      : integer := 22;    -- Byte   0-21 = Header
constant PKTIDX_DATA        : integer := 26;    -- Bytes 22-25 = R/W data
constant PKTIDX_STATUS      : integer := 27;    -- Byte  26-26 = Status (read-reply only)

-- Command count starts at M = N-1 and decrements after each read/write.
-- After the last read/write operation, it wraps around from 0 to 255.
-- The command and reply state machines stop when they see this value.
subtype cmdct_t is unsigned(7 downto 0);
constant COUNT_DONE : cmdct_t := (others => '1');

-- Get Nth byte from a larger vector, starting from MSB.
--  x = Input word (Big-endian)
--  b = Byte offset from start of packet
--  f = Byte offset for end of current field
function get_byte(x: std_logic_vector; b,f: natural) return byte_t is
    variable n : integer := 8 * (f-1-b);
    variable y : byte_t := (others => '0');
begin
    if (n >= 0) then
        y := x(n+7 downto n);
    end if;
    return y;
end function;

-- Receive state machine.
signal rx_write     : std_logic;
signal rx_busy      : std_logic := '0';
signal rx_bcount    : integer range 0 to PKTIDX_DATA-1 := 0;
signal rx_match     : std_logic := '0';
signal rx_macaddr   : mac_addr_t := (others => '0');
signal rx_opcode    : opcode_t := (others => '0');
signal rx_wrmask    : opcode_t := (others => '0');
signal rx_cmdlen    : std_logic_vector(7 downto 0) := (others => '0');
signal rx_sequence  : std_logic_vector(7 downto 0) := (others => '0');
signal rx_addr      : std_logic_vector(31 downto 0) := (others => '0');
signal rx_wdata     : cfgbus_word := (others => '0');
signal rx_is_read   : std_logic;
signal rx_is_write  : std_logic;

-- Timeout handling
signal int_cmd      : cfgbus_cmd;
signal int_ack      : cfgbus_ack;
signal int_irq      : std_logic := '0';

-- Issue command and latch response.
signal cmd_start    : std_logic := '0';
signal cmd_remct    : cmdct_t := (others => '0');
signal cmd_addr     : unsigned(31 downto 0) := (others => '0');
signal cmd_wrcmd    : std_logic := '0';
signal cmd_rdcmd    : std_logic := '0';
signal cmd_rderr    : std_logic := '0';
signal cmd_busy     : std_logic := '0';

-- Transmit state machine.
signal ack_rdata    : cfgbus_word := (others => '0');
signal ack_rvalid   : std_logic := '0';
signal ack_rnext    : std_logic;
signal ack_rbyte    : std_logic;
signal ack_rword    : std_logic;
signal ack_bcount   : integer range 0 to PKTIDX_STATUS-1 := 0;
signal ack_data     : byte_t := (others => '0');
signal ack_last     : std_logic := '0';
signal ack_valid    : std_logic := '0';
signal ack_ready    : std_logic;
signal ack_done     : std_logic;

begin

-- Drive top-level outputs:
irq_out     <= int_irq;
rx_ready    <= not rx_busy;

-- Receive state machine.
rx_write    <= rx_valid and not rx_busy;
rx_is_read  <= bool2bit(rx_opcode = OPCODE_READ_RPT
                     or rx_opcode = OPCODE_READ_INC);
rx_is_write <= bool2bit(rx_opcode = OPCODE_WRITE_RPT
                     or rx_opcode = OPCODE_WRITE_INC);

p_rx : process(txrx_clk)
    variable dst_match, dst_bcast : std_logic := '0';
begin
    if rising_edge(txrx_clk) then
        -- Busy flag is used for upstream flow control.
        -- Set at end-of-frame; hold until command is completed.
        if (reset_p = '1') then
            rx_busy <= '0';
        elsif (rx_write = '1' and rx_last = '1') then
            rx_busy <= cmd_start or cmd_busy;
        elsif (cmd_start = '0' and cmd_busy = '0') then
            rx_busy <= '0';
        end if;

        -- Count bytes in each frame.
        if (reset_p = '1') then
            rx_bcount <= 0;             -- Global reset
        elsif (rx_write = '1' and rx_last = '1') then
            rx_bcount <= 0;             -- End of frame
        elsif (rx_write = '1' and rx_bcount = PKTIDX_DATA-1) then
            rx_bcount <= rx_bcount - 3; -- Wraparound (write words)
        elsif (rx_write = '1') then
            rx_bcount <= rx_bcount + 1; -- Normal increment
        end if;

        -- Latch various parameters.
        if (rx_write = '0' or rx_match = '0') then
            null;   -- No change
        elsif (rx_bcount < PKTIDX_MAC_DST) then
            null;   -- Destination MAC is checked elsewhere
        elsif (rx_bcount < PKTIDX_MAC_SRC) then
            rx_macaddr  <= rx_macaddr(39 downto 0) & rx_data;
        elsif (rx_bcount < PKTIDX_ETYPE) then
            null;   -- EtherType is checked elsewhere
        elsif (rx_bcount < PKTIDX_OPCODE) then
            rx_opcode   <= rx_data(7 downto 4);
            rx_wrmask   <= rx_data(3 downto 0);
        elsif (rx_bcount < PKTIDX_LENGTH) then
            rx_cmdlen   <= rx_data;
        elsif (rx_bcount < PKTIDX_SEQUENCE) then
            rx_sequence <= rx_data;
        elsif (rx_bcount < PKTIDX_RESERVED) then
            null;   -- Reserved field, ignored for now
        elsif (rx_bcount < PKTIDX_ADDR) then
            rx_addr     <= rx_addr(23 downto 0) & rx_data;
        elsif (rx_bcount < PKTIDX_DATA) then
            rx_wdata    <= rx_wdata(23 downto 0) & rx_data;
        end if;

        -- Start-of-command occurs on byte 20.
        -- Write strobe, if applicable, is asserted on bytes 24, 28, 32, ...
        cmd_start <= rx_write and rx_match
                 and bool2bit(rx_bcount = PKTIDX_HEADER-1);
        cmd_wrcmd <= rx_write and rx_match and rx_is_write
                 and bool2bit(rx_bcount = PKTIDX_DATA-1 and cmd_remct /= COUNT_DONE);

        -- Address-matching state machine.
        if ((reset_p = '1') or (rx_write = '1' and rx_last = '1')) then
            dst_match := '1';
            dst_bcast := '1';
        elsif (rx_write = '1' and rx_bcount < PKTIDX_MAC_DST) then
            dst_match := dst_match and bool2bit(
                rx_data = get_byte(CFG_MACADDR, rx_bcount, PKTIDX_MAC_DST));
            dst_bcast := dst_bcast and bool2bit(
                rx_data = get_byte(MAC_ADDR_BROADCAST, rx_bcount, PKTIDX_MAC_DST));
        end if;

        -- Ignore commands based on address or EtherType.
        if (reset_p = '1') then
            rx_match <= '0';
        elsif (rx_write = '0') then
            null;   -- No new data
        elsif (rx_bcount < PKTIDX_MAC_DST) then
            rx_match <= dst_match or dst_bcast;
        elsif (rx_bcount < PKTIDX_MAC_SRC) then
            null;   -- Not checking source MAC
        elsif (rx_bcount < PKTIDX_ETYPE) then
            rx_match <= rx_match and bool2bit(
                rx_data = get_byte(CFG_ETYPE, rx_bcount, PKTIDX_ETYPE));
        end if;
    end if;
end process;

-- Drive each ConfigBus signal.
int_cmd.clk     <= txrx_clk;
int_cmd.sysaddr <= to_integer(shift_right(cmd_addr, 18)) mod 4096;
int_cmd.devaddr <= to_integer(shift_right(cmd_addr, 10)) mod 256;
int_cmd.regaddr <= to_integer(shift_right(cmd_addr,  0)) mod 1024;
int_cmd.wdata   <= rx_wdata;
int_cmd.wstrb   <= rx_wrmask;
int_cmd.wrcmd   <= cmd_wrcmd;
int_cmd.rdcmd   <= cmd_rdcmd;
int_cmd.reset_p <= reset_p;

-- Handle timeouts (each RDCMD will produce exactly one RDACK or ERR).
u_timeout : cfgbus_timeout
    generic map(
    RD_TIMEOUT  => RD_TIMEOUT)
    port map(
    host_cmd    => int_cmd,
    host_ack    => int_ack,
    host_wait   => open,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack);

-- Command state machine.
p_reply : process(txrx_clk)
begin
    if rising_edge(txrx_clk) then
        -- Set busy flag at the start of any command.
        -- Clear it once we've finished sending reply.
        if (ack_done = '1') then
            cmd_busy <= '0';
        elsif (cmd_start = '1') then
            cmd_busy <= '1';
        end if;

        -- Update remaining-length and address counters.
        if (cmd_start = '1') then
            cmd_remct   <= unsigned(rx_cmdlen);
            cmd_addr    <= unsigned(rx_addr);
        elsif (cmd_wrcmd = '1' or cmd_rdcmd = '1') then
            cmd_remct   <= cmd_remct - 1;
            if (rx_opcode = OPCODE_WRITE_INC or rx_opcode = OPCODE_READ_INC) then
                cmd_addr <= cmd_addr + 1;
            end if;
        end if;

        -- Issue each read command, one at a time.
        --  * First read is sent as soon as command is issued.
        --  * Subsequent reads wait for each reply word to be sent.
        if (cmd_start = '1') then
            cmd_rdcmd <= rx_is_read;
        elsif (ack_rword = '1') then
            cmd_rdcmd <= rx_is_read and bool2bit(cmd_remct /= COUNT_DONE);
        else
            cmd_rdcmd <= '0';
        end if;

        -- Latch and shift read-response.
        if (cmd_start = '1') then
            ack_rdata  <= (others => '0');
            ack_rvalid <= '0';
        elsif (int_ack.rdack = '1' or int_ack.rderr = '1') then
            ack_rdata  <= int_ack.rdata;
            ack_rvalid <= '1';
        elsif (ack_rbyte = '1') then
            ack_rdata  <= ack_rdata(23 downto 0) & x"00";
            ack_rvalid <= not ack_rword;
        end if;

        -- Sticky read-error flag.
        if (cmd_start = '1') then
            cmd_rderr <= '0';
        elsif (int_ack.rderr = '1') then
            cmd_rderr <= '1';
        end if;

        -- Buffer the interrupt flag.
        int_irq <= int_ack.irq;
    end if;
end process;

-- Transmit state machine.
ack_done    <= (reset_p) or (ack_last and ack_valid and ack_ready);
ack_rnext   <= ack_rvalid and (ack_ready or not ack_valid);
ack_rbyte   <= ack_rnext and bool2bit(ack_bcount >= PKTIDX_HEADER);
ack_rword   <= ack_rnext and bool2bit(ack_bcount = PKTIDX_DATA-1);

p_ack : process(txrx_clk)
begin
    if rising_edge(txrx_clk) then
        -- Count bytes in each frame.
        if (ack_done = '1') then
            ack_valid   <= '0';     -- Reset or completion
            ack_last    <= '0';
            ack_bcount  <= 0;
        elsif (cmd_start = '1') then
            ack_valid   <= '1';     -- Start of new reply
            ack_last    <= '0';
            ack_bcount  <= 1;
        elsif (cmd_busy = '0') then
            ack_valid   <= '0';     -- Idle
            ack_last    <= '0';
            ack_bcount  <= 0;
        elsif (rx_is_read = '0' and ack_ready = '1') then
            ack_valid   <= '1';     -- Normal reply is header only.
            ack_last    <= bool2bit(ack_bcount = PKTIDX_HEADER-1);
            ack_bcount  <= ack_bcount + 1;
        elsif (ack_bcount < PKTIDX_HEADER and ack_ready = '1') then
            ack_valid   <= '1';     -- Read reply header
            ack_last    <= '0';
            ack_bcount  <= ack_bcount + 1;
        elsif (ack_bcount = PKTIDX_STATUS-1 and ack_ready = '1') then
            ack_valid   <= '1';     -- End read-reply with status code
            ack_last    <= '1';
            ack_bcount  <= 0;
        elsif (ack_rnext = '1') then
            ack_valid   <= '1';     -- Emit next data byte
            ack_last    <= '0';
            if (ack_rword = '1' and cmd_remct = COUNT_DONE) then
                ack_bcount <= PKTIDX_STATUS - 1;    -- Done (emit status)
            elsif (ack_rword = '1') then
                ack_bcount <= PKTIDX_DATA - 4;      -- Next data word
            else
                ack_bcount <= ack_bcount + 1;       -- Continue data word
            end if;
        elsif (ack_ready = '1') then
            ack_valid   <= '0';     -- Waiting for ConfigBus reply
        end if;

        -- Choose next output byte.
        if (ack_valid = '1' and ack_ready = '0') then
            null;   -- Hold current value
        elsif (ack_bcount < PKTIDX_MAC_DST) then
            -- Destination MAC (6 bytes)
            ack_data <= get_byte(rx_macaddr, ack_bcount, PKTIDX_MAC_DST);
        elsif (ack_bcount < PKTIDX_MAC_SRC) then
            -- Source MAC (6 bytes)
            ack_data <= get_byte(CFG_MACADDR, ack_bcount, PKTIDX_MAC_SRC);
        elsif (ack_bcount < PKTIDX_ETYPE) then
            -- Ethertype (2 bytes)
            ack_data <= get_byte(REPLY_ETYPE, ack_bcount, PKTIDX_ETYPE);
        elsif (ack_bcount < PKTIDX_OPCODE) then
            -- Opcode (echo 1 byte)
            ack_data <= rx_opcode & rx_wrmask;
        elsif (ack_bcount < PKTIDX_LENGTH) then
            -- Length parameter (echo 1 byte)
            ack_data <= rx_cmdlen;
        elsif (ack_bcount < PKTIDX_SEQUENCE) then
            -- Sequence count (echo 1 byte)
            ack_data <= rx_sequence;
        elsif (ack_bcount < PKTIDX_RESERVED) then
            -- Reserved field (1 byte)
            ack_data <= (others => '0');
        elsif (ack_bcount < PKTIDX_ADDR) then
            -- Register address (echo 4 bytes)
            ack_data <= get_byte(rx_addr, ack_bcount, PKTIDX_ADDR);
        elsif (ack_bcount < PKTIDX_DATA) then
            -- Read value (4 bytes)
            ack_data <= ack_rdata(31 downto 24);
        else
            -- Read-error code
            ack_data <= (others => cmd_rderr);
        end if;
    end if;
end process;

-- Frame checksum and zero-padding.
u_frm : entity work.eth_frame_adjust
    generic map(
    MIN_FRAME   => MIN_FRAME,
    APPEND_FCS  => APPEND_FCS,
    STRIP_FCS   => false)
    port map(
    in_data     => ack_data,
    in_last     => ack_last,
    in_valid    => ack_valid,
    in_ready    => ack_ready,
    out_data    => tx_data,
    out_last    => tx_last,
    out_valid   => tx_valid,
    out_ready   => tx_ready,
    clk         => txrx_clk,
    reset_p     => reset_p);

end cfgbus_host_eth;
