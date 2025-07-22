--------------------------------------------------------------------------
-- Copyright 2025 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Diagnostic logging for Ethernet frames
--
-- Given an input stream containing Ethernet frames and VLAN metadata, this
-- block gathers the first 14 bytes and presents a completed "log_meta_t"
-- packet descriptor for use by the "mac_logging" block.  The input stream
-- should NOT contain VLAN tags; these must be presented as a side channel.
--
-- In normal mode, the block presents a packet descriptor for every input
-- packet.  (i.e., By strobing "out_write" and toggling "out_toggle".)
-- In filter mode, the block presents only dropped or rejected packets.
--
-- If this block is used in clock-domain crossings, enable OUT_BUFFER to
-- ensure outputs change only at the end of each packet.  Disabling this
-- flag saves resources by omitting the secondary register.
-- TODO: Is this required on 1-gigabit ports? Inter-packet gap = 8 clocks.
--
-- Optional inputs "in_dmask" and "in_psrc" are not used internally, but
-- are provided as a passthrough to "out_dmask" and "out_psrc", with delay
-- matched to the other output signals.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;
use     work.switch_types.all;

entity eth_frame_log is
    generic (
    INPUT_BYTES : positive;             -- Datapath width
    FILTER_MODE : boolean := false;     -- Log dropped packets only?
    OUT_BUFFER  : boolean := true;      -- Enable double-buffering?
    OVR_DELAY   : positive := 1;        -- Delay of overflow strobe (1 or 2)
    PORT_COUNT  : positive := 1);       -- Number of ports (for psrc)
    port (
    -- Input port does not use flow control.
    in_data     : in  std_logic_vector(8*INPUT_BYTES-1 downto 0);
    in_dmask    : in  std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
    in_psrc     : in  integer range 0 to PORT_COUNT-1 := 0;
    in_meta     : in  switch_meta_t;
    in_nlast    : in  integer range 0 to INPUT_BYTES;
    in_result   : in  frm_result_t;
    in_write    : in  std_logic;

    -- Optional overflow strobe arrives OVR_DELAY after other inputs.
    -- (Matched-delay destination mask is provided for reference.)
    ovr_strobe  : in  std_logic := '0';
    ovr_dmask   : out std_logic_vector(PORT_COUNT-1 downto 0);

    -- Output port uses AXI-style flow control.
    out_data    : out log_meta_t;
    out_dmask   : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_psrc    : out integer range 0 to PORT_COUNT-1;
    out_strobe  : out std_logic;
    out_toggle  : out std_logic;

    -- Clock and synchronous reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_log;

architecture eth_frame_log of eth_frame_log is

-- Matched delay for most inputs.
signal dly_data     : std_logic_vector(8*INPUT_BYTES-1 downto 0);
signal dly_dmask    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal dly_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal dly_meta     : switch_meta_t;
signal dly_nlast    : integer range 0 to INPUT_BYTES;
signal dly_result   : frm_result_t;
signal dly_write    : std_logic;

-- Frame header parsing.
signal frm_dst      : mac_addr_t := (others => '0');
signal frm_src      : mac_addr_t := (others => '0');
signal frm_typ      : mac_type_t := (others => '0');
signal frm_vtag     : vlan_hdr_t := (others => '0');
signal frm_dmask    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal frm_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal frm_reason   : reason_t := REASON_KEEP;
signal frm_commit   : std_logic := '0';
signal frm_revert   : std_logic := '0';

-- Double-buffered output.
signal log_data     : log_meta_t := LOG_META_NULL;
signal log_reason   : reason_t := REASON_KEEP;
signal log_toggle   : std_logic := '0';
signal log_write    : std_logic := '0';
signal reg_data     : log_meta_t := LOG_META_NULL;
signal reg_dmask    : std_logic_vector(PORT_COUNT-1 downto 0) := (others => '0');
signal reg_psrc     : integer range 0 to PORT_COUNT-1 := 0;
signal reg_strobe   : std_logic := '0';
signal reg_toggle   : std_logic := '0';

begin

-- Delay inputs to align with the overflow strobe.
u_dly : entity work.packet_delay
    generic map(
    IO_BYTES    => INPUT_BYTES,
    DELAY_COUNT => OVR_DELAY - 1,
    PORT_COUNT  => PORT_COUNT)
    port map(
    in_data     => in_data,
    in_mask     => in_dmask,
    in_meta     => in_meta,
    in_psrc     => in_psrc,
    in_nlast    => in_nlast,
    in_write    => in_write,
    in_result   => in_result,
    out_data    => dly_data,
    out_mask    => dly_dmask,
    out_meta    => dly_meta,
    out_psrc    => dly_psrc,
    out_nlast   => dly_nlast,
    out_write   => dly_write,
    out_result  => dly_result,
    io_clk      => clk,
    reset_p     => reset_p);

-- Frame header parsing.
p_frame : process(clk)
    -- Count words for frame parsing using strm_byte_xx functions.
    constant WCOUNT_MAX : integer := 1 + div_floor(ETH_HDR_DATA, INPUT_BYTES);
    variable wcount : integer range 0 to WCOUNT_MAX := 0;
    variable btmp : byte_t;
begin
    if rising_edge(clk) then
        -- Store each field in the Ethernet frame header.
        if (dly_write = '1') then
            -- Destination MAC (Bytes 0-5)
            for n in 0 to 5 loop
                if (strm_byte_present(INPUT_BYTES, ETH_HDR_DSTMAC+n, wcount)) then
                    frm_dst(47-8*n downto 40-8*n) <=
                        strm_byte_value(ETH_HDR_DSTMAC+n, dly_data);
                end if;
            end loop;

            -- Source MAC (Bytes 6-11)
            for n in 0 to 5 loop
                if (strm_byte_present(INPUT_BYTES, ETH_HDR_SRCMAC+n, wcount)) then
                    frm_src(47-8*n downto 40-8*n) <=
                        strm_byte_value(ETH_HDR_SRCMAC+n, dly_data);
                end if;
            end loop;

            -- EtherType (Bytes 12-13)
            for n in 0 to 1 loop
                if (strm_byte_present(INPUT_BYTES, ETH_HDR_ETYPE+n, wcount)) then
                    frm_typ(15-8*n downto 8-8*n) <=
                        strm_byte_value(ETH_HDR_ETYPE+n, dly_data);
                end if;
            end loop;

            -- VLAN metadata.
            if (dly_nlast > 0) then
                frm_dmask <= dly_dmask;
                frm_psrc  <= dly_psrc;
                frm_vtag  <= dly_meta.vtag;
            end if;
        end if;

        -- Matched delay for commit and revert strobes.
        -- (With "packet_delay" above, aligned with "dly_ovrflow" strobe.)
        frm_commit <= dly_write and bool2bit(dly_nlast > 0) and dly_result.commit;
        frm_revert <= dly_write and bool2bit(dly_nlast > 0) and dly_result.revert;
        frm_reason <= dly_result.reason;

        -- Count words for frame parsing.
        if (reset_p = '1') then
            wcount := 0;
        elsif (dly_write = '1' and dly_nlast > 0) then
            wcount := 0;
        elsif (dly_write = '1' and wcount < WCOUNT_MAX) then
            wcount := wcount + 1;
        end if;
    end if;
end process;

-- Normal mode logs all packets, filter logs only dropped packets.
ovr_dmask   <= frm_dmask;
log_reason  <= DROP_OVERFLOW when (ovr_strobe = '1') else frm_reason;
log_toggle  <= log_write xor reg_toggle;
log_write   <= (frm_revert or ovr_strobe) when FILTER_MODE
          else (frm_revert or ovr_strobe or frm_commit);
log_data    <= (
    dst_mac => frm_dst,
    src_mac => frm_src,
    etype   => frm_typ,
    vtag    => frm_vtag,
    reason  => log_reason);

-- Optionally double-buffer the final output.
p_buffer : process(clk)
begin
    if rising_edge(clk) then
        reg_strobe <= log_write;
        reg_toggle <= log_toggle;

        if (OUT_BUFFER and log_write = '1') then
            reg_data  <= log_data;
            reg_dmask <= frm_dmask;
            reg_psrc  <= frm_psrc;
        end if;
    end if;
end process;

out_data    <= reg_data   when OUT_BUFFER else log_data;
out_dmask   <= reg_dmask  when OUT_BUFFER else frm_dmask;
out_psrc    <= reg_psrc   when OUT_BUFFER else frm_psrc;
out_strobe  <= reg_strobe when OUT_BUFFER else log_write;
out_toggle  <= reg_toggle when OUT_BUFFER else log_toggle;

end eth_frame_log;
