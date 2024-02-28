--------------------------------------------------------------------------
-- Copyright 2020-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Auxiliary packet injector
--
-- This is a general-purpose infrastructure function that allows packets
-- from various secondary streams to be "injected" during idle time on a
-- primary data stream.  (e.g., For insertion of keep-alive messages,
-- ARP requests, and other low-volume traffic.)
--
-- All ports use AXI-style valid/ready flow control.  The lowest-numbered
-- input port gets the highest priority, followed by port #1, #2, and so on.
-- That input is locked-in until the end-of-frame, at which point a new port
-- is selected.
--
-- Due to limitations of VHDL'93 syntax, we use "named index" ports rather
-- than a true array-of-vectors for input data.  Maximum supported size is
-- INPUT_COUNT = 8 to keep copy-pasted code size manageable.  Leave any
-- unused ports disconnected. This is an ugly but necessary workaround.
--
-- An optional PAUSE flag can be used to withhold input selection for as
-- long as the flag is asserted. If a frame is currently in-progress, this
-- will halt output at the next packet boundary.
--
-- By default, all inputs are required to provide contiguous data (i.e., once
-- asserted, VALID cannot be deasserted until end-of-frame), but this rule-
-- check can be disabled if desired. This includes separate options for the
-- "primary" input (Index 0) and "auxiliary" inputs (Index 1+).
--
-- If the primary input stream CANNOT use flow control, use a FIFO such as
-- "fifo_large_sync".  The FIFO depth must be large enough to accommodate the
-- worst-case time spent servicing another output.  If out_ready is held
-- constant-high, then the minimum FIFO size is equal to:
--  MIN_FIFO_BYTES = MAX_OUT_BYTES + 3*IO_BYTES
--
-- The "out_aux" flag indicates if the current output was taken from the
-- primary input or one of the auxiliary input(s).
--
-- As a failsafe, malformed packets from auxiliary sources may be fragmented
-- in order to preserve data flow on the primary stream.  This contingency
-- is triggered only if they exceed the specified maximum length.  Error
-- strobes are provided to facilitate any further required action.
--
-- Example usage:
--  * Primary data port with no flow control.  Data should be written to a
--    FIFO large enough for one max-length packet (typically 2 kiB).
--  * Secondary port(s) each have AXI valid/ready flow control, with the
--    added caveat that packet data must be contiguous once started.
--  * When idle, or at the end of each output packet, or if an auxiliary
--    frame exceeds the specified maximum length, switch inputs:
--     a) If there's any data in the FIFO, always prioritize that input.
--     b) Otherwise select any of the waiting secondary ports.
--  * Once selected, that port selection is locked until end-of-frame.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity packet_inject is
    generic (
    -- Number and size of of input data ports.
    INPUT_COUNT     : positive;
    IO_BYTES        : positive := 1;
    META_WIDTH      : natural := 0;
    -- Options for each output frame.
    APPEND_FCS      : boolean;
    MIN_OUT_BYTES   : natural := 0;
    MAX_OUT_BYTES   : positive := 65535;
    -- Enforce rules on primary and secondary inputs?
    RULE_PRI_MAXLEN : boolean := true;
    RULE_PRI_CONTIG : boolean := true;
    RULE_AUX_MAXLEN : boolean := true;
    RULE_AUX_CONTIG : boolean := true);
    port (
    -- "Vector" of named input ports:
    -- Priority goes to the lowest-numbered input channel with valid data.
    -- The "in_last" port is for legacy compatiblity, ignored if IO_BYTES > 1.
    in0_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in1_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in2_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in3_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in4_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in5_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in6_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in7_data        : in  std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
    in0_nlast       : in  integer range 0 to IO_BYTES := 0;
    in1_nlast       : in  integer range 0 to IO_BYTES := 0;
    in2_nlast       : in  integer range 0 to IO_BYTES := 0;
    in3_nlast       : in  integer range 0 to IO_BYTES := 0;
    in4_nlast       : in  integer range 0 to IO_BYTES := 0;
    in5_nlast       : in  integer range 0 to IO_BYTES := 0;
    in6_nlast       : in  integer range 0 to IO_BYTES := 0;
    in7_nlast       : in  integer range 0 to IO_BYTES := 0;
    in0_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in1_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in2_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in3_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in4_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in5_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in6_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in7_meta        : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_last         : in  std_logic_vector(INPUT_COUNT-1 downto 0) := (others => '0');
    in_valid        : in  std_logic_vector(INPUT_COUNT-1 downto 0);
    in_ready        : out std_logic_vector(INPUT_COUNT-1 downto 0);

    -- Rule-violation error strobe for any of the inputs.
    in_error        : out std_logic;

    -- Combined output port
    out_data        : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta        : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast       : out integer range 0 to IO_BYTES;
    out_last        : out std_logic;
    out_valid       : out std_logic;
    out_ready       : in  std_logic;
    out_aux         : out std_logic;
    out_pause       : in  std_logic := '0';

    -- System clock and reset.
    clk             : in  std_logic;
    reset_p         : in  std_logic);
end packet_inject;

architecture packet_inject of packet_inject is

-- Local type definitions.
-- Note: Metadata appends an extra bit for the source flag (PRI/AUX).
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;
subtype meta_t is std_logic_vector(META_WIDTH downto 0);
type data_array is array(0 to INPUT_COUNT-1) of data_t;
type last_array is array(0 to INPUT_COUNT-1) of last_t;
type meta_array is array(0 to INPUT_COUNT-1) of meta_t;

-- Legacy format conversion for LAST strobe if IO_BYTES = 1.
function convert_nlast(nlast: last_t; last: std_logic) return last_t is
begin
    if (IO_BYTES = 1 and last = '1') then
        return 1;
    else
        return nlast;
    end if;
end function;

-- Convert input to a proper array.
signal in_data          : data_array;
signal in_nlast         : last_array;
signal in_meta          : meta_array;

-- State encoding: 0 = Idle, 1+ = Input N-1
constant STATE_IDLE     : integer := 0;
signal sel_state        : integer range 0 to INPUT_COUNT := STATE_IDLE;
signal sel_change       : std_logic := '0';
signal sel_mask         : std_logic_vector(0 to INPUT_COUNT-1);

-- Select the designated output.
signal mux_data         : data_t := (others => '0');
signal mux_meta         : meta_t := (others => '0');
signal mux_nlast        : last_t := 0;
signal mux_valid        : std_logic := '0';
signal mux_ready        : std_logic;
signal mux_clken        : std_logic;
signal adj_meta         : meta_t;

-- Max-length watchdog.
signal len_watchdog     : integer range 0 to MAX_OUT_BYTES-IO_BYTES := 0;
signal error_contig     : std_logic := '0';
signal error_maxlen     : std_logic := '0';

begin

-- Upstream flow-control.
gen_flow : for n in in_ready'range generate
    sel_mask(n) <= bool2bit(sel_state = n + 1)
                or bool2bit(n = 0 and sel_state = STATE_IDLE and out_pause = '0');
    in_ready(n) <= sel_mask(n) and mux_clken;
end generate;

-- Combined error strobe.
in_error <= error_contig or error_maxlen;

-- Convert input to a proper array.
assert (INPUT_COUNT <= 8);  -- Limited only by named port indices

gen_in0 : if INPUT_COUNT > 0 generate
    in_data(0)  <= in0_data;
    in_meta(0)  <= in0_meta & '0';  -- Source-flag = primary
    in_nlast(0) <= convert_nlast(in0_nlast, in_last(0));
end generate;

gen_in1 : if INPUT_COUNT > 1 generate
    in_data(1)  <= in1_data;
    in_meta(1)  <= in1_meta & '1';  -- Source-flag = secondary
    in_nlast(1) <= convert_nlast(in1_nlast, in_last(1));
end generate;

gen_in2 : if INPUT_COUNT > 2 generate
    in_data(2)  <= in2_data;
    in_meta(2)  <= in2_meta & '1';
    in_nlast(2) <= convert_nlast(in2_nlast, in_last(2));
end generate;

gen_in3 : if INPUT_COUNT > 3 generate
    in_data(3)  <= in3_data;
    in_meta(3)  <= in3_meta & '1';
    in_nlast(3) <= convert_nlast(in3_nlast, in_last(3));
end generate;

gen_in4 : if INPUT_COUNT > 4 generate
    in_data(4)  <= in4_data;
    in_meta(4)  <= in4_meta & '1';
    in_nlast(4) <= convert_nlast(in4_nlast, in_last(4));
end generate;

gen_in5 : if INPUT_COUNT > 5 generate
    in_data(5)  <= in5_data;
    in_meta(5)  <= in5_meta & '1';
    in_nlast(5) <= convert_nlast(in5_nlast, in_last(5));
end generate;

gen_in6 : if INPUT_COUNT > 6 generate
    in_data(6)  <= in6_data;
    in_meta(6)  <= in6_meta & '1';
    in_nlast(6) <= convert_nlast(in6_nlast, in_last(6));
end generate;

gen_in7 : if INPUT_COUNT > 7 generate
    in_data(7)  <= in7_data;
    in_meta(7)  <= in7_meta & '1';
    in_nlast(7) <= convert_nlast(in7_nlast, in_last(7));
end generate;

-- Input-selection state machine.
mux_clken  <= mux_ready or not mux_valid;
sel_change <= mux_clken when (sel_state = STATE_IDLE)
         else mux_clken when (len_watchdog + IO_BYTES >= MAX_OUT_BYTES)
         else (in_valid(sel_state-1) and bool2bit(in_nlast(sel_state-1) > 0));

p_sel : process(clk)
    function get_index(x : natural) return natural is
    begin
        if (x = STATE_IDLE) then
            return 0;       -- Idle state defaults to primary input.
        else
            return x - 1;   -- Specific active index.
        end if;
    end function;
begin
    if rising_edge(clk) then
        -- Update the selected input channel between packets.
        if (reset_p = '1') then
            sel_state <= STATE_IDLE;
        elsif (mux_clken = '1' and sel_change = '1') then
            -- Revert to idle state in most cases.
            sel_state <= STATE_IDLE;
            -- If we're already idle, pick the highest priority active input.
            if (sel_state = STATE_IDLE and out_pause = '0') then
                for n in INPUT_COUNT-1 downto 0 loop
                    if (in_valid(n) = '1') then
                        sel_state <= n+1;
                    end if;
                end loop;
            end if;
        end if;

        -- Watchdog timer for designated inputs.
        if (reset_p = '1' or sel_change = '1') then
            len_watchdog <= 0;
        elsif (mux_clken = '1' and RULE_PRI_MAXLEN and sel_state = 1) then
            len_watchdog <= len_watchdog + IO_BYTES;
        elsif (mux_clken = '1' and RULE_AUX_MAXLEN and sel_state > 1) then
            len_watchdog <= len_watchdog + IO_BYTES;
        end if;

        -- One-word buffer for the selected input.
        if (reset_p = '1') then
            mux_valid <= '0';   -- Global reset
        elsif (mux_clken = '0') then
            null;               -- Retain current data
        elsif (sel_state = STATE_IDLE and out_pause = '1') then
            mux_valid <= '0';   -- Pause before next frame
        else
            -- Normal case: Copy in_valid from the active input.
            mux_valid <= in_valid(get_index(sel_state));
        end if;

        if (mux_clken = '1') then
            -- Buffered copy of the active input.
            mux_data  <= in_data(get_index(sel_state));
            mux_meta  <= in_meta(get_index(sel_state));
            mux_nlast <= in_nlast(get_index(sel_state));
        end if;

        -- Check for various error conditions.
        if (reset_p = '1' or sel_state = STATE_IDLE) then
            error_maxlen <= '0';
            error_contig <= '0';
        elsif (mux_clken = '1') then
            error_maxlen <= bool2bit(len_watchdog + IO_BYTES >= MAX_OUT_BYTES
                                 and in_nlast(sel_state-1) = 0);
            error_contig <= bool2bit((sel_state = 1 and RULE_PRI_CONTIG)
                                  or (sel_state > 1 and RULE_AUX_CONTIG))
                        and not in_valid(sel_state-1);
        end if;
    end if;
end process;

-- (Optional) Add zero-padding and append FCS/CRC32 to each frame.
gen_crc : if (MIN_OUT_BYTES > 0 or APPEND_FCS) generate
    u_crc : entity work.eth_frame_adjust
        generic map(
        MIN_FRAME   => MIN_OUT_BYTES,   -- Zero-padding as needed
        APPEND_FCS  => APPEND_FCS,      -- Append FCS to final output?
        IO_BYTES    => IO_BYTES,        -- Main port width
        META_WIDTH  => META_WIDTH + 1,  -- Extra bit for "aux" flag
        STRIP_FCS   => false)           -- No FCS to be stripped
        port map(
        in_data     => mux_data,
        in_meta     => mux_meta,
        in_nlast    => mux_nlast,
        in_valid    => mux_valid,
        in_ready    => mux_ready,
        out_data    => out_data,
        out_meta    => adj_meta,
        out_nlast   => out_nlast,
        out_last    => out_last,
        out_valid   => out_valid,
        out_ready   => out_ready,
        clk         => clk,
        reset_p     => reset_p);
end generate;

gen_nocrc : if (MIN_OUT_BYTES = 0 and not APPEND_FCS) generate
    out_data  <= mux_data;
    adj_meta  <= mux_meta;
    out_nlast <= mux_nlast;
    out_last  <= bool2bit(mux_nlast > 0);
    out_valid <= mux_valid;
    mux_ready <= out_ready;
end generate;

-- Split AUX flag from the rest of the metadata, if present.
out_aux <= adj_meta(0);
gen_meta : if META_WIDTH > 0 generate
    out_meta <= adj_meta(META_WIDTH downto 1);
end generate;

end packet_inject;
