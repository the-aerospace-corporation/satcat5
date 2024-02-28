--------------------------------------------------------------------------
-- Copyright 2019-2022 The Aerospace Corporation.
-- This file is a part of SatCat5, licensed under CERN-OHL-W v2 or later.
--------------------------------------------------------------------------
--
-- Ethernet frame adjustment prior to transmission.
--
-- Given a stream of frames, perform any of the following steps to
-- produce valid Ethernet frames:
-- * Strip original FCS, if present (optional, enabled by default)
-- * Pad short frames with zeros to bring them up to minimum size.
--   (Optional, minimum size 64 by default per 802.3 spec)
-- * Append a newly-calculated FCS (optional, enabled by default)
--
-- This block can be used for multiple purposes, including calculating
-- FCS for a raw data stream, padding runt frames to a minimum length before
-- transmission on another network segment, etc.
--
-- The block can process several bytes per clock, depending on IO_BYTES.
-- If IO_BYTES = 1, then either "in_last" or "in_nlast" can be used to
-- indicate the end-of-frame for legacy compatibility.  If IO_BYTES > 1,
-- then "in_last" is ignored, data should be left-packed, and "in_nlast"
-- indicates end-of-frame (see "fifo_packet" for details).
--
-- The optional "in_error" strobe can be used to invalidate the output frame.
-- If APPEND_FCS is true, then asserting this flag at any point during the
-- input frame will cause the recalculated FCS to be inverted.  This allows
-- downstream processing to ignore the invalid frame contents.  The strobe
-- has no effect if APPEND_FCS is false.
--
-- Note: This block uses AXI-style flow control, with additional guarantees.
-- If input data is supplied immediately on request, then the output will have
-- the same property.  This allows use with port_adjust and other blocks that
-- require contiguous data streams.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     work.common_functions.all;
use     work.eth_frame_common.all;

entity eth_frame_adjust is
    generic (
    MIN_FRAME   : natural := 64;        -- Minimum output frame size
    META_WIDTH  : natural := 0;         -- Width of optional metadata field
    APPEND_FCS  : boolean := true;      -- Append new FCS to output?
    STRIP_FCS   : boolean := true;      -- Remove FCS from input?
    IO_BYTES    : positive := 1);       -- I/O width for frame data
    port (
    -- Input data stream (with or without FCS, AXI flow control).
    in_data     : in  std_logic_vector(8*IO_BYTES-1 downto 0);
    in_meta     : in  std_logic_vector(META_WIDTH-1 downto 0) := (others => '0');
    in_error    : in  std_logic := '0';     -- Invalidates generated FCS
    in_nlast    : in  integer range 0 to IO_BYTES := 0;
    in_last     : in  std_logic := '0';     -- Ignored if IO_BYTES > 1
    in_valid    : in  std_logic;
    in_ready    : out std_logic;

    -- Output data stream (with zero-padding and FCS, AXI flow control).
    out_data    : out std_logic_vector(8*IO_BYTES-1 downto 0);
    out_meta    : out std_logic_vector(META_WIDTH-1 downto 0);
    out_error   : out std_logic;
    out_nlast   : out integer range 0 to IO_BYTES;
    out_last    : out std_logic;            -- Legacy compatibility only
    out_valid   : out std_logic;
    out_ready   : in  std_logic;

    -- System interface.
    clk         : in  std_logic;
    reset_p     : in  std_logic);
end eth_frame_adjust;

architecture eth_frame_adjust of eth_frame_adjust is

subtype data_t is std_logic_vector(8*IO_BYTES-1 downto 0);
subtype meta_t is std_logic_vector(META_WIDTH-1 downto 0);
subtype last_t is integer range 0 to IO_BYTES;

-- Legacy compatibility.
signal in_nlast_mod : last_t;

-- Sticky error flag.
signal in_first     : std_logic := '1';
signal in_error_i   : std_logic;
signal in_error_d   : std_logic := '0';

-- FCS removal (optional)
signal in_ready_i   : std_logic;
signal in_write     : std_logic := '0';
signal frm_data     : data_t := (others => '0');
signal frm_meta     : meta_t := (others => '0');
signal frm_error    : std_logic := '0';
signal frm_nlast    : last_t := 0;
signal frm_valid    : std_logic := '0';
signal frm_ready    : std_logic := '0';
signal frm_ovr      : std_logic := '0';

-- Zero-padding of runt frames
signal pad_data     : data_t := (others => '0');
signal pad_meta     : meta_t := (others => '0');
signal pad_error    : std_logic := '0';
signal pad_nlast    : last_t := 0;
signal pad_valid    : std_logic := '0';
signal pad_ready    : std_logic := '0';
signal pad_ovr      : std_logic := '0';

-- Frame-check recalculation
signal fcs_data     : data_t := (others => '0');
signal fcs_meta     : meta_t := (others => '0');
signal fcs_nlast    : last_t := 0;
signal fcs_valid    : std_logic := '0';
signal fcs_ready    : std_logic := '0';
signal fcs_error    : std_logic := '0';
signal fcs_first    : std_logic := '1';
signal fcs_ovr      : std_logic := '0';

begin

-- Legacy compatibility for "in_last":
-- This signal overrides "in_nlast" if IO_BYTES = 1.
in_nlast_mod <= 1 when (IO_BYTES = 1 and in_last = '1') else in_nlast;

-- Sticky per-frame error flag.
in_write    <= in_valid and in_ready_i;
in_error_i  <= in_error or in_error_d;

p_error_flag : process(clk)
begin
    if rising_edge(clk) then
        if (reset_p = '1') then
            in_error_d <= '0';
        elsif (in_write = '1' and in_nlast_mod > 0) then
            in_error_d <= '0';
        elsif (in_write = '1' and in_error = '1') then
            in_error_d <= '1';
        end if;
    end if;
end process;

---------------------------------------------------------------------
-- Frame Check Sequence Removal (STRIP_FCS) -------------------------
---------------------------------------------------------------------

-- Optionally remove FCS from the end of each packet.
gen_nostrip : if not STRIP_FCS generate
    -- Input has already had FCS removed, no need to modify.
    frm_data    <= in_data;
    frm_meta    <= in_meta;
    frm_error   <= in_error_i;
    frm_nlast   <= in_nlast_mod;
    frm_valid   <= in_valid;
    in_ready    <= frm_ready;
end generate;

gen_strip : if STRIP_FCS generate
    -- Upstream flow control.
    in_ready    <= in_ready_i;
    in_ready_i  <= frm_ready or not (frm_valid or frm_ovr);

    -- Remove the last four bytes of each packet.
    p_out_strip : process(clk)
        -- Set delay to ensure we have at least four bytes in buffer.
        constant DELAY_MAX : integer := div_ceil(FCS_BYTES, IO_BYTES);
        type sreg_data_t is array(0 to DELAY_MAX) of data_t;
        type sreg_meta_t is array(0 to DELAY_MAX) of meta_t;
        variable sreg_data : sreg_data_t := (others => (others => '0'));
        variable sreg_meta : sreg_meta_t := (others => (others => '0'));
        -- Maximum "overflow" size if IO_BYTES doesn't divide evenly.
        function OVR_MAX return integer is
            constant dly : integer := DELAY_MAX * IO_BYTES;
        begin
            if (dly >= FCS_BYTES) then
                return dly - FCS_BYTES;
            else
                return dly;
            end if;
        end function;
        constant OVR_THR : integer := IO_BYTES - OVR_MAX;
        variable ovr_ct  : integer range 0 to OVR_MAX := 0;
        variable ovr_err : std_logic := '0';
        -- Countdown to detect when we've received at least four bytes.
        variable count : integer range 0 to DELAY_MAX := DELAY_MAX;
    begin
        if rising_edge(clk) then
            -- Delay input using a shift register.
            if (in_write = '1' or (frm_ovr = '1' and frm_ready = '1')) then
                sreg_data := in_data & sreg_data(0 to DELAY_MAX-1);
                if (META_WIDTH > 0) then
                    sreg_meta := in_meta & sreg_meta(0 to DELAY_MAX-1);
                end if;
            end if;
            frm_data <= sreg_data(DELAY_MAX);
            if (META_WIDTH > 0) then
                frm_meta <= sreg_meta(DELAY_MAX);
            end if;

            -- Once the initial delay has elapsed, forward valid/nlast.
            if (reset_p = '1') then
                frm_valid <= '0';   -- Global reset
                frm_nlast <= 0;
                frm_error <= '0';
            elsif (frm_ovr = '1' and frm_ready = '1') then
                frm_valid <= '1';   -- Extra trailing word
                frm_nlast <= ovr_ct;
                frm_error <= ovr_err;
            elsif (in_write = '1' and count = 0 and in_nlast_mod > 0) then
                frm_valid <= '1';   -- End of input frame
                frm_error <= in_error_i;
                if (in_nlast_mod > OVR_THR) then
                    frm_nlast <= 0; -- Overflow required
                else
                    frm_nlast <= in_nlast_mod + OVR_MAX;
                end if;
            elsif (in_write = '1' and count = 0) then
                frm_valid <= '1';   -- Forward delayed data
                frm_nlast <= 0;
                frm_error <= in_error_i;
            elsif (in_write = '1' or frm_ready = '1') then
                frm_valid <= '0';   -- Previous output consumed
                frm_nlast <= 0;
                frm_error <= '0';
            end if;

            -- Drive the overflow counter and error flag, if enabled.
            if (reset_p = '1' or OVR_MAX = 0) then
                ovr_ct  := 0;
                ovr_err := '0';
            elsif (in_write = '1' and count < 2 and in_nlast_mod > OVR_THR) then
                ovr_ct  := in_nlast_mod - OVR_THR;
                ovr_err := in_error_i;
            elsif (frm_ready = '1') then
                ovr_ct  := 0;
                ovr_err := '0';
            end if;
            frm_ovr <= bool2bit(ovr_ct > 0);

            -- Counter suppresses the first four bytes in each frame.
            if (reset_p = '1') then
                count := DELAY_MAX; -- General reset
            elsif (in_write = '1' and in_nlast_mod > 0) then
                count := DELAY_MAX; -- End of packet
            elsif (in_write = '1' and count > 0) then
                count := count - 1; -- Countdown to zero
            end if;
        end if;
    end process;
end generate;

---------------------------------------------------------------------
-- Minimum-length Padding -------------------------------------------
---------------------------------------------------------------------

-- Upstream flow control
frm_ready <= (not pad_valid) or (pad_ready and not pad_ovr);

-- Pad stub-frames to minimum normal size as needed.
p_pad : process(clk)
    -- Mask ensures we don't forward junk data after EOF.
    variable frm_mask : data_t := (others => '0');
    -- Counter max value is equal to the worst-case pad length.
    -- i.e., min size = N bytes + current byte + 4-byte FCS.
    constant PAD_LEN : natural := int_max(0, MIN_FRAME - FCS_BYTES);
    constant PAD_REM : positive := 1 + ((PAD_LEN-1) mod IO_BYTES);
    constant WCOUNT_MAX : natural := div_ceil(PAD_LEN, IO_BYTES);
    variable wcount : integer range 0 to WCOUNT_MAX := WCOUNT_MAX;
begin
    if rising_edge(clk) then
        -- Byte-valid mask for incoming data.
        if (frm_nlast = 0) then
            frm_mask := (others => '1');
        else
            for b in frm_mask'range loop
                frm_mask(frm_mask'left - b) := bool2bit(b/8 < frm_nlast);
            end loop;
        end if;

        -- Update the output stream.
        if (frm_valid = '1' and frm_ready = '1') then
            -- Pass along input data.
            pad_data  <= frm_data and frm_mask;
            pad_meta  <= frm_meta;
            pad_error <= frm_error;
        elsif (pad_ready = '1' and pad_ovr = '1') then
            -- Zero-padding mode.
            pad_data  <= (others => '0');
        end if;

        -- Update output state and word counter.
        if (reset_p = '1') then
            pad_valid <= '0';
            pad_nlast <= 0;
            pad_ovr   <= '0';
            wcount    := WCOUNT_MAX;
        elsif (WCOUNT_MAX = 0) then
            -- Simplified passthrough if length-padding is disabled.
            if (frm_valid = '1' and frm_ready = '1') then
                pad_valid <= '1';   -- New upstream data
                pad_nlast <= frm_nlast;
            elsif (pad_ready = '1') then
                pad_valid <= '0';   -- Previous word consumed
                pad_nlast <= 0;
            end if;
        elsif (frm_valid = '1' and frm_ready = '1') then
            -- Regular data, pass "last" strobe only if packet exceeds
            -- minimum size or we can pad remaining bytes immediately.
            pad_valid <= '1';
            if (frm_nlast = 0) then
                pad_nlast <= 0;         -- Continue input frame
                pad_ovr   <= '0';
                wcount    := int_max(0, wcount - 1);
            elsif (wcount > 1) then
                pad_nlast <= 0;         -- More data or padding required.
                pad_ovr   <= '1';
                wcount    := int_max(0, wcount - 1);
            elsif (wcount = 1 and frm_nlast < PAD_REM) then
                pad_nlast <= PAD_REM;   -- Complete padding this cycle.
                pad_ovr   <= '0';
                wcount    := WCOUNT_MAX;
            else
                pad_nlast <= frm_nlast; -- No padding required.
                pad_ovr   <= '0';
                wcount    := WCOUNT_MAX;
            end if;
        elsif (pad_ready = '1' and pad_ovr = '1') then
            -- Zero-padding up to minimum frame size.
            pad_valid <= '1';
            if (wcount = 0 or wcount = 1) then
                pad_nlast <= PAD_REM;   -- End of output frame
                pad_ovr   <= '0';
                wcount    := WCOUNT_MAX;
            else
                pad_nlast <= 0;         -- Continue padding
                wcount    := wcount - 1;
            end if;
        elsif (pad_ready = '1') then
            -- Otherwise, mark previous byte as consumed.
            pad_valid <= '0';
            pad_nlast <= 0;
        end if;
    end if;
end process;

---------------------------------------------------------------------
-- Append new Frame Check Sequence (APPEND_FCS) ---------------------
---------------------------------------------------------------------

-- Optionally append a new FCS to the end of each packet.
gen_append_none : if not APPEND_FCS generate
    fcs_data  <= pad_data;
    fcs_error <= pad_error;
    fcs_meta  <= pad_meta;
    fcs_nlast <= pad_nlast;
    fcs_valid <= pad_valid;
    pad_ready <= fcs_ready;
end generate;

gen_append_single : if APPEND_FCS and IO_BYTES = 1 generate
    -- Upstream flow control
    pad_ready <= (not fcs_valid) or (fcs_ready and not fcs_ovr);

    -- Recalculate and append the CRC.
    -- Byte-at-a-time pipeline requires a single clock cycle.
    p_crc : process(clk)
        variable bcount : integer range 0 to 3 := 0;
        variable crc32  : crc_word_t := CRC_INIT;
        variable emask  : byte_t := (others => '0');
    begin
        if rising_edge(clk) then
            -- Relay data until end-of-frame, then append FCS.
            emask := (others => fcs_error);
            if (pad_valid = '1' and pad_ready = '1') then
                -- Relay normal data until end of frame.
                fcs_data  <= pad_data;
                fcs_meta  <= pad_meta;
            elsif (fcs_ovr = '1' and fcs_ready = '1') then
                -- Append each FCS byte, flipping polarity and bit order.
                -- (CRC is MSB-first, but Ethernet convention is LSB-first.)
                fcs_data  <= emask xnor flip_byte(crc32(31 downto 24));
            end if;

            -- Override flag is asserted while we write FCS.
            if (reset_p = '1') then
                fcs_ovr <= '0';
            elsif (pad_valid = '1' and pad_ready = '1') then
                fcs_ovr <= bool2bit(pad_nlast > 0);
            elsif (fcs_ovr = '1' and fcs_ready = '1') then
                fcs_ovr <= bool2bit(bcount < 3);
            end if;

            -- Update the VALID and LAST strobes.
            if (reset_p = '1') then
                -- Global reset.
                fcs_valid <= '0';
                fcs_nlast <= 0;
            elsif ((pad_valid = '1' and pad_ready = '1')
                or (fcs_ovr = '1' and fcs_ready = '1')) then
                -- Append each new data or FCS byte.
                fcs_valid <= '1';
                fcs_nlast <= u2i(bcount = 3);
            elsif (fcs_ready = '1') then
                -- Mark previous byte as consumed.
                fcs_valid <= '0';
                fcs_nlast <= 0;
            end if;

            -- Sticky "error" flag persists over each frame.
            if (reset_p = '1') then
                fcs_error <= '0';
                fcs_first <= '1';
            elsif (pad_valid = '1' and pad_ready = '1') then
                fcs_error <= pad_error or (fcs_error and not fcs_first);
                fcs_first <= bool2bit(pad_nlast > 0);
            end if;

            -- Update the CRC word and output byte counter.
            if (reset_p = '1') then
                -- General reset.
                crc32   := CRC_INIT;
                bcount  := 0;
            elsif (pad_valid = '1' and pad_ready = '1') then
                -- Normal data, update CRC.
                crc32   := crc_next(crc32, pad_data);
                bcount  := 0;
            elsif (fcs_ovr = '1' and fcs_ready = '1') then
                -- Emit next byte from CRC.
                -- (Shifting in 0xFF means we'll be ready to start the next
                --  frame's CRC as soon as we read out the 4th byte.)
                crc32 := crc32(23 downto 0) & x"FF";
                if (bcount < 3) then
                    bcount := bcount + 1;
                else
                    bcount := 0;
                end if;
            end if;
        end if;
    end process;
end generate;

gen_append_parallel : if APPEND_FCS and IO_BYTES > 1 generate
    -- Recalculate and append the CRC using "eth_frame_parcrc" block.
    -- Multi-byte pipeline requires 1 + log2(N) clock cycles.
    blk_fcs : block is
        signal pad_write    : std_logic;
        signal dly_data     : data_t;
        signal dly_crc      : crc_word_t;
        signal dly_error    : std_logic;
        signal dly_nlast    : last_t;
        signal dly_write    : std_logic;
        signal fifo_data    : data_t := (others => '0');
        signal fifo_nlast   : last_t := 0;
        signal fifo_error   : std_logic := '0';
        signal fifo_write   : std_logic := '0';
        signal fifo_ready   : std_logic;
        signal fcs_read     : std_logic;
    begin
        -- Upstream and downstream flow control.
        pad_ready   <= fifo_ready and not fcs_ovr;
        pad_write   <= pad_valid and pad_ready;
        fcs_read    <= fcs_valid and fcs_ready;

        -- Parallel CRC calculation.
        u_parcrc : entity work.eth_frame_parcrc
            generic map(IO_BYTES => IO_BYTES)
            port map(
            in_data     => pad_data,
            in_nlast    => pad_nlast,
            in_error    => pad_error,
            in_write    => pad_write,
            out_data    => dly_data,
            out_crc     => dly_crc,
            out_error   => dly_error,
            out_nlast   => dly_nlast,
            out_write   => dly_write,
            clk         => clk,
            reset_p     => reset_p);

        -- Append calculated CRC onto each frame.
        p_append : process(clk)
            variable crc_delay : crc_word_t := (others => '0');
            variable crc_error : std_logic := '0';
            variable crc_idx   : integer range 0 to FCS_BYTES := 0;
            variable crc_shift : data_t := (others => '0');
            variable tmp_crc   : byte_t;
            variable tmp_err   : byte_t;
            variable tmp_idx   : integer range 7 to crc_shift'left;
            variable pre_bytes : integer range 0 to FCS_BYTES := 0;
            variable ovr_bytes : integer range 0 to FCS_BYTES := 0;
        begin
            if rising_edge(clk) then
                -- Appending CRC may add extra word(s) to some frames.
                -- Override upstream flow-control to skip a beat as needed.
                if (reset_p = '1') then
                    pre_bytes := 0;
                    fcs_ovr   <= '0';   -- Global reset
                elsif (pad_write = '1' and pad_nlast > 0
                   and pad_nlast + FCS_BYTES > IO_BYTES) then
                    pre_bytes := pad_nlast + FCS_BYTES - IO_BYTES;
                    fcs_ovr   <= '1';   -- End of frame, overflow required.
                elsif (pre_bytes > IO_BYTES) then
                    pre_bytes := pre_bytes - IO_BYTES;
                    fcs_ovr   <= '1';   -- Skip another cycle if needed.
                else
                    pre_bytes := 0;
                    fcs_ovr   <= '0';   -- Skip completed, return to normal.
                end if;

                -- Generate the shifted CRC word, if applicable.
                -- (Combinational logic; each byte is effectively an N-way MUX.)
                for b in 0 to IO_BYTES-1 loop
                    if (b < ovr_bytes) then
                        crc_idx := ovr_bytes - b;
                        tmp_crc := crc_delay(8*crc_idx-1 downto 8*crc_idx-8);
                        tmp_err := (others => crc_error);
                    elsif (dly_nlast > 0 and b >= dly_nlast and b < dly_nlast + FCS_BYTES) then
                        crc_idx := dly_nlast + FCS_BYTES - b;
                        tmp_crc := dly_crc(8*crc_idx-1 downto 8*crc_idx-8);
                        tmp_err := (others => dly_error);
                    else
                        crc_idx := 0;   -- No selection
                        tmp_crc := (others => '0');
                        tmp_err := (others => '0');
                    end if;
                    tmp_idx := crc_shift'left - 8*b;
                    crc_shift(tmp_idx downto tmp_idx-7) := tmp_crc xor tmp_err;
                end loop;

                -- Modify the primary output stream.
                if (ovr_bytes > IO_BYTES) then
                    -- Multi-word carryover from previous frame.
                    fifo_data   <= crc_shift;
                    fifo_error  <= crc_error;
                    fifo_nlast  <= 0;
                elsif (ovr_bytes > 0) then
                    -- Final carryover from previous frame.
                    fifo_data   <= crc_shift;
                    fifo_error  <= crc_error;
                    fifo_nlast  <= ovr_bytes;
                elsif (dly_nlast = 0) then
                    -- Regular data feedthrough.
                    fifo_data   <= dly_data;
                    fifo_error  <= dly_error;
                    fifo_nlast  <= dly_nlast;
                elsif (dly_nlast + FCS_BYTES <= IO_BYTES) then
                    -- Insertion without carryover.
                    fifo_data   <= dly_data or crc_shift;
                    fifo_error  <= dly_error;
                    fifo_nlast  <= dly_nlast + FCS_BYTES;
                else
                    -- Insertion with carryover.
                    fifo_data   <= dly_data or crc_shift;
                    fifo_error  <= dly_error;
                    fifo_nlast  <= 0;
                end if;
                fifo_write <= dly_write or bool2bit(ovr_bytes > 0);

                -- Carryover next cycle?
                if (reset_p = '1') then
                    ovr_bytes := 0;     -- Global reset
                elsif (dly_write = '1' and dly_nlast > 0
                   and dly_nlast + FCS_BYTES > IO_BYTES) then
                    -- End of frame, carryover required.
                    ovr_bytes := dly_nlast + FCS_BYTES - IO_BYTES;
                elsif (ovr_bytes > 0) then
                    -- Countdown back to zero.
                    ovr_bytes := int_max(0, ovr_bytes - IO_BYTES);
                end if;

                -- Latch CRC and error flag for later use.
                if (dly_write = '1' and dly_nlast > 0) then
                    crc_delay := dly_crc;
                    crc_error := dly_error;
                end if;
            end if;
        end process;

        -- Output FIFO required because "parcrc" block has no flow-control.
        u_fifo_data : entity work.fifo_smol_bytes
            generic map(
            IO_BYTES    => IO_BYTES,
            META_WIDTH  => 1)
            port map(
            in_data     => fifo_data,
            in_meta(0)  => fifo_error,
            in_nlast    => fifo_nlast,
            in_write    => fifo_write,
            out_data    => fcs_data,
            out_meta(0) => fcs_error,
            out_nlast   => fcs_nlast,
            out_valid   => fcs_valid,
            out_read    => fcs_read,
            fifo_hempty => fifo_ready,
            clk         => clk,
            reset_p     => reset_p);

        -- Separate FIFO for metadata, if enabled.
        gen_meta : if META_WIDTH > 0 generate
            u_fifo_meta : entity work.fifo_smol_sync
                generic map(IO_WIDTH => META_WIDTH)
                port map(
                in_data     => pad_meta,
                in_write    => pad_write,
                out_data    => fcs_meta,
                out_valid   => open,
                out_read    => fcs_read,
                clk         => clk,
                reset_p     => reset_p);
        end generate;
    end block;
end generate;

---------------------------------------------------------------------
-- Final output stage
---------------------------------------------------------------------

out_data  <= fcs_data;
gen_withmeta : if (META_WIDTH > 0) generate
    out_meta  <= fcs_meta;
end generate;
out_error <= fcs_error;
out_nlast <= fcs_nlast;
out_last  <= bool2bit(fcs_nlast > 0);
out_valid <= fcs_valid;
fcs_ready <= out_ready;

end eth_frame_adjust;
