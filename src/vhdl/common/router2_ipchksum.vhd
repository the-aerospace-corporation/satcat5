--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- IPv4 header checksum validation and adjustment
--
-- This block handles calculation of the IPv4 header checksum, and can
-- be configured in various modes.
--
-- In validation mode, it calculates the running checksum using the
-- method recommended in IETF RFC1141. The block emits a pass/fail
-- strobe two just after the end of the IPv4 header.
--
-- In adjustment mode, the block is used to replace the outgoing header.
-- Though RFC1624 gives a method for incremental updates, implementation
-- on an FPGA often requires out-of-order operations on the byte-stream,
-- which complicates on-the-fly updates to various header fields.
--
-- Instead, adjustment mode calculates a new checksum using the modified
-- IPv4 header, reducing the need for upstream blocks to repeatedly make
-- and apply read-modify-write calculations.  From-scratch calculation is
-- simpler and less error-prone than maintaining metadata for incremental
-- changes through the entire upstream pipeline.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.router2_common.all;

entity router2_ipchksum is
    generic (
    IO_BYTES    : positive;             -- Width of datapath
    ADJ_MODE    : boolean := true;      -- Adjustment or validation mode?
    ALLOW_JUMBO : boolean := false;     -- Allow jumbo frames?
    ALLOW_RUNT  : boolean := false;     -- Allow runt frames?
    META_WIDTH  : natural := 0);        -- Additional packet metadata?
    port (
    -- Input data stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_write    : in  std_logic;
    -- Early match/error strobes asserted at end of IPv4 header.
    early_match : out std_logic;    -- Validation mode only
    early_error : out std_logic;    -- Validation mode only
    -- Output data stream
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_write   : out std_logic;
    out_match   : out std_logic;    -- Validation mode only
    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_ipchksum;

architecture router2_ipchksum of router2_ipchksum is

-- Maximum byte-index of interest is end of the IPv4 header.
-- (Required to correctly generate the "pre_mask" signal.)
constant WCOUNT_MAX : integer := 1 + IP_HDR_MAX / IO_BYTES;
subtype counter_t is integer range 0 to WCOUNT_MAX;
signal in_wcount    : counter_t := 0;
signal dly_wcount   : counter_t := 0;

-- Other type shortcuts
constant META_TOTAL : integer := META_WIDTH + 17;
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;
subtype meta1_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype meta2_t is std_logic_vector(META_TOTAL-1 downto 0);

-- Byte masking
signal pre_data     : data_t := (others => '0');
signal pre_mask     : data_t := (others => '0');
signal pre_nlast    : last_t := 0;
signal pre_ipv4     : std_logic := '0';
signal pre_meta     : meta1_t := (others => '0');
signal pre_write    : std_logic := '0';
signal pre_done     : std_logic := '0';

-- Checksum calculation
signal chk_data     : data_t := (others => '0');
signal chk_nlast    : last_t := 0;
signal chk_meta     : meta2_t := (others => '0');
signal chk_write    : std_logic := '0';
signal chk_accum    : ip_checksum_t := (others => '0');
signal chk_final    : std_logic := '0';
signal chk_match    : std_logic := '0';
signal chk_error    : std_logic := '0';

-- Packet metadata FIFO
signal dly_data     : data_t := (others => '0');
signal dly_nlast    : last_t := 0;
signal dly_meta     : meta2_t := (others => '0');
signal dly_write    : std_logic := '0';
signal dly_ipv4     : std_logic := '0';

-- Apply new checksum
signal adj_data     : data_t := (others => '0');
signal adj_nlast    : last_t := 0;
signal adj_meta     : meta1_t := (others => '0');
signal adj_write    : std_logic := '0';

begin

-- Count current position in packet for each pipeline stage.
p_count : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            in_wcount <= 0; -- Global reset
        elsif (in_write = '1' and in_nlast > 0) then
            in_wcount <= 0; -- Start of new packet
        elsif (in_write = '1' and in_wcount < WCOUNT_MAX) then
            in_wcount <= in_wcount + 1;
        end if;

        if (reset_p = '1' or not ADJ_MODE) then
            dly_wcount <= 0; -- Global reset
        elsif (dly_write = '1' and dly_nlast > 0) then
            dly_wcount <= 0; -- Start of new packet
        elsif (dly_write = '1' and dly_wcount < WCOUNT_MAX) then
            dly_wcount <= dly_wcount + 1;
        end if;
    end if;
end process;

-- Identify and mask bytes that are part of the checksum.
p_pre : process(clk)
    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, in_data);
        return strm_byte_present(IO_BYTES, bidx, in_wcount);
    end function;
    -- Packet parser reads length of the IPv4 header.
    variable bsel, is_ipv4 : std_logic := '0';
    variable bidx, bmax : integer range 0 to 127 := 0;
begin
    if rising_edge(clk) then
        -- Packet-parsing state machine.
        if (in_write = '1') then
            -- Is this an IPv4 packet?
            if (get_eth_byte(ETH_HDR_ETYPE+0)) then
                is_ipv4 := bool2bit(btmp = ETYPE_IPV4(15 downto 8));
            elsif (in_wcount = 0) then
                is_ipv4 := '0'; -- Reset at start of frame.
            end if;
            if (get_eth_byte(ETH_HDR_ETYPE+1)) then
                is_ipv4 := is_ipv4 and bool2bit(btmp = ETYPE_IPV4(7 downto 0));
            end if;
            -- Read the header length field (IHL).
            -- (This value is don't-care if is_ipv4 = 0.)
            if (get_eth_byte(IP_HDR_VERSION)) then
                bmax := IP_HDR_VERSION + 4 * u2i(btmp(3 downto 0));
            elsif (in_wcount = 0) then
                bmax := 0;      -- Reset at start of frame.
            end if;
        end if;

        -- Which bytes are part of the IPv4 header checksum?
        -- In validation mode, include the entire header.
        -- In adjustment mode, do not include the checksum itself.
        pre_done <= '0';    -- Set default, override below.
        for n in 0 to IO_BYTES-1 loop
            bidx := IO_BYTES*in_wcount + n;
            if (bidx + 1 = bmax) then
                pre_done <= is_ipv4;    -- Strobe for last IPv4 header byte.
            end if;
            bsel := is_ipv4 and bool2bit(bidx >= IP_HDR_VERSION and bidx < bmax);
            if (ADJ_MODE and (bidx = IP_HDR_CHECKSUM or bidx = IP_HDR_CHECKSUM+1)) then
                bsel := '0';            -- Skip this field in adjustment mode.
            end if;
            pre_mask(pre_mask'left-8*n downto pre_mask'left-8*n-7) <= (others => bsel);
        end loop;

        -- Matched delay for other signals.
        pre_data    <= in_data;
        pre_nlast   <= in_nlast;
        pre_meta    <= in_meta;
        pre_ipv4    <= is_ipv4;
        pre_write   <= in_write and not reset_p;
    end if;
end process;

-- Checksum calculation on masked bytes.
p_chk : process(clk)
    constant ODD_BYTES : natural := IO_BYTES mod 2;
    variable ipchk : ip_checksum_t := (others => '0');
    variable bidx  : integer range 0 to ODD_BYTES := ODD_BYTES;
begin
    if rising_edge(clk) then
        -- Update checksum with the new data word.
        ipchk := ip_checksum(chk_accum, pre_data and pre_mask, bidx);

        -- Matched delay for all data and metadata.
        chk_data    <= pre_data;
        chk_meta    <= pre_meta & pre_ipv4 & std_logic_vector(not ipchk);
        chk_nlast   <= pre_nlast;
        chk_write   <= pre_write and not reset_p;
        chk_final   <= bool2bit(ipchk = 65535);
        chk_match   <= pre_done and bool2bit(ipchk = 65535);
        chk_error   <= pre_done and bool2bit(ipchk /= 65535);

        -- Cumulative checksum resets at the end of each frame.
        -- (Also track even/odd byte index, if applicable.)
        if (reset_p = '1') then
            chk_accum <= (others => '0');
            bidx := ODD_BYTES;
        elsif (pre_write = '1' and pre_nlast > 0) then
            chk_accum <= (others => '0');
            bidx := ODD_BYTES;
        elsif (pre_write = '1') then
            chk_accum <= ipchk;
            bidx := ODD_BYTES - bidx;
        end if;
    end if;
end process;

-- Additional logic for adjustment mode.
gen_adj : if ADJ_MODE generate
    -- Buffer data to ensure metadata is available from the beginning.
    u_dly : entity work.fifo_pktmeta
        generic map(
        IO_BYTES    => IO_BYTES,
        META_WIDTH  => chk_meta'length,
        ALLOW_JUMBO => ALLOW_JUMBO,
        ALLOW_RUNT  => ALLOW_RUNT)
        port map(
        in_data     => chk_data,
        in_meta     => chk_meta,
        in_nlast    => chk_nlast,
        in_write    => chk_write,
        out_data    => dly_data,
        out_meta    => dly_meta,
        out_nlast   => dly_nlast,
        out_valid   => dly_write,
        out_ready   => '1',
        clk         => clk,
        reset_p     => reset_p);

    dly_ipv4 <= dly_meta(16);

    -- Overwrite the checksum field.
    p_adj : process(clk)
        -- Thin wrapper for the stream-to-byte extractor functions.
        impure function is_ip_byte(n, bidx: natural) return boolean is
            variable bmod : natural := bidx mod IO_BYTES;
        begin
            return (n = bmod) and (dly_ipv4 = '1') and strm_byte_present(IO_BYTES, bidx, dly_wcount);
        end function;
        -- Temporary variables.
        variable btmp : byte_t := (others => '0');
    begin
        if rising_edge(clk) then
            -- Replace the checksum field, everything else as-is.
            for n in 0 to IO_BYTES-1 loop
                if (is_ip_byte(n, IP_HDR_CHECKSUM+0)) then
                    btmp := dly_meta(15 downto 8);
                elsif (is_ip_byte(n, IP_HDR_CHECKSUM+1)) then
                    btmp := dly_meta(7 downto 0);
                else
                    btmp := strm_byte_value(n, dly_data);
                end if;
                adj_data(adj_data'left-8*n downto adj_data'left-8*n-7) <= btmp;
            end loop;

            -- Matched delay for other signals.
            adj_nlast   <= dly_nlast;
            adj_meta    <= dly_meta(dly_meta'left downto 17);
            adj_write   <= dly_write and not reset_p;
        end if;
    end process;

    -- Drive top-level outputs.
    out_data    <= adj_data;
    out_nlast   <= adj_nlast;
    out_meta    <= adj_meta;
    out_write   <= adj_write;

    -- Unused in adjust mode.
    out_match   <= '1';
    early_match <= '0';
    early_error <= '0';
end generate;

-- Additional logic for validation mode.
gen_val : if not ADJ_MODE generate
    out_data    <= chk_data;
    out_nlast   <= chk_nlast;
    out_meta    <= chk_meta(chk_meta'left downto 17);
    out_write   <= chk_write;
    out_match   <= chk_final;
    early_match <= chk_match;
    early_error <= chk_error;
end generate;

end router2_ipchksum;
