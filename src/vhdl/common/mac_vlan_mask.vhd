--------------------------------------------------------------------------
-- Copyright 2021 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Virtual-LAN port mask lookup
--
-- Given the VLAN Tag Control Information (TCI) for each frame, determine
-- which ports are part of the designated VLAN and the priority.  The port
-- mask is combined with the normal MAC-lookup mask to determine which ports,
-- if any, can and should receive the current frame.
--
-- The tag metadata is sampled on the last word in the frame; only the PCP
-- and VID fields are considered.  The output for a given frame is the port
-- mask associated with its VID.  (An optional "error" flag forces the port
-- mask to all-zeros, dropping the frame.)  The PCP field is also used to
-- set the queueing priority, if that feature is supported.
--
-- As with other blocks in "mac_core.vhd", a small FIFO buffers these outputs
-- to automatically accommodate variations in pipeline delay.
--
-- VLAN masks are stored in a 4096-element lookup table, matching the number
-- of possible VID tags allowed in a 802.1Q tag.  Word size is equal to the
-- number of ports on the switch, so a 16-port switch requires 8 kiB of BRAM.
-- By default, each VID is connected to every port.
--
-- Table contents are loaded via two ConfigBus registers.  To use, write the
-- VID register and then write the port-mask register one or more times.  The
-- mask sets the ports included in each VID, with LSB = Port #0 and MSB = Port
-- #31 (if present).  If readback is enabled, the mask register can also be
-- read to report the port-mask for the current VID.
--
-- To facilitate rapid loading of the entire table, the VID is automatically
-- incremented after each read or write to the mask register, with wraparound
-- after VID = FFF.  Writes to reserved VIDs 000 and FFF are ignored, as are
-- mask bits above PORT_COUNT-1.
--
-- For example, To connect VID = 0x123 to ports 1, 3, and 8:
--  * Write REG_ADDR_V = 0x123
--  * Write REG_ADDR_M = 0b0000000100001010 = 0x010A
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.dpram;
use     work.eth_frame_common.all;

entity mac_vlan_mask is
    generic (
    DEV_ADDR    : integer;          -- ConfigBus device address
    REG_ADDR_V  : integer;          -- ConfigBus register address (VID)
    REG_ADDR_M  : integer;          -- ConfigBus register address (mask)
    PORT_COUNT  : positive;         -- Number of Ethernet ports
    READBACK_EN : boolean := true); -- Enable mask readback?
    port (
    -- Main input stream (metadata only)
    in_psrc     : in  integer range 0 to PORT_COUNT-1;
    in_vtag     : in  vlan_hdr_t;
    in_error    : in  std_logic := '0';
    in_last     : in  std_logic;
    in_write    : in  std_logic;

    -- Port-mask and priority results
    out_vtag    : out vlan_hdr_t;
    out_pmask   : out std_logic_vector(PORT_COUNT-1 downto 0);
    out_hipri   : out std_logic;
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- Configuration interface (writes required, reads optional)
    cfg_cmd     : in  cfgbus_cmd;
    cfg_ack     : out cfgbus_ack;

    -- System interface
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end mac_vlan_mask;

architecture mac_vlan_mask of mac_vlan_mask is

subtype port_mask_t is std_logic_vector(PORT_COUNT-1 downto 0);

-- Main lookup-table datapath
signal rd_psrc      : integer range 0 to PORT_COUNT-1 := 0;
signal rd_vtag      : vlan_hdr_t := (others => '0');
signal rd_addr      : vlan_vid_t := (others => '0');
signal rd_en        : std_logic := '0';
signal rd_error     : std_logic := '0';
signal lkup_vtag    : vlan_hdr_t := (others => '0');
signal lkup_ovr     : std_logic := '0';
signal lkup_write   : std_logic := '0';
signal lkup_hipri   : std_logic := '0';
signal lkup_frm_ok  : std_logic;
signal lkup_smask   : port_mask_t := (others => '0');   -- Source mask
signal lkup_raw     : port_mask_t;  -- Raw data from loookup
signal lkup_vmask   : port_mask_t;  -- VLAN membership mask
signal lkup_dmask   : port_mask_t;  -- Destination mask

-- ConfigBus interface
signal cfg_addr     : vlan_vid_t := (others => '0');
signal cfg_wmask    : port_mask_t := (others => '0');
signal cfg_rmask    : port_mask_t := (others => '0');
signal cfg_rword    : cfgbus_word;
signal cfg_incr     : std_logic := '0';
signal cfg_wren     : std_logic := '0';
signal cfg_rden     : std_logic := '0';
signal cfg_rden_d   : std_logic := '0';

begin

-- Main datapath: VID field sets the lookup index.
p_lookup : process(clk)
begin
    if rising_edge(clk) then
        -- Pipeline stage 1: Buffer raw inputs and extract VID field.
        rd_psrc     <= in_psrc;
        rd_vtag     <= in_vtag;
        rd_addr     <= vlan_get_vid(in_vtag);
        rd_en       <= in_write and in_last and not reset_p;
        rd_error    <= in_error;

        -- Pipeline stage 2: Priority lookup and override flag.
        -- Note: Only two priority classes (high/low), refer to 802.1Q Table 8-4.
        for n in lkup_smask'range loop
            lkup_smask(n) <= bool2bit(n = rd_psrc);
        end loop;
        lkup_vtag   <= rd_vtag;
        lkup_write  <= rd_en and not reset_p;
        lkup_hipri  <= bool2bit(vlan_get_pcp(rd_vtag) >= 4);
        lkup_ovr    <= bool2bit(rd_addr = VID_NONE)
                    or bool2bit(rd_addr = VID_RSVD)
                    or rd_error;
    end if;
end process;

-- Lookup table for all 2^12 = 4,096 possible VID values.
-- (Concurrent with pipeline stage 2, above.)
u_table : dpram
    generic map(
    AWIDTH      => VLAN_VID_WIDTH,
    DWIDTH      => PORT_COUNT,
    TRIPORT     => READBACK_EN)
    port map(
    wr_clk      => cfg_cmd.clk,
    wr_addr     => cfg_addr,
    wr_en       => cfg_wren,
    wr_val      => cfg_wmask,
    wr_rval     => cfg_rmask,
    rd_clk      => clk,
    rd_addr     => rd_addr,
    rd_en       => rd_en,
    rd_val      => lkup_raw);

-- BRAM default value is all zeros, so invert masks on both read
-- and write so that the default is "All VLANs fully connected".
-- TODO: If we change to a more complicated default, add a state
--       machine that overwrites on reset and remove inversion.
lkup_vmask <= not lkup_raw;

-- Reject any frames where the source port isn't a part of the VLAN,
-- or if it failed any other validation checks (see above).
lkup_frm_ok <= or_reduce(lkup_vmask and lkup_smask) and not lkup_ovr;

-- Set the destination mask only if we decide to keep the frame.
lkup_dmask <= lkup_vmask when (lkup_frm_ok = '1') else (others => '0');

-- FIFO for metadata and lookup table results.
u_fifo : entity work.fifo_smol_sync
    generic map(
    IO_WIDTH    => PORT_COUNT,
    META_WIDTH  => VLAN_HDR_WIDTH)
    port map(
    in_data     => lkup_dmask,
    in_meta     => lkup_vtag,
    in_last     => lkup_hipri,
    in_write    => lkup_write,
    out_data    => out_pmask,
    out_meta    => out_vtag,
    out_last    => out_hipri,
    out_valid   => out_valid,
    out_read    => out_ready,
    clk         => clk,
    reset_p     => reset_p);

-- ConfigBus interface (writes)
-- (Inversion required for startup state, see note above.)
p_cfg : process(cfg_cmd.clk)
begin
    if rising_edge(cfg_cmd.clk) then
        -- Address register is write-only.
        if (cfg_cmd.reset_p = '1') then
            cfg_addr <= (others => '0');
        elsif (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_ADDR_V)) then
            cfg_addr <= unsigned(cfg_cmd.wdata(cfg_addr'range));
        elsif (cfg_wren = '1' or cfg_rden = '1') then
            cfg_addr <= cfg_addr + 1;   -- Auto-increment
        end if;

        -- Mask is a simple register write.
        -- (Inversion required for startup state, see note above.)
        if (cfgbus_wrcmd(cfg_cmd, DEV_ADDR, REG_ADDR_M)) then
            cfg_wmask <= not cfg_cmd.wdata(PORT_COUNT-1 downto 0);
            cfg_wren  <= '1';
        else
            cfg_wren  <= '0';
        end if;

        -- Single-cycle delay for read replies.
        cfg_rden_d <= cfg_rden and not cfg_cmd.reset_p;
    end if;
end process;

-- ConfigBus interface (reads, optional)
cfg_rden    <= bool2bit(READBACK_EN and cfgbus_rdcmd(cfg_cmd, DEV_ADDR, REG_ADDR_M));
cfg_rword   <= resize(not cfg_wmask, CFGBUS_WORD_SIZE);
cfg_ack     <= cfgbus_reply(cfg_rword) when (cfg_rden_d = '1') else cfgbus_idle;

end mac_vlan_mask;
