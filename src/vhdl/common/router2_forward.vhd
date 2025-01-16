--------------------------------------------------------------------------
-- Copyright 2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- In-place header modification for IPv4 forwarding
--
-- This block implements basic forwarding for the IPv4 router:
--  * Replace the destination MAC with the designated address.
--  * Replace the source MAC address with the router's address.
--  * For IPv4 packets, decrement the IPv4 header's TTL field.
--
-- Note that this block does NOT make required updates to the IPv4
-- header's checksum field.  That update must be applied separately
-- by a downstream "router2_ipchksum" block.
--
-- All input and output streams contain Ethernet frames with no FCS and no
-- VLAN tags.  Provided packet metadata is preserved with a matched delay.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity router2_forward is
    generic (
    IO_BYTES    : positive;     -- Width of datapath
    META_WIDTH  : natural);     -- Width of metadata
    port (
    -- Input stream with AXI-stream flow control.
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;
    in_dstmac   : in  mac_addr_t;
    in_srcmac   : in  mac_addr_t;

    -- Output stream with AXI-stream flow control.
    -- (Offload port is indicated by MSB of out_dstmask.)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end router2_forward;

architecture router2_forward of router2_forward is

-- Packet parsing counts words from start-of-frame.
-- Last byte of interest is the IPv4 header's TTL field.
constant WORD_MAX : positive := 1 + IP_HDR_TTL / IO_BYTES;
signal in_wcount : integer range 0 to WORD_MAX := 0;

-- Modified data stream.
signal in_write     : std_logic;
signal in_ready_i   : std_logic;
signal adj_data     : std_logic_vector(8*IO_BYTES-1 downto 0) := (others => '0');
signal adj_meta     : std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
signal adj_nlast    : integer range 0 to IO_BYTES := 0;
signal adj_valid    : std_logic := '0';
signal adj_ready    : std_logic;

begin

-- Connect top-level outputs.
in_ready    <= in_ready_i;
out_data    <= adj_data;
out_meta    <= adj_meta;
out_nlast   <= adj_nlast;
out_valid   <= adj_valid;
adj_ready   <= out_ready;

-- Flow-control signals.
in_ready_i  <= out_ready or not adj_valid;
in_write    <= in_valid and in_ready_i;

-- Packet-update state machine.
p_fwd : process(clk)
    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, in_data);
        return strm_byte_present(IO_BYTES, bidx, in_wcount);
    end function;

    -- Parser state:
    variable bidx : natural := 0;
    variable is_ipv4 : std_logic := '0';
begin
    if rising_edge(clk) then
        -- Count words from start-of-frame.
        if (reset_p = '1') then
            in_wcount <= 0;                 -- System reset
        elsif (in_write = '1' and in_nlast > 0) then
            in_wcount <= 0;                 -- Start of new frame
        elsif (in_write = '1' and in_wcount < WORD_MAX) then
            in_wcount <= in_wcount + 1;     -- Count up to max
        end if;

        -- Update the "valid" strobe.
        if (reset_p = '1') then
            adj_valid <= '0';
        elsif (in_write = '1') then
            adj_valid <= '1';
        elsif (adj_ready = '1') then
            adj_valid <= '0';
        end if;

        -- Update the output word for each "in_write" strobe.
        if (in_write = '1') then
            -- Matched delay for unmodified fields.
            adj_meta    <= in_meta;
            adj_nlast   <= in_nlast;

            -- Parse each input byte...
            if (get_eth_byte(ETH_HDR_ETYPE + 0)) then
                is_ipv4 := bool2bit(btmp = ETYPE_IPV4(15 downto 8));
            elsif (get_eth_byte(ETH_HDR_ETYPE + 1)) then
                is_ipv4 := bool2bit(btmp = ETYPE_IPV4(7 downto 0)) and is_ipv4;
            end if;

            -- Choose each output byte...
            for b in 0 to IO_BYTES-1 loop
                bidx := in_wcount * IO_BYTES + b;
                btmp := strm_byte_value(b, in_data);
                if (bidx < 6) then
                    -- Replace DstMAC (first 6 bytes)
                    btmp := strm_byte_value(bidx, in_dstmac);
                elsif (bidx < 12) then
                    -- Replace SrcMAC (next 6 bytes)
                    btmp := strm_byte_value(bidx-6, in_srcmac);
                elsif (bidx = IP_HDR_TTL and is_ipv4 = '1') then
                    -- Decrement TTL field (1 byte)
                    btmp := std_logic_vector(unsigned(btmp) - 1);
                end if;
                adj_data(adj_data'left-8*b downto adj_data'left-8*b-7) <= btmp;
            end loop;
        end if;
    end if;
end process;

end router2_forward;
