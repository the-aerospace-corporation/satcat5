--------------------------------------------------------------------------
-- Copyright 2021-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- On-demand insertion of 802.1Q Virtual-LAN tags
--
-- In Virtual-LAN mode, ports serving multiple VLAN domains must include
-- 802.1Q tags, which are inserted just before the EtherType field of each
-- frame.
--
-- Note: This block modifies the frame contents, but does not recalculate
-- the frame check sequence (FCS).  It MUST be followed by a block that
-- calculates and appends a new FCS, such as "eth_frame_adjust".
--
-- Runtime configuration is write-only, using the same ConfigBus register
-- as "eth_frame_vstrip".  This block should be set to the same register
-- address.  The egress policy is set using register bits 21-20:
--  * 00 = VTAG_ADMIT_ALL (default)
--      Tags are never emitted
--  * 01 = VTAG_PRIORITY
--      Tags are always emitted (VID = 0, DEI and PCP set upstream)
--  * 10 = VTAG_MANDATORY
--      Tags are always emitted (VID, DEI, and PCP set upstream)
--  * 11 = Reserved
--
-- Note: This block uses AXI-style flow control, with additional guarantees.
-- If input data is supplied immediately on request, then the output will have
-- the same property.  This allows use with port_adjust and other blocks that
-- require contiguous data streams.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_vtag is
    generic (
    DEV_ADDR    : integer;          -- ConfigBus device address
    REG_ADDR    : integer;          -- ConfigBus register address
    PORT_INDEX  : natural;          -- Port index (for ConfigBus filtering)
    IO_BYTES    : positive := 1);   -- Width of main data port
    port (
    -- Input data stream
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_vtag     : in  vlan_hdr_t;
    in_error    : in  std_logic := '0';
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    -- Output data stream
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_error   : out std_logic;
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Configuration interface (write-only).
    cfg_cmd     : in  cfgbus_cmd;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_vtag;

architecture eth_frame_vtag of eth_frame_vtag is

-- Maximum byte-shift after inserting the four-byte tag.
constant OVR_MAX    : natural := 4 mod IO_BYTES;
constant OVR_THRESH : natural := IO_BYTES - OVR_MAX;
constant OVR_PRERD  : natural := u2i(OVR_MAX > 0);

-- Count output words to specific events.
constant WCOUNT_TAG_BEG : integer := div_floor(ETH_HDR_ETYPE-1, IO_BYTES);
constant WCOUNT_TAG_END : integer := div_floor(ETH_HDR_ETYPE+3, IO_BYTES) - OVR_PRERD;
constant WCOUNT_MAX     : integer := div_floor(ETH_HDR_ETYPE+3, IO_BYTES) + 1;

-- Define local types.
subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype sreg_t is std_logic_vector(8*(IO_BYTES+OVR_MAX)-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;
subtype shift_t is integer range 0 to OVR_MAX;

-- Input shift-register buffers leftover bytes from previous input word.
signal in_write     : std_logic;
signal in_ready_i   : std_logic;
signal in_sreg      : sreg_t := (others => '0');

-- Parse and modify the upstream VLAN tag.
signal mod_pcp      : vlan_pcp_t;
signal mod_dei      : vlan_dei_t;
signal mod_vid      : vlan_vid_t;
signal mod_vtag     : vlan_hdr_t;
signal mod_vtag_d   : vlan_hdr_t := (others => '0');

-- Control and MUX logic.
signal tag_wcount   : integer range 0 to WCOUNT_MAX := 0;
signal tag_policy   : tag_policy_t := VTAG_ADMIT_ALL;
signal tag_data     : data_t := (others => '0');
signal tag_nlast    : last_t := 0;
signal tag_novr     : shift_t := 0;
signal tag_busy     : std_logic := '0';
signal tag_error    : std_logic := '0';
signal tag_valid    : std_logic := '0';
signal tag_ready    : std_logic;
signal tag_next     : std_logic;
signal tag_prewr    : std_logic;
signal tag_final    : std_logic;

-- ConfigBus interface
signal cfg_policy   : tag_policy_t := VTAG_ADMIT_ALL;

begin

-- Upstream flow-control.
in_write    <= (in_valid and in_ready_i);
in_ready_i  <= (tag_ready or not tag_valid) and not (tag_busy or tag_prewr);
tag_next    <= (tag_ready or not tag_valid) and (in_valid or tag_busy or tag_prewr);
tag_prewr   <= bool2bit(tag_novr > 0);
tag_final   <= bool2bit(tag_novr > 0)
            or bool2bit(tag_policy = VTAG_ADMIT_ALL and in_nlast > 0)
            or bool2bit(tag_busy = '0' and in_nlast > 0 and in_nlast <= OVR_THRESH);

-- Input shift-register buffers leftover bytes from previous input word.
in_sreg(8*IO_BYTES-1 downto 0) <= in_data;

gen_sreg : for b in 0 to OVR_MAX-1 generate
    p_sreg : process(clk)
        constant POS_RD : natural := 8*b; 
        constant POS_WR : natural := 8*(IO_BYTES + b);
    begin
        if rising_edge(clk) then
            if (in_write = '1') then
                in_sreg(POS_WR+7 downto POS_WR) <= in_data(POS_RD+7 downto POS_RD);
            end if;
        end if;
    end process;
end generate;

-- Parse and modify the upstream VLAN tag.
mod_pcp     <= vlan_get_pcp(in_vtag);
mod_dei     <= vlan_get_dei(in_vtag);
mod_vid     <= vlan_get_vid(in_vtag) when (tag_policy = VTAG_MANDATORY) else VID_NONE;
mod_vtag    <= vlan_get_hdr(mod_pcp, mod_dei, mod_vid) when (tag_novr = 0) else mod_vtag_d;

-- Shared control logic.
p_ctrl : process(clk)
begin
    if rising_edge(clk) then
        -- Delayed copy of the VLAN tag, for overflow handling.
        mod_vtag_d <= mod_vtag;

        -- Buffer for propagating the upstream error flag.
        -- (This block does not generate errors of its own.)
        tag_error <= in_error;

        -- Update the output-valid flag and end-of-frame indicators.
        if (reset_p = '1') then
            tag_valid   <= '0';             -- Global reset
            tag_nlast   <= 0;
            tag_novr    <= 0;
        elsif (tag_next = '1') then
            tag_valid   <= '1';             -- Write new data (normal)
            if (tag_novr > 0) then
                tag_nlast   <= tag_novr;    -- Handle overflow
                tag_novr    <= 0;
            elsif (tag_policy = VTAG_ADMIT_ALL) then
                tag_nlast   <= in_nlast;    -- Insertion disabled
                tag_novr    <= 0;
            elsif (in_nlast = 0 or tag_busy = '1') then
                tag_nlast   <= 0;           -- Waiting for EOF
                tag_novr    <= 0;
            elsif (in_nlast > OVR_THRESH) then
                tag_nlast   <= 0;           -- Overflow to next word
                tag_novr    <= in_nlast - OVR_THRESH;
            else
                tag_nlast   <= in_nlast + OVR_MAX;
                tag_novr    <= 0;           -- EOF in current word
            end if;
        elsif (tag_ready = '1') then
            tag_valid   <= '0';             -- Old data consumed
            tag_nlast   <= 0;
            tag_novr    <= 0;
        end if;

        -- Pause reading from input while we're busy emitting the tag.
        if (reset_p = '1' or WCOUNT_TAG_BEG >= WCOUNT_TAG_END) then
            tag_busy <= '0';                -- Global reset or bypass
        elsif (tag_next = '1' and tag_nlast > 0) then
            tag_busy <= '0';                -- End of frame
        elsif (tag_next = '1' and tag_policy = VTAG_ADMIT_ALL) then
            tag_busy <= '0';                -- Tags disabled
        elsif (tag_next = '1' and tag_wcount = WCOUNT_TAG_END) then
            tag_busy <= '0';                -- End of tag-insertion
        elsif (tag_next = '1' and tag_wcount = WCOUNT_TAG_BEG) then
            tag_busy <= '1';                -- Start of tag-insertion
        end if;

        -- Count words from start of frame.
        if (reset_p = '1') then
            tag_wcount <= 0;                -- Global reset
        elsif (tag_next = '1' and tag_final = '1') then
            tag_wcount <= 0;                -- End of frame
        elsif (tag_next = '1' and tag_wcount < WCOUNT_MAX) then
            tag_wcount <= tag_wcount + 1;   -- Normal increment
        end if;

        -- Latch new tag policy at EOF or when idle.
        -- (i.e., Don't change it in the middle of a frame.)
        if (reset_p = '1') then
            tag_policy <= VTAG_ADMIT_ALL;   -- Global reset
        elsif (tag_next = '1' and tag_nlast > 0) then
            tag_policy <= cfg_policy;       -- End of frame
        elsif (tag_next = '0' and tag_wcount = 0) then
            tag_policy <= cfg_policy;       -- Idle between frames
        end if;
    end if;
end process;

-- Register for each output byte.
gen_mux : for b in 0 to IO_BYTES-1 generate
    p_mux : process(clk)
        function get_input(data: sreg_t; shift: shift_t) return byte_t is
            constant idx : natural := IO_BYTES-1 + shift - b;
            variable tmp : byte_t := data(8*idx+7 downto 8*idx);
        begin
            return tmp;
        end function;

        constant BMAX : integer := (WCOUNT_MAX + 1) * IO_BYTES - 1;
        variable bidx : integer range 0 to BMAX;        -- Combinational logic
        variable bval : byte_t;                         -- Combinational logic
    begin
        if rising_edge(clk) then
            -- MUX selects input, tag data, or shifted input.
            bidx := IO_BYTES * tag_wcount + b;
            if (tag_policy = VTAG_ADMIT_ALL or bidx < ETH_HDR_ETYPE) then
                bval := get_input(in_sreg, 0);          -- Original input
            elsif (bidx = ETH_HDR_ETYPE + 0) then
                bval := ETYPE_VLAN(15 downto 8);        -- Tag ID (MSBs)
            elsif (bidx = ETH_HDR_ETYPE + 1) then
                bval := ETYPE_VLAN(7 downto 0);         -- Tag ID (LSBs)
            elsif (bidx = ETH_HDR_ETYPE + 2) then
                bval := mod_vtag(15 downto 8);          -- Tag header (MSBs)
            elsif (bidx = ETH_HDR_ETYPE + 3) then
                bval := mod_vtag(7 downto 0);           -- Tag header (LSBs)
            elsif (tag_novr > 0 and b >= OVR_MAX) then
                bval := (others => '0');                -- Zero-pad overflow
            else
                bval := get_input(in_sreg, OVR_MAX);    -- Shifted input
            end if;
            -- Drive the next output byte.
            if (tag_next = '1') then
                tag_data(tag_data'left-8*b downto tag_data'left-8*b-7) <= bval;
            end if;
        end if;
    end process;
end generate;

-- Drive top-level outputs.
in_ready    <= in_ready_i;
out_data    <= tag_data;
out_error   <= tag_error;
out_nlast   <= tag_nlast;
out_valid   <= tag_valid;
tag_ready   <= out_ready;

-- ConfigBus interface handling.
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        if (cfg_cmd.reset_p = '1') then
            -- Global reset reverts to required default under 802.1Q.
            cfg_policy <= VTAG_ADMIT_ALL;
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_ADDR)) then
            -- Ignore writes unless they have a matching port-index.
            if (u2i(cfg_cmd.wdata(31 downto 24)) = PORT_INDEX) then
                cfg_policy <= cfg_cmd.wdata(21 downto 20);
            end if;
        end if;
    end if;
end process;

end eth_frame_vtag;
