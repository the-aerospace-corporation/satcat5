--------------------------------------------------------------------------
-- Copyright 2022 The Aerospace Corporation
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
-- Egress processing for the Precision Time Protocol (PTP)
--
-- This block provides last-second adjustments to outgoing PTP frames,
-- in order to apply per-port parameters, such as the egress timestamp.
-- It works in conjunction with the "ptp_adjust" block, which identifies
-- frames that need changes and precomputes reference timestamps.
--
-- The block is compatible with both Ethernet and UDP transport modes.
-- It replaces the contents at specific locations in the common PTP
-- message header (See IEEE 1588-2019 Table 35):
--  * correctionField: In each marked frame, overwrite with:
--      (correctionField - ingressTimestamp) + egressTimestamp
--      The first component is provided as frame metadata.
--  * flagField/twoStepFlag: In each marked frame, overwrite this flag
--      with a '1' if the port is in mandatory "two-step" mode.
--
-- Whenever PTP is enabled, the "switch_port_tx" chain will recalculate the
-- Ethernet FCS.  Therefore, there is no need for this block to update it.
--


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.eth_frame_common.all;
use     work.ptp_types.all;

entity ptp_egress is
    generic (
    IO_BYTES    : positive;         -- Width of datapath
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Input data
    in_tnow     : in  tstamp_t;     -- Time reference (from port interface)
    in_tref     : in  tstamp_t;     -- Frame metadata (modified timestamp)
    in_pmode    : in  ptp_mode_t;   -- Frame metadata (PTP change mode)
    in_vtag     : in  vlan_hdr_t;   -- Frame metadata (VLAN tags)
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;    -- AXI flow-control
    in_ready    : out std_logic;    -- AXI flow-control
    -- Modified data
    out_vtag    : out vlan_hdr_t;   -- Frame metadata (to VLAN block)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;    -- AXI flow-control
    out_ready   : in  std_logic;    -- AXI flow-control
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    cfg_2step   : in  std_logic := '0';
    -- Port timestamp, clock, and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_egress;

architecture ptp_egress of ptp_egress is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Parser counts to the word just after the last possible header byte.
constant PTP_BYTE_MAX   : positive := UDP_HDR_MAX + PTP_HDR_MSGDAT;
constant PTP_WORD_MAX   : positive := 1 + (PTP_BYTE_MAX / IO_BYTES);

-- Input stream and metadata.
signal in_ready_i   : std_logic;
signal in_write     : std_logic;
signal in_wcount    : integer range 0 to PTP_WORD_MAX := 0;
signal tcorr_val    : tstamp_t := (others => '0');
signal tcorr_word   : std_logic_vector(63 downto 0);
signal tcorr_rd     : std_logic;

-- Packet-modification state machine.
signal mod_ihl      : nybb_u := (others => '0');
signal mod_data     : data_t := (others => '0');
signal mod_nlast    : last_t := 0;
signal mod_valid    : std_logic := '0';
signal mod_ready    : std_logic;
signal mod_2step    : std_logic;
signal mod_vtag     : vlan_hdr_t := VHDR_NONE;

begin

-- Upstream flow-control logic.
in_ready    <= in_ready_i;
in_ready_i  <= mod_ready or not mod_valid;
in_write    <= in_valid and in_ready_i;

-- Calculate the new correctionField for each input frame.
-- Note: This block has a latency of two clock cycles.  However, the earliest
--  correctionField occurs at byte 22, so we can tolerate IO_BYTES <= 11
--  without needing a matched delay for the input data.
u_tstamp : entity work.ptp_timestamp
    generic map(
    IO_BYTES    => IO_BYTES,
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    in_tnow     => in_tnow,
    in_tref     => in_tref,
    in_nlast    => in_nlast,
    in_write    => in_write,
    out_tstamp  => tcorr_val,
    out_valid   => open,
    out_ready   => tcorr_rd,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk,
    reset_p     => reset_p);

-- Pad the new correctionField value to 64 bits.
-- (Saving a LOT of resources by assuming elapsed time never exceeds ~4 seconds.)
tcorr_word <= std_logic_vector(resize(tcorr_val, 64));

-- Read from timestamp FIFO at the end of each modified frame.
tcorr_rd <= mod_valid and mod_ready and bool2bit(mod_nlast > 0);

-- Cross-clock buffer for each port's "two-step" flag.
u_buffer : sync_buffer
    port map(
    in_flag     => cfg_2step,
    out_flag    => mod_2step,
    out_clk     => clk);

-- Packet-modification state machine.
p_modify : process(clk)
    -- Thin wrapper for the stream-to-byte extractor functions.
    variable btmp : byte_t := (others => '0');  -- Stores output
    impure function get_eth_byte(bidx : natural) return boolean is
    begin
        btmp := strm_byte_value(IO_BYTES, bidx, in_data);
        return strm_byte_present(IO_BYTES, bidx, in_wcount);
    end function;

    -- Replace the bit or byte at the specified offset from start of frame.
    procedure replace_eth_bit(bidx: natural; bval: std_logic) is
        variable bmod : natural := bidx mod (8*IO_BYTES);
    begin
        if (strm_byte_present(IO_BYTES, bidx/8, in_wcount)) then
            mod_data(8*IO_BYTES-bmod-1) <= bval;
        end if;
    end procedure;

    procedure replace_eth_byte(bidx: natural; bval: byte_t) is
        variable bmod : natural := bidx mod IO_BYTES;
    begin
        if (strm_byte_present(IO_BYTES, bidx, in_wcount)) then
            mod_data(8*(IO_BYTES-bmod)-1 downto 8*(IO_BYTES-bmod-1)) <= bval;
        end if;
    end procedure;

    -- Replace the bit or byte at the specified offset from start of PTP message.
    procedure replace_ptp_bit(pidx: natural; bval: std_logic) is
    begin
        if (in_pmode = PTP_MODE_UDP) then
            replace_eth_bit(8*UDP_HDR_DAT(mod_ihl) + pidx, bval);
        elsif (in_pmode = PTP_MODE_ETH) then
            replace_eth_bit(8*ETH_HDR_DATA + pidx, bval);
        end if;
    end procedure;

    procedure replace_ptp_byte(pidx: natural; bval: byte_t) is
    begin
        if (in_pmode = PTP_MODE_UDP) then
            replace_eth_byte(UDP_HDR_DAT(mod_ihl) + pidx, bval);
        elsif (in_pmode = PTP_MODE_ETH) then
            replace_eth_byte(ETH_HDR_DATA + pidx, bval);
        end if;
    end procedure;

begin
    if rising_edge(clk) then
        -- VALID signal needs a true reset.
        if (reset_p = '1') then
            mod_valid <= '0';                   -- Global reset
        elsif (in_ready_i = '1') then
            mod_valid <= in_valid;              -- Storing new data?
        end if;

        -- WCOUNT signal needs a true reset.
        if (reset_p = '1') then
            in_wcount  <= 0;                    -- Global reset
        elsif (in_valid = '1' and in_ready_i = '1') then
            if (in_nlast > 0) then              -- Word-count for parser:
                in_wcount <= 0;                 -- Start of new frame
            elsif (in_wcount < PTP_WORD_MAX) then
                in_wcount <= in_wcount + 1;     -- Count up to max
            end if;
        end if;

        -- Remaining registers don't use a reset, to minimize excess fanout.
        if (in_ready_i = '1') then
            -- Passthrough buffer for unmodified fields.
            mod_nlast   <= in_nlast;
            mod_vtag    <= in_vtag;

            -- Read the IHL field from the IPv4 header, if present.
            -- Note: IHL is at offset 14 and won't be needed until offset 34
            --  at the earliest, so this is safe up to IO_BYTES <= 16.
            if (get_eth_byte(IP_HDR_VERSION)) then
                mod_ihl <= unsigned(btmp(3 downto 0));
            end if;

            -- Retain data by default and replace selected fields on request.
            mod_data <= in_data;
            if (mod_2step = '1') then
                replace_ptp_bit(8*PTP_HDR_FLAG+6, '1');
            end if;
            for n in 0 to 7 loop
                replace_ptp_byte(PTP_HDR_CORR+n, strm_byte_value(n, tcorr_word));
            end loop;
        end if;
    end if;
end process;

-- Connect modified stream to the output.
out_vtag    <= mod_vtag;
out_data    <= mod_data;
out_nlast   <= mod_nlast;
out_valid   <= mod_valid;
mod_ready   <= out_ready;

end ptp_egress;
