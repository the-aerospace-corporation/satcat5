--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Validation tool for mac_log_core and related blocks.
--
-- This block accepts a mirrored copy of the inputs to "mac_log_core",
-- plus the processed output messages. The processed messages may contain
-- an unpredictable mixture of exact matches and "skip" messages.  This
-- block validates that stream against the reference sequence and reports
-- the total number of accepted, dropped, and skipped packets.
--

library ieee;
use     ieee.numeric_std.all;
use     ieee.std_logic_1164.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity mac_log_validate is
    generic (
    CORE_CLK_HZ : positive;         -- Core clock frequency (Hz)
    LEN_HISTORY : positive;         -- Size of history buffer
    OUT_BYTES   : positive;         -- Test stream width
    PORT_COUNT  : positive);        -- Number of ingress ports
    port (
    -- Packet logs from the shared pipeline.
    mac_data    : in  log_meta_t;
    mac_psrc    : in  integer range 0 to PORT_COUNT-1;
    mac_dmask   : in  std_logic_vector(PORT_COUNT-1 downto 0);
    mac_write   : in  std_logic;

    -- Packet logs from each ingress port.
    port_data   : in  log_meta_array(PORT_COUNT-1 downto 0);
    port_write  : in  std_logic_vector(PORT_COUNT-1 downto 0);

    -- Formatted log data to be validated.
    -- (Choose out_last or out_nlast; no need for both.)
    out_clk     : in  std_logic;
    out_data    : in  std_logic_vector(8*OUT_BYTES-1 downto 0);
    out_nlast   : in  integer range 0 to OUT_BYTES := 0;
    out_last    : in  std_logic := '0';
    out_read    : in  std_logic;

    -- Overall test status.
    test_done   : out std_logic;    -- Idle + empty queue
    total_keep  : out natural;
    total_drop  : out natural;
    total_skip  : out natural;

    -- Clock and synchronous reset.
    core_clk    : in  std_logic;
    reset_p     : in  std_logic);
end mac_log_validate;

architecture mac_log_validate of mac_log_validate is

-- Microsecond-resolution timestamp counter.
subtype time_t is unsigned(23 downto 0);
signal time_ctr     : time_t;

-- Idle detection.
signal action_wr    : std_logic;
signal action_rd    : std_logic;
signal idle_wr      : natural := 0;
signal idle_rd      : natural := 0;

-- Count inputs of each type.
signal count_keep   : natural := 0;
signal count_drop   : natural := 0;

-- Define message header fields.
subtype msg_type_t is std_logic_vector(2 downto 0);
constant TYPE_KEEP  : msg_type_t := "000";
constant TYPE_DROP  : msg_type_t := "001";
constant TYPE_SKIP  : msg_type_t := "010";
subtype msg_meta_t is std_logic_vector(31 downto 0);
subtype msg_pkt_t is std_logic_vector(191 downto 0);

impure function make_pkt(
    typ:    msg_type_t;
    psrc:   natural;
    log:    log_meta_t;
    meta:   std_logic_vector)
    return msg_pkt_t
is
    variable tmp : msg_pkt_t :=
        std_logic_vector(time_ctr) & typ & i2s(psrc, 5) &
        log.dst_mac & log.src_mac & log.etype & log.vtag &
        resize(meta, 32);
begin
    return tmp;
end function;

-- Circular buffer of received packets.
type packet_array is array(0 to LEN_HISTORY-1) of msg_pkt_t;
shared variable rcvd_pkts : packet_array := (others => (others => 'X'));
shared variable rd_ptr, wr_ptr : natural := 0;
signal rd_ptr_q, wr_ptr_q : natural := 0;

begin

-- Microsecond-resolution timestamp counter.
u_timer : entity work.config_timestamp
    generic map(
    REFCLK_HZ   => CORE_CLK_HZ,
    CTR_HZ      => 1_000_000,
    CTR_WIDTH   => time_ctr'length)
    port map(
    out_ctr     => time_ctr,
    refclk      => core_clk,
    reset_p     => reset_p);

-- Idle detection.
test_done   <= bool2bit(idle_wr > 100 and idle_rd > 100 and rd_ptr = wr_ptr);
action_wr   <= reset_p or mac_write or or_reduce(port_write);
action_rd   <= reset_p or out_read;

p_idle_wr : process(core_clk)
begin
    if rising_edge(core_clk) then
        if (action_wr = '1') then
            idle_wr <= 0;
        else
            idle_wr <= idle_wr + 1;
        end if;
    end if;
end process;

p_idle_rd : process(out_clk)
begin
    if rising_edge(out_clk) then
        if (action_rd = '1') then
            idle_rd <= 0;
        else
            idle_rd <= idle_rd + 1;
        end if;
    end if;
end process;

-- Write packet events into the log.
p_write : process(core_clk)
    procedure write_pkt(msg: msg_pkt_t) is
    begin
        rcvd_pkts(wr_ptr) := msg;
        wr_ptr := (wr_ptr + 1) mod LEN_HISTORY;
        assert (wr_ptr /= rd_ptr) report "Buffer overflow.";
    end procedure;
begin
    if rising_edge(core_clk) then
        -- Incoming packet from the shared pipeline?
        if (mac_write = '1' and or_reduce(mac_dmask) = '1') then
            write_pkt(make_pkt(TYPE_KEEP, mac_psrc, mac_data, mac_dmask));
        elsif (mac_write = '1') then
            write_pkt(make_pkt(TYPE_DROP, mac_psrc, mac_data, mac_data.reason));
        end if;

        -- Dropped packet(s) from any of the ingress ports?
        for n in port_write'range loop
            if (port_write(n) = '1') then
                write_pkt(make_pkt(TYPE_DROP, n, port_data(n), port_data(n).reason));
            end if;
        end loop;
    end if;
end process;

-- Validate incoming messages.
p_check : process(out_clk)
    -- Parse fields in an input packet.
    type parse_t is record
        typ    : msg_type_t;
        psrc   : natural;
        log    : log_meta_t;
        meta   : msg_meta_t;
    end record;
        
    function parse(msg: msg_pkt_t) return parse_t is
        variable tmp : parse_t;
    begin
        -- Timestamp ignored = msg(191 downto 168)
        tmp.typ         := msg(167 downto 165);
        tmp.psrc        := u2i(msg(164 downto 160));
        tmp.log.dst_mac := msg(159 downto 112);
        tmp.log.src_mac := msg(111 downto  64);
        tmp.log.etype   := msg( 63 downto  48);
        tmp.log.vtag    := msg( 47 downto  32);
        tmp.meta        := msg( 31 downto   0);
        if (tmp.typ = TYPE_KEEP) then
            tmp.log.reason := REASON_KEEP;
        else
            tmp.log.reason := tmp.meta(7 downto 0);
        end if;
        return tmp;
    end function;

    -- Advance the read pointer, checking for underflow.
    procedure read_next is
    begin
        if (rd_ptr = wr_ptr) then
            report "Buffer underflow." severity error;
        else
            rd_ptr := (rd_ptr + 1) mod LEN_HISTORY;
        end if;
    end procedure;

    -- Parser state for each word in the packet.
    variable bidx, rdrop, rkeep, udrop, ukeep : natural := 0;
    variable sreg : msg_pkt_t := (others => '0');
    variable rcvd, ref : parse_t := (
        typ    => (others => '0'),
        psrc   => 0,
        log    => LOG_META_NULl,
        meta   => (others => '0'));
begin
    if rising_edge(out_clk) then
        if (out_read = '1') then
            -- Update the shift register with each input word.
            sreg := sreg(sreg'left-8*OUT_BYTES downto 0) & out_data;
            bidx := bidx + OUT_BYTES;
            -- End of frame?
            if (rd_ptr = wr_ptr) then
                -- Reference buffer is empty. Why are we getting data?
                report "Unexpected input data." severity error;
            elsif (out_nlast > 0 or out_last = '1') then
                -- Sanity check before parsing the received message.
                -- TODO: Do we need to support zero-padding?
                assert (bidx = 24) report "Length mismatch.";
                bidx    := 0;
                rcvd    := parse(sreg);
                rdrop   := 0;
                rkeep   := 0;
                udrop   := u2i(rcvd.meta(31 downto 16));
                ukeep   := u2i(rcvd.meta(15 downto  0));
                -- Take action based on packet type...
                if (rcvd.typ = TYPE_SKIP) then
                    -- Skip ahead N messages, counting drop vs keep packets.
                    count_drop <= count_drop + udrop;
                    count_keep <= count_keep + ukeep;
                    for n in 1 to udrop + ukeep loop
                        ref := parse(rcvd_pkts(rd_ptr));
                        if (ref.typ = TYPE_KEEP) then
                            rkeep := rkeep + 1;
                        else
                            rdrop := rdrop + 1;
                        end if;
                        read_next;
                    end loop;
                    -- Compare expected keep/drop count vs the received values.
                    assert (udrop > 0 or ukeep > 0) report "SKIP empty.";
                    assert (rdrop = udrop and rkeep = ukeep) report "SKIP mismatch.";
                elsif (rcvd.typ = TYPE_KEEP) then
                    -- Next queued message should be an exact match.
                    count_keep <= count_keep + 1;
                    ref := parse(rcvd_pkts(rd_ptr));
                    assert (rcvd = ref) report "KEEP mismatch.";
                    read_next;
                elsif (rcvd.typ = TYPE_DROP) then
                    -- Next queued message should be an exact match.
                    count_drop <= count_drop + 1;
                    ref := parse(rcvd_pkts(rd_ptr));
                    assert (rcvd = ref) report "DROP mismatch.";
                    read_next;
                else
                    report "Invalid message type." severity error;
                end if;
            end if;
        end if;

        -- Buffered copy of shared variables.
        -- (Required for display in some VHDL simulators.)
        rd_ptr_q <= rd_ptr;
        wr_ptr_q <= wr_ptr;
    end if;
end process;

end mac_log_validate;
