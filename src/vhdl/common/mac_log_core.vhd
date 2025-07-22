--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Diagnostic logging system for the Ethernet switch
--
-- This block records a diagnostic log of packets that reach the switch,
-- providing basic information about packet source/destination/type, and
-- where it was directed or why it was dropped.
--
-- Packet drops are logged from each ingress port (i.e., "switch_port_rx").
-- All other packets reach the shared pipeline, logged as they are written
-- to the egress FIFO (i.e., "mac_core" or "router2_pipeline"). This log
-- includes packets dropped due to routine egress FIFO overflows.
--
-- However, it is not practical to log packets dropped by the egress pipeline
-- (i.e., "switch_port_tx"). Currently, this can only be caused by missing PTP
-- timestamps, so this coverage gap is non-essential.
-- TODO: Is there a practical way to detect and log egress errors?
--
-- In low-rate debugging (i.e., only a few packets per second), the log
-- will record every single packet.  At higher rates, it will attempt to
-- record packet information on a best-effort basis, with placeholders
-- indicating how many packets were skipped between complete records.
--
-- The "core" block provides a generic byte-stream output, with one
-- packet per 24-byte descriptor message as follows:
--  * Timestamp in microseconds (24-bit)
--    Counts up from switch reset, wraparound every 16.7 seconds.
--  * Type indicator (3-bit)
--      * 0 = Delivered packet
--      * 1 = Dropped packet
--      * 2 = Skipped packet(s)
--      * (3-7 reserved)
--  * Source port number (5-bit)
--  * Destination MAC address (48-bit)
--  * Source MAC address (48-bit)
--  * EtherType (16-bit)
--  * VLAN tag (16-bit)
--  * Metadata for this packet
--    Interpretation depends on the "Type indicator", see above.
--      * Type = 0: Destination bit-mask
--        Bit 31-00: Packet delivered to each port with a '1' bit.
--      * Type = 1: Reason for packet drop
--        Bit 31-08: Reserved
--        Bit 07-00: Reason code, see "eth_frame_common.vhd"
--      * Type = 2: Number of skipped packets
--        Bit 31-16: Packets dropped
--        Bit 15-00: Packets delivered
--
-- See also: eth_frame_log, mac_log_cfgbus, mac_log_uart.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.switch_types.all;

entity mac_log_core is
    generic (
    CORE_CLK_HZ : positive;         -- Core clock frequency (Hz)
    OUT_BYTES   : positive;         -- Output stream width
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

    -- Formatted log data w/ AXI flow-control.
    out_clk     : in  std_logic;
    out_data    : out std_logic_vector(8*OUT_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to OUT_BYTES;
    out_last    : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Clock and synchronous reset.
    core_clk    : in  std_logic;
    reset_p     : in  std_logic);
end mac_log_core;

architecture mac_log_core of mac_log_core is

-- Fixed-length packet descriptor is sent over many clock cycles.
-- Calculate the number of valid bytes in the final output word.
constant BYTE_COUNT : positive := 24;   -- Bytes per descriptor
constant WORD_COUNT : positive := div_ceil(BYTE_COUNT, OUT_BYTES);
constant WORD_EXTRA : natural  := OUT_BYTES * WORD_COUNT - BYTE_COUNT;
constant WORD_NLAST : positive := OUT_BYTES - WORD_EXTRA;

-- Define message header fields.
subtype msg_type_t is std_logic_vector(2 downto 0);
constant TYPE_KEEP  : msg_type_t := "000";
constant TYPE_DROP  : msg_type_t := "001";
constant TYPE_SKIP  : msg_type_t := "010";

-- Other convenience types.
subtype array_log is log_meta_array(PORT_COUNT-1 downto 0);
subtype array_std is std_logic_vector(PORT_COUNT-1 downto 0);
subtype count_t is unsigned(15 downto 0);
subtype nlast_t is integer range 0 to OUT_BYTES;
subtype sreg_t is std_logic_vector(0 to 8*OUT_BYTES*WORD_COUNT-1);

-- Timestamp counter.
signal time_ctr     : unsigned(23 downto 0);

-- Input pipeline.
signal mac_drop     : std_logic;
signal mac_keep     : std_logic;
signal mask_data    : array_log := (others => LOG_META_NULL);
signal mask_count   : count_t := (others => '0');
signal mask_psrc    : unsigned(4 downto 0) := (others => '0');
signal comb_data    : log_meta_t := LOG_META_NULL;
signal comb_count   : count_t := (others => '0');
signal comb_drop    : count_t := (others => '0');
signal comb_keep    : count_t := (others => '0');
signal comb_dmask   : array_std := (others => '0');
signal comb_psrc    : unsigned(4 downto 0) := (others => '0');
signal sreg_data    : sreg_t := (others => 'X');
signal sreg_nlast   : integer range 0 to OUT_BYTES := 0;
signal sreg_rem     : integer range 0 to WORD_COUNT := 0;
signal comb_any     : std_logic;
signal skip_any     : std_logic;
signal skip_drop_d  : count_t;
signal skip_drop_q  : count_t := (others => '0');
signal skip_keep_d  : count_t;
signal skip_keep_q  : count_t := (others => '0');
signal skip_meta    : std_logic_vector(31 downto 0);
signal start_valid  : std_logic;
signal start_ready  : std_logic;
signal fifo_data    : std_logic_vector(8*OUT_BYTES-1 downto 0) := (others => '0');
signal fifo_nlast   : nlast_t;
signal fifo_commit  : std_logic;
signal fifo_write   : std_logic;
signal fifo_qfull   : std_logic;

-- Clock-crossing constraints for selected input signals.
attribute satcat5_cross_clock_src : boolean;
attribute satcat5_cross_clock_src of port_data : signal is true;
attribute satcat5_cross_clock_dst : boolean;
attribute satcat5_cross_clock_dst of mask_data : signal is true;

begin

-- Microsecond-resolution timestamp counter.
u_timer : entity work.config_timestamp
    generic map(
    REFCLK_HZ   => CORE_CLK_HZ,
    CTR_HZ      => 1_000_000,
    CTR_WIDTH   => 24)
    port map(
    out_ctr     => time_ctr,
    refclk      => core_clk,
    reset_p     => reset_p);

-- Is the MAC input a KEEP or DROP event?
mac_keep <= mac_write and or_reduce(mac_dmask);
mac_drop <= mac_write and not mac_keep;

-- Consolidate active input(s) from ingress ports, noting collisions.
-- Use of OR-trees is smaller and faster than a 32-way MUX, at the
-- cost of collisions if there are concurrent inputs. (See below.)
p_input : process(core_clk)
    function int2count(x: natural) return count_t is
    begin
        return to_unsigned(x, count_t'length);
    end function;

    function or_reduce(x: array_log) return log_meta_t is
        variable tmp : log_meta_t := LOG_META_NULL;
    begin
        for n in x'range loop
            tmp.dst_mac := tmp.dst_mac or x(n).dst_mac;
            tmp.src_mac := tmp.src_mac or x(n).src_mac;
            tmp.etype   := tmp.etype   or x(n).etype;
            tmp.vtag    := tmp.vtag    or x(n).vtag;
            tmp.reason  := tmp.reason  or x(n).reason;
        end loop;
        return tmp;
    end function;
begin
    if rising_edge(core_clk) then
        -- Pipeline stage 2: OR-reduce all active input(s).
        if (mac_write = '1') then
            comb_data   <= mac_data;
            comb_dmask  <= mac_dmask;
            comb_psrc   <= to_unsigned(mac_psrc, comb_psrc'length);
        else
            comb_data   <= or_reduce(mask_data);
            comb_dmask  <= mac_dmask;
            comb_psrc   <= mask_psrc;
        end if;

        comb_drop <= int2count(u2i(mac_drop)) + mask_count;
        comb_keep <= int2count(u2i(mac_keep));

        -- Pipeline stage 1: Count and mask active inputs.
        -- TODO: Extra buffers on each input is resource-intensive. Can
        --   we be more aggressive on timing to save FPGA resources?
        mask_count  <= int2count(count_ones(port_write));
        mask_psrc   <= one_hot_decode(port_write, mask_psrc'length);
        for n in port_data'range loop
            if (port_write(n) = '1') then
                mask_data(n) <= port_data(n);
            else
                mask_data(n) <= LOG_META_NULL;
            end if;
        end loop;
    end if;
end process;

-- Cumulative counters for skipped packets.
comb_any    <= bool2bit(comb_drop = 1 xor comb_keep = 1);
skip_any    <= bool2bit(skip_drop_q > 0 or skip_keep_q > 0);
skip_drop_d <= skip_drop_q + comb_drop;
skip_keep_d <= skip_keep_q + comb_keep;
skip_meta   <= std_logic_vector(skip_drop_d & skip_keep_d);

-- Are we able to accept a new message into the shift register?
start_valid <= comb_any or skip_any;
start_ready <= bool2bit(sreg_rem < 2) and not fifo_qfull;

-- Message formatting using a shift-register.
p_sreg : process(core_clk)
    impure function make_msg(
        typ:  msg_type_t;       -- Message type (normal / drop / skip)
        meta: std_logic_vector) -- Other metadata (varies by type)
        return sreg_t
    is
        constant PAD : std_logic_vector(8*WORD_EXTRA-1 downto 0) := (others => '0');
        variable msg : sreg_t :=
            std_logic_vector(time_ctr) &                -- 24 bits
            typ & std_logic_vector(comb_psrc) &         -- 8 bits
            comb_data.dst_mac & comb_data.src_mac &     -- 96 bits
            comb_data.etype & comb_data.vtag &          -- 32 bits
            resize(meta, 32) & PAD;                     -- 32 bits + zpad
    begin
        return msg;
    end function;
begin
    if rising_edge(core_clk) then
        -- Load new shift-register contents.
        if (sreg_rem > 1) then
            -- Emit next word in the current message.
            sreg_data <= shift_left(sreg_data, 8*OUT_BYTES);
        elsif (skip_any = '1') then
            -- Emit a summary of all skipped packets.
            sreg_data <= make_msg(TYPE_SKIP, skip_meta);
        elsif (comb_drop = 1) then
            -- Log the dropped packet.
            sreg_data <= make_msg(TYPE_DROP, comb_data.reason);
        elsif (comb_keep = 1) then
            -- Log the accepted packet.
            sreg_data <= make_msg(TYPE_KEEP, comb_dmask);
        else
            -- Idle state / don't-care.
            sreg_data <= (others => 'X');
        end if;

        -- Update the counters for skipped packets.
        if (reset_p = '1') then
            skip_drop_q <= (others => '0');
            skip_keep_q <= (others => '0');
        elsif (start_valid = '1' and start_ready = '1') then
            skip_drop_q <= (others => '0');
            skip_keep_q <= (others => '0');
        else
            skip_drop_q <= skip_drop_d;
            skip_keep_q <= skip_keep_d;
        end if;

        -- Update the remaining-words counter.
        if (reset_p = '1') then
            sreg_rem <= 0;              -- Reset
        elsif (start_valid = '1' and start_ready = '1') then
            sreg_rem <= WORD_COUNT;     -- Start
        elsif (sreg_rem > 0) then
            sreg_rem <= sreg_rem - 1;   -- Continue
        end if;
    end if;
end process;

-- Output buffer and clock-domain crossing.
fifo_data   <= sreg_data(0 to 8*OUT_BYTES-1);
fifo_write  <= bool2bit(sreg_rem > 0);
fifo_commit <= bool2bit(sreg_rem = 1);
fifo_nlast  <= WORD_NLAST when (sreg_rem = 1) else 0;

u_fifo : entity work.fifo_packet
    generic map(
    INPUT_BYTES     => OUT_BYTES,
    OUTPUT_BYTES    => OUT_BYTES,
    BUFFER_KBYTES   => 2,
    MAX_PACKETS     => 64,
    MAX_PKT_BYTES   => 32)
    port map(
    in_clk          => core_clk,
    in_data         => fifo_data,
    in_nlast        => fifo_nlast,
    in_last_commit  => fifo_commit,
    in_last_revert  => '0',
    in_write        => fifo_write,
    in_qfull        => fifo_qfull,
    out_clk         => out_clk,
    out_data        => out_data,
    out_nlast       => out_nlast,
    out_last        => out_last,
    out_valid       => out_valid,
    out_ready       => out_ready,
    reset_p         => reset_p);

end mac_log_core;
