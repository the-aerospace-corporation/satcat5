--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Explicit Congestion Notification (ECN) with Random Early Detection (RED)
--
-- The ECN flag is a two-bit field in the IPv4 header, which allows
-- routers to indicate persistent congestion without dropping a packet.
-- Use of the ECN field is defined in IETF RFC-3168:
--  https://www.rfc-editor.org/rfc/rfc3168
--
-- To decide when the ECN flag should be set, this block uses the
-- Random Early Detection (RED) process defined in IETF RFC-2309:
--  https://www.rfc-editor.org/rfc/rfc2309
--
-- Decisions to mark (i.e., set the ECN flag) or drop a frame are based
-- on the time-averaged queue depth (see "router2_qdepth"). As this
-- quantity increases, so does the probability of taking action:
--
-- P(mark/drop) ^
--   256 = 100% |        / P_mark
--              |       /    / P_drop
--              |      /    /
--              |     /    /
--              |    /    /
--      0 = 0%  +------------+-> Queue depth
--              0 = Empty    255 = Full
--
-- Queue depth is a scale from 0 (empty) to 255 (completely full).
-- Mark/drop probability (P) is a matching scale from 0 (0%) to 256 (100%).
-- The probability is a memoryless function of the queue depth (d), given
-- by a minimum threshold (t) and a slope (s):
-- * If d <= t, P = 0               (Depth is below minimum threshold)
-- * Otherwise, P = (d-t) * s       (Linear increase above threshold)
--
-- Finally, an internal PRNG (x) decides the action for each packet:
--  * If x < P_drop: Drop the packet.
--  * Otherwise, if x < P_mark:
--      * If ECN is enabled (ECN /= 0), mark the packet (ECN = "CE").
--      * Otherwise, drop the packet.
--  * Otherwise, forward the packet as-is.
--
-- Since this block requires status from the selected output queue, it
-- must be positioned after the gateway determines which output port(s)
-- are active.  External logic must select and present the appropriate
-- queue depth signal concurrently with the first word of the frame.
--
-- To reduce logic duplication, this block relies on "router2_ipchk" to
-- apply required changes to the IPv4 header checksum.
--
-- Control parameters are loaded over a single ConfigBus register:
--  * RT_ADDR_ECN_RED: 2x write, then read to apply
--      1st write = Mark threshold and slope.
--      2nd write = Drop threshold and slope.
--      Each word is formatted as follows:
--          Bits 31..24 = Reserved (write zeros)
--          Bits 23..16 = Threshold
--          Bits 15..00 = Slope (8.8 fixed point)
--      Read the register to latch the new configuration.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.prng_lfsr_common.all;
use     work.router2_common.all;

entity router2_ecn_red is
    generic (
    IO_BYTES    : positive;     -- Width of datapath
    META_WIDTH  : natural;      -- Width of metadata
    DEVADDR     : integer;      -- ConfigBus address
    REGADDR     : integer := RT_ADDR_ECN_RED);
    port (
    -- Input data stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_drop     : in  std_logic := '0';
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0);
    in_write    : in  std_logic;
    in_qdepth   : in  unsigned(7 downto 0);
    -- Output data stream
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_drop    : out std_logic;
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_write   : out std_logic;
    -- ConfigBus interface
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;
    -- Overrides for test and simulation (leave disconnected)
    sim_mode    : in  std_logic := '0';
    sim_prng    : in  unsigned(7 downto 0) := (others => '0');
    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_ecn_red;

architecture router2_ecn_red of router2_ecn_red is

-- Maximum byte-index of interest is end of the DSCP/ECN field.
constant WCOUNT_MAX : integer := 1 + IP_HDR_DSCP_ECN / IO_BYTES;
subtype counter_t is integer range 0 to WCOUNT_MAX;

-- Other type shortcuts
subtype word_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype prng_t is unsigned(7 downto 0);
subtype slope_t is unsigned(15 downto 0);

-- Internal PRNG and mark/drop decision
signal prng_raw     : byte_t;
signal prng_value   : unsigned(7 downto 0);
signal prng_next    : std_logic := '0';
signal prng_mark    : std_logic := '0';
signal prng_drop    : std_logic := '0';
signal in_first     : std_logic := '1';

-- Matched delay for incoming data
signal dly_data     : word_t := (others => '0');
signal dly_meta     : meta_t := (others => '0');
signal dly_nlast    : integer range 0 to IO_BYTES := 0;
signal dly_write    : std_logic := '0';
signal dly_wcount   : counter_t := 0;

-- Packet parsing and adjustments
signal adj_data     : word_t := (others => '0');
signal adj_meta     : meta_t := (others => '0');
signal adj_nlast    : integer range 0 to IO_BYTES := 0;
signal adj_drop     : std_logic := '0';
signal adj_write    : std_logic := '0';

-- ConfigBus interface
signal cpu_word     : std_logic_vector(63 downto 0);
signal cpu_mark_t   : prng_t;
signal cpu_mark_s   : slope_t;
signal cpu_drop_t   : prng_t;
signal cpu_drop_s   : slope_t;

begin

-- Internal PRNG is updated after each packet.
-- (With option to override the output for unit testing.)
prng_next   <= in_write and in_first;
prng_value  <= unsigned(prng_raw) when (sim_mode = '0') else sim_prng;

u_prng : entity work.prng_lfsr_gen
    generic map(
    IO_WIDTH    => 8,
    LFSR_SPEC   => create_prbs(23))
    port map(
    out_data    => prng_raw,
    out_valid   => open,
    out_ready   => prng_next,
    clk         => clk,
    reset_p     => reset_p);

-- Make the initial mark/drop decision.
p_prng : process(clk)
    function threshold(depth, thresh: prng_t; slope: slope_t) return slope_t is
        variable tmp : unsigned(23 downto 0) := (depth - thresh) * slope;
    begin
        if (depth < thresh) then
            return to_unsigned(0, 16);
        else
            return resize(shift_right(tmp, 8), 16);
        end if;
    end function;

    variable in_drop_d : std_logic := '0';
    variable pmark, pdrop, prng : slope_t := (others => '0');
begin
    if rising_edge(clk) then
        -- Pipeline stage 2: Compare PRNG to each calculated threshold.
        -- (Roll the dice at the start of each packet, hold decision until the end.)
        prng_mark <= bool2bit(prng < pmark);
        prng_drop <= bool2bit(prng < pdrop) or in_drop_d;

        -- Pipeline stage 1: Compute P_mark and P_drop based on queue depth.
        -- (Sync with start of frame to allow multiple destination queues.)
        if (prng_next = '1') then
            pmark := threshold(in_qdepth, cpu_mark_t, cpu_mark_s);
            pdrop := threshold(in_qdepth, cpu_drop_t, cpu_drop_s);
            prng  := resize(prng_value, prng'length);
        end if;

        -- Detect start of frame, and delay the optional "in_drop" strobe.
        if (reset_p = '1') then
            in_first  <= '1';
            in_drop_d := '0';
        elsif (in_write = '1') then
            in_first  <= bool2bit(in_nlast > 0);
            in_drop_d := in_drop;
        end if;
    end if;
end process;

-- Matched delay for incoming data.
p_dly : process(clk)
    variable tmp_data   : word_t := (others => '0');
    variable tmp_meta   : meta_t := (others => '0');
    variable tmp_nlast  : integer range 0 to IO_BYTES := 0;
    variable tmp_write  : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Pipeline stage 2:
        dly_data    <= tmp_data;
        dly_meta    <= tmp_meta;
        dly_nlast   <= tmp_nlast;
        dly_write   <= tmp_write and not reset_p;

        -- Pipeline stage 1:
        tmp_data    := in_data;
        tmp_meta    := in_meta;
        tmp_nlast   := in_nlast;
        tmp_write   := in_write and not reset_p;
    end if;
end process;

-- Packet parsing and updates.
p_packet : process(clk)
    -- Bit-mask used to set the ECN congestion flag.
    constant ECN_BYTE : natural := (IO_BYTES-1) - (IP_HDR_DSCP_ECN mod IO_BYTES);
    constant ECN_MASK : word_t := shift_left(resize(x"03", 8*IO_BYTES), 8*ECN_BYTE);
    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, dly_data);
        return strm_byte_present(IO_BYTES, bidx, dly_wcount);
    end function;
    -- Internal state uses variables to simplify sequential parsing.
    variable ecn_enable : std_logic := '0';
    variable ecn_value  : std_logic_vector(1 downto 0) := (others => '0');
begin
    if rising_edge(clk) then
        -- Packet parsing: Is this an ECN-enabled IPv4 packet?
        if (dly_write = '1') then
            -- EtherType (2 bytes)
            if (get_eth_byte(ETH_HDR_ETYPE+0)) then
                ecn_enable := bool2bit(btmp = ETYPE_IPV4(15 downto 8));
            end if;
            if (get_eth_byte(ETH_HDR_ETYPE+1)) then
                ecn_enable := ecn_enable and bool2bit(btmp = ETYPE_IPV4(7 downto 0));
            end if;
            -- DSCP/ECN field (1 byte)
            if (get_eth_byte(IP_HDR_DSCP_ECN)) then
                ecn_value := btmp(1 downto 0);
                ecn_enable := ecn_enable and or_reduce(ecn_value);
            end if;
        end if;

        -- Adjust data stream to reflect the mark/drop decision.
        if (get_eth_byte(IP_HDR_DSCP_ECN) and ecn_enable = '1' and prng_mark = '1') then
            adj_data <= dly_data or ECN_MASK;
        else
            adj_data <= dly_data;
        end if;

        -- Set the drop flag for this frame?
        if (prng_drop = '1') then
            -- Explicit drop command, including upstream requests.
            adj_drop <= '1';
        elsif (prng_mark = '1') then
            -- Mark command may be promoted if ECN isn't possible.
            adj_drop <= not ecn_enable;
        else
            -- No drop or mark requests.
            adj_drop <= '0';
        end if;

        -- Matched delay for all other signals.
        adj_meta  <= dly_meta;
        adj_nlast <= dly_nlast;
        adj_write <= dly_write and not reset_p;

        -- Word count synchronized with the "dly_data" stream.
        if (reset_p = '1') then
            dly_wcount <= 0;                -- Global reset
        elsif (dly_write = '1' and dly_nlast > 0) then
            dly_wcount <= 0;                -- Start of new frame
        elsif (dly_write = '1' and dly_wcount < WCOUNT_MAX) then
            dly_wcount <= dly_wcount + 1;   -- Count up to max
        end if;
    end if;
end process;

-- Drive top-level outputs.
out_data    <= adj_data;
out_nlast   <= adj_nlast;
out_drop    <= adj_drop;
out_meta    <= adj_meta;
out_write   <= adj_write;

-- ConfigBus interface
cpu_mark_t  <= unsigned(cpu_word(55 downto 48));
cpu_mark_s  <= unsigned(cpu_word(47 downto 32));
cpu_drop_t  <= unsigned(cpu_word(23 downto 16));
cpu_drop_s  <= unsigned(cpu_word(15 downto 0));

u_cfg : cfgbus_register_wide
    generic map(
    DWIDTH      => 64,
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    sync_clk    => clk,
    sync_val    => cpu_word);

end router2_ecn_red;
