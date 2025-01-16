--------------------------------------------------------------------------
-- Copyright 2022-2024 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
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
--    The difference component is provided as frame metadata.
--  * flagField/twoStepFlag: In each marked frame, overwrite this flag
--    with a '1' if the port is in mandatory "two-step" mode.
--    (Since required output varies, it cannot be performed upstream.)
--  * If PTP_DOPPLER is enabled, and the experimental Doppler TLV was
--    detected (see ptp_ingress), then overwrite the frequency field:
--      (dopplerField - ingressFrequency) + egressFrequency
--    The difference component is provided as frame metadata.
--
-- Whenever PTP is enabled, the "switch_port_tx" chain will recalculate the
-- Ethernet FCS.  Therefore, there is no need for this block to update it.
--
-- The "port_pstart" (PTP start) signal is used to coordinate the precise
-- timing of outgoing packets.  Used correctly, it ensures the delay from
-- the output of this block to the MAC/PHY interface is deterministic.
--
-- The "port_pstart" strobe indicates that the port is ready to accept the
-- start of a new outgoing frame. Any reasonable delay is acceptable, as
-- long as it is fixed and deterministic for a given port configuration.
-- For ports with fixed delay, the signal may simply be tied to '1'.
-- Otherwise, it indicates that all of the following are true:
--  * No outgoing data is currently queued. (e.g., If your port contains
--    an internal FIFO, tie this to the FIFO-empty flag.)
--  * A new start-of-frame would be accepted on the current clock cycle.
--    (e.g., The "frmst" strobe from "eth_enc8b10b.vhd".)
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.cfgbus_common.all;
use     work.common_functions.all;
use     work.common_primitives.sync_buffer;
use     work.eth_frame_common.all;
use     work.ptp_types.all;
use     work.switch_types.switch_meta_t;

entity ptp_egress is
    generic (
    IO_BYTES    : positive;         -- Width of datapath
    PTP_DOPPLER : boolean := false; -- Enable Doppler-TLV tags?
    PTP_STRICT  : boolean := true;  -- Drop frames with missing timestamps?
    DEVADDR     : integer := CFGBUS_ADDR_NONE;
    REGADDR     : integer := CFGBUS_ADDR_NONE);
    port (
    -- Timestamp and other signals from the port interface
    port_tnow   : in  tstamp_t;     -- Time reference
    port_tfreq  : in  tfreq_t;      -- Frequency reference
    port_pstart : in  std_logic;    -- Precision packet-start
    port_dvalid : in  std_logic;    -- Transmit data-valid
    -- Input data
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  switch_meta_t;
    in_nlast    : in  integer range 0 to IO_BYTES;
    in_valid    : in  std_logic;    -- AXI flow-control
    in_ready    : out std_logic;    -- AXI flow-control
    -- Modified data
    out_vtag    : out vlan_hdr_t;   -- Frame metadata (to VLAN block)
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_error   : out std_logic;    -- Drop this frame
    out_nlast   : out integer range 0 to IO_BYTES;
    out_valid   : out std_logic;    -- AXI flow-control
    out_ready   : in  std_logic;    -- AXI flow-control
    -- Optional ConfigBus interface.
    cfg_cmd     : in  cfgbus_cmd := CFGBUS_CMD_NULL;
    cfg_ack     : out cfgbus_ack;
    cfg_2step   : in  std_logic := '0';
    -- Port transmit clock and reset.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end ptp_egress;

architecture ptp_egress of ptp_egress is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Parser counts to the word just after the last byte of interest.
constant PTP_BYTE_MAX : positive := ptp_parse_bytes(PTP_DOPPLER, true);
constant PTP_WORD_MAX : positive := 1 + (PTP_BYTE_MAX / IO_BYTES);

-- Input stream and metadata.
signal in_ready_i   : std_logic;
signal in_write     : std_logic;
signal in_wcount    : integer range 0 to PTP_WORD_MAX := 0;
signal in_pstart    : std_logic := '0';
signal in_adj_time  : std_logic := '0';
signal in_adj_freq  : std_logic := '0';
signal tcorr_time   : tstamp_t := (others => '0');
signal tcorr_freq   : tfreq_t := (others => '0');
signal tcorr_time2  : std_logic_vector(63 downto 0);
signal tcorr_freq2  : std_logic_vector(47 downto 0);
signal tcorr_rd     : std_logic;
signal tcorr_error  : std_logic;

-- Packet-modification state machine.
signal mod_data     : data_t := (others => '0');
signal mod_nlast    : last_t := 0;
signal mod_valid    : std_logic := '0';
signal mod_ready    : std_logic;
signal mod_2step    : std_logic;
signal mod_pstart   : std_logic := '0';
signal mod_vtag     : vlan_hdr_t := VHDR_NONE;

begin

-- Upstream flow-control logic.
-- At start-of-frame for PTP messages only, the IN_READY flag is
-- additionally qualified by the IN_PSTART strobe (see below).
in_adj_time <= bool2bit(in_meta.pmsg /= TLVPOS_NONE);
in_adj_freq <= bool2bit(in_meta.pfreq /= TLVPOS_NONE);
in_ready    <= in_ready_i;
in_ready_i  <= mod_ready and bool2bit(
    in_pstart = '1' or in_adj_time = '0' or in_wcount > 0);
in_write    <= in_valid and in_ready_i;

-- Deterministic-delay state machine ensures:
--  * The rest of the egress pipeline is completely flushed.
--    i.e., Delay through all remaining blocks in "switch_port_tx",
--    typically ~4-8 clock cycles depending on switch configuration.
--  * The port has just asserted its "port_pstart" strobe.
--    This *should* indicate that any queues in the port itself have
--    been flushed, but we want to give a little leeway just in case.
p_pstart : process(clk)
    -- Delay here burns idle time before each PTP frame, but must be
    -- large enough to exceed all above requirements with margin.
    constant MAX_WAIT : integer := 15;
    variable count : integer range 0 to MAX_WAIT := 0;
begin
    if rising_edge(clk) then
        if (mod_valid = '1' or port_dvalid = '1') then
            count := MAX_WAIT;  -- Busy / transmission in progress.
            in_pstart <= '0';
        elsif (count > 0) then  -- Wait for egress pipeline to flush.
            count := count - 1;
            in_pstart <= '0';
        else                    -- Ready for precision-timed packet?
            in_pstart <= port_pstart;
        end if;
    end if;
end process;

-- Calculate the new correctionField for each input frame.
-- Note: This block has a latency of two clock cycles from start-of-frame.
--  However, the earliest correctionField occurs at byte 22, so we can tolerate
--  IO_BYTES <= 11 without needing a matched delay for the input data.
u_tstamp : entity work.ptp_timestamp
    generic map(
    IO_BYTES    => IO_BYTES,
    PTP_DOPPLER => PTP_DOPPLER,
    PTP_STRICT  => PTP_STRICT,
    DEVADDR     => DEVADDR,
    REGADDR     => REGADDR)
    port map(
    in_tnow     => port_tnow,
    in_tfreq    => port_tfreq,
    in_adj_time => in_adj_time,
    in_adj_freq => in_adj_freq,
    in_nlast    => in_nlast,
    in_write    => in_write,
    ref_time    => in_meta.tstamp,
    ref_freq    => in_meta.tfreq,
    out_tstamp  => tcorr_time,
    out_tfreq   => tcorr_freq,
    out_error   => tcorr_error,
    out_valid   => open,
    out_ready   => tcorr_rd,
    cfg_cmd     => cfg_cmd,
    cfg_ack     => cfg_ack,
    clk         => clk,
    reset_p     => reset_p);

-- Pad the new correctionField value to 64 bits, and pad correctionFreq to 48.
-- (Default of 48-bit timestamps saves a LOT of resources by assuming that
--  incoming correctionField plus residence time never exceeds +/-2 seconds.)
tcorr_time2 <= std_logic_vector(resize(signed(tcorr_time), tcorr_time2'length));
tcorr_freq2 <= std_logic_vector(resize(tcorr_freq, tcorr_freq2'length));

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
    -- Bit-offset for the PTP two-step flag.
    constant PTP_2STEP_BIT : integer := 8*PTP_HDR_FLAG + 6;

    -- Replace the bit or byte at the specified reference + offset.
    procedure replace_bit(tref: tlvpos_t; pidx: natural; bval: std_logic) is
        variable bidx : natural := 8*tlvpos_to_bidx(tref) + pidx;
        variable bmod : natural := bidx mod (8*IO_BYTES);
    begin
        if (strm_byte_present(IO_BYTES, bidx/8, in_wcount)) then
            mod_data(8*IO_BYTES-bmod-1) <= bval;
        end if;
    end procedure;

    procedure replace_byte(tref: tlvpos_t; pidx: natural; bval: byte_t) is
        variable bidx : natural := tlvpos_to_bidx(tref) + pidx;
        variable bmod : natural := bidx mod IO_BYTES;
    begin
        if (strm_byte_present(IO_BYTES, bidx, in_wcount)) then
            mod_data(8*(IO_BYTES-bmod)-1 downto 8*(IO_BYTES-bmod-1)) <= bval;
        end if;
    end procedure;
begin
    if rising_edge(clk) then
        -- VALID signal needs a true reset.
        if (reset_p = '1') then
            mod_valid <= '0';                   -- Global reset
        elsif (mod_ready = '1') then
            mod_valid <= in_write;              -- Storing new data?
        end if;

        -- WCOUNT signal needs a true reset.
        if (reset_p = '1') then
            in_wcount <= 0;                     -- Global reset
        elsif (in_write = '1') then
            if (in_nlast > 0) then              -- Word-count for parser:
                in_wcount <= 0;                 -- Start of new frame
            elsif (in_wcount < PTP_WORD_MAX) then
                in_wcount <= in_wcount + 1;     -- Count up to max
            end if;
        end if;

        -- Remaining registers don't use a reset, to minimize excess fanout.
        if (mod_ready = '1') then
            -- Passthrough buffer for unmodified fields.
            mod_nlast   <= in_nlast;
            mod_vtag    <= in_meta.vtag;

            -- Retain data by default and replace selected fields on request.
            mod_data <= in_data;
            if (in_adj_time = '1' and mod_2step = '1') then
                replace_bit(in_meta.pmsg, PTP_2STEP_BIT, '1');
            end if;
            if (in_adj_time = '1') then
                for n in 0 to 7 loop
                    replace_byte(
                        in_meta.pmsg, PTP_HDR_CORR + n,
                        strm_byte_value(n, tcorr_time2));
                end loop;
            end if;
            if (in_adj_freq = '1') then
                for n in 0 to 5 loop
                    replace_byte(
                        in_meta.pfreq, n,
                        strm_byte_value(n, tcorr_freq2));
                end loop;
            end if;
        end if;
    end if;
end process;

-- Connect modified stream to the output.
-- Strict mode drops frames with missing egress timestamps.
out_vtag    <= mod_vtag;
out_data    <= mod_data;
out_error   <= tcorr_error;
out_nlast   <= mod_nlast;
out_valid   <= mod_valid;
mod_ready   <= out_ready or not mod_valid;

end ptp_egress;
